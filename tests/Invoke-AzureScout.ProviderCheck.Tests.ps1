#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:Source = Get-Content -LiteralPath (Join-Path $script:Root 'src/Invoke-AzureScout.ps1') -Raw
    $start = $script:Source.IndexOf('if ($CheckResourceProviders.IsPresent)')
    $end = $script:Source.IndexOf('# Run isolation (AB#331)', $start)
    $script:ProviderBlock = $script:Source.Substring($start, $end - $start)
}

Describe 'Invoke-AzureScout -CheckResourceProviders' {
    It 'reads every provider registration with one listing per subscription' {
        # One call per namespace took about six seconds apiece on a live tenant, so ten
        # namespaces across nine subscriptions held the run for nine minutes before collection.
        $script:ProviderBlock | Should -Match 'Get-AzResourceProvider -ListAvailable'
        $script:ProviderBlock | Should -Not -Match 'Get-AzResourceProvider -ProviderNamespace'
    }

    It 'treats a namespace missing from the listing as not registered' {
        $script:ProviderBlock | Should -Match "else \{ 'NotRegistered' \}"
    }

    It 'reads only the ten needed namespaces, concurrently, naming the subscription in the path' {
        # Live 42-subscription tenant: the sequential full listing (6.4 MB, ~10 s per subscription)
        # took 4 m 45 s; ten single-namespace GETs, 16 at a time, took 75 s with the same 226 notes.
        $script:ProviderBlock | Should -Match 'ForEach-Object -ThrottleLimit 16 -Parallel'
        $script:ProviderBlock | Should -Match '/subscriptions/\$\(\$item\.Id\)/providers/\$\(\$item\.Provider\)\?api-version=2021-04-01'
        $script:ProviderBlock | Should -Match "if \(\`$status -eq 404\) \{ \[pscustomobject\]@\{ Id = \`$item\.Id; Provider = \`$item\.Provider; State = 'NotRegistered'"
    }

    It 'keeps the sequential check for test stand-ins of the Az REST cmdlet' {
        $script:ProviderBlock | Should -Match "\`$restCommand\.CommandType -eq 'Cmdlet'"
        $script:ProviderBlock | Should -Match 'Invoke-AZSCInSubscriptionContext -Subscription \$Subscriptions'
    }
}

Describe 'Test-AZSCPS platform message' {
    It 'does not call PowerShell 7 on Windows "PowerShell Desktop"' {
        $text = Get-Content -LiteralPath (Join-Path $script:Root 'src/Test-AZTIPS.ps1') -Raw
        $text | Should -Not -Match 'Write-Host "PowerShell Desktop Identified\.'
        $text | Should -Match "\`$PlatOS\s+= 'PowerShell Desktop'"
    }
}
