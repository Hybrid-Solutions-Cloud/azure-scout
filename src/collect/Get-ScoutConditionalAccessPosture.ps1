#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Collect the tenant's Entra Conditional Access policies, named locations and Security Defaults
    state into the shape `domains.identity.conditionalAccess` carries, with the computed booleans
    the assessment rules test.

.DESCRIPTION
    Conditional Access is the control that decides who may sign in to Azure and under what proof
    (MFA, a compliant device, a trusted location). It governs ACCESS TO Azure even though it is
    stored in Entra, and Scout collected it into `entraResources` during the inventory pass while
    no assessment rule could read it: every identity item that depends on it (MFA for Azure
    management, MFA for Azure Virtual Desktop, block legacy authentication) was left Manual.

    WHERE THE DATA COMES FROM, in this order:

      1. The rows the inventory pass already read (`entra/conditionalaccesspolicies`,
         `entra/namedlocations`, `entra/securitydefaults`). A combined inventory + assessment run
         therefore makes no second Graph call. The pass records a per-query outcome; an outcome of
         Failed / Unavailable / NotAssessed is reported as such and is NOT retried, because the
         same permission would fail the same way.
      2. When the inventory pass did not run Entra at all (an assessment-only run, or an inventory
         limited to another category), direct Graph GETs through Invoke-AZSCGraphRequest -- the
         same authentication path Get-ScoutExternalIdentitiesPolicy uses.
      3. Never, when -SkipGraph is set (-Scope ArmOnly, or an offline render): `Collected = $false`.

    It NEVER throws. Every failure -- no Graph token, a 403 for a reader without Policy.Read.All, a
    tenant with no Entra ID P1, a network error -- becomes `Collected = $false` plus a `Reason`, so
    a rule that gates on `Collected` reads NotAssessed instead of Pass or Fail.

    COMPUTED BOOLEANS (each policy row carries them next to the raw `conditions`, `grantControls`
    and `sessionControls`, so a Newtonsoft JSONPath filter -- no parentheses, no `!`, a missing
    property never matches -- can test them):

      enabled                          state == 'enabled' (report-only and disabled are NOT enforced)
      reportOnly                       state == 'enabledForReportingButNotEnforced'
      targetsAllUsers                  includeUsers contains 'All'
      targetsDirectoryRoles            includeRoles is non-empty
      targetsGuests                    all users, or guests/external users included explicitly
      targetsAllApps                   includeApplications contains 'All'
      hasAppExclusions                 excludeApplications is non-empty
      targetsAzureManagement           covers the Windows Azure Service Management API app
                                       (797f4846-ba00-4fd7-ba43-dac1f8f63013: Azure Resource
                                       Manager, the Azure portal, CLI and PowerShell) or 'All',
                                       and does not exclude it. Strict on purpose: the
                                       'MicrosoftAdminPortals' grouping is NOT counted here
      targetsAdminPortals              covers the 'MicrosoftAdminPortals' grouping or the Azure
                                       portal app (c44b4083-3bb0-49c1-b47d-974e53cbdf3c), or
                                       'All'. The portal only: Azure CLI and PowerShell sign in
                                       through the management API, so a policy that targets just
                                       this grouping leaves them unprotected
      targetsAvd                       covers the Azure Virtual Desktop app
                                       (9cdead84-a844-4324-93f2-b2e6bb768d07) or 'All', and does
                                       not exclude it. The session-host sign-in app (Windows Cloud
                                       Login) is a second policy and is not part of this flag
      requiresMfa                      grants MFA or an authentication strength AND does not let an
                                       alternative satisfy the policy: with operator OR, any control
                                       that is not MFA turns it into "MFA or something else"
      blocks                           grant control 'block'
      blocksLegacyAuth                 blocks AND applies to Exchange ActiveSync or "other" clients
      usesSignInRisk / usesUserRisk    a risk-level condition is set
      usesLocations                    a named-location condition is set
      requiresCompliantOrHybridDevice  compliant or hybrid-joined device required (same AND/OR rule)
      hasExclusions                    excludeUsers or excludeGroups is non-empty (the break-glass
                                       accounts are normally excluded this way)

    SECURITY DEFAULTS. When Security Defaults are on, no Conditional Access policy can be active,
    so a tenant protected only by them would fail every "an enabled policy requires MFA" check.
    `securityDefaultsCoverage` therefore holds ONE policy-shaped row, present only when they are
    enabled, stating what they enforce (MFA registration for everyone, MFA for administrators and
    for Azure management, legacy authentication blocked) with the same boolean names. It is a
    separate array so `policies[]` is only ever real policies; a rule that accepts either
    mechanism unions the two with `conditionalAccess['policies','securityDefaultsCoverage'][?(...)]`.
    The row does NOT claim `targetsAllApps` or `targetsAvd`: Security Defaults require MFA "when
    necessary" for ordinary users, which is not a guarantee for any particular app.

    BASELINE ASSESSABLE. Reading Security Defaults needs a role some readers lack (a 403 on a
    tenant where the policy read itself succeeded was seen live). With no Conditional Access policy
    and Security Defaults unreadable, "is MFA required by policy OR by Security Defaults" has NO
    answer: the tenant may well be protected by Security Defaults. `baselineAssessable` is true only
    when Conditional Access was read AND (the Security Defaults state is known OR at least one
    policy is enabled, since the two cannot coexist). A rule that accepts either mechanism gates on
    it, so that case reads Not assessed instead of Fail.

    WHAT IS NOT KEPT. Named locations keep counts, never the IP ranges. Policy rows carry object
    ids (users, groups, roles) exactly as Graph returns them and never a user's name; nothing
    here reads a user or a group.

