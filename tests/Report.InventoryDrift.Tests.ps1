#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/report/Get-ScoutInventoryDrift.ps1 — cross-run
    RESOURCE/inventory drift tracking (ADO Story AB#326). Builds small
    synthetic collect.json-shaped objects (the canonical shape
    Invoke-Collect.ps1 documents) and points -HistoryPath at a throwaway
    folder under $env:TEMP so runs never touch a real assessment's
    .scout-history. No Azure connection required.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/report/Get-ScoutInventoryDrift.ps1"

    function New-InventoryTestCollect {
        # A minimal but multi-shape collect object: a top-level array
        # (subscriptions), a nested-object-with-array (networking.
        # virtualNetworks, compute.virtualMachines), and a resource whose
        # only identity-ish field is 'nsg' + 'resourceGroup' (nsgPublicInbound
        # never carries a 'name' field in the real collector) — exercises the
        # non-'name' branch of the identity-field priority list.
        param(
            [array] $VirtualNetworks = @(),
            [array] $VirtualMachines = @(),
            [array] $NsgRules = @(),
            [array] $Subscriptions = @()
        )
        [pscustomobject]@{
            subscriptions = $Subscriptions
            networking    = [pscustomobject]@{
                virtualNetworks  = $VirtualNetworks
                nsgPublicInbound = $NsgRules
            }
            compute       = [pscustomobject]@{ virtualMachines = $VirtualMachines }
            _meta         = [pscustomobject]@{ generatedOn = '2026-01-01T00:00:00Z'; scope = 'All' }
        }
    }

    function New-Vnet { param($Name, $Rg = 'rg1', $Sub = 'sub1', $PeeringCount = 0)
        [pscustomobject]@{ name = $Name; resourceGroup = $Rg; subscriptionId = $Sub; peeringCount = $PeeringCount; ddosEnabled = $false }
    }
    function New-Vm { param($Name, $Rg = 'rg1', $Sub = 'sub1', $Size = 'Standard_D2s_v3')
        [pscustomobject]@{ name = $Name; resourceGroup = $Rg; subscriptionId = $Sub; size = $Size; zoneRedundant = $false }
    }
    function New-NsgRule { param($Nsg, $Rg = 'rg1', $Rule = 'AllowAny', $Port = '*')
        [pscustomobject]@{ nsg = $Nsg; resourceGroup = $Rg; rule = $Rule; port = $Port }
    }

    function Get-DriftEntry($List, $Id) { return $List | Where-Object Id -eq $Id }
}

