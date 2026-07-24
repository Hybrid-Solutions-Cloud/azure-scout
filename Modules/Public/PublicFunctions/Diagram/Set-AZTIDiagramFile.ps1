<#
.Synopsis
File Module for Draw.io Diagram

.DESCRIPTION
This module merges the standalone Draw.io cache files produced for the
Organization and Subscriptions topologies (each a full <mxfile> document,
potentially containing several <diagram> pages) into the main diagram
file ($DDFile, e.g. the Network Topology <mxfile>) as additional
sibling <diagram> pages. The result is a single, valid, multi-page
mxfile/diagram/mxGraphModel document that opens cleanly in draw.io.

.DESCRIPTION
This module is used for setting and managing files in the Draw.io Diagram.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/PublicFunctions/Diagram/Set-AZSCDiagramFile.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.7.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Set-AZSCDiagramFile {
    Param ($XMLFiles, $DDFile, $LogFile)
    try
    {
        ('DrawIOFileJob - '+(get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - Merging XML Files ') | Out-File -FilePath $LogFile -Append
        foreach ($File in $XMLFiles)
        {
            try
            {
                if (-not (Test-Path -Path $File))
                {
                    ('DrawIOFileJob - '+(get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - Skipping missing cache file: ' + $File) | Out-File -FilePath $LogFile -Append
                    continue
                }

                $SourceXml = New-Object System.Xml.XmlDocument
                $SourceXml.Load($File)

                $DestXml = New-Object System.Xml.XmlDocument
                $DestXml.Load($DDFile)

                # Each source cache file is itself a complete <mxfile> document that can
                # contain one or more <diagram> pages (e.g. Subscriptions.xml has one
                # <diagram> per subscription). Import every <diagram> page as a sibling
                # under the destination's <mxfile> root rather than nesting a whole
                # <mxfile> element inside another one, which is not a valid draw.io page.
                $DiagramNodes = $SourceXml.SelectNodes('/mxfile/diagram')

                if ($DiagramNodes.Count -eq 0)
                {
                    ('DrawIOFileJob - '+(get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - No <diagram> nodes found in: ' + $File) | Out-File -FilePath $LogFile -Append
                }

                foreach ($DiagramNode in $DiagramNodes)
                {
                    $ImportedNode = $DestXml.ImportNode($DiagramNode, $true)
                    $DestXml.DocumentElement.AppendChild($ImportedNode) | Out-Null
                }

                $DestXml.Save($DDFile)

                ('DrawIOFileJob - '+(get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - Merged '+$DiagramNodes.Count+' diagram page(s) from: ' + $File) | Out-File -FilePath $LogFile -Append

                Remove-Item -Path $File

                Start-Sleep -Milliseconds 200
            }
            catch
            {
                ('DrawIOFileJob - '+(get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - Error merging '+$File+': ' + $_.Exception.Message) | Out-File -FilePath $LogFile -Append
            }
        }
    }
    catch
    {
        ('DrawIOFileJob - '+(get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - Error: ' + $_.Exception.Message) | Out-File -FilePath $LogFile -Append
    }
}