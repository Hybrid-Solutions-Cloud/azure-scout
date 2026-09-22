#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot=Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/collect/Get-ScoutOktaEvidence.ps1')
    function New-OktaResponse {
        param([object]$Body=@(),[hashtable]$Headers=@{})
        [pscustomobject]@{StatusCode=200;Content=($Body|ConvertTo-Json -Depth 30 -Compress);Headers=$Headers}
    }
}

Describe 'Get-ScoutOktaEvidence' {
    BeforeEach {
        $script:oktaCalls=[System.Collections.Generic.List[string]]::new()
        function global:Invoke-WebRequest {
            param($Uri,$Method,$Headers,$ErrorAction)
            $null=$Method,$ErrorAction
            $Headers.Authorization | Should -Match '^SSWS '
            $script:oktaCalls.Add($Uri)
            switch -Regex ($Uri) {
                '/api/v1/apps\?' { return New-OktaResponse @([pscustomobject]@{id='app-one';name='office365';label='Microsoft Office 365';status='ACTIVE';signOnMode='WS_FEDERATION';settings=[pscustomobject]@{app=[pscustomobject]@{emOptInStatus='ENABLED'}}}) }
                '/api/v1/apps/app-one/groups' { return New-OktaResponse @([pscustomobject]@{id='group-one';profile=[pscustomobject]@{name='Office Users'}}) }
                '/api/v1/apps/app-one/users' { return New-OktaResponse @([pscustomobject]@{id='user-one';scope='USER'}) }
                '/api/v1/policies\?' { return New-OktaResponse @([pscustomobject]@{id='policy-one';name='Authentication policy';type='OKTA_SIGN_ON';status='ACTIVE';priority=1;conditions=[pscustomobject]@{};settings=[pscustomobject]@{}}) }
                '/api/v1/policies/policy-one/rules' { return New-OktaResponse @([pscustomobject]@{id='rule-one';name='Require MFA';status='ACTIVE';priority=1;conditions=[pscustomobject]@{};actions=[pscustomobject]@{signon=[pscustomobject]@{access='ALLOW';factorPromptMode='ALWAYS'}}}) }
                '/api/v1/zones' { return New-OktaResponse @([pscustomobject]@{id='zone-one';name='Trusted';type='IP';status='ACTIVE'}) }
                '/api/v1/idps' { return New-OktaResponse @() }
                '/api/v1/threats/configuration' { return New-OktaResponse ([pscustomobject]@{action='block';excludeZones=@()}) }
                '/api/v1/directories\?' { return New-OktaResponse @([pscustomobject]@{id='directory-one';name='Gentherm AD';type='ACTIVE_DIRECTORY'}) }
                '/api/v1/directories/directory-one/agents' { return New-OktaResponse @([pscustomobject]@{id='agent-one';status='ACTIVE'}) }
                '/api/v1/meta/schemas/user/default' { return New-OktaResponse ([pscustomobject]@{id='schema-one';definitions=[pscustomobject]@{}}) }
                '/api/v1/logs\?' { return New-OktaResponse @([pscustomobject]@{uuid='event-one';eventType='user.authentication.sso';target=@([pscustomobject]@{id='app-one';type='AppInstance';displayName='Microsoft Office 365'})}) }
                '/api/v1/users\?' { return New-OktaResponse @([pscustomobject]@{id='user-one';status='ACTIVE';profile=[pscustomobject]@{login='person@example.test'}}) }
                '/api/v1/users/user-one/factors' { return New-OktaResponse @([pscustomobject]@{id='factor-one';factorType='webauthn';provider='FIDO';status='ACTIVE'}) }
                '/api/v1/users/user-one/roles' { return New-OktaResponse @([pscustomobject]@{id='role-one';type='SUPER_ADMIN';status='ACTIVE';assignmentType='USER'}) }
                default { throw "Unexpected Okta request $Uri" }
            }
        }
    }
    AfterEach {Remove-Item Function:global:Invoke-WebRequest -Force -ErrorAction SilentlyContinue}

    It 'collects federation, policy, factor, and administrator evidence read-only' {
        $token=ConvertTo-SecureString 'unit-test-token' -AsPlainText -Force
        $result=Get-ScoutOktaEvidence -OrganizationUrl 'https://example.okta.test' -ApiToken $token
        @($result.Resources|Where-Object type -eq 'AZSC/Okta/Applications').Count|Should -Be 1
        @($result.Resources|Where-Object type -eq 'AZSC/Okta/MicrosoftAppGroupAssignments').Count|Should -Be 1
        @($result.Resources|Where-Object type -eq 'AZSC/Okta/Policies').Count|Should -Be 4
        @($result.Resources|Where-Object type -eq 'AZSC/Okta/UserFactors').Count|Should -Be 1
        @($result.Resources|Where-Object type -eq 'AZSC/Okta/FactorEnrollmentSummary').Count|Should -Be 1
        @($result.Resources|Where-Object type -eq 'AZSC/Okta/AdminRoleSummary').properties.AssignmentCount|Should -Be 1
        @($result.Resources|Where-Object type -eq 'AZSC/Okta/ApplicationUsageSummary').properties.SignOnCount30Days|Should -Be 1
        @($result.Resources|Where-Object type -eq 'AZSC/Okta/Directories').Count|Should -Be 1
        @($script:oktaCalls|Where-Object {$_ -match '/factors$'}).Count|Should -Be 1
        @($script:oktaCalls|Where-Object {$_ -match '/roles$'}).Count|Should -Be 1
    }

    It 'never persists the Okta token in raw evidence, health, or source operations' {
        $tokenText='unit-test-token'
        $result=Get-ScoutOktaEvidence -OrganizationUrl 'https://example.okta.test' -ApiToken (ConvertTo-SecureString $tokenText -AsPlainText -Force)
        ($result|ConvertTo-Json -Depth 50) | Should -Not -Match [regex]::Escape($tokenText)
    }

    It 'rejects a non-TLS Okta organization URL before making a request' {
        {Get-ScoutOktaEvidence -OrganizationUrl 'http://example.okta.test' -ApiToken (ConvertTo-SecureString 'x' -AsPlainText -Force)} | Should -Throw
        $script:oktaCalls.Count | Should -Be 0
    }

    It 'ships importable Okta report manifests' {
        foreach($name in 'OktaFederation','OktaAuthenticationPolicies','OktaFactorEnrollment','OktaAdministrators','OktaApplicationUsage'){
            {Import-PowerShellDataFile (Join-Path $script:RepoRoot "manifests/collectors/Identity/$name.psd1")}|Should -Not -Throw
        }
    }

    It 'emits an explicit zero-factor summary when active users have no enrolled factor' {
        $original = ${function:global:Invoke-WebRequest}
        function global:Invoke-WebRequest {
            param($Uri,$Method,$Headers,$ErrorAction)
            if ($Uri -match '/api/v1/users/user-one/factors') { return New-OktaResponse @() }
            & $original -Uri $Uri -Method $Method -Headers $Headers -ErrorAction $ErrorAction
        }
        $result=Get-ScoutOktaEvidence -OrganizationUrl 'https://example.okta.test' -ApiToken (ConvertTo-SecureString 'x' -AsPlainText -Force)
        $summary=@($result.Resources|Where-Object type -eq 'AZSC/Okta/FactorEnrollmentSummary')
        $summary.Count|Should -Be 1
        $summary[0].properties.ActiveUsersWithoutFactorCount|Should -Be 1
    }
}
