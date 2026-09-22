#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Draw.io diagram generation pipeline (AB#342).

.DESCRIPTION
    Exercises Start-AZSCDiagramOrganization, Start-AZSCDiagramNetwork,
    Start-AZSCDiagramSubscription, and Set-AZSCDiagramFile end-to-end against
    small synthetic fixtures (no live Azure connection required), then
    XML-parses the merged .drawio output to assert it is a well-formed,
    multi-page mxfile/diagram/mxGraphModel document with consistent styling:

      - every vertex cell has a non-empty style and a non-zero-size mxGeometry
      - edge cells are not also marked as vertices
      - edges use consistent orthogonal routing (no legacy edgeStyle=none)
      - long resource names are truncated for the on-canvas label while the
        full value is retained in a dedicated custom attribute

    The module is imported normally (Import-Module ./AzureScout.psd1), which
    is deliberate: the assessment platform under src/ calls
    Set-StrictMode -Version Latest at file scope, and because every *.ps1
    under Modules/ and src/ is dot-sourced into the same module SessionState,
    that strict mode setting is ambient for the whole module -- including
    these diagram functions -- in real usage. Fixtures here are intentionally
    "small but shallow" (few resources, exactly one item in several
    collections) because that shape is what previously tripped
    empty-array/scalar-collapse member-enumeration errors under strict mode.

.NOTES
    Author:  AzureScout Contributors
    Version: 1.0.0
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ModuleRoot 'AzureScout.psd1'
    $script:DiagramPath = Join-Path $script:ModuleRoot 'src' 'pipeline' 'diagram'

    Import-Module $script:ManifestPath -Force

    $script:TestRoot = Join-Path $script:ModuleRoot 'tests' 'test-output' 'DiagramCache'
    if (Test-Path $script:TestRoot) { Remove-Item -Path $script:TestRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $script:TestRoot | Out-Null

    $script:CacheDir = Join-Path $script:TestRoot 'DiagramCache'
    New-Item -ItemType Directory -Path $script:CacheDir | Out-Null
    $script:LogFile = Join-Path $script:TestRoot 'log.txt'
    $script:DDFile = Join-Path $script:TestRoot 'AzureScout.drawio'

    $script:LongVnetName = 'vnet-hub-prod-westus2-shared-services-connectivity-platform-team-01'
    $script:LongMgName = 'Very Long Management Group Display Name Used To Exercise The New Truncation Helper 001'
    $script:LongSubName = 'This Is An Extremely Long Subscription Name That Should Be Truncated For Display In The Org Diagram'

    # ---- Organization fixture: a single subscription, two levels below the
    # tenant root (a very common, shallow real-world shape) ----
    $mgEntry = [PSCustomObject]@{ name = 'mg-eng'; displayname = $script:LongMgName }
    $rootEntry = [PSCustomObject]@{ name = 'tenant root group'; displayname = 'Tenant Root Group' }

    $orgSub = [PSCustomObject]@{
        Type           = 'microsoft.resources/subscriptions'
        subscriptionid = 'sub-0001'
        id             = 'sub-0001'
        name           = $script:LongSubName
        properties     = [PSCustomObject]@{
            managementgroupancestorschain = @($mgEntry, $rootEntry)
        }
    }
    $orgRg = [PSCustomObject]@{ Type = 'microsoft.resources/subscriptions/resourcegroups'; subscriptionid = 'sub-0001'; Name = 'rg-network' }
    $script:ResourceContainers = @($orgSub, $orgRg)

    # ---- Network fixture: one VNET, one (empty/delegation-less) subnet --
    # the most common real subnet shape, and the one that previously tripped
    # empty-collection member-enumeration under strict mode.
    $subnet1 = [PSCustomObject]@{
        Name       = 'snet-default'
        id         = '/subscriptions/sub-0001/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet1/subnets/snet-default'
        properties = [PSCustomObject]@{
            addressPrefix                      = '10.0.0.0/24'
            networkSecurityGroup               = $null
            routeTable                         = $null
            delegations                        = @()
            resourceNavigationLinks             = @()
            serviceAssociationLinks             = @()
            applicationGatewayIPConfigurations  = @()
            ipconfigurations                    = @()
        }
    }

    $script:Vnet1 = [PSCustomObject]@{
        Name           = $script:LongVnetName
        id             = '/subscriptions/sub-0001/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet1'
        subscriptionId = 'sub-0001'
        properties     = [PSCustomObject]@{
            addressSpace           = [PSCustomObject]@{ addressPrefixes = @('10.0.0.0/16') }
            subnets                = @($subnet1)
            virtualNetworkPeerings = @()
            enableDdosProtection   = $false
            dhcpoptions            = [PSCustomObject]@{ dnsServers = @() }
        }
    }

    $script:Job = @{
        AZVNETs = @($script:Vnet1); AZLGWs = @(); AZEXPROUTEs = @(); AZVPNSITES = @(); AZVERs = @()
        AKS = @(); VMSS = @(); NIC = @(); PrivEnd = @(); VM = @(); ARO = @(); Kusto = @(); AppGtw = @()
        Databricks = @(); AppWeb = @(); APIM = @(); LB = @(); Bastion = @(); FW = @(); NetProf = @()
        Container = @(); ANF = @(); AZVGWs = @(); AZCONs = @(); PIPs = @(); AZVWAN = @(); AZVHUB = @()
    }

    $script:Subscriptions = @([PSCustomObject]@{ id = 'sub-0001'; name = 'Sub One' })

    # ---- Subscription fixture: a single resource group with one VM ----
    $script:Resources = @(
        [PSCustomObject]@{ Type = 'microsoft.compute/virtualmachines'; subscriptionId = 'sub-0001'; resourceGroup = 'rg-network'; name = 'vm-test-01' }
    )

    function Get-DiagramXml {
        [xml]$xml = Get-Content -Path $script:DDFile -Raw
        return $xml
    }
}

