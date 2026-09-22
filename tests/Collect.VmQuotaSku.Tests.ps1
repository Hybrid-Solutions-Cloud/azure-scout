#Requires -Version 7.0
#Requires -Modules Pester

<#
    Pester tests for src/collect/Get-ScoutVmQuotas.ps1 and Get-ScoutVmSkuDetails.ps1
    (AB#5639/5646, Epic AB#5638).

    Get-AzContext / Set-AzContext / Get-AzVMUsage / Get-AzComputeResourceSku are mocked
    throughout -- no live Azure connection is made.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/collect/Get-ScoutVmQuotas.ps1"
    . "$root/src/collect/Get-ScoutVmSkuDetails.ps1"

    function Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'original-sub' } } }
    function Set-AzContext { param([Parameter(ValueFromRemainingArguments)] $Rest) }

    # Mixed array: Resource Graph rows carrying subscriptionId/type, alongside a REST-API row
    # (e.g. from Get-ScoutApiResources) that carries neither -- the exact AB#5633 shape.
    $script:mixedResources = @(
        [pscustomobject]@{ type = 'microsoft.compute/virtualmachines'; subscriptionId = 'sub-1'; location = 'eastus' }
        [pscustomobject]@{ type = 'microsoft.compute/virtualmachinescalesets'; subscriptionId = 'sub-1'; location = 'westus' }
        [pscustomobject]@{ type = 'microsoft.storage/storageaccounts'; subscriptionId = 'sub-1'; location = 'eastus' }
        [pscustomobject]@{ Subscription = 'sub-1'; ResourceHealth = @() }   # REST-API row, no type/subscriptionId
    )
    $script:subs = @([pscustomobject]@{ id = 'sub-1'; name = 'sub-one' })
}

Describe 'Get-ScoutVmQuotas' {
    It 'does not throw on a mixed array missing type/subscriptionId on some rows (AB#5633)' {
        function Get-AzVMUsage { param([string] $Location) return @() }
        { Get-ScoutVmQuotas -Subscriptions $script:subs -Resources $script:mixedResources } | Should -Not -Throw
    }

    It 'queries only the locations that actually have a VM/VMSS' {
        $script:queriedLocations = @()
        function Get-AzVMUsage {
            param([string] $Location)
            $script:queriedLocations += $Location
            return @()
        }
        Get-ScoutVmQuotas -Subscriptions $script:subs -Resources $script:mixedResources | Out-Null
        ($script:queriedLocations | Sort-Object) | Should -Be @('eastus', 'westus')
    }

    It 'preserves the AZSC/VM/Quotas type tag and filters to CurrentValue >= 1' {
        function Get-AzVMUsage {
            param([string] $Location)
            return @(
                [pscustomobject]@{ Name = [pscustomobject]@{ Value = 'cores' }; CurrentValue = 4; Limit = 100 }
                [pscustomobject]@{ Name = [pscustomobject]@{ Value = 'unused' }; CurrentValue = 0; Limit = 100 }
            )
        }
        $result = Get-ScoutVmQuotas -Subscriptions $script:subs -Resources $script:mixedResources
        $result.type | Should -Be 'AZSC/VM/Quotas'
        $entry = $result.properties | Where-Object { $_.Location -eq 'eastus' }
        $entry.Data.Count | Should -Be 1
        $entry.Data[0].Name.Value | Should -Be 'cores'
    }

    It 'restores the original Az context even when a quota lookup throws' {
        $script:restoredTo = $null
        function Set-AzContext {
            param([string] $Subscription, [string] $Tenant, [Parameter(ValueFromRemainingArguments)] $Rest)
            if ($Subscription -eq 'original-sub') { $script:restoredTo = $Subscription }
        }
        function Get-AzVMUsage { param([string] $Location) throw 'transient quota API error' }
        { Get-ScoutVmQuotas -Subscriptions $script:subs -Resources $script:mixedResources -WarningAction SilentlyContinue } | Should -Not -Throw
        $script:restoredTo | Should -Be 'original-sub'
    }
}

Describe 'Get-ScoutVmSkuDetails' {
    It 'does not throw on a mixed array missing type on some rows' {
        function Get-AzComputeResourceSku { param([string] $Location) return @() }
        { Get-ScoutVmSkuDetails -Resources $script:mixedResources } | Should -Not -Throw
    }

    It 'queries only the distinct VM/VMSS locations and preserves the AZSC/VM/SKU type tag' {
        $script:queriedLocations = @()
        function Get-AzComputeResourceSku {
            param([string] $Location)
            $script:queriedLocations += $Location
            return @([pscustomobject]@{ Name = 'Standard_D2s_v5' })
        }
        $result = Get-ScoutVmSkuDetails -Resources $script:mixedResources
        $result.type | Should -Be 'AZSC/VM/SKU'
        ($script:queriedLocations | Sort-Object) | Should -Be @('eastus', 'westus')
        ($result.properties | Where-Object Location -eq 'eastus').SKUs[0].Name | Should -Be 'Standard_D2s_v5'
    }
}
