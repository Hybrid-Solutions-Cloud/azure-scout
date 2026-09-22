#
# HAND-AUTHORED -- AB#7098 (Story AB#7071, Feature AB#7069, Epic AB#7099). Unlike its Identity
# category neighbours, this collector has no legacy Modules/Public/InventoryModules/*.ps1 to be
# converted FROM -- Microsoft Entra External ID's tenant-wide default cross-tenant access
# configuration has never been collected by this codebase before. There is therefore no
# SourceCollector key and no scripts/ConvertTo-ScoutCollectorDefinition.ps1 provenance; this
# definition is authored directly against the shape src/collect/Get-ScoutEntraQueryCatalog.ps1's
# 'External Identities' query (GET /v1.0/policies/crossTenantAccessPolicy/default) normalises
# into `entra/externalidentities` rows, following the SAME field-expression style as
# CrossTenantAccess.psd1 (its nearest sibling -- the per-PARTNER override list, where this
# collector is the tenant-wide DEFAULT every non-listed partner inherits).
#
# See Get-ScoutEntraQueryCatalog.ps1's 'External Identities' entry for why
# /v1.0/policies/crossTenantAccessPolicy/default was chosen over the /beta-only
# /policies/externalIdentitiesPolicy self-service toggle.
#
@{
    ResourceTypes = @(
        'entra/externalidentities'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
            $data = $1.properties

            # B2B Collaboration -- default inbound/outbound stance for every partner organization
            # not covered by a Cross-Tenant Access partner override (CrossTenantAccess.psd1).
            $b2bCollabInbound = if ($data.b2bCollaborationInbound.applications.accessType) { $data.b2bCollaborationInbound.applications.accessType } else { 'Not Configured' }
            $b2bCollabOutbound = if ($data.b2bCollaborationOutbound.applications.accessType) { $data.b2bCollaborationOutbound.applications.accessType } else { 'Not Configured' }

            # B2B Direct Connect -- same shape, for Direct Connect rather than Collaboration.
            $b2bDirectInbound = if ($data.b2bDirectConnectInbound.applications.accessType) { $data.b2bDirectConnectInbound.applications.accessType } else { 'Not Configured' }
            $b2bDirectOutbound = if ($data.b2bDirectConnectOutbound.applications.accessType) { $data.b2bDirectConnectOutbound.applications.accessType } else { 'Not Configured' }

            # Inbound trust -- which external Conditional Access claims (MFA / compliant device /
            # hybrid Azure AD join) this tenant accepts from an external organization by default.
            $inboundTrust = ''
            if ($data.inboundTrust) {
                $trustParts = @()
                if ($data.inboundTrust.isMfaAccepted) { $trustParts += 'MFA' }
                if ($data.inboundTrust.isCompliantDeviceAccepted) { $trustParts += 'CompliantDevice' }
                if ($data.inboundTrust.isHybridAzureADJoinedDeviceAccepted) { $trustParts += 'HybridAADJoined' }
                $inboundTrust = ($trustParts -join ', ')
            }

            # Tenant Restrictions -- the default stance for OUR users accessing an EXTERNAL
            # organization from our network/devices using an external identity.
            $tenantRestrictions = if ($data.tenantRestrictions.usersAndGroups.accessType) { $data.tenantRestrictions.usersAndGroups.accessType } else { 'Not Configured' }
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
            Name = 'Is Service Default'
            Expression = '[bool]$data.isServiceDefault'
        }
        @{
            Name = 'B2B Collaboration Inbound'
            Expression = '$b2bCollabInbound'
        }
        @{
            Name = 'B2B Collaboration Outbound'
            Expression = '$b2bCollabOutbound'
        }
        @{
            Name = 'B2B Direct Connect Inbound'
            Expression = '$b2bDirectInbound'
        }
        @{
            Name = 'B2B Direct Connect Outbound'
            Expression = '$b2bDirectOutbound'
        }
        @{
            Name = 'Inbound Trust'
            Expression = '$inboundTrust'
        }
        @{
            Name = 'Tenant Restrictions'
            Expression = '$tenantRestrictions'
        }
        @{
            Name = 'Resource U'
            Expression = '$ResUCount'
        }
    )

    Export = @{
        WorksheetName = 'External Identities'
        TableNamePrefix = 'ExtIdTable_'
        Columns = @(
            'Is Service Default'
            'B2B Collaboration Inbound'
            'B2B Collaboration Outbound'
            'B2B Direct Connect Inbound'
            'B2B Direct Connect Outbound'
            'Inbound Trust'
            'Tenant Restrictions'
            'Resource U'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
