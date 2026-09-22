#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#7279 -- production remote-command compatibility and test-ownership gate.

    Azure Scout has broad collector/output golden coverage, but a mock can accidentally expose a
    parameter that the real Az cmdlet does not support. That exact failure escaped in v3.12.2:
    the ARM-child test double invented Invoke-AzRestMethod -SkipHttpErrorCheck, so every collector
    was green while the supported Az.Accounts cmdlet rejected the live call before sending it.

    This gate works from the production AST rather than a hand-maintained list. Every literal
    parameter used on an installed Az cmdlet or PowerShell HTTP cmdlet must exist in the real
    command metadata, every function containing a remote call must have a test owner, and every
    remote command must be shadowed somewhere in the hermetic test suite. A newly added remote
    call therefore cannot silently bypass compatibility and offline-execution coverage.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:SourceRoot = Join-Path -Path $script:RepoRoot -ChildPath 'src'
    $script:TestFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File)
    $script:TestText = ($script:TestFiles | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw
    }) -join "`n"

    $SourceFiles = @(Get-ChildItem -LiteralPath $script:SourceRoot -Recurse -Filter '*.ps1' -File)
    $LocalFunctions = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($File in $SourceFiles) {
        $LocalTokens = $null
        $LocalErrors = $null
        $LocalAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $File.FullName,
            [ref]$LocalTokens,
            [ref]$LocalErrors
        )
        foreach ($Definition in $LocalAst.FindAll({
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)) {
            $null = $LocalFunctions.Add($Definition.Name)
        }
    }
    $CommandCache = @{}

    function Get-ContainingFunctionName {
        param([System.Management.Automation.Language.Ast]$Ast)

        $Current = $Ast.Parent
        $Owner = $null
        while ($Current) {
            if ($Current -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                # A helper declared inside a public collector is an implementation detail. The
                # outer function is the independently invokable/testable unit that owns its call.
                $Owner = $Current.Name
            }
            $Current = $Current.Parent
        }
        return $Owner
    }

    $script:RemoteCalls = @(
        foreach ($File in $SourceFiles) {
            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $File.FullName,
                [ref]$Tokens,
                [ref]$Errors
            )
            if ($Errors.Count -gt 0) {
                throw "Cannot build the remote-command contract because '$($File.FullName)' does not parse."
            }

            foreach ($CommandAst in $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst]
            }, $true)) {
                $Name = $CommandAst.GetCommandName()
                if (-not $Name) { continue }

                $LooksRemote = $Name -match '^(?:Get|Set|Connect|Search|Invoke)-Az' -or
                    $Name -in @('Invoke-RestMethod', 'Invoke-WebRequest')
                if (-not $LooksRemote -or $LocalFunctions.Contains($Name)) { continue }

                $CacheKey = $Name.ToLowerInvariant()
                if (-not $CommandCache.ContainsKey($CacheKey)) {
                    $CommandCache[$CacheKey] = @(Get-Command -Name $Name -All -ErrorAction SilentlyContinue | Where-Object {
                        ($_.CommandType -eq 'Cmdlet' -and $_.Source -like 'Az.*') -or
                        ($_.CommandType -eq 'Cmdlet' -and $_.Source -eq 'Microsoft.PowerShell.Utility' -and
                            $_.Name -in @('Invoke-RestMethod', 'Invoke-WebRequest'))
                    } | Select-Object -First 1)
                }
                $Resolved = @($CommandCache[$CacheKey])
                if ($Resolved.Count -eq 0) { continue }

                [pscustomobject]@{
                    File       = $File.FullName
                    Relative   = $File.FullName.Substring($script:RepoRoot.Length + 1)
                    Line       = $CommandAst.Extent.StartLineNumber
                    Function   = Get-ContainingFunctionName -Ast $CommandAst
                    Command    = $Resolved[0]
                    Parameters = @($CommandAst.CommandElements | Where-Object {
                        $_ -is [System.Management.Automation.Language.CommandParameterAst]
                    } | ForEach-Object ParameterName)
                }
            }
        }
    )
}

Describe 'Production remote-command compatibility' {
    It 'discovers production Az/HTTP call sites' {
        $script:RemoteCalls.Count | Should -BeGreaterThan 25
        @($script:RemoteCalls.Function | Where-Object { -not $_ }).Count |
            Should -Be 0 -Because 'remote calls must be owned by named, independently testable functions'
    }

    It 'uses only parameters supported by each installed real command' {
        $Violations = foreach ($Call in $script:RemoteCalls) {
            foreach ($Parameter in $Call.Parameters) {
                $Supported = $Call.Command.Parameters.ContainsKey($Parameter) -or @(
                    $Call.Command.Parameters.Values | Where-Object {
                        $_.Aliases -contains $Parameter
                    }
                ).Count -gt 0
                if (-not $Supported) {
                    "$($Call.Relative):$($Call.Line) $($Call.Command.Name) -$Parameter " +
                        "is absent from $($Call.Command.Source)"
                }
            }
        }
        @($Violations) | Should -BeNullOrEmpty
    }

    It 'has an explicit test owner for every remote-calling function' {
        $Unowned = foreach ($Call in $script:RemoteCalls) {
            $OwnerPattern = '(?im)(?:^|[^A-Za-z0-9_-])' +
                [regex]::Escape($Call.Function) + '(?:$|[^A-Za-z0-9_-])'
            if ($script:TestText -notmatch $OwnerPattern) {
                "$($Call.Relative):$($Call.Line) $($Call.Function) -> $($Call.Command.Name)"
            }
        }
        @($Unowned | Sort-Object -Unique) | Should -BeNullOrEmpty
    }

    It 'shadows every remote command in the offline test suite' {
        $Unshadowed = foreach ($RemoteCommand in ($script:RemoteCalls.Command.Name | Sort-Object -Unique)) {
            $ShadowPattern = '(?im)^\s*(?:Mock\s+(?:-[A-Za-z]+\s+)*|function\s+(?:global:|script:)?|Set-Alias\s+(?:-[A-Za-z]+\s+)*)' +
                [regex]::Escape($RemoteCommand) + '(?:\s|\{|$)'
            if ($script:TestText -notmatch $ShadowPattern) { $RemoteCommand }
        }
        @($Unshadowed) | Should -BeNullOrEmpty
    }
}
