#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ScoutOktaEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            $parsed = $null
            [uri]::TryCreate($_, [System.UriKind]::Absolute, [ref]$parsed) -and $parsed.Scheme -eq 'https'
        })]
        [string] $OrganizationUrl,

        [Parameter(Mandatory)]
        [securestring] $ApiToken
    )

    $baseUri = $OrganizationUrl.TrimEnd('/')
    $plainToken = ConvertFrom-SecureString -SecureString $ApiToken -AsPlainText
    $headers = @{ Authorization = "SSWS $plainToken"; Accept = 'application/json' }
    $resources = [System.Collections.Generic.List[object]]::new()
    $sourceOperations = [System.Collections.Generic.List[object]]::new()
    $collectionHealth = [System.Collections.Generic.List[object]]::new()

    function Get-OktaValue {
        param([AllowNull()][object] $InputObject, [Parameter(Mandatory)][string] $Path)
        $current = $InputObject
        foreach ($segment in $Path.Split('.')) {
            if ($null -eq $current) { return $null }
            if ($current -is [System.Collections.IDictionary]) {
                $key = @($current.Keys | Where-Object { [string]$_ -ieq $segment } | Select-Object -First 1)
                if ($key.Count -eq 0) { return $null }
                $current = $current[$key[0]]
            }
            else {
                $property = @($current.PSObject.Properties | Where-Object Name -ieq $segment | Select-Object -First 1)
                if ($property.Count -eq 0) { return $null }
                $current = $property[0].Value
            }
        }
        return $current
    }

    function Add-OktaEnvelope {
        param([string] $Dataset, [object] $Raw, [string] $Uri, [datetime] $CollectedAt, [string] $ParentId)
        $rawId = [string](Get-OktaValue $Raw 'id')
        if ([string]::IsNullOrWhiteSpace($rawId)) { $rawId = "$Dataset-$($resources.Count + 1)" }
        $rawName = [string](Get-OktaValue $Raw 'name')
        if ([string]::IsNullOrWhiteSpace($rawName)) { $rawName = [string](Get-OktaValue $Raw 'label') }
        if ([string]::IsNullOrWhiteSpace($rawName)) { $rawName = $rawId }
        $resources.Add([pscustomobject][ordered]@{
                id = "/providers/AzureScout/okta/$Dataset/$([uri]::EscapeDataString($rawId))"
                name = $rawName
                type = "AZSC/Okta/$Dataset"
                PARENTID = $ParentId
                properties = [pscustomobject][ordered]@{ Raw = $Raw }
                AZSC = [pscustomobject][ordered]@{
                    Source = 'Okta Management API'; Dataset = $Dataset; Operation = 'GET'; Uri = $Uri
                    Permission = 'Read-only Okta administrator or OAuth read scopes'; CollectedAt = $CollectedAt.ToString('o')
                }
            })
    }

    function Get-OktaNextLink {
        param([AllowNull()][object] $Response)
        if ($null -eq $Response -or -not $Response.PSObject.Properties['Headers']) { return $null }
        $link = $Response.Headers['Link']
        foreach ($part in @([string]$link -split ',')) {
            if ($part -match '<([^>]+)>\s*;\s*rel="next"') { return $Matches[1] }
        }
        return $null
    }

    function Invoke-OktaRead {
        param(
            [Parameter(Mandatory)][string] $Dataset,
            [Parameter(Mandatory)][string] $RelativeUri,
            [string] $ParentId,
            [switch] $Optional
        )
        $items = [System.Collections.Generic.List[object]]::new()
        $currentUri = if ([uri]::IsWellFormedUriString($RelativeUri, [System.UriKind]::Absolute)) { $RelativeUri } else { "$baseUri$RelativeUri" }
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        while ($currentUri) {
            if (-not $seen.Add($currentUri)) { throw "Okta returned a repeated next link for $Dataset." }
            $startedAt = Get-Date
            try {
                $response = Invoke-WebRequest -Uri $currentUri -Method GET -Headers $headers -ErrorAction Stop
                $statusCode = [int]$response.StatusCode
                if ($statusCode -lt 200 -or $statusCode -ge 300) { throw "Okta returned HTTP $statusCode." }
                $content = if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { $null } else { $response.Content | ConvertFrom-Json }
                [object[]]$pageItems = @()
                if ($null -ne $content) {
                    if ($content -is [System.Collections.IEnumerable] -and $content -isnot [string] -and $content -isnot [System.Collections.IDictionary] -and $content -isnot [pscustomobject]) {
                        $pageItems = @($content | Where-Object { $null -ne $_ })
                    }
                    else { $pageItems = @($content) }
                }
                $collectedAt = Get-Date
                foreach ($item in $pageItems) {
                    $items.Add($item)
                    Add-OktaEnvelope -Dataset $Dataset -Raw $item -Uri $currentUri -CollectedAt $collectedAt -ParentId $ParentId
                }
                $sourceOperations.Add([pscustomobject][ordered]@{
                        Source='Okta Management API'; Dataset=$Dataset; Operation='GET'; Uri=$currentUri
                        Status=if($pageItems.Count){'Success'}else{'Empty'}; Count=$pageItems.Count; Reason=$null
                        StartedAt=$startedAt.ToString('o'); CompletedAt=$collectedAt.ToString('o')
                    })
                $currentUri = Get-OktaNextLink -Response $response
            }
            catch {
                $reason = $_.Exception.Message -replace [regex]::Escape($plainToken), '[REDACTED]'
                $status = if ($Optional -and $reason -match '(?i)HTTP\s+(404|501)') { 'NotApplicable' } else { 'Unavailable' }
                $sourceOperations.Add([pscustomobject][ordered]@{
                        Source='Okta Management API'; Dataset=$Dataset; Operation='GET'; Uri=$currentUri
                        Status=$status; Count=0; Reason=$reason; StartedAt=$startedAt.ToString('o'); CompletedAt=(Get-Date).ToString('o')
                    })
                if ($status -eq 'Unavailable') {
                    $collectionHealth.Add([pscustomobject]@{
                            Dataset="Okta/$Dataset"; Operation='GET'; Status='Unavailable'; Reason=$reason
                            ResourceTypes=@("AZSC/Okta/$Dataset")
                        })
                }
                break
            }
        }
        return @($items)
    }

    try {
        $apps = @(Invoke-OktaRead -Dataset 'Applications' -RelativeUri '/api/v1/apps?limit=200')
        $microsoftApps = @($apps | Where-Object {
                [string](Get-OktaValue $_ 'name') -match '(?i)(office365|microsoft)' -or
                [string](Get-OktaValue $_ 'label') -match '(?i)(office\s*365|microsoft)'
            })
        foreach ($app in $microsoftApps) {
            $appId = [string](Get-OktaValue $app 'id')
            if (-not $appId) { continue }
            $null = Invoke-OktaRead -Dataset 'MicrosoftAppGroupAssignments' -RelativeUri "/api/v1/apps/$appId/groups?limit=200" -ParentId $appId
            $null = Invoke-OktaRead -Dataset 'MicrosoftAppUserAssignments' -RelativeUri "/api/v1/apps/$appId/users?limit=200" -ParentId $appId
        }

        $policies = [System.Collections.Generic.List[object]]::new()
        foreach ($policyType in 'OKTA_SIGN_ON','ACCESS_POLICY','MFA_ENROLL','PASSWORD') {
            foreach ($policy in @(Invoke-OktaRead -Dataset 'Policies' -RelativeUri "/api/v1/policies?type=$policyType&limit=200")) {
                $policies.Add($policy)
            }
        }
        foreach ($policy in $policies) {
            $policyId = [string](Get-OktaValue $policy 'id')
            if ($policyId) { $null = Invoke-OktaRead -Dataset 'PolicyRules' -RelativeUri "/api/v1/policies/$policyId/rules?limit=200" -ParentId $policyId }
        }

        $null = Invoke-OktaRead -Dataset 'NetworkZones' -RelativeUri '/api/v1/zones?limit=200'
        $null = Invoke-OktaRead -Dataset 'IdentityProviders' -RelativeUri '/api/v1/idps?limit=200'
        $null = Invoke-OktaRead -Dataset 'ThreatInsight' -RelativeUri '/api/v1/threats/configuration' -Optional
        $directories = @(Invoke-OktaRead -Dataset 'Directories' -RelativeUri '/api/v1/directories?limit=200' -Optional)
        foreach ($directory in $directories) {
            $directoryId = [string](Get-OktaValue $directory 'id')
            if ($directoryId) {
                $null = Invoke-OktaRead -Dataset 'DirectoryAgents' -RelativeUri "/api/v1/directories/$directoryId/agents?limit=200" -ParentId $directoryId -Optional
            }
        }
        $null = Invoke-OktaRead -Dataset 'DefaultUserSchema' -RelativeUri '/api/v1/meta/schemas/user/default' -Optional

        # The System Log is the read-only source of application usage. Retain every returned
        # event for the requested 30-day window, then derive a top-20 view without discarding the
        # underlying events. No actor names are copied into the aggregate rows.
        $since = (Get-Date).ToUniversalTime().AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $filter = [uri]::EscapeDataString('eventType eq "user.authentication.sso"')
        $systemLogEvents = @(Invoke-OktaRead -Dataset 'SystemLogSsoEvents' -RelativeUri "/api/v1/logs?since=$since&filter=$filter&limit=1000" -Optional)

        $users = @(Invoke-OktaRead -Dataset 'ActiveUsers' -RelativeUri '/api/v1/users?limit=200&filter=status%20eq%20%22ACTIVE%22')
        foreach ($user in $users) {
            $userId = [string](Get-OktaValue $user 'id')
            if (-not $userId) { continue }
            $null = Invoke-OktaRead -Dataset 'UserFactors' -RelativeUri "/api/v1/users/$userId/factors" -ParentId $userId
            $null = Invoke-OktaRead -Dataset 'UserAdminRoles' -RelativeUri "/api/v1/users/$userId/roles" -ParentId $userId
        }

        $factorRows = @($resources | Where-Object type -eq 'AZSC/Okta/UserFactors')
        $factorTypes = @($factorRows | Group-Object { [string](Get-OktaValue $_.properties.Raw 'factorType') })
        $usersWithFactors = @($factorRows | ForEach-Object { $_.PARENTID } | Where-Object { $_ } | Sort-Object -Unique)
        $summaryGroups = @($factorTypes)
        if ($summaryGroups.Count -eq 0) {
            $summaryGroups = @([pscustomobject]@{ Name = 'No enrolled factors returned'; Count = 0 })
        }
        foreach ($group in $summaryGroups) {
            $weakFactor = [string]$group.Name -match '(?i)^(sms|call|question|token:software:totp)$'
            $resources.Add([pscustomobject][ordered]@{
                    id="/providers/AzureScout/okta/FactorEnrollmentSummary/$([uri]::EscapeDataString($group.Name))"
                    name=$group.Name; type='AZSC/Okta/FactorEnrollmentSummary'
                    properties=[pscustomobject]@{ FactorType=$group.Name; EnrollmentCount=$group.Count; ActiveUserCount=$users.Count; ActiveUsersWithoutFactorCount=[Math]::Max(0,$users.Count-$usersWithFactors.Count); WeakFactor=$weakFactor }
                    AZSC=[pscustomobject]@{Source='Azure Scout derived evidence';Dataset='OktaFactorEnrollmentSummary';Operation='Aggregate retained Okta users and factors';SourceDatasets=@('ActiveUsers','UserFactors');CollectedAt=(Get-Date).ToString('o')}
                })
        }

        foreach ($group in @($resources | Where-Object type -eq 'AZSC/Okta/UserAdminRoles' | Group-Object { [string](Get-OktaValue $_.properties.Raw 'type') })) {
            $resources.Add([pscustomobject][ordered]@{
                    id="/providers/AzureScout/okta/AdminRoleSummary/$([uri]::EscapeDataString($group.Name))"
                    name=$group.Name; type='AZSC/Okta/AdminRoleSummary'
                    properties=[pscustomobject]@{ RoleType=$group.Name; AssignmentCount=$group.Count }
                    AZSC=[pscustomobject]@{Source='Azure Scout derived evidence';Dataset='OktaAdminRoleSummary';Operation='Aggregate retained Okta role assignments';SourceDatasets=@('UserAdminRoles');CollectedAt=(Get-Date).ToString('o')}
                })
        }

        $applicationUsage = [System.Collections.Generic.List[object]]::new()
        foreach ($event in $systemLogEvents) {
            $appTarget = @(@(Get-OktaValue $event 'target') | Where-Object {
                    [string](Get-OktaValue $_ 'type') -match '(?i)^App'
                } | Select-Object -First 1)
            if ($appTarget.Count -eq 0) { continue }
            $applicationUsage.Add([pscustomobject]@{
                    Id = [string](Get-OktaValue $appTarget[0] 'id')
                    Name = [string](Get-OktaValue $appTarget[0] 'displayName')
                })
        }
        foreach ($group in @($applicationUsage | Group-Object { if ($_.Id) { $_.Id } else { $_.Name } } | Sort-Object Count -Descending | Select-Object -First 20)) {
            $representative = $group.Group[0]
            $appKey = if ($representative.Id) { $representative.Id } else { $representative.Name }
            $resources.Add([pscustomobject][ordered]@{
                    id="/providers/AzureScout/okta/ApplicationUsageSummary/$([uri]::EscapeDataString($appKey))"
                    name=$representative.Name; type='AZSC/Okta/ApplicationUsageSummary'
                    properties=[pscustomobject]@{ ApplicationId=$representative.Id; ApplicationName=$representative.Name; SignOnCount30Days=$group.Count; Rank=$null }
                    AZSC=[pscustomobject]@{Source='Azure Scout derived evidence';Dataset='OktaApplicationUsageSummary';Operation='Aggregate retained Okta System Log SSO events';SourceDatasets=@('SystemLogSsoEvents');CollectedAt=(Get-Date).ToString('o')}
                })
        }
    }
    finally {
        $plainToken = $null
        $headers.Clear()
    }

    [pscustomobject]@{ Resources=@($resources); SourceOperations=@($sourceOperations); CollectionHealth=@($collectionHealth) }
}
