#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Focused regression tests for the collector audit and converter boundary (AB#5923/5924).

    The classifier must distinguish command names structurally:
      * local Get-AZSC helpers are data shaping, not Get-Az network calls;
      * Search-AzGraph is live access despite not starting with Get/Invoke;
      * New-Object is ordinary shaping unless its AST contains -Com/-ComObject.

    The converter must enforce the same boundary before it lifts any source into a definition.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:AuditScript = Join-Path $script:RepoRoot 'scripts' 'Invoke-CollectorAudit.ps1'
    $script:ConverterScript = Join-Path $script:RepoRoot 'scripts' 'ConvertTo-ScoutCollectorDefinition.ps1'
    $script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("azsc-collector-tooling-" + [guid]::NewGuid().ToString('N'))
    $script:InventoryRoot = Join-Path $script:Sandbox 'Modules' 'Public' 'InventoryModules'
    $script:CategoryRoot = Join-Path $script:InventoryRoot 'Test'
    $script:AuditJson = Join-Path $script:Sandbox 'collector-audit.json'
    New-Item -ItemType Directory -Path $script:CategoryRoot -Force | Out-Null

    function New-ToolingCollector {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [string[]] $ProcessingStatements
        )

        $Path = Join-Path $script:CategoryRoot "$Name.ps1"
        $Lines = @(
            'param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, $TableStyle, $Unsupported)'
            "if (`$Task -eq 'Processing') {"
            "    `$Rows = `$Resources | Where-Object { `$_.TYPE -eq 'microsoft.test/widgets' }"
        )
        $Lines += @($ProcessingStatements | ForEach-Object { "    $_" })
        $Lines += @(
            '    $tmp = foreach ($1 in $Rows) {'
            "        `$obj = @{ 'ID' = `$1.id; 'Name' = `$1.name }"
            '        $obj'
            '    }'
            '    return $tmp'
            '} else {'
            '    $Exc = [System.Collections.Generic.List[string]]::new()'
            "    [void]`$Exc.Add('Name')"
            "    `$SmaResources | Select-Object -Property `$Exc | Export-Excel -Path `$File -WorksheetName '$Name' -TableName '${Name}Table_1'"
            '}'
        )
        Set-Content -LiteralPath $Path -Value $Lines -Encoding utf8
        return $Path
    }

    $script:SafePath = New-ToolingCollector -Name 'SafeHelpers' -ProcessingStatements @(
        "`$null = Get-AZSCSafeProperty -InputObject `$Rows -Path 'name' -Enumerate"
        "`$null = Get-AZSCIdSegment -Id '/subscriptions/sub/resourceGroups/rg/providers/microsoft.test/widgets/one' -Index 8"
        "`$null = Get-AZSCCollectedValue -InputObject `$Rows -Name 'name'"
        '$null = New-Object System.Collections.Generic.List[string]'
    )
    $script:GraphPath = New-ToolingCollector -Name 'GraphAccess' -ProcessingStatements @(
        "`$null = Search-AzGraph -Query 'resources | take 1'"
    )
    $script:ComPath = New-ToolingCollector -Name 'ComAccess' -ProcessingStatements @(
        "`$null = New-Object -Com 'HTMLFile'"
    )

    $null = & $script:AuditScript -InventoryRoot $script:InventoryRoot -OutputJson $script:AuditJson
    $script:Audit = @(Get-Content -LiteralPath $script:AuditJson -Raw | ConvertFrom-Json)
}

AfterAll {
    if (Test-Path -LiteralPath $script:Sandbox) {
        Remove-Item -LiteralPath $script:Sandbox -Recurse -Force
    }
}

Describe 'Collector audit external-access classification' {
    It 'does not classify the three in-process Get-AZSC helpers or ordinary New-Object as live access' {
        $Record = $script:Audit | Where-Object Name -eq 'SafeHelpers'
        $Record.Classification | Should -Be 'PureShaping'
        @($Record.ExternalCalls).Count | Should -Be 0
    }

    It 'detects Search-AzGraph as live access' {
        $Record = $script:Audit | Where-Object Name -eq 'GraphAccess'
        $Record.Classification | Should -Be 'EscapeHatch'
        @($Record.ExternalCalls) | Should -Contain 'Search-AzGraph'
    }

    It 'detects New-Object -Com as live access without banning ordinary New-Object' {
        $Record = $script:Audit | Where-Object Name -eq 'ComAccess'
        $Record.Classification | Should -Be 'EscapeHatch'
        @($Record.ExternalCalls) | Should -Contain 'New-Object -Com'
    }
}

Describe 'Collector converter external-access guard' {
    It 'still converts a collector that uses only the three in-process helpers' {
        $Definition = & $script:ConverterScript -CollectorPath $script:SafePath -Show
        ($Definition -join "`n") | Should -Match "SourceCollector"
    }

    It '<Name> refuses conversion before emitting a definition' -ForEach @(
        @{ Name = 'Search-AzGraph'; PathVariable = 'GraphPath'; Expected = 'Search-AzGraph' }
        @{ Name = 'New-Object -Com'; PathVariable = 'ComPath'; Expected = 'New-Object -Com' }
    ) {
        $CollectorPath = Get-Variable -Name $PathVariable -Scope Script -ValueOnly
        { & $script:ConverterScript -CollectorPath $CollectorPath -Show } |
            Should -Throw -ExpectedMessage "*live external access*$Expected*"
    }
}
