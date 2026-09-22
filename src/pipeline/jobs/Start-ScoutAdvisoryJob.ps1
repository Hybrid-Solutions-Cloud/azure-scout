#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
# Relocated from Modules/Public/PublicFunctions/Jobs for the v3 pipeline.
.Synopsis
Public Advisory Job Module

.DESCRIPTION
This script creates the job to process the Advisory data.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Public/PublicFunctions/Jobs/Start-AZSCAdvisoryJob.ps1

.COMPONENT
    This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.9
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Start-AZSCAdvisoryJob {
    param($Advisories)
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


    $tmp = foreach ($1 in $Advisories)
        {
            $data = $1.PROPERTIES

            if ($data.resourceMetadata.resourceId)
                {
                    $Savings = if([string]::IsNullOrEmpty($data.extendedProperties.annualSavingsAmount)){0}Else{$data.extendedProperties.annualSavingsAmount}
                    $SavingsCurrency = if([string]::IsNullOrEmpty($data.extendedProperties.savingsCurrency)){'USD'}Else{$data.extendedProperties.savingsCurrency}
                    $Resource = $data.resourceMetadata.resourceId.split('/')

                    if ($Resource.Count -lt 4) {
                        $ResourceType = $data.impactedField
                        $ResourceName = $data.impactedValue
                    }
                    else {
                        $ResourceType = ($Resource[6] + '/' + $Resource[7])
                        $ResourceName = $Resource[8]
                    }

                    if ($data.impactedField -eq $ResourceType) {
                            $ImpactedField = ''
                    }
                    else {
                            $ImpactedField = $data.impactedField
                    }

                    if ($data.impactedValue -eq $ResourceName) {
                            $ImpactedValue = ''
                    }
                    else {
                            $ImpactedValue = $data.impactedValue
                        }

                    $obj = @{
                        'Subscription'           = $Resource[2];
                        'Resource Group'         = $Resource[4];
                        'Resource Type'          = $ResourceType;
                        'Name'                   = $ResourceName;
                        'Detailed Type'          = $ImpactedField;
                        'Detailed Name'          = $ImpactedValue;
                        'Category'               = $data.category;
                        'Impact'                 = $data.impact;
                        'Description'            = $data.shortDescription.problem;
                        'SKU'                    = $data.extendedProperties.sku;
                        'Term'                   = $data.extendedProperties.term;
                        'Look-back Period'       = $data.extendedProperties.lookbackPeriod;
                        'Quantity'               = $data.extendedProperties.qty;
                        'Savings Currency'       = $SavingsCurrency;
                        'Annual Savings'         = "=$Savings";
                        'Savings Region'         = $data.extendedProperties.region
                    }
                    $obj
                }
        }
    $tmp
}