.PARAMETER TenantID
    Pins the Graph token to the tenant being assessed.

.PARAMETER EntraResources
    The `entraResources` rows of an inventory pass, or $null when none ran.

.PARAMETER EntraQueryOutcomes
    The inventory pass's per-query outcomes (Type, Status, Reason), or $null.

.PARAMETER SkipGraph
    Make no Graph call. Rows the inventory pass already read are still used.

.PARAMETER SkipReason
    The `Reason` reported when nothing could be read because -SkipGraph was set.

.OUTPUTS
    One [pscustomobject], never $null: Collected, Reason, securityDefaultsEnabled ($true / $false /
    $null when unread), baselineAssessable, namedLocationsCollected, policies[], namedLocations[],
    securityDefaultsCoverage[].
#>
function Get-ScoutConditionalAccessPosture {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantID,
        [AllowNull()] [object[]] $EntraResources,
        [AllowNull()] [object[]] $EntraQueryOutcomes,
        [switch] $SkipGraph,
        [string] $SkipReason = 'Microsoft Graph was not queried for this collect.'
    )

    $azureManagementAppId = '797f4846-ba00-4fd7-ba43-dac1f8f63013'   # Windows Azure Service Management API
    $azurePortalAppId = 'c44b4083-3bb0-49c1-b47d-974e53cbdf3c'            # Azure portal (part of Microsoft Admin Portals)
    $azureVirtualDesktopAppId = '9cdead84-a844-4324-93f2-b2e6bb768d07'

    function Get-ScoutCaValue {
        param($InputObject, [string[]] $Path)
        $cursor = $InputObject
        foreach ($segment in $Path) {
            if ($null -eq $cursor) { return $null }
            if ($cursor -is [System.Collections.IDictionary]) {
                $hit = $null
                foreach ($key in $cursor.Keys) { if ([string]$key -ieq $segment) { $hit = $key; break } }
                if ($null -eq $hit) { return $null }
                $cursor = $cursor[$hit]
                continue
            }
            $property = $cursor.PSObject.Properties[$segment]
            if ($null -eq $property) { return $null }
            $cursor = $property.Value
        }
        return $cursor
    }

    # A Graph collection as a flat string[] (absent, null and empty all read as zero items).
    function Get-ScoutCaList {
        param($InputObject, [string[]] $Path)
        $value = Get-ScoutCaValue -InputObject $InputObject -Path $Path
        if ($null -eq $value) { return , [string[]]@() }
        return , [string[]]@(@($value) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    }

    function Test-ScoutCaMember {
        param([string[]] $List, [string[]] $Value)
        foreach ($item in $List) { foreach ($wanted in $Value) { if ($item -ieq $wanted) { return $true } } }
        return $false
    }

    # True when the policy's grant controls REQUIRE one of $Satisfying. Under operator AND any one
    # present control is required; under OR the user may pick any single control, so the policy
    # requires the capability only when EVERY control is one of $Satisfying.
    function Test-ScoutCaGrantEnforced {
        param([string[]] $Controls, [string] $Operator, [string[]] $Satisfying)
        if ($Controls.Count -eq 0) { return $false }
        $present = @($Controls | Where-Object { Test-ScoutCaMember -List $Satisfying -Value @($_) })
        if ($present.Count -eq 0) { return $false }
        if ($Operator -ieq 'AND') { return $true }
        return ($present.Count -eq $Controls.Count)
    }

    function ConvertTo-ScoutCaPolicyRow {
        param($Policy)

        $state = [string](Get-ScoutCaValue $Policy @('state'))
        $includeUsers = Get-ScoutCaList $Policy @('conditions', 'users', 'includeUsers')
        $excludeUsers = Get-ScoutCaList $Policy @('conditions', 'users', 'excludeUsers')
        $excludeGroups = Get-ScoutCaList $Policy @('conditions', 'users', 'excludeGroups')
        $includeRoles = Get-ScoutCaList $Policy @('conditions', 'users', 'includeRoles')
        $includeGuests = Get-ScoutCaValue $Policy @('conditions', 'users', 'includeGuestsOrExternalUsers')
        $includeApps = Get-ScoutCaList $Policy @('conditions', 'applications', 'includeApplications')
        $excludeApps = Get-ScoutCaList $Policy @('conditions', 'applications', 'excludeApplications')
        $clientTypes = Get-ScoutCaList $Policy @('conditions', 'clientAppTypes')
        $signInRisk = Get-ScoutCaList $Policy @('conditions', 'signInRiskLevels')
        $userRisk = Get-ScoutCaList $Policy @('conditions', 'userRiskLevels')
        $includeLocations = Get-ScoutCaList $Policy @('conditions', 'locations', 'includeLocations')
        $excludeLocations = Get-ScoutCaList $Policy @('conditions', 'locations', 'excludeLocations')

        $grant = Get-ScoutCaValue $Policy @('grantControls')
        $operator = [string](Get-ScoutCaValue $grant @('operator'))
        $builtIn = Get-ScoutCaList $grant @('builtInControls')
        $strength = Get-ScoutCaValue $grant @('authenticationStrength')
        $customFactors = Get-ScoutCaList $grant @('customAuthenticationFactors')
        $termsOfUse = Get-ScoutCaList $grant @('termsOfUse')

        # Every control the user could be asked for, so the OR rule can see "MFA or something else".
        $controls = [System.Collections.Generic.List[string]]::new()
        foreach ($control in $builtIn) { $controls.Add($control.ToLowerInvariant()) }
        if ($null -ne $strength) { $controls.Add('authenticationstrength') }
        for ($i = 0; $i -lt $customFactors.Count; $i++) { $controls.Add('customauthenticationfactor') }
        for ($i = 0; $i -lt $termsOfUse.Count; $i++) { $controls.Add('termsofuse') }

        $targetsAllUsers = Test-ScoutCaMember -List $includeUsers -Value @('All')
        $targetsAllApps = Test-ScoutCaMember -List $includeApps -Value @('All')
        $blocks = Test-ScoutCaMember -List $builtIn -Value @('block')

        $managementIncluded = $targetsAllApps -or (Test-ScoutCaMember -List $includeApps -Value @($azureManagementAppId))
        $managementExcluded = Test-ScoutCaMember -List $excludeApps -Value @($azureManagementAppId)
        $portalsIncluded = $targetsAllApps -or (Test-ScoutCaMember -List $includeApps -Value @('MicrosoftAdminPortals', $azurePortalAppId))
        $portalsExcluded = Test-ScoutCaMember -List $excludeApps -Value @('MicrosoftAdminPortals', $azurePortalAppId)
        $avdIncluded = $targetsAllApps -or (Test-ScoutCaMember -List $includeApps -Value @($azureVirtualDesktopAppId))
        $avdExcluded = Test-ScoutCaMember -List $excludeApps -Value @($azureVirtualDesktopAppId)

        [pscustomobject][ordered]@{
            id                              = [string](Get-ScoutCaValue $Policy @('id'))
            displayName                     = [string](Get-ScoutCaValue $Policy @('displayName'))
            state                           = $state
            source                          = 'ConditionalAccess'
            conditions                      = Get-ScoutCaValue $Policy @('conditions')
            grantControls                   = $grant
            sessionControls                 = Get-ScoutCaValue $Policy @('sessionControls')
            enabled                         = ($state -ieq 'enabled')
            reportOnly                      = ($state -ieq 'enabledForReportingButNotEnforced')
            targetsAllUsers                 = $targetsAllUsers
            targetsDirectoryRoles           = ($includeRoles.Count -gt 0)
            targetsGuests                   = ($targetsAllUsers -or (Test-ScoutCaMember -List $includeUsers -Value @('GuestsOrExternalUsers')) -or ($null -ne $includeGuests))
            targetsAllApps                  = $targetsAllApps
            hasAppExclusions                = ($excludeApps.Count -gt 0)
            targetsAzureManagement          = ($managementIncluded -and -not $managementExcluded)
            targetsAdminPortals             = ($portalsIncluded -and -not $portalsExcluded)
            targetsAvd                      = ($avdIncluded -and -not $avdExcluded)
            requiresMfa                     = (Test-ScoutCaGrantEnforced -Controls $controls.ToArray() -Operator $operator -Satisfying @('mfa', 'authenticationstrength'))
            blocks                          = $blocks
            blocksLegacyAuth                = ($blocks -and (Test-ScoutCaMember -List $clientTypes -Value @('exchangeActiveSync', 'other')))
            usesSignInRisk                  = ($signInRisk.Count -gt 0)
            usesUserRisk                    = ($userRisk.Count -gt 0)
            usesLocations                   = (($includeLocations.Count + $excludeLocations.Count) -gt 0)
            requiresCompliantOrHybridDevice = (Test-ScoutCaGrantEnforced -Controls $controls.ToArray() -Operator $operator -Satisfying @('compliantdevice', 'domainjoineddevice'))
            hasExclusions                   = (($excludeUsers.Count + $excludeGroups.Count) -gt 0)
        }
    }

    # Counts only: the address ranges themselves are a customer's network layout, not a posture fact.
    function ConvertTo-ScoutCaNamedLocationRow {
        param($Location)
        $odataType = [string](Get-ScoutCaValue $Location @('@odata.type'))
        $ranges = Get-ScoutCaValue $Location @('ipRanges')
        $countries = Get-ScoutCaValue $Location @('countriesAndRegions')
        $trusted = Get-ScoutCaValue $Location @('isTrusted')
        [pscustomobject][ordered]@{
            id                                 = [string](Get-ScoutCaValue $Location @('id'))
            displayName                        = [string](Get-ScoutCaValue $Location @('displayName'))
            locationType                       = if ($odataType -match '(?i)ipNamedLocation') { 'ip' }
                                                 elseif ($odataType -match '(?i)countryNamedLocation') { 'country' }
                                                 else { 'other' }
            isTrusted                          = if ($null -eq $trusted) { $null } else { [bool]$trusted }
            ipRangeCount                       = @($ranges | Where-Object { $null -ne $_ }).Count
            countryCount                       = @($countries | Where-Object { $null -ne $_ }).Count
            includeUnknownCountriesAndRegions  = [bool](Get-ScoutCaValue $Location @('includeUnknownCountriesAndRegions'))
        }
    }

    function Protect-ScoutCaMessage {
        param([string] $Message)
        if ([string]::IsNullOrWhiteSpace($Message)) { return 'no error text' }
        $clean = [regex]::Replace($Message, '(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b', '{id}')
        $clean = ($clean -replace '\s+', ' ').Trim()
        if ($clean.Length -gt 300) { $clean = $clean.Substring(0, 300) + '...' }
        return $clean
    }

    function New-ScoutCaResult {
        param([bool] $Collected, [string] $Reason, $SecurityDefaultsEnabled, [bool] $NamedLocationsCollected,
            [object[]] $Policies, [object[]] $NamedLocations, [object[]] $SecurityDefaultsCoverage)
        $anyEnabled = @($Policies | Where-Object { $null -ne $_ -and $_.enabled -eq $true }).Count -gt 0
        [pscustomobject][ordered]@{
            Collected                = $Collected
            Reason                   = if ($Collected) { $null } else { $Reason }
            securityDefaultsEnabled  = $SecurityDefaultsEnabled
            baselineAssessable       = [bool]($Collected -and (($null -ne $SecurityDefaultsEnabled) -or $anyEnabled))
            namedLocationsCollected  = $NamedLocationsCollected
            policies                 = @($Policies)
            namedLocations           = @($NamedLocations)
            securityDefaultsCoverage = @($SecurityDefaultsCoverage)
        }
    }

    try {
        $rows = @($EntraResources | Where-Object { $null -ne $_ })
        $outcomes = @($EntraQueryOutcomes | Where-Object { $null -ne $_ })

        function Get-ScoutCaInventorySlice {
            # What the inventory pass knows about one Entra dataset: its rows, and whether it
            # answered (Success/Empty), was refused (Failed/Unavailable/NotAssessed) or never asked.
            param([string] $Type)
            $typed = @($rows | Where-Object {
                    $rowType = if ($_.PSObject.Properties['TYPE']) { $_.TYPE } elseif ($_.PSObject.Properties['type']) { $_.type } else { $null }
                    [string]$rowType -ieq $Type
                })
            $outcome = @($outcomes | Where-Object { $_.PSObject.Properties['Type'] -and [string]$_.Type -ieq $Type }) | Select-Object -Last 1
            $status = if ($outcome -and $outcome.PSObject.Properties['Status']) { [string]$outcome.Status } else { $null }
            $statusReason = if ($outcome -and $outcome.PSObject.Properties['Reason']) { [string]$outcome.Reason } else { $null }
            $answered = ($typed.Count -gt 0) -or ($status -in @('Success', 'Empty'))
            $refused = (-not $answered) -and ($status -in @('Failed', 'Unavailable', 'NotAssessed'))
            [pscustomobject]@{
                Rows = @($typed | ForEach-Object {
                        if ($_.PSObject.Properties['properties']) { $_.properties } elseif ($_.PSObject.Properties['PROPERTIES']) { $_.PROPERTIES } else { $null }
                    } | Where-Object { $null -ne $_ })
                Answered = $answered
                Refused = $refused
                Status = $status
                Reason = $statusReason
            }
        }

        function Invoke-ScoutCaGraph {
            param([string] $Uri)
            if (-not (Get-Command Invoke-AZSCGraphRequest -ErrorAction SilentlyContinue)) {
                throw 'Invoke-AZSCGraphRequest is not available in this session.'
            }
            @(Invoke-AZSCGraphRequest -Uri $Uri -TenantID $TenantID -RequiredScopes @('Policy.Read.All') -SuppressFailureWarning)
        }

        # ---- 1. Conditional Access policies -----------------------------------------------------
        $policyRows = $null
        $failure = $null
        $policySlice = Get-ScoutCaInventorySlice -Type 'entra/conditionalaccesspolicies'
        if ($policySlice.Answered) { $policyRows = @($policySlice.Rows) }
        elseif ($policySlice.Refused) {
            $failure = "The Entra inventory pass could not read Conditional Access policies ($($policySlice.Status)): $(Protect-ScoutCaMessage $policySlice.Reason)"
        }
        elseif ($SkipGraph) { $failure = $SkipReason }
        else {
            try { $policyRows = @(Invoke-ScoutCaGraph -Uri '/v1.0/identity/conditionalAccess/policies') }
            catch {
                $failure = "Microsoft Graph did not return the Conditional Access policies (needs Policy.Read.All and a reader role such as Security Reader or Conditional Access Administrator): $(Protect-ScoutCaMessage $_.Exception.Message)"
            }
        }
        if ($null -eq $policyRows) {
            return New-ScoutCaResult -Collected $false -Reason $failure -SecurityDefaultsEnabled $null `
                -NamedLocationsCollected $false -Policies @() -NamedLocations @() -SecurityDefaultsCoverage @()
        }
        $policies = @($policyRows | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-ScoutCaPolicyRow -Policy $_ })

        # ---- 2. named locations -----------------------------------------------------------------
        $locationRows = $null
        $locationSlice = Get-ScoutCaInventorySlice -Type 'entra/namedlocations'
        if ($locationSlice.Answered) { $locationRows = @($locationSlice.Rows) }
        elseif (-not $locationSlice.Refused -and -not $SkipGraph) {
            try { $locationRows = @(Invoke-ScoutCaGraph -Uri '/v1.0/identity/conditionalAccess/namedLocations') }
            catch { Write-Verbose "Get-ScoutConditionalAccessPosture: named locations were not read: $($_.Exception.Message)" }
        }
        $namedLocations = @(if ($null -ne $locationRows) { $locationRows | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-ScoutCaNamedLocationRow -Location $_ } })

        # ---- 3. Security Defaults ---------------------------------------------------------------
        # The catalog keeps this query disabled for the inventory pass, so an inventory row is
        # unusual; the direct read is the normal source. Read only after the policies were.
        $securityDefaultsEnabled = $null
        $defaultsSlice = Get-ScoutCaInventorySlice -Type 'entra/securitydefaults'
        $defaultsPolicy = $null
        if ($defaultsSlice.Answered -and @($defaultsSlice.Rows).Count -gt 0) { $defaultsPolicy = @($defaultsSlice.Rows)[0] }
        elseif (-not $SkipGraph) {
            try { $defaultsPolicy = Invoke-AZSCGraphRequest -Uri '/v1.0/policies/identitySecurityDefaultsEnforcementPolicy' -TenantID $TenantID -RequiredScopes @('Policy.Read.All') -SinglePage -SuppressFailureWarning }
            catch { Write-Verbose "Get-ScoutConditionalAccessPosture: Security Defaults state was not read: $($_.Exception.Message)" }
        }
        $isEnabled = Get-ScoutCaValue $defaultsPolicy @('isEnabled')
        if ($null -ne $isEnabled) { $securityDefaultsEnabled = [bool]$isEnabled }

        $defaultsCoverage = @()
        if ($securityDefaultsEnabled -eq $true) {
            $defaultsCoverage = @([pscustomobject][ordered]@{
                    id                              = 'securityDefaults'
                    displayName                     = 'Security defaults'
                    state                           = 'enabled'
                    source                          = 'SecurityDefaults'
                    conditions                      = $null
                    grantControls                   = $null
                    sessionControls                 = $null
                    enabled                         = $true
                    reportOnly                      = $false
                    targetsAllUsers                 = $true
                    targetsDirectoryRoles           = $true
                    targetsGuests                   = $true
                    targetsAllApps                  = $false
                    hasAppExclusions                = $false
                    targetsAzureManagement          = $true
                    targetsAdminPortals             = $true
                    targetsAvd                      = $false
                    requiresMfa                     = $true
                    blocks                          = $false
                    blocksLegacyAuth                = $true
                    usesSignInRisk                  = $false
                    usesUserRisk                    = $false
                    usesLocations                   = $false
                    requiresCompliantOrHybridDevice = $false
                    hasExclusions                   = $false
                })
        }

        return New-ScoutCaResult -Collected $true -Reason $null -SecurityDefaultsEnabled $securityDefaultsEnabled `
            -NamedLocationsCollected ($null -ne $locationRows) -Policies $policies -NamedLocations $namedLocations `
            -SecurityDefaultsCoverage $defaultsCoverage
    }
    catch {
        return New-ScoutCaResult -Collected $false -Reason ("Conditional Access collection failed: " + (Protect-ScoutCaMessage $_.Exception.Message)) `
            -SecurityDefaultsEnabled $null -NamedLocationsCollected $false -Policies @() -NamedLocations @() -SecurityDefaultsCoverage @()
    }
}