Describe 'Get-ScoutInventoryDrift — first-ever run (baseline)' {
    BeforeAll {
        $script:HistoryPath = Join-Path $env:TEMP "ScoutInvDriftTest_$([guid]::NewGuid().ToString('N'))"
        $collect1 = New-InventoryTestCollect -VirtualNetworks @((New-Vnet 'vnetA'), (New-Vnet 'vnetB')) -VirtualMachines @((New-Vm 'vm1'))
        $script:Drift1 = Get-ScoutInventoryDrift -Collect $collect1 -HistoryPath $script:HistoryPath -RunId 'run1'
    }

    AfterAll {
        if (Test-Path $script:HistoryPath) { Remove-Item $script:HistoryPath -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns an explicit baseline result, not an error, on the first run' {
        $script:Drift1.IsBaseline | Should -BeTrue
        $script:Drift1.PreviousRunId | Should -BeNullOrEmpty
    }

    It 'reports NO drift on the baseline run — everything is baseline, not Added' {
        $script:Drift1.Added.Count | Should -Be 0
        $script:Drift1.Removed.Count | Should -Be 0
        $script:Drift1.Changed.Count | Should -Be 0
        $script:Drift1.Summary.Added | Should -Be 0
        $script:Drift1.Summary.Removed | Should -Be 0
        $script:Drift1.Summary.Changed | Should -Be 0
        $script:Drift1.Summary.Unchanged | Should -Be 0
    }

    It 'still counts the current inventory in the summary' {
        $script:Drift1.Summary.TotalCurrent | Should -Be 3
        $script:Drift1.Summary.TotalPrevious | Should -Be 0
    }

    It 'creates the inventory-history file and folder' {
        (Join-Path $script:HistoryPath 'inventory-history.json') | Should -Exist
    }
}

Describe 'Get-ScoutInventoryDrift — second run: added / removed / changed / unchanged' {
    BeforeAll {
        $script:HistoryPath = Join-Path $env:TEMP "ScoutInvDriftTest_$([guid]::NewGuid().ToString('N'))"

        # run1: vnetA (peeringCount 1), vnetB, vm1 unchanged-to-be, one nsg rule
        $collect1 = New-InventoryTestCollect `
            -VirtualNetworks @((New-Vnet 'vnetA' -PeeringCount 1), (New-Vnet 'vnetB')) `
            -VirtualMachines @((New-Vm 'vm1')) `
            -NsgRules @((New-NsgRule -Nsg 'nsg1'))
        Get-ScoutInventoryDrift -Collect $collect1 -HistoryPath $script:HistoryPath -RunId 'run1' | Out-Null

        # run2: vnetA peeringCount changes 1->2 (Changed), vnetB removed,
        # vm1 unchanged, vm2 is new (Added), nsg rule unchanged.
        $collect2 = New-InventoryTestCollect `
            -VirtualNetworks @((New-Vnet 'vnetA' -PeeringCount 2)) `
            -VirtualMachines @((New-Vm 'vm1'), (New-Vm 'vm2')) `
            -NsgRules @((New-NsgRule -Nsg 'nsg1'))
        $script:Drift2 = Get-ScoutInventoryDrift -Collect $collect2 -HistoryPath $script:HistoryPath -RunId 'run2'
    }

    AfterAll {
        if (Test-Path $script:HistoryPath) { Remove-Item $script:HistoryPath -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is not a baseline and points PreviousRunId at the prior run' {
        $script:Drift2.IsBaseline | Should -BeFalse
        $script:Drift2.PreviousRunId | Should -Be 'run1'
    }

    It 'detects the new virtual machine as Added' {
        $script:Drift2.Summary.Added | Should -Be 1
        $addedIds = $script:Drift2.Added.Id
        ($addedIds -match 'vm2') | Should -Not -BeNullOrEmpty
        ($script:Drift2.Added | Where-Object { $_.Id -match 'vm2' }).Path | Should -Be 'compute.virtualMachines'
    }

    It 'detects the dropped virtual network as Removed' {
        $script:Drift2.Summary.Removed | Should -Be 1
        $removedIds = $script:Drift2.Removed.Id
        ($removedIds -match 'vnetB') | Should -Not -BeNullOrEmpty
        ($script:Drift2.Removed | Where-Object { $_.Id -match 'vnetB' }).Fields.name | Should -Be 'vnetB'
    }

    It 'detects the peeringCount property change on vnetA as Changed, with the changed field named' {
        $script:Drift2.Summary.Changed | Should -Be 1
        $changedEntry = $script:Drift2.Changed | Where-Object { $_.Id -match 'vnetA' }
        $changedEntry | Should -Not -BeNullOrEmpty
        $peeringChange = $changedEntry.Changes | Where-Object Field -eq 'peeringCount'
        $peeringChange | Should -Not -BeNullOrEmpty
        $peeringChange.PreviousValue | Should -Be 1
        $peeringChange.CurrentValue | Should -Be 2
    }

    It 'does not report an unrelated field as changed' {
        $changedEntry = $script:Drift2.Changed | Where-Object { $_.Id -match 'vnetA' }
        ($changedEntry.Changes | Where-Object Field -eq 'ddosEnabled') | Should -BeNullOrEmpty
    }

    It 'rolls unaffected resources (vm1, nsg1) up as Unchanged, not into Added/Removed/Changed' {
        $script:Drift2.Summary.Unchanged | Should -Be 2
        (@($script:Drift2.Added.Id) -match 'vm1\|') | Should -BeNullOrEmpty
        (@($script:Drift2.Changed.Id) -match 'vm1\|') | Should -BeNullOrEmpty
    }

    It 'a rerun of the same RunId replaces its own history record instead of duplicating it' {
        Get-ScoutInventoryDrift -Collect $collect2 -HistoryPath $script:HistoryPath -RunId 'run2' | Out-Null
        $historyRaw = Get-Content (Join-Path $script:HistoryPath 'inventory-history.json') -Raw | ConvertFrom-Json -Depth 100
        @($historyRaw | Where-Object RunId -eq 'run2').Count | Should -Be 1
    }
}

Describe 'Get-ScoutInventoryDrift — stable id matching' {
    BeforeAll {
        $script:HistoryPath = Join-Path $env:TEMP "ScoutInvDriftTest_$([guid]::NewGuid().ToString('N'))"
    }

    AfterAll {
        if (Test-Path $script:HistoryPath) { Remove-Item $script:HistoryPath -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'matches the same resource across runs even when array order changes' {
        $collect1 = New-InventoryTestCollect -VirtualNetworks @((New-Vnet 'vnetA'), (New-Vnet 'vnetB'), (New-Vnet 'vnetC'))
        Get-ScoutInventoryDrift -Collect $collect1 -HistoryPath $script:HistoryPath -RunId 'order1' | Out-Null

        # Same three vnets, reversed order, no field changes — should be entirely Unchanged.
        $collect2 = New-InventoryTestCollect -VirtualNetworks @((New-Vnet 'vnetC'), (New-Vnet 'vnetB'), (New-Vnet 'vnetA'))
        $drift = Get-ScoutInventoryDrift -Collect $collect2 -HistoryPath $script:HistoryPath -RunId 'order2'

        $drift.Summary.Added | Should -Be 0
        $drift.Summary.Removed | Should -Be 0
        $drift.Summary.Changed | Should -Be 0
        $drift.Summary.Unchanged | Should -Be 3
    }

    It 'does not confuse two resources with the same name in different resource groups' {
        $collect1 = New-InventoryTestCollect -VirtualNetworks @((New-Vnet 'shared-name' -Rg 'rgA'), (New-Vnet 'shared-name' -Rg 'rgB'))
        $baseline = Get-ScoutInventoryDrift -Collect $collect1 -HistoryPath $script:HistoryPath -RunId 'sameNameBaseline'
        $baseline.Summary.TotalCurrent | Should -Be 2

        # Only the rgB copy changes; the rgA copy must be recognized as Unchanged, not confused with rgB.
        $collect2 = New-InventoryTestCollect -VirtualNetworks @((New-Vnet 'shared-name' -Rg 'rgA'), (New-Vnet 'shared-name' -Rg 'rgB' -PeeringCount 5))
        $drift = Get-ScoutInventoryDrift -Collect $collect2 -HistoryPath $script:HistoryPath -RunId 'sameNameNext'

        $drift.Summary.Changed | Should -Be 1
        $drift.Summary.Unchanged | Should -Be 1
        $changedEntry = $drift.Changed | Select-Object -First 1
        # Changed entries carry Changes (a field-level diff), not the raw Fields
        # bag Added/Removed entries carry — confirms the two shapes stay distinct.
        $changedEntry.PSObject.Properties.Name | Should -Not -Contain 'Fields'
        $changedEntry.Id | Should -Match 'rgB'
    }

    It 'keys a resource identified only by a non-name field (nsg) correctly' {
        $collect1 = New-InventoryTestCollect -NsgRules @((New-NsgRule -Nsg 'nsg-only-id'))
        Get-ScoutInventoryDrift -Collect $collect1 -HistoryPath $script:HistoryPath -RunId 'nsgBaseline' | Out-Null

        $collect2 = New-InventoryTestCollect -NsgRules @((New-NsgRule -Nsg 'nsg-only-id' -Port '443'))
        $drift = Get-ScoutInventoryDrift -Collect $collect2 -HistoryPath $script:HistoryPath -RunId 'nsgNext'

        $drift.Summary.Changed | Should -Be 1
        $portChange = ($drift.Changed | Select-Object -First 1).Changes | Where-Object Field -eq 'port'
        $portChange.PreviousValue | Should -Be '*'
        $portChange.CurrentValue | Should -Be '443'
    }
}

Describe 'Get-ScoutInventoryDrift — malformed/corrupt history is tolerated' {
    BeforeAll {
        $script:HistoryPath = Join-Path $env:TEMP "ScoutInvDriftTest_$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $script:HistoryPath -Force | Out-Null
        'this is not { valid json at all' | Out-File (Join-Path $script:HistoryPath 'inventory-history.json') -Encoding utf8

        $collect = New-InventoryTestCollect -VirtualNetworks @((New-Vnet 'vnetA'))
        $script:DriftBlock = { Get-ScoutInventoryDrift -Collect $collect -HistoryPath $script:HistoryPath -RunId 'run1' }
    }

    AfterAll {
        if (Test-Path $script:HistoryPath) { Remove-Item $script:HistoryPath -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not throw on a malformed history file' {
        $script:DriftBlock | Should -Not -Throw
    }

    It 'treats malformed history as a baseline' {
        $result = & $script:DriftBlock
        $result.IsBaseline | Should -BeTrue
        $result.PreviousRunId | Should -BeNullOrEmpty
    }

    It 'overwrites the malformed file with valid JSON afterward' {
        & $script:DriftBlock | Out-Null
        { Get-Content (Join-Path $script:HistoryPath 'inventory-history.json') -Raw | ConvertFrom-Json -Depth 100 } | Should -Not -Throw
    }
}

Describe 'Get-ScoutInventoryDrift — parameter validation' {
    It 'throws when -Collect is not supplied' {
        { Get-ScoutInventoryDrift -Collect $null -HistoryPath $env:TEMP -RunId 'run1' } | Should -Throw
    }

    It 'throws when -RunId is not supplied' {
        $collect = New-InventoryTestCollect -VirtualNetworks @((New-Vnet 'vnetA'))
        { Get-ScoutInventoryDrift -Collect $collect -HistoryPath $env:TEMP -RunId '' } | Should -Throw
    }
}
