#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: everything that can be deployed in Azure is discovered AND filed under one of the 18
    categories. These tests hold the category map to Azure's provider catalogue, the collectors,
    the resolver's precedence, the discovery index and the generated documentation.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . "$script:RepoRoot/src/pipeline/Get-ScoutResourceCategory.ps1"
    $script:Map = Import-PowerShellDataFile "$script:RepoRoot/manifests/resource-categories.psd1"
    $script:Categories = @(Get-ChildItem "$script:RepoRoot/manifests/collectors" -Directory | ForEach-Object Name | Sort-Object)
}

Describe 'Resource category map' {
    It 'uses exactly the 18 collector categories' {
        @($script:Map.Categories | Sort-Object) | Should -Be $script:Categories
        foreach ($entry in @($script:Map.Namespaces.GetEnumerator()) + @($script:Map.Types.GetEnumerator())) {
            $entry.Value | Should -BeIn $script:Map.Categories -Because $entry.Name
        }
    }

    It 'gives every namespace in Azure''s provider catalogue a category' {
        $catalogue = Get-Content "$script:RepoRoot/manifests/azure-provider-types.json" -Raw | ConvertFrom-Json
        $missing = @($catalogue.Types | ForEach-Object { (([string]$_) -split '/')[0].ToLowerInvariant() } | Sort-Object -Unique |
                Where-Object { -not $script:Map.Namespaces.ContainsKey($_) })
        $missing | Should -BeNullOrEmpty
    }

    It 'gives every namespace a collector reads a category' {
        $missing = foreach ($manifest in Get-ChildItem "$script:RepoRoot/manifests/collectors" -Recurse -Filter '*.psd1') {
            foreach ($type in @((Import-PowerShellDataFile $manifest.FullName).ResourceTypes)) {
                $namespace = (([string]$type) -split '/')[0].ToLowerInvariant()
                if ($namespace -notmatch '^(azsc|\*)' -and -not $script:Map.Namespaces.ContainsKey($namespace)) { "$namespace ($($manifest.BaseName))" }
            }
        }
        @($missing) | Should -BeNullOrEmpty
    }

    It 'stores keys in lower case so lookups and docs agree' {
        @($script:Map.Namespaces.Keys + $script:Map.Types.Keys | Where-Object { $_ -cne ([string]$_).ToLowerInvariant() }) | Should -BeNullOrEmpty
    }
}

Describe 'Get-ScoutResourceCategory' {
    It 'lets the collector that reads a type decide' {
        $r = Get-ScoutResourceCategory -Type 'microsoft.aad/domainservices' -CollectorCategories @('Security')
        $r.Category | Should -Be 'Security'
        $r.Source | Should -Be 'Collector'
    }

    It 'uses the longest type entry, which also covers child types' {
        (Get-ScoutResourceCategory -Type 'microsoft.authorization/roleassignments').Category | Should -Be 'Identity'
        (Get-ScoutResourceCategory -Type 'microsoft.authorization/policyassignments').Category | Should -Be 'Management'
        $patch = Get-ScoutResourceCategory -Type 'microsoft.compute/virtualmachines/patchinstallationresults/softwarepatches'
        $patch.Category | Should -Be 'Management'
        $patch.Source | Should -Be 'Type'
        (Get-ScoutResourceCategory -Type 'microsoft.compute/virtualmachines/extensions').Category | Should -Be 'Compute'
        (Get-ScoutResourceCategory -Type 'Microsoft.Compute/Disks').Category | Should -Be 'Storage'
    }

    It 'falls back to the namespace, then to General marked as Fallback' {
        $ns = Get-ScoutResourceCategory -Type 'microsoft.managedservices/registrationdefinitions'
        $ns.Category | Should -Be 'Management'
        $ns.Source | Should -Be 'Namespace'
        (Get-ScoutResourceCategory -Type 'entra/signins').Category | Should -Be 'Identity'
        $unknown = Get-ScoutResourceCategory -Type 'contoso.brandnew/widgets'
        $unknown.Category | Should -Be 'General'
        $unknown.Source | Should -Be 'Fallback'
    }
}

