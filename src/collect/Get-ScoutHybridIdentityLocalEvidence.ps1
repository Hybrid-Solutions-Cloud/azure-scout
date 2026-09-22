#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ScoutHybridIdentityLocalEvidence {
    [CmdletBinding()]
    param(
        [Parameter(DontShow)]
        [AllowNull()]
        [System.Collections.IDictionary]$CommandAvailability
    )

    $resources=[System.Collections.Generic.List[object]]::new()
    $sourceOperations=[System.Collections.Generic.List[object]]::new()
    $collectionHealth=[System.Collections.Generic.List[object]]::new()

    function Add-HybridLocalRows {
        param([string]$Dataset,[string]$Command,[object[]]$Rows,[datetime]$StartedAt)
        $collectedAt=Get-Date
        $index=0
        foreach($row in @($Rows|Where-Object{$null-ne $_})){
            $index++
            $nameProperty=@($row.PSObject.Properties|Where-Object Name -in @('Name','Forest','Target')|Select-Object -First 1)
            $name=if($nameProperty.Count){[string]$nameProperty[0].Value}else{"$Dataset-$index"}
            $resources.Add([pscustomobject][ordered]@{
                    id="/providers/AzureScout/hybridIdentity/$Dataset/$([uri]::EscapeDataString($name))-$index"
                    name=$name;type="AZSC/HybridIdentity/$Dataset"
                    properties=[pscustomobject][ordered]@{Raw=$row}
                    AZSC=[pscustomobject][ordered]@{Source='Local read-only identity command';Dataset=$Dataset;Operation=$Command;Host=$env:COMPUTERNAME;CollectedAt=$collectedAt.ToString('o')}
                })
        }
        $sourceOperations.Add([pscustomobject][ordered]@{
                Source='Local read-only identity command';Dataset=$Dataset;Operation=$Command;Host=$env:COMPUTERNAME
                Status=if(@($Rows).Count){'Success'}else{'Empty'};Count=@($Rows).Count;Reason=$null
                StartedAt=$StartedAt.ToString('o');CompletedAt=$collectedAt.ToString('o')
            })
    }

    function Invoke-HybridLocalRead {
        param([string]$Dataset,[string]$Command,[scriptblock]$Operation,[string]$MissingReason)
        $startedAt=Get-Date
        $commandIsAvailable = if ($null -ne $CommandAvailability -and $CommandAvailability.Contains($Command)) {
            [bool]$CommandAvailability[$Command]
        }
        else {
            $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
        }
        if(-not $commandIsAvailable){
            $reason=$MissingReason
            $sourceOperations.Add([pscustomobject]@{Source='Local read-only identity command';Dataset=$Dataset;Operation=$Command;Host=$env:COMPUTERNAME;Status='NotAssessed';Count=0;Reason=$reason;StartedAt=$startedAt.ToString('o');CompletedAt=(Get-Date).ToString('o')})
            $collectionHealth.Add([pscustomobject]@{Dataset="HybridIdentity/$Dataset";Operation=$Command;Status='NotAssessed';Reason=$reason;ResourceTypes=@("AZSC/HybridIdentity/$Dataset")})
            return
        }
        try{
            $rows=@(& $Operation)
            Add-HybridLocalRows -Dataset $Dataset -Command $Command -Rows $rows -StartedAt $startedAt
        }catch{
            $reason=$_.Exception.Message
            $sourceOperations.Add([pscustomobject]@{Source='Local read-only identity command';Dataset=$Dataset;Operation=$Command;Host=$env:COMPUTERNAME;Status='Unavailable';Count=0;Reason=$reason;StartedAt=$startedAt.ToString('o');CompletedAt=(Get-Date).ToString('o')})
            $collectionHealth.Add([pscustomobject]@{Dataset="HybridIdentity/$Dataset";Operation=$Command;Status='Unavailable';Reason=$reason;ResourceTypes=@("AZSC/HybridIdentity/$Dataset")})
        }
    }

    Invoke-HybridLocalRead -Dataset 'EntraConnectScheduler' -Command 'Get-ADSyncScheduler' -MissingReason 'Microsoft Entra Connect ADSync cmdlets are not installed on this host.' -Operation {Get-ADSyncScheduler}
    Invoke-HybridLocalRead -Dataset 'EntraConnectConnectors' -Command 'Get-ADSyncConnector' -MissingReason 'Microsoft Entra Connect ADSync cmdlets are not installed on this host.' -Operation {Get-ADSyncConnector}
    Invoke-HybridLocalRead -Dataset 'EntraConnectGlobalSettings' -Command 'Get-ADSyncGlobalSettings' -MissingReason 'Microsoft Entra Connect ADSync cmdlets are not installed on this host.' -Operation {Get-ADSyncGlobalSettings}
    Invoke-HybridLocalRead -Dataset 'EntraConnectService' -Command 'Get-CimInstance' -MissingReason 'CIM is unavailable, so the local ADSync service version and binary path were not assessed.' -Operation {Get-CimInstance -ClassName Win32_Service -Filter "Name='ADSync'"}
    Invoke-HybridLocalRead -Dataset 'EntraConnectHealthAgents' -Command 'Get-Service' -MissingReason 'Service Control Manager access is unavailable, so Entra Connect Health agents were not assessed.' -Operation {Get-Service -Name 'AzureADConnectHealth*' -ErrorAction SilentlyContinue}
    Invoke-HybridLocalRead -Dataset 'ActiveDirectoryForest' -Command 'Get-ADForest' -MissingReason 'ActiveDirectory cmdlets are not installed or this host is not joined to a readable forest.' -Operation {Get-ADForest}
    Invoke-HybridLocalRead -Dataset 'ActiveDirectoryDomain' -Command 'Get-ADDomain' -MissingReason 'ActiveDirectory cmdlets are not installed or this host is not joined to a readable domain.' -Operation {Get-ADDomain}
    Invoke-HybridLocalRead -Dataset 'ActiveDirectoryTrusts' -Command 'Get-ADTrust' -MissingReason 'ActiveDirectory cmdlets are not installed or this host is not joined to a readable domain.' -Operation {Get-ADTrust -Filter *}

    [pscustomobject]@{Resources=@($resources);SourceOperations=@($sourceOperations);CollectionHealth=@($collectionHealth)}
}
