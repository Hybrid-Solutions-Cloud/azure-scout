<#
# Relocated from Modules/Public/PublicFunctions/Jobs for the v3 pipeline.
.Synopsis
Start Policy Job Module

.DESCRIPTION
This script processes and creates the Policy sheet based on advisor resources.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/PublicFunctions/Jobs/Start-AZSCPolicyJob.ps1

.COMPONENT
    This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Start-AZSCPolicyJob {
    param($Subscriptions, $PolicySetDef, $PolicyAssign, $PolicyDef)
    # ── StrictMode boundary (AB#5633, revised by AB#5649) ────────────────────────────
    # v1 inventory engine (forked from microsoft/ARI), written without StrictMode: it reads
    # optional fields off Azure payloads whose shape varies by tenant, so a Defender assessment
    # or Advisor recommendation that simply omits one would abort the run.
    #
    # This function is now CALLED DIRECTLY by Start-AZSCExtraJobs, in-process. It used to run
    # inside a Start-Job script block that re-imported the module, which re-applied module-scope
    # StrictMode inside the job even when the caller had opted out -- that is why the v2.5.3
    # opt-out had to be repeated at 17 entry points. With the job gone, this opt-out covers the
    # functions own call tree and nothing else. Removing it altogether is AB#5667s job, with
    # the recorded live-payload fixtures needed to do it safely.
    Set-StrictMode -Off


    $poltmp = $PolicyDef | Select-Object -Property id,properties -Unique

    $tmp = foreach ($1 in $PolicyAssign.policyAssignments)
        {
            if(![string]::IsNullOrEmpty($1.policySetDefinitionId))
                {
                    $TempPolDef = foreach ($PolDe in $PolicySetDef)
                        {
                            if ($PolDe.id -eq $1.policySetDefinitionId)
                                {
                                    $PolDe.properties.displayName
                                }
                        }
                    $Initiative = if(@($TempPolDef).count -gt 1){$TempPolDef[0]}else{$TempPolDef}
                    $InitNonCompRes = $1.results.nonCompliantResources
                    $InitNonCompPol = $1.results.nonCompliantPolicies
                }
            else
                {
                    $Initiative = ''
                    $InitNonCompRes = ''
                    $InitNonCompPol = ''
                }

            foreach ($2 in $1.policyDefinitions)
                {
                    $Pol = (($poltmp | Where-Object {$_.id -eq $2.policyDefinitionId}).properties)
                    if(![string]::IsNullOrEmpty($Pol))
                        {
                            $PolResUnkown = ($2.results.resourceDetails | Where-Object {$_.complianceState -eq 'unknown'} | Select-Object -ExpandProperty Count)
                            $PolResUnkown = if (![string]::IsNullOrEmpty($PolResUnkown)){$PolResUnkown}else{'0'}
                            $PolResCompl = ($2.results.resourceDetails | Where-Object {$_.complianceState -eq 'compliant'} | Select-Object -ExpandProperty Count)
                            $PolResCompl = if (![string]::IsNullOrEmpty($PolResCompl)){$PolResCompl}else{'0'}
                            $PolResNonCompl = ($2.results.resourceDetails | Where-Object {$_.complianceState -eq 'noncompliant'} | Select-Object -ExpandProperty Count)
                            $PolResNonCompl = if (![string]::IsNullOrEmpty($PolResNonCompl)){$PolResNonCompl}else{'0'}
                            $PolResExemp = ($2.results.resourceDetails | Where-Object {$_.complianceState -eq 'exempt'} | Select-Object -ExpandProperty Count)
                            $PolResExemp = if (![string]::IsNullOrEmpty($PolResExemp)){$PolResExemp}else{'0'}

                            $obj = @{
                                'Initiative'                            = $Initiative;
                                'Initiative Non Compliance Resources'   = $InitNonCompRes;
                                'Initiative Non Compliance Policies'    = $InitNonCompPol;
                                'Policy'                                = $Pol.displayName;
                                'Policy Type'                           = $Pol.policyType;
                                'Effect'                                = $2.effect;
                                'Compliance Resources'                  = $PolResCompl;
                                'Non Compliance Resources'              = $PolResNonCompl;
                                'Unknown Resources'                     = $PolResUnkown;
                                'Exempt Resources'                      = $PolResExemp
                                'Policy Mode'                           = $Pol.mode;
                                'Policy Version'                        = $Pol.version;
                                'Policy Deprecated'                     = $Pol.metadata.deprecated;
                                'Policy Category'                       = $Pol.metadata.category
                            }
                            $obj
                        }
                }
        }
    $tmp
}
