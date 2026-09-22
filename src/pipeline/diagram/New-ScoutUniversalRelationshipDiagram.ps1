#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Write a universal draw.io page from every discovered resource and ARM reference.

.DESCRIPTION
    The curated network diagram remains useful for presentation, but it cannot be the
    completeness boundary because it knows a finite resource-type map. This page uses the same
    generic ARM-reference extraction as the discovery report. Every discovered ARM resource is a
    node, every ARM id found in its control-plane properties is an edge, and referenced targets
    outside the discovered set are retained as explicit external-reference nodes.

.NOTES
    AB#7367.
#>
function New-ScoutUniversalRelationshipDiagram {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Resources,
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Get-Command Get-ScoutResourceCompleteness -ErrorAction SilentlyContinue)) {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Get-ScoutResourceCompleteness.ps1')
    }
    $discovery = Get-ScoutResourceCompleteness -Resources $Resources
    $nodesById = [ordered]@{}
    foreach ($resource in @($discovery.Resources)) {
        if (-not $resource.Id) { continue }
        $nodesById[[string]$resource.Id] = [pscustomobject]@{
            Id       = [string]$resource.Id
            Name     = [string]$resource.Name
            Type     = [string]$resource.Type
            Exposure = [string]$resource.Exposure
            Detail   = [string]$resource.DetailStatus
            External = $false
        }
    }
    foreach ($relationship in @($discovery.Relationships)) {
        $targetId = [string]$relationship.TargetId
        if ([string]::IsNullOrWhiteSpace($targetId) -or $nodesById.Contains($targetId)) { continue }
        $targetSegments = @($targetId.TrimEnd('/') -split '/')
        $nodesById[$targetId] = [pscustomobject]@{
            Id       = $targetId
            Name     = if ($targetSegments.Count -gt 0) { $targetSegments[-1] } else { $targetId }
            Type     = 'Referenced resource outside discovered set'
            Exposure = 'Unknown'
            Detail   = 'ExternalReference'
            External = $true
        }
    }

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('mxfile')
        $writer.WriteAttributeString('host', 'AzureScout')
        $writer.WriteStartElement('diagram')
        $writer.WriteAttributeString('id', 'azure-scout-universal-resource-graph')
        $writer.WriteAttributeString('name', 'Universal Resource Graph')
        $writer.WriteStartElement('mxGraphModel')
        $writer.WriteAttributeString('grid', '1')
        $writer.WriteAttributeString('page', '1')
        $writer.WriteAttributeString('pageScale', '1')
        $writer.WriteAttributeString('pageWidth', '1169')
        $writer.WriteAttributeString('pageHeight', '827')
        $writer.WriteStartElement('root')
        foreach ($base in @(@{ Id = '0'; Parent = $null }, @{ Id = '1'; Parent = '0' })) {
            $writer.WriteStartElement('mxCell')
            $writer.WriteAttributeString('id', $base.Id)
            if ($base.Parent) { $writer.WriteAttributeString('parent', $base.Parent) }
            $writer.WriteEndElement()
        }

        $cellByResourceId = @{}
        $index = 0
        foreach ($entry in $nodesById.GetEnumerator()) {
            $node = $entry.Value
            $cellId = "resource-$index"
            $cellByResourceId[[string]$entry.Key] = $cellId
            $column = $index % 8
            $row = [math]::Floor($index / 8)
            $fill = switch ($node.Exposure) {
                'Public'  { '#f8cecc' }
                'Mixed'   { '#ffe6cc' }
                'Private' { '#d5e8d4' }
                default   { if ($node.External) { '#e1d5e7' } else { '#dae8fc' } }
            }
            $writer.WriteStartElement('mxCell')
            $writer.WriteAttributeString('id', $cellId)
            $label = '<b>{0}</b><br><font style="font-size: 9px">{1}</font>' -f $node.Name, $node.Type
            $writer.WriteAttributeString('value', $label)
            $writer.WriteAttributeString('style', "rounded=1;whiteSpace=wrap;html=1;fillColor=$fill;strokeColor=#666666;fontSize=10;")
            $writer.WriteAttributeString('vertex', '1')
            $writer.WriteAttributeString('parent', '1')
            $writer.WriteAttributeString('ResourceId', $node.Id)
            $writer.WriteAttributeString('ResourceType', $node.Type)
            $writer.WriteAttributeString('Exposure', $node.Exposure)
            $writer.WriteAttributeString('DetailStatus', $node.Detail)
            $writer.WriteStartElement('mxGeometry')
            $writer.WriteAttributeString('x', [string](20 + ($column * 225)))
            $writer.WriteAttributeString('y', [string](20 + ($row * 90)))
            $writer.WriteAttributeString('width', '205')
            $writer.WriteAttributeString('height', '64')
            $writer.WriteAttributeString('as', 'geometry')
            $writer.WriteEndElement()
            $writer.WriteEndElement()
            $index++
        }

        $edgeIndex = 0
        foreach ($relationship in @($discovery.Relationships)) {
            $sourceId = [string]$relationship.SourceId
            $targetId = [string]$relationship.TargetId
            if (-not $cellByResourceId.ContainsKey($sourceId) -or -not $cellByResourceId.ContainsKey($targetId)) { continue }
            $writer.WriteStartElement('mxCell')
            $writer.WriteAttributeString('id', "relationship-$edgeIndex")
            $writer.WriteAttributeString('value', [string]$relationship.RelationshipType)
            $writer.WriteAttributeString('style', 'edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=block;endFill=1;fontSize=8;')
            $writer.WriteAttributeString('edge', '1')
            $writer.WriteAttributeString('parent', '1')
            $writer.WriteAttributeString('source', $cellByResourceId[$sourceId])
            $writer.WriteAttributeString('target', $cellByResourceId[$targetId])
            $writer.WriteAttributeString('PropertyPath', [string]$relationship.PropertyPath)
            $writer.WriteStartElement('mxGeometry')
            $writer.WriteAttributeString('relative', '1')
            $writer.WriteAttributeString('as', 'geometry')
            $writer.WriteEndElement()
            $writer.WriteEndElement()
            $edgeIndex++
        }

        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally { $writer.Dispose() }

    [pscustomobject]@{ Path = $Path; Resources = $nodesById.Count; Relationships = @($discovery.Relationships).Count }
}
