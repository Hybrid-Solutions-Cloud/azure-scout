#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
#Requires -Modules ImportExcel

<#
.SYNOPSIS
    Pester tests for Web inventory modules (AppServicePlan, AppServices).
#>

$WebPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules' 'Public' 'InventoryModules' 'Web'

$WebModules = @(
    @{ Name = 'AppServicePlan'; File = 'APPServicePlan.ps1'; Type = 'microsoft.web/serverfarms'; Worksheet = 'App Service Plan' }
    @{ Name = 'AppServices';    File = 'APPServices.ps1';    Type = 'microsoft.web/sites';       Worksheet = 'App Services' }
)

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot

    # Collectors are executed here as bare scriptblocks, NOT through the imported module, so any
    # private helper they call has to be dot-sourced in explicitly. Get-AZSCSafeProperty is the
    # StrictMode-safe dotted-path read that converted collectors use instead of a raw `$data.a.b`
    # chain (which throws when an intermediate segment is genuinely ABSENT rather than $null), and
    # Get-AZSCCollectedValue is its member-ENUMERATION counterpart for a read over a collection
    # that may be empty. Both are needed here from AB#5671 onwards.
    . (Join-Path $script:ModuleRoot 'Modules' 'Private' 'Main' 'Get-AZSCSafeProperty.ps1')
    . (Join-Path $script:ModuleRoot 'Modules' 'Private' 'Main' 'Get-AZTICollectedValue.ps1')
    # Get-AZSCIdSegment (AB#5671) guards the FIXED .split('/')[8] index ~30 collectors use to pull
    # a name out of a related resource id -- an out-of-range index THROWS under StrictMode, where
    # without it the same expression quietly returned $null.
    . (Join-Path $script:ModuleRoot 'Modules' 'Private' 'Main' 'Get-AZSCIdSegment.ps1')
    $script:WebPath    = Join-Path $script:ModuleRoot 'Modules' 'Public' 'InventoryModules' 'Web'
    $script:TempDir    = Join-Path $env:TEMP 'AZSC_WebTests'
    if (Test-Path $script:TempDir) { Remove-Item $script:TempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    $script:MockResources = @()

    $aspId = '/subscriptions/sub-00000001/resourceGroups/rg-web/providers/microsoft.web/serverfarms/asp-prod'

    # --- App Service Plan ---
    $script:MockResources += [PSCustomObject]@{
        id             = $aspId
        NAME           = 'asp-prod'
        TYPE           = 'microsoft.web/serverfarms'
        KIND           = 'app'
        LOCATION       = 'eastus'
        RESOURCEGROUP  = 'rg-web'
        subscriptionId = 'sub-00000001'
        tags           = [PSCustomObject]@{ env = 'prod' }
        SKU            = [PSCustomObject]@{ tier = 'Standard'; name = 'S1' }
        PROPERTIES     = [PSCustomObject]@{
            numberOfSites = 2
            computeMode = 'Dedicated'
            currentWorkerSize = 'Small'
            currentNumberOfWorkers = 2
            maximumNumberOfWorkers = 10
            reserved = 'false'
            kind = 'app'
            zoneRedundant = $false
        }
    }

    # --- AutoScale Setting (cross-resource lookup for AppServicePlan) ---
    $script:MockResources += [PSCustomObject]@{
        id             = '/subscriptions/sub-00000001/resourceGroups/rg-web/providers/microsoft.insights/autoscalesettings/autoscale-asp-prod'
        NAME           = 'autoscale-asp-prod'
        TYPE           = 'microsoft.insights/autoscalesettings'
        LOCATION       = 'eastus'
        RESOURCEGROUP  = 'rg-web'
        subscriptionId = 'sub-00000001'
        tags           = [PSCustomObject]@{}
        Properties     = [PSCustomObject]@{
            enabled = 'true'
            targetResourceUri = $aspId
        }
    }

    # --- App Service ---
    $script:MockResources += [PSCustomObject]@{
        id             = '/subscriptions/sub-00000001/resourceGroups/rg-web/providers/microsoft.web/sites/webapp-prod'
        NAME           = 'webapp-prod'
        TYPE           = 'microsoft.web/sites'
        KIND           = 'app'
        LOCATION       = 'eastus'
        RESOURCEGROUP  = 'rg-web'
        subscriptionId = 'sub-00000001'
        tags           = [PSCustomObject]@{ env = 'prod' }
        PROPERTIES     = [PSCustomObject]@{
            sku = 'Standard'
            virtualNetworkSubnetId = '/subscriptions/sub-00000001/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-web/subnets/webapp-subnet'
            siteConfig = [PSCustomObject]@{ ftpsState = 'Disabled'; linuxFxVersion = ''; windowsFxVersion = 'DOTNETCORE|6.0' }
            Properties = [PSCustomObject]@{ SiteConfig = [PSCustomObject]@{ acrUseManagedIdentityCreds = $false } }
            hostNameSslStates = @(
                [PSCustomObject]@{ Name = 'webapp-prod.azurewebsites.net'; hostType = 'Standard'; sslState = 'SniEnabled' }
            )
            zoneRedundant = $false
            maximumNumberOfZones = 3
            currentNumberOfZonesUtilized = 1
            enabled = $true
            state = 'Running'
            clientCertEnabled = $false
            clientCertMode = 'Optional'
            contentAvailabilityState = 'Normal'
            runtimeAvailabilityState = 'Normal'
            httpsOnly = $true
            possibleInboundIpAddresses = '20.1.2.3'
            repositorySiteName = 'webapp-prod'
            availabilityState = 'Normal'
            defaultHostName = 'webapp-prod.azurewebsites.net'
            containerSize = 0
            adminEnabled = $false
            ftpsHostName = 'ftps://waws-prod.ftp.azurewebsites.windows.net'
        }
    }
}

