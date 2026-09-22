#
# AB#7097. Authored by hand in the same shape scripts/ConvertTo-ScoutCollectorDefinition.ps1
# produces for the other Graph-backed Identity collectors (see AdminUnits.psd1, Groups.psd1)
# -- there is no source .ps1 to convert from, this service never had one. Field expressions read
# the normalised envelope Start-ScoutEntraExtraction's Add-NormalizedResource produces:
# $1.id / $1.tenantId / $1.properties, exactly like every other entra/* collector in this
# category. Fields cover verifiedIdProfile's documented v1.0 schema (name, description, state,
# priority, verifierDid, usage purpose, Face Check) -- see
# https://learn.microsoft.com/graph/api/resources/verifiedidprofile.
#
@{
    ResourceTypes = @(
        'entra/verifiedidprofiles'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
            $data = $1.properties

            $usagePurposes = if ($data.verifiedIdUsageConfigurations) { [string](@($data.verifiedIdUsageConfigurations | ForEach-Object { $_.purpose }) -join ', ') } else { '' }
            $faceCheckEnabled = if ($data.faceCheckConfiguration) { [string]$data.faceCheckConfiguration.state } else { '' }
            $acceptedIssuer = $data.verifiedIdProfileConfiguration.acceptedIssuer
'@

    AdditionalRowLoops = @()

    TagLoop = $null

    Fields = @(
        @{
            Name = 'ID'
            Expression = '$1.id'
        }
        @{
            Name = 'Tenant ID'
            Expression = '$1.tenantId'
        }
        @{
            Name = 'Display Name'
            Expression = '$data.name'
        }
        @{
            Name = 'Description'
            Expression = '$data.description'
        }
        @{
            Name = 'State'
            Expression = '$data.state'
        }
        @{
            Name = 'Priority'
            Expression = '[string]$data.priority'
        }
        @{
            Name = 'Verifier DID'
            Expression = '$data.verifierDid'
        }
        @{
            Name = 'Accepted Issuer'
            Expression = '$acceptedIssuer'
        }
        @{
            Name = 'Usage Purpose'
            Expression = '$usagePurposes'
        }
        @{
            Name = 'Face Check State'
            Expression = '$faceCheckEnabled'
        }
        @{
            Name = 'Last Modified'
            Expression = '[string]$data.lastModifiedDateTime'
        }
        @{
            Name = 'Resource U'
            Expression = '$ResUCount'
        }
    )

    Export = @{
        WorksheetName = 'Verified ID Profiles'
        TableNamePrefix = 'VerifiedIDProfilesTable_'
        Columns = @(
            'Display Name'
            'Description'
            'State'
            'Priority'
            'Verifier DID'
            'Accepted Issuer'
            'Usage Purpose'
            'Face Check State'
            'Last Modified'
            'Resource U'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @(
            'New-ConditionalText enabled -Range C:C -ConditionalType ContainsText -BackgroundColor LightGreen'
        )
    }

    SourceCollector = $null
}
