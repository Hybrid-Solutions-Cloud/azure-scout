#Requires -Version 7.0
#Requires -Modules Pester

<#
    Excel gap-inventory workbook v2 (Task AB#6857, User Story AB#6443, Feature AB#6449,
    Epic AB#6450).

    The reference workbook attached to AB#6443 is useful because of two things the v1 export
    had neither of: a Cover carrying scope, a four-value verdict legend and a contents index;
    and a per-row Verdict on every gap tab. That column is what turns "149 non-group Owner
    assignments" into "141 deliberate vending service principals plus 8 humans".

    Skips cleanly when ImportExcel is absent, the same way the renderer itself degrades.
#>

# Probed at FILE scope, not inside BeforeAll: Pester evaluates a Describe's -Skip: during
# discovery, which runs before any BeforeAll body. Setting this in BeforeAll left it $null at
# the moment every -Skip: was read, so the whole file silently skipped.
$HasImportExcel = [bool](Get-Module -ListAvailable -Name ImportExcel)

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/assess/engine/Get-GovernanceDomainScore.ps1"
    . "$root/src/report/Build-ScoutReportModel.ps1"
    . "$root/src/report/renderers/Export-Excel.ps1"

    $Script:HasImportExcel = [bool](Get-Module -ListAvailable -Name ImportExcel)

    function New-Finding {
        param(
            [string] $Id, [string] $Area, [string] $Status, [string] $Severity = 'high',
            [int] $EvidenceCount = 0, $Evidence = @(), [bool] $Truncated = $false,
            [string] $Title = 'A control', $TargetState = $null, $Owner = $null, $Phase = $null
        )
        [pscustomobject]@{
            Id = $Id; Title = $Title; Framework = 'Cloud Governance'; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = $EvidenceCount; Evidence = $Evidence
            EvidenceTruncated = $Truncated; EvidenceCap = 25
            Remediation = "Remediate $Id."; Manual = $false
            TargetState = $TargetState; Owner = $Owner; Effort = 'M'; Phase = $Phase
        }
    }

    $Script:Collect = [pscustomobject]@{
        subscriptions = @([pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; name = 'sub-prod'; state = 'Enabled' })
        _meta = [pscustomobject]@{ scope = 'All'; managementGroupId = 'mg-root'; tenantId = 'tenant-abc' }
    }

    $evidence = @(
        [pscustomobject]@{
            id = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-prod/providers/Microsoft.Storage/storageAccounts/stpayments01'
            name = 'stpayments01'; type = 'Microsoft.Storage/storageAccounts'; location = 'westus'
        }
        [pscustomobject]@{
            id = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sandbox-dev/providers/Microsoft.Storage/storageAccounts/stsbx01'
            name = 'stsbx01'; type = 'Microsoft.Storage/storageAccounts'; location = 'westus'
        }
    )

    $Script:Scored = [pscustomobject]@{
        GeneratedOn = '2026-08-01T10:00:00.0000000Z'
        Frameworks = @([pscustomobject]@{ Framework = 'Cloud Governance'; Score = 50; Version = 'CAF Govern' })
        Areas = @([pscustomobject]@{
                Framework = 'Cloud Governance'; Area = 'Security'; Score = 50; Weight = 1.0
                Pass = 1; Partial = 0; Fail = 1; Manual = 0; Unknown = 0; Error = 0
            })
        Gaps = @(); Manual = @(); Errors = @()
        Findings = @(
            New-Finding -Id 'SEC-01' -Area 'Security' -Status 'Fail' -Severity 'high' `
                -EvidenceCount 198 -Evidence $evidence -Truncated $true `
                -Title 'Storage accounts should disable public network access' `
                -TargetState 'PublicNetworkAccess=Disabled' -Owner 'Network Engineering' -Phase 1
            New-Finding -Id 'SEC-02' -Area 'Security' -Status 'Pass' -EvidenceCount 9 -Title 'Purge protection'
        )
    }

    $Script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-xlv2-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $Script:OutDir -Force | Out-Null
    $Script:Model = Build-ScoutReportModel -Findings $Script:Scored -Collect $Script:Collect -RunId 'run-v2'

    if ($Script:HasImportExcel) {
        Export-Excel -Findings $Script:Scored -Collect $Script:Collect -OutputPath $Script:OutDir -Model $Script:Model
        $Script:Xlsx = Join-Path $Script:OutDir 'assessment_evidence.xlsx'
        Import-Module ImportExcel
        $Script:Sheets = @((Get-ExcelSheetInfo -Path $Script:Xlsx).Name)
    }
}

AfterAll {
    if ($Script:OutDir -and (Test-Path $Script:OutDir)) {
        Remove-Item $Script:OutDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Excel v2 workbook structure' -Skip:(-not $HasImportExcel) {
    It 'writes the workbook' {
        Test-Path $Script:Xlsx | Should -BeTrue
    }

    It 'carries a Cover sheet' {
        $Script:Sheets | Should -Contain 'Cover'
    }

    It 'carries a consolidated Gap_Register sheet' {
        $Script:Sheets | Should -Contain 'Gap_Register'
    }

    It 'carries one sheet per gap that has resource-level evidence' {
        ($Script:Sheets | Where-Object { $_ -like 'G01*' }) | Should -Not -BeNullOrEmpty
    }

    It 'retains the pre-v2 per-area evidence sheets rather than replacing them' {
        $Script:Sheets | Should -Contain 'Security'
    }
}

Describe 'Excel v2 Cover sheet' -Skip:(-not $HasImportExcel) {
    BeforeAll {
        $Script:Cover = @(Import-Excel -Path $Script:Xlsx -WorksheetName 'Cover')
        $Script:CoverText = ($Script:Cover | ForEach-Object { "$($_.Item) $($_.Value)" }) -join "`n"
    }

    It 'publishes the four-value verdict legend' -ForEach @(
        @{ Verdict = 'Real - investigate' }
        @{ Verdict = 'Platform-required - deliberate pattern' }
        @{ Verdict = 'Sandbox - out of scope by design' }
        @{ Verdict = 'Inherited from legacy' }
    ) {
        $Script:CoverText | Should -BeLike "*$Verdict*"
    }

    It 'says the verdict is heuristic and still needs human review' {
        $Script:CoverText | Should -BeLike '*NOT a confirmed judgement*'
    }

    It 'carries scope, source and classification' {
        $Script:CoverText | Should -BeLike '*mg-root*'
        $Script:CoverText | Should -BeLike '*No tenant state was modified*'
        $Script:CoverText | Should -BeLike '*CONFIDENTIAL*'
    }

    It 'carries a contents index naming each gap tab with its verdict mix' {
        $Script:CoverText | Should -BeLike '*CONTENTS*'
        $Script:CoverText | Should -BeLike '*G01*'
        $Script:CoverText | Should -BeLike '*Real - investigate*'
    }

    It 'states retained rows against the affected total where evidence was truncated' {
        # A contents index that reads "2" for a gap affecting 198 resources is a lie of
        # omission, and the index is exactly where a reader looks for a total.
        $Script:CoverText | Should -BeLike '*2 of 198 affected*'
    }

    It 'reports domains that could not be assessed rather than omitting them' {
        $Script:CoverText | Should -BeLike '*neither a pass nor a failure is claimed*'
    }
}

Describe 'Excel v2 gap sheets' -Skip:(-not $HasImportExcel) {
    BeforeAll {
        $sheet = $Script:Sheets | Where-Object { $_ -like 'G01*' } | Select-Object -First 1
        $Script:GapRows = @(Import-Excel -Path $Script:Xlsx -WorksheetName $sheet)
    }

    It 'is one row per affected resource' {
        $Script:GapRows.Count | Should -Be 2
    }

    It 'carries the full ARM resource id, not just the name' {
        $Script:GapRows[0].ResourceId | Should -BeLike '/subscriptions/*/providers/Microsoft.Storage/storageAccounts/*'
    }

    It 'carries the subscription and resource group the resource lives in' {
        $Script:GapRows[0].SubscriptionName | Should -Be 'sub-prod'
        $Script:GapRows[0].ResourceGroup | Should -Be 'rg-prod'
    }

    It 'carries a per-row Verdict and stamps its source as heuristic' {
        $Script:GapRows[0].Verdict | Should -Not -BeNullOrEmpty
        $Script:GapRows[0].VerdictSource | Should -Be 'heuristic'
    }

    It 'triages the sandbox resource differently from the production one' {
        # The whole value of the column: two rows of the same finding, sorted apart.
        $prod = $Script:GapRows | Where-Object ResourceName -eq 'stpayments01'
        $sbx = $Script:GapRows | Where-Object ResourceName -eq 'stsbx01'
        $prod.Verdict | Should -Be 'Real - investigate'
        $sbx.Verdict | Should -Be 'Sandbox - out of scope by design'
    }

    It 'carries the closure action and owner on every row' {
        $Script:GapRows[0].ClosureAction | Should -Be 'Remediate SEC-01.'
        $Script:GapRows[0].Owner | Should -Be 'Network Engineering'
    }
}

Describe 'Excel v2 Gap_Register sheet' -Skip:(-not $HasImportExcel) {
    BeforeAll {
        $Script:Register = @(Import-Excel -Path $Script:Xlsx -WorksheetName 'Gap_Register')
    }

    It 'separates the affected total from the rows actually retained' {
        $row = $Script:Register | Where-Object RuleId -eq 'SEC-01'
        [int]$row.AffectedTotal | Should -Be 198
        [int]$row.RowsRetained | Should -Be 2
        "$($row.EvidenceTruncated)" | Should -Be 'True'
    }

    It 'carries the target state, closure action, owner, effort and phase' {
        $row = $Script:Register | Where-Object RuleId -eq 'SEC-01'
        $row.TargetState | Should -Be 'PublicNetworkAccess=Disabled'
        $row.Owner | Should -Be 'Network Engineering'
        $row.Effort | Should -Be 'M'
        [int]$row.Phase | Should -Be 1
    }
}

Describe 'Excel v2 degrades rather than failing' -Skip:(-not $HasImportExcel) {
    It 'writes a workbook when there are no gaps at all' {
        $scored = [pscustomobject]@{
            GeneratedOn = '2026-08-01T10:00:00.0000000Z'
            Frameworks = @(); Areas = @(); Gaps = @(); Manual = @(); Errors = @(); Findings = @()
        }
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-xlv2e-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            { Export-Excel -Findings $scored -Collect ([pscustomobject]@{}) -OutputPath $dir } | Should -Not -Throw
            (Get-ExcelSheetInfo -Path (Join-Path $dir 'assessment_evidence.xlsx')).Name | Should -Contain 'Cover'
        }
        finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