AfterAll {
    if (Test-Path $script:TempDir) { Remove-Item $script:TempDir -Recurse -Force }
}

Describe 'Web Module Files Exist' {
    It 'Web module folder exists' { $script:WebPath | Should -Exist }
    It '<Name> module file exists' -ForEach $WebModules { Join-Path $script:WebPath $File | Should -Exist }
}

Describe 'Web Module Processing Phase — <Name>' -ForEach $WebModules {
    BeforeAll {
        $script:ModFile = Join-Path $script:WebPath $File
        $script:ResType = $Type
    }
    It 'Processing returns results when matching resources are present' {
        $matchedResources = $script:MockResources | Where-Object { $_.TYPE -eq $script:ResType }
        if ($matchedResources) {
            $content = Get-Content -Path $script:ModFile -Raw
            $sb = [ScriptBlock]::Create($content)
            $result = Invoke-Command -ScriptBlock $sb -ArgumentList $null, $null, $null, $script:MockResources, $null, 'Processing', $null, $null, 'Light20', $null
            $result | Should -Not -BeNullOrEmpty
        } else { Set-ItResult -Skipped -Because "No mock resource of type '$script:ResType'" }
    }
    It 'Processing does not throw when given an empty resource list' {
        $content = Get-Content -Path $script:ModFile -Raw
        $sb = [ScriptBlock]::Create($content)
        { Invoke-Command -ScriptBlock $sb -ArgumentList $null, $null, $null, @(), $null, 'Processing', $null, $null, 'Light20', $null } | Should -Not -Throw
    }
}

Describe 'Web Module Reporting Phase — <Name>' -ForEach $WebModules {
    BeforeAll {
        $script:ModFile  = Join-Path $script:WebPath $File
        $script:ResType  = $Type
        $script:XlsxFile = Join-Path $script:TempDir ("Web_{0}_{1}.xlsx" -f $Name, [System.IO.Path]::GetRandomFileName())
        $matchedResources = $script:MockResources | Where-Object { $_.TYPE -eq $script:ResType }
        if ($matchedResources) {
            $content = Get-Content -Path $script:ModFile -Raw
            $sb = [ScriptBlock]::Create($content)
            $script:ProcessedData = Invoke-Command -ScriptBlock $sb -ArgumentList $null, $null, $null, $script:MockResources, $null, 'Processing', $null, $null, 'Light20', $null
        } else { $script:ProcessedData = $null }
    }
    It 'Reporting phase does not throw' {
        if ($script:ProcessedData) {
            $content = Get-Content -Path $script:ModFile -Raw
            $sb = [ScriptBlock]::Create($content)
            { Invoke-Command -ScriptBlock $sb -ArgumentList $null, $null, $null, $null, $null, 'Reporting', $script:XlsxFile, $script:ProcessedData, 'Light20', $null } | Should -Not -Throw
        } else { Set-ItResult -Skipped -Because 'No processed data' }
    }
    It 'Excel file is created' {
        if ($script:ProcessedData) { $script:XlsxFile | Should -Exist }
        else { Set-ItResult -Skipped -Because 'No processed data' }
    }
}