Describe 'Discovery index carries the category' {
    BeforeAll {
        . "$script:RepoRoot/src/pipeline/Get-ScoutResourceCompleteness.ps1"
    }

    It 'files every resource under a category and counts them in the summary' {
        $resources = @(
            [pscustomobject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/ra'; name = 'ra'; type = 'microsoft.authorization/roleassignments'; subscriptionId = 's'; properties = [pscustomobject]@{ principalId = 'p' } }
            [pscustomobject]@{ id = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Security/automations/a'; name = 'a'; type = 'microsoft.security/automations'; subscriptionId = 's'; properties = [pscustomobject]@{ isEnabled = $true } }
            [pscustomobject]@{ id = '/subscriptions/s/resourceGroups/rg/providers/Contoso.BrandNew/widgets/w'; name = 'w'; type = 'contoso.brandnew/widgets'; subscriptionId = 's'; properties = [pscustomobject]@{ x = 1 } }
        )
        $collectors = @([pscustomobject]@{ FolderCategory = 'Security'; Name = 'DefenderAutomations'; ResourceTypes = @('microsoft.security/automations') })

        $d = Get-ScoutResourceCompleteness -Resources $resources -Collectors $collectors

        ($d.Resources | Where-Object Name -eq 'ra').Category | Should -Be 'Identity'
        ($d.Resources | Where-Object Name -eq 'a').Category | Should -Be 'Security'
        ($d.Resources | Where-Object Name -eq 'a').CategorySource | Should -Be 'Collector'
        ($d.Resources | Where-Object Name -eq 'w').CategorySource | Should -Be 'Fallback'
        $d.Summary.Categories.Identity | Should -Be 1
        $d.Summary.Categories.Security | Should -Be 1
        $d.Summary.Categories.General | Should -Be 1
        $d.Summary.Uncategorized | Should -Be 1
        @($d.Summary.Categories.PSObject.Properties.Name) | Should -Be @($script:Map.Categories)
    }
}

Describe 'Report lists resources without a collector under their category' {
    It 'adds an Other discovered resources dataset per category, after the collector datasets' {
        . "$script:RepoRoot/src/report/Import-ScoutReportInventory.ps1"
        $cache = Join-Path $TestDrive 'ReportCache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        @{ VirtualMachines = @(@{ id = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1'; Name = 'vm1' }) } |
            ConvertTo-Json -Depth 5 | Set-Content (Join-Path $cache 'Compute.json')
        @{
            Schema = 'azure-scout/discovery-completeness/v1'
            Resources = @(
                @{ Id = '/x/ra'; Name = 'ra'; Type = 'microsoft.authorization/roleassignments'; Category = 'Identity'; CategorySource = 'Type'; PropertyCount = 3 }
                @{ Id = '/x/ext'; Name = 'ext'; Type = 'microsoft.compute/virtualmachines/extensions'; Category = 'Compute'; CategorySource = 'Namespace'; PropertyCount = 5 }
                @{ Id = '/x/vm1'; Name = 'vm1'; Type = 'microsoft.compute/virtualmachines'; Category = 'Compute'; CategorySource = 'Collector'; PropertyCount = 9 }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cache 'Discovery.json')

        $collect = Import-ScoutReportInventory -Collect ([pscustomobject]@{}) -ReportCachePath $cache
        $inventory = $collect._reportInventory

        $inventory.Contains('collected.identity.OtherDiscoveredResources') | Should -BeTrue
        $inventory['collected.compute.OtherDiscoveredResources'].count | Should -Be 1
        $inventory['collected.compute.OtherDiscoveredResources'].rows[0].Name | Should -Be 'ext'
        $inventory['collected.compute.OtherDiscoveredResources'].label | Should -Match '^Compute → Other discovered resources'
        $keys = @($inventory.Keys)
        [array]::IndexOf($keys, 'collected.compute.VirtualMachines') | Should -BeLessThan ([array]::IndexOf($keys, 'collected.compute.OtherDiscoveredResources'))
    }
}

Describe 'Resource categories documentation' {
    It 'matches the map it is generated from' {
        $expected = & "$script:RepoRoot/scripts/Build-ResourceCategoryCatalog.ps1" -PassThru
        $actual = [System.IO.File]::ReadAllText("$script:RepoRoot/docs/reference/resource-categories.md").Replace("`r`n", "`n")
        $actual | Should -Be $expected -Because 'run scripts/Build-ResourceCategoryCatalog.ps1 after changing manifests/resource-categories.psd1'
    }
}