AfterAll {
    if (Test-Path $script:TestRoot) { Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

# =====================================================================
# FILE EXISTENCE / SYNTAX
# =====================================================================
Describe 'Diagram module files exist and parse cleanly' {
    $diagramFiles = @(
        'Build-ScoutDiagramSubnet.ps1', 'Set-ScoutDiagramFile.ps1',
        'Start-ScoutDiagramJob.ps1', 'Start-ScoutDiagramNetwork.ps1',
        'Start-ScoutDiagramOrganization.ps1', 'Start-ScoutDiagramSubscription.ps1',
        'Start-ScoutDrawIoDiagram.ps1'
    )

    It '<_> exists' -ForEach $diagramFiles {
        Join-Path $script:DiagramPath $_ | Should -Exist
    }

    It '<_> parses without errors' -ForEach $diagramFiles {
        $filePath = Join-Path $script:DiagramPath $_
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
}

# =====================================================================
# GENERATION (no live Azure connection required)
# =====================================================================
Describe 'Draw.io diagram generation end-to-end' {

    It 'Start-AZSCDiagramOrganization generates Organization.xml without throwing' {
        { Start-AZSCDiagramOrganization -ResourceContainers $script:ResourceContainers -DiagramCache $script:CacheDir -LogFile $script:LogFile } |
            Should -Not -Throw
        Join-Path $script:CacheDir 'Organization.xml' | Should -Exist
    }

    It 'Organization.xml is well-formed XML with an mxfile root' {
        $orgFile = Join-Path $script:CacheDir 'Organization.xml'
        { [xml](Get-Content -Path $orgFile -Raw) } | Should -Not -Throw
        [xml]$orgXml = Get-Content -Path $orgFile -Raw
        $orgXml.mxfile | Should -Not -BeNullOrEmpty
        $orgXml.mxfile.diagram.name | Should -Be 'Organization'
    }

    It 'Start-AZSCDiagramNetwork generates the main .drawio file without throwing' {
        { Start-AZSCDiagramNetwork -Subscriptions $script:Subscriptions -Job $script:Job -Advisories @() `
            -DiagramCache $script:CacheDir -FullEnvironment $false -DDFile $script:DDFile `
            -XMLFiles @() -LogFile $script:LogFile -Automation ([switch]$true) } | Should -Not -Throw
        $script:DDFile | Should -Exist
    }

    It 'the main .drawio file is well-formed XML with a Network Topology page' {
        { [xml](Get-Content -Path $script:DDFile -Raw) } | Should -Not -Throw
        [xml]$netXml = Get-Content -Path $script:DDFile -Raw
        $netXml.mxfile.diagram.name | Should -Be 'Network Topology'
    }

    It 'Start-AZSCDiagramSubscription generates Subscriptions.xml without throwing' {
        { Start-AZSCDiagramSubscription -Subscriptions $script:Subscriptions -Resources $script:Resources `
            -DiagramCache $script:CacheDir -LogFile $script:LogFile } | Should -Not -Throw
        Join-Path $script:CacheDir 'Subscriptions.xml' | Should -Exist
    }

    It 'Subscriptions.xml is well-formed XML with one page per subscription' {
        $subFile = Join-Path $script:CacheDir 'Subscriptions.xml'
        { [xml](Get-Content -Path $subFile -Raw) } | Should -Not -Throw
        [xml]$subXml = Get-Content -Path $subFile -Raw
        $subXml.mxfile.diagram.name | Should -Be 'Sub One'
    }

    It 'Set-AZSCDiagramFile merges Organization.xml and Subscriptions.xml into the main file as additional pages' {
        $xmlFiles = @(
            (Join-Path $script:CacheDir 'Organization.xml'),
            (Join-Path $script:CacheDir 'Subscriptions.xml')
        )

        { Set-AZSCDiagramFile -XMLFiles $xmlFiles -DDFile $script:DDFile -LogFile $script:LogFile } | Should -Not -Throw

        # The merge function deletes each source cache file once merged.
        Join-Path $script:CacheDir 'Organization.xml' | Should -Not -Exist
        Join-Path $script:CacheDir 'Subscriptions.xml' | Should -Not -Exist

        $mergeErrors = Get-Content $script:LogFile | Select-String -Pattern 'Error merging'
        $mergeErrors | Should -BeNullOrEmpty
    }
}

# =====================================================================
# MERGED OUTPUT QUALITY (well-formed XML + consistent styling)
# =====================================================================
Describe 'Merged .drawio output quality' {

    It 'is still well-formed XML after the merge' {
        { Get-DiagramXml } | Should -Not -Throw
    }

    It 'contains all three diagram pages' {
        $xml = Get-DiagramXml
        $names = $xml.mxfile.diagram.name
        $names | Should -Contain 'Network Topology'
        $names | Should -Contain 'Organization'
        $names | Should -Contain 'Sub One'
    }

    It 'has at least one vertex cell' {
        $xml = Get-DiagramXml
        $vertices = $xml.SelectNodes('//mxCell[@vertex="1"]')
        $vertices.Count | Should -BeGreaterThan 0
    }

    It 'every vertex cell has a non-empty style and non-zero-size geometry' {
        $xml = Get-DiagramXml
        $vertices = $xml.SelectNodes('//mxCell[@vertex="1"]')
        foreach ($vertex in $vertices) {
            $vertex.style | Should -Not -BeNullOrEmpty -Because "cell id=$($vertex.id) should be styled"
            $geometry = $vertex.mxGeometry
            $geometry | Should -Not -BeNullOrEmpty -Because "cell id=$($vertex.id) should carry geometry"
            [double]$geometry.width | Should -BeGreaterThan 0 -Because "cell id=$($vertex.id) should not be zero-width"
            [double]$geometry.height | Should -BeGreaterThan 0 -Because "cell id=$($vertex.id) should not be zero-height"
        }
    }

    It 'never marks the same cell as both an edge and a vertex' {
        $xml = Get-DiagramXml
        $badCells = $xml.SelectNodes('//mxCell[@edge="1" and @vertex="1"]')
        $badCells.Count | Should -Be 0
    }

    It 'uses consistent orthogonal edge routing (no legacy edgeStyle=none)' {
        $xml = Get-DiagramXml
        $edges = $xml.SelectNodes('//mxCell[@edge="1"]')
        $edges.Count | Should -BeGreaterThan 0
        foreach ($edge in $edges) {
            $edge.style | Should -Match 'edgeStyle=orthogonalEdgeStyle'
        }
    }

    It 'truncates the long VNET name in the label but retains the full value in Full_VNET_Name' {
        $xml = Get-DiagramXml
        $vnetNode = $xml.SelectSingleNode('//object[@Full_VNET_Name]')
        $vnetNode | Should -Not -BeNullOrEmpty
        $vnetNode.Full_VNET_Name | Should -Be $script:LongVnetName
        $vnetNode.label | Should -Not -Be $script:LongVnetName
        ($vnetNode.label -split "`n")[0].Length | Should -BeLessOrEqual 40
    }

    It 'truncates the long subscription name in the Organization page but retains it in Full_Subscription_Name' {
        $xml = Get-DiagramXml
        $subNode = $xml.SelectSingleNode('//object[@Full_Subscription_Name]')
        $subNode | Should -Not -BeNullOrEmpty
        $subNode.Full_Subscription_Name | Should -Be $script:LongSubName
        $subNode.label | Should -Not -Be $script:LongSubName
    }

    It 'truncates the long management group title on its container swimlane' {
        $xml = Get-DiagramXml
        $mgCell = $xml.SelectSingleNode("//mxCell[contains(@style,'swimlane') and string-length(@value) > 0 and string-length(@value) < string-length('$($script:LongMgName)')]")
        $mgCell | Should -Not -BeNullOrEmpty
    }
}

# =====================================================================
# REGRESSION: subnet with no recognizable resource type ("EmptySubnet")
# =====================================================================
Describe 'Build-AZSCDiagramSubnet handles a subnet with no matching resource type' {

    BeforeAll {
        # A subnet with no delegation, no links, and no IP configurations at all
        # drives Get-AZSCDiagramSubnetResourceType to its 'EmptySubnet' fallback,
        # which none of the branches in the nested Get-AZSCDiagramSubnetResourcesName
        # switch match. Before the fix, $ResNames/$RESNames was never assigned in
        # that function's scope for this case, and `return $ResNames` threw "the
        # variable '$ResNames' cannot be retrieved because it has not been set"
        # under Set-StrictMode -Version Latest -- breaking the diagram for any
        # ordinary unused/empty subnet (an extremely common real-world shape).
        $script:EmptySubnetFixture = [PSCustomObject]@{
            Name       = 'snet-truly-empty'
            id         = '/subscriptions/sub-0001/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-empty/subnets/snet-truly-empty'
            properties = [PSCustomObject]@{
                addressPrefix                      = '10.0.2.0/24'
                networkSecurityGroup               = $null
                routeTable                         = $null
                delegations                        = @()
                resourceNavigationLinks            = @()
                serviceAssociationLinks            = @()
                applicationGatewayIPConfigurations = @()
                ipconfigurations                   = @()
            }
        }

        $script:EmptySubnetVnet = [PSCustomObject]@{
            Name           = 'vnet-empty-test'
            id             = '/subscriptions/sub-0001/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-empty'
            subscriptionId = 'sub-0001'
            properties     = [PSCustomObject]@{
                addressSpace           = [PSCustomObject]@{ addressPrefixes = @('10.0.2.0/16') }
                subnets                = @($script:EmptySubnetFixture)
                virtualNetworkPeerings = @()
                enableDdosProtection   = $false
                dhcpoptions            = [PSCustomObject]@{ dnsServers = @() }
            }
        }

        # Empty on every resource-type bucket the nested resolver switches on, so
        # none of its branches match and $ResNames is left to fall through.
        $script:EmptyJob = @{
            AZVNETs = @($script:EmptySubnetVnet); AZLGWs = @(); AZEXPROUTEs = @(); AZVPNSITES = @(); AZVERs = @()
            AKS = @(); VMSS = @(); NIC = @(); PrivEnd = @(); VM = @(); ARO = @(); Kusto = @(); AppGtw = @()
            Databricks = @(); AppWeb = @(); APIM = @(); LB = @(); Bastion = @(); FW = @(); NetProf = @()
            Container = @(); ANF = @(); AZVGWs = @(); AZCONs = @(); PIPs = @(); AZVWAN = @(); AZVHUB = @()
        }
    }

    It 'does not throw when the subnet has no delegation, links, or IP configurations and no resource matches it' {
        { Build-AZSCDiagramSubnet -SubnetLocation 0 -VNET $script:EmptySubnetVnet -IDNum 0 `
            -DiagramCache $script:CacheDir -ContainerID 1 -Job $script:EmptyJob -LogFile $script:LogFile } |
            Should -Not -Throw
    }

    It 'still produces a subnet cache .xml file for the empty subnet' {
        Get-ChildItem -Path $script:CacheDir -Filter '*.xml' | Should -Not -BeNullOrEmpty
    }
}
