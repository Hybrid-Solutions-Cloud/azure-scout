#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Load and structurally validate a declarative collector definition (AB#5657/AB#5661).

.DESCRIPTION
    Loads a `.psd1` collector definition with `Import-PowerShellDataFile` -- restricted-language
    parsing, so a definition that tried to smuggle a function call or a live variable reference
    back in fails to load rather than silently running as code. See
    `docs/design/decisions/declarative-collectors.md` for the schema this validates against.

    Used by both `Invoke-ScoutDeclarativeCollector` (to run one) and
    `tests/CollectorDefinitionSchema.Tests.ps1` (to validate every one in CI), so the two can
    never drift on what "a valid definition" means.

.PARAMETER Path
    Path to the `.psd1` file.

.OUTPUTS
    The loaded definition (PSCustomObject) with every optional key defaulted, so callers never
    need `$Definition.Foo ?? <default>` scattered through their own code.

.NOTES
    Tracks ADO AB#5657 (Feature AB#5656, Epic AB#5638).
#>
function Get-ScoutCollectorDefinition {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Collector definition not found: $Path"
    }

    $Raw = Import-PowerShellDataFile -Path $Path

    $Errors   = [System.Collections.Generic.List[string]]::new()
    $Warnings = [System.Collections.Generic.List[string]]::new()

    if (-not $Raw.ContainsKey('ResourceTypes') -or @($Raw.ResourceTypes).Count -eq 0) {
        $Errors.Add('ResourceTypes must be a non-empty array of Azure resource type strings.')
    } else {
        foreach ($Type in @($Raw.ResourceTypes)) {
            if ($Type -isnot [string] -or [string]::IsNullOrWhiteSpace($Type)) {
                $Errors.Add("ResourceTypes contains a non-string or empty entry: '$Type'.")
            }
        }
    }

    # 'Grouped' (one filtered pass per declared type, appended -- the `+=` shape) or 'SinglePass'
    # (one pass admitting several types -- the `-in @(...)` shape). An unrecognised value is an
    # ERROR, not a fallback to the default: the two produce different ROW ORDER for a multi-type
    # collector, and quietly guessing is how `Hybrid/ArcSites.ps1` came out with its worksheet
    # reordered (see the interpreter, and declarative-collectors.md §2.5).
    $ValidMatching = @('Grouped', 'SinglePass')
    if ($Raw.Contains('ResourceTypeMatching') -and $ValidMatching -notcontains $Raw.ResourceTypeMatching) {
        $Errors.Add("ResourceTypeMatching is '$($Raw.ResourceTypeMatching)'; it must be one of: $($ValidMatching -join ', ').")
    }

    if (-not $Raw.ContainsKey('RowLoopVariable') -or [string]::IsNullOrWhiteSpace($Raw.RowLoopVariable)) {
        $Errors.Add('RowLoopVariable must name the variable field expressions use for the current resource (e.g. "1").')
    }

    if (-not $Raw.ContainsKey('Fields') -or @($Raw.Fields).Count -eq 0) {
        $Errors.Add('Fields must be a non-empty array of { Name; Expression } entries.')
    } else {
        $SeenNames = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Field in @($Raw.Fields)) {
            if ($Field -isnot [System.Collections.IDictionary]) {
                $Errors.Add('Every Fields entry must be a hashtable with Name and Expression.')
                continue
            }
            if (-not $Field.Contains('Name') -or [string]::IsNullOrWhiteSpace($Field.Name)) {
                $Errors.Add('A Fields entry is missing a non-empty Name.')
            } elseif (-not $SeenNames.Add($Field.Name)) {
                $Errors.Add("Fields declares '$($Field.Name)' more than once.")
            }
            if (-not $Field.Contains('Expression') -or [string]::IsNullOrWhiteSpace($Field.Expression)) {
                $Errors.Add("Field '$($Field.Name)' is missing a non-empty Expression.")
            }
        }
    }

    if (-not $Raw.ContainsKey('Export') -or $Raw.Export -isnot [System.Collections.IDictionary]) {
        $Errors.Add('Export must be a hashtable describing the Excel sheet.')
    } else {
        if ([string]::IsNullOrWhiteSpace($Raw.Export.WorksheetName)) { $Errors.Add('Export.WorksheetName must be a non-empty string.') }
        if (-not $Raw.Export.Contains('Columns') -or @($Raw.Export.Columns).Count -eq 0) { $Errors.Add('Export.Columns must be a non-empty ordered array of field names.') }
        if ($Raw.Export.Contains('Columns')) {
            # A WARNING, not a schema error: `Select-Object $Exc` in the original engine does not
            # require the property to exist either -- a name mismatch produces a silently blank
            # column rather than a failure. Two of the 13 converted Databases collectors have
            # exactly this pre-existing bug (Databases/RedisCache.ps1 exports 'Resource Group'
            # for a field processed as 'ResourceGroup'; Databases/SQLMI.ps1 exports
            # 'ActiveDirectoryOnlyAuthentication' for a field processed as
            # 'AzureADOnlyAuthentication' -- both columns have been blank in every shipped
            # release). Faithful conversion means keeping the bug, not silently fixing it here.
            $FieldNames = @(@($Raw.Fields) | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('Name') } | ForEach-Object { $_.Name })
            foreach ($Col in @($Raw.Export.Columns)) {
                if ($FieldNames -notcontains $Col) { $Warnings.Add("Export.Columns references '$Col', which is not a declared Field name -- this column will always be blank (pre-existing behaviour, not a conversion defect).") }
            }
        }
        # Unlike a Columns/Fields name mismatch, this one IS an error: a TagColumnsBefore naming a
        # column that does not exist would silently fall back to appending, reintroducing exactly
        # the column-reordering defect the key exists to prevent.
        if ($Raw.Export.Contains('TagColumnsBefore') -and -not [string]::IsNullOrWhiteSpace($Raw.Export.TagColumnsBefore)) {
            if (@($Raw.Export.Columns) -notcontains $Raw.Export.TagColumnsBefore) {
                $Errors.Add("Export.TagColumnsBefore is '$($Raw.Export.TagColumnsBefore)', which is not one of Export.Columns.")
            }
        }
    }

    if ($Raw.Contains('AdditionalRowLoops')) {
        foreach ($Loop in @($Raw.AdditionalRowLoops)) {
            if ($Loop -isnot [System.Collections.IDictionary] -or -not $Loop.Contains('Variable') -or -not $Loop.Contains('Source')) {
                $Errors.Add('Every AdditionalRowLoops entry must be a hashtable with Variable and Source.')
                continue
            }
            # Optional per-loop setup, run once per item of the fanned-out collection. Rejected as a
            # non-string rather than coerced: a hashtable slipped in here would stringify to
            # 'System.Collections.Hashtable' and be injected into the generated script as garbage.
            if ($Loop.Contains('Preamble') -and $null -ne $Loop.Preamble -and $Loop.Preamble -isnot [string]) {
                $Errors.Add("AdditionalRowLoops entry '$($Loop.Variable)' has a Preamble that is not a string.")
            }
        }
    }

    # The per-tag row expansion is DECLARED, not assumed. It is neither universal (25 collectors --
    # every convertible Identity one, most Management ones, Monitor/Outages -- emit exactly one row
    # per resource and have no tag loop at all) nor consistently named (Networking/RouteTables calls
    # its tag variable $TagKey). `TagLoop = $null` means "no tag expansion"; omitting the key
    # entirely keeps the historic default of `foreach ($Tag in $Tags)`.
    if ($Raw.Contains('TagLoop') -and $null -ne $Raw.TagLoop) {
        if ($Raw.TagLoop -isnot [System.Collections.IDictionary] -or
            -not $Raw.TagLoop.Contains('Variable') -or -not $Raw.TagLoop.Contains('Source')) {
            $Errors.Add('TagLoop must be $null or a hashtable with Variable and Source.')
        }
    }

    if ($Raw.Contains('FilterPreamble') -and $null -ne $Raw.FilterPreamble -and $Raw.FilterPreamble -isnot [string]) {
        $Errors.Add('FilterPreamble must be a string of statements to run before AdditionalFilter is evaluated.')
    }
    if ($Raw.Contains('FilterPreamble') -and -not [string]::IsNullOrWhiteSpace($Raw.FilterPreamble) -and
        [string]::IsNullOrWhiteSpace($Raw.AdditionalFilter)) {
        # A FilterPreamble with nothing to filter is dead code that reads as if it were doing
        # something. Loud, because a lost AdditionalFilter is a silently over-broad collector.
        $Errors.Add('FilterPreamble is set but AdditionalFilter is empty, so the preamble would never be used.')
    }

    if (@($Errors).Count -gt 0) {
        throw "Collector definition '$Path' failed schema validation:`n - $($Errors -join "`n - ")"
    }

    [PSCustomObject]@{
        Path               = $Path
        ResourceTypes      = @($Raw.ResourceTypes)
        # Absent means 'Grouped' -- the shape the 13 already-proven Databases definitions were
        # written against, so their behaviour is unchanged by this key existing.
        ResourceTypeMatching = if ($Raw.Contains('ResourceTypeMatching') -and -not [string]::IsNullOrWhiteSpace($Raw.ResourceTypeMatching)) { [string]$Raw.ResourceTypeMatching } else { 'Grouped' }
        AdditionalFilter   = if ($Raw.Contains('AdditionalFilter')) { $Raw.AdditionalFilter } else { $null }
        FilterPreamble     = if ($Raw.Contains('FilterPreamble')) { [string]$Raw.FilterPreamble } else { '' }
        RowLoopVariable    = $Raw.RowLoopVariable
        Preamble           = if ($Raw.Contains('Preamble')) { [string]$Raw.Preamble } else { '' }
        # Normalised so the interpreter can read .Preamble unconditionally instead of testing for
        # the key on every loop of every collector.
        AdditionalRowLoops = @(if ($Raw.Contains('AdditionalRowLoops')) {
            foreach ($Loop in @($Raw.AdditionalRowLoops)) {
                @{
                    Variable = $Loop.Variable
                    Source   = $Loop.Source
                    Preamble = if ($Loop.Contains('Preamble') -and $null -ne $Loop.Preamble) { [string]$Loop.Preamble } else { '' }
                }
            }
        } else { @() })
        TagLoop            = if (-not $Raw.Contains('TagLoop')) {
                                 @{ Variable = 'Tag'; Source = '$Tags'; Preamble = '' }
                             } elseif ($null -eq $Raw.TagLoop) {
                                 $null
                             } else {
                                 @{
                                     Variable = $Raw.TagLoop.Variable
                                     Source   = $Raw.TagLoop.Source
                                     Preamble = if ($Raw.TagLoop.Contains('Preamble') -and $null -ne $Raw.TagLoop.Preamble) { [string]$Raw.TagLoop.Preamble } else { '' }
                                 }
                             }
        Fields             = @($Raw.Fields)
        Export             = [PSCustomObject]@{
            WorksheetName   = $Raw.Export.WorksheetName
            TableNamePrefix = if ($Raw.Export.Contains('TableNamePrefix')) { $Raw.Export.TableNamePrefix } else { $Raw.Export.WorksheetName + '_' }
            Columns         = @($Raw.Export.Columns)
            TagColumns      = @(if ($Raw.Export.Contains('TagColumns')) { @($Raw.Export.TagColumns) } else { @('Tag Name', 'Tag Value') })
            # Name of the Columns entry the tag block is inserted BEFORE when $InTag is set.
            # $null (or absent) means "append at the end", which is what the schema's first draft
            # always did -- and was wrong for all 13 Databases collectors, every one of which adds
            # 'Resource U' after its `if ($InTag)` block.
            TagColumnsBefore = if ($Raw.Export.Contains('TagColumnsBefore')) { $Raw.Export.TagColumnsBefore } else { $null }
            NumberFormat    = if ($Raw.Export.Contains('NumberFormat')) { $Raw.Export.NumberFormat } else { '0' }
            ConditionalText = @(if ($Raw.Export.Contains('ConditionalText')) { @($Raw.Export.ConditionalText) } else { @() })
        }
        SourceCollector    = if ($Raw.Contains('SourceCollector')) { $Raw.SourceCollector } else { $null }
        SchemaWarnings     = @($Warnings)
    }
}
