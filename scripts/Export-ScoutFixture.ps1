#Requires -Version 7.0
<#
.SYNOPSIS
    Capture real Azure Resource Graph payload SHAPES into anonymised, reusable test fixtures
    (AB#5667).

.DESCRIPTION
    The former source-script collectors were unit-tested only against
    small, hand-built mock objects (see e.g. `tests/Compute.Module.Tests.ps1`). That is enough
    to prove a collector does not throw on ONE clean shape, but it is not enough to catch the
    StrictMode class of defect: real Azure API responses omit properties, return empty arrays
    where a collector expects a populated one, and produce resource IDs of varying segment
    counts (a subscription-scoped Defender assessment vs. a resource-scoped one). None of that
    shows up in a mock built from imagination.

    This script runs the SAME three Resource Graph queries the extraction phase runs --
    `resources`, `resourcecontainers`, `networkresources` -- against whatever tenant the caller
    is signed into (`Search-AzGraph`), plus `Get-AzSubscription` for the subscription list, and
    writes the results to `tests/fixtures/` as JSON so `tests/CollectorStrictMode.Tests.ps1` can
    replay them offline, with no Azure connection, on every run.

    WHAT A FIXTURE IS FOR -- AND WHY THE VALUES DO NOT MATTER
    ---------------------------------------------------------
    These fixtures exist to reproduce STRUCTURE: which properties are present, which are
    absent, which arrays are empty, how many segments a resource id has, how deep a nesting
    goes. That -- not the content of any string -- is what decides whether a collector throws
    under `Set-StrictMode -Version Latest`. A VM whose `hardwareProfile.vmSize` reads
    "Standard_D2s_v5" and one whose reads "res4f2a91c0" exercise a collector identically.

    That observation is what makes safe anonymisation tractable, and it drives the design
    below.

    ANONYMISATION IS DEFAULT-DENY
    -----------------------------
    An EARLIER version of this script anonymised any string that MATCHED a sensitive pattern
    (a GUID, an email, an IPv4, an ARM id) and passed everything else through untouched. That
    polarity is unsafe, and it leaked badly in practice. Real payloads carry identifying data
    in forms no pattern anticipates:

      * free-text tag values and tag KEYS  -- "BusinessUnit: <company name>", "Contact:"
      * URL PATHS after an anonymised host -- ".../resourceGroups/<real rg>/containerApps/<real app>"
      * Key Vault secret NAMES             -- a complete map of an estate's secret inventory
      * container image repositories/digests
      * base64-encoded shell commands      -- carrying real client IDs, FQDNs and DB usernames
                                              straight past a plaintext scanner
      * assorted opaque tokens (domain-verification ids, internal ids)

    So the polarity is now inverted. EVERY string leaf, and every dictionary KEY that is not
    itself part of the ARM schema, is replaced with a deterministic token UNLESS it is
    explicitly allow-listed. There are exactly three ways a string survives:

      1. It sits under an allow-listed SCHEMA key ($script:SchemaValueKeys -- `type`, `kind`,
         `location`, `zones`) AND matches $script:SchemaValuePattern. These are ARM provider
         types, resource kinds and region names: platform vocabulary, identical in every
         tenant on earth, and the one thing collectors genuinely branch on
         (`$Resources | Where-Object { $_.TYPE -eq 'microsoft.compute/virtualmachines' }`).
      2. It is an ARM resource id, rebuilt segment-by-segment: the `/subscriptions/{guid}/
         resourceGroups/{rg}/providers/{Namespace}/{type}/{name}` skeleton and its SEGMENT
         COUNT are preserved (about thirty collectors index a split id by a fixed `[7]`/`[8]`
         -- AB#5649 -- so the count is load-bearing structure), provider namespaces and type
         segments are kept as schema, and every GUID / resource-group / name segment is
         tokenised.
      3. It is a structural key name (a property NAME from the ARM schema, as opposed to a
         customer-chosen tag key).

    Everything else -- every value, however innocent it looks -- becomes `res########`. There
    is no pattern list to keep up to date, and a payload field nobody anticipated fails CLOSED.

    DETERMINISTIC: the replacement is a SHA-256 hash of "$Kind|$Value", not a random seed or a
    per-run counter, so:
      * a subscriptionId that appears on 40 resources tokenises to the same fake GUID on all 40,
        keeping cross-references between rows intact;
      * fixtures are stable across re-capture -- a diff against a previous fixture shows only
        genuine tenant drift, not anonymisation noise;
      * re-running the scrubber over an already-scrubbed file is a no-op-shaped, idempotent
        operation (a token re-tokenises, but consistently), so -ReScrub is safe to repeat.

    NUMBERS, BOOLEANS AND NULLS ARE PRESERVED EXACTLY, as is nesting depth, array length and
    property ORDER -- that is the entire point of a fixture.

    FAIL-CLOSED VERIFICATION
    ------------------------
    Writing a fixture runs `Test-ScoutFixtureAnonymity` over the ANONYMISED result and THROWS
    rather than write a file that still contains anything unrecognised. `tests/
    FixtureAnonymity.Tests.ps1` runs the same check over the committed `captured-*.json` on
    every CI run, so a fixture cannot silently regain a leak later.

.PARAMETER OutputPath
    Directory fixtures are written to. Defaults to `tests/fixtures` under the repo root.

.PARAMETER First
    Page size passed to Search-AzGraph. Defaults to 1000 (the Resource Graph maximum).

.PARAMETER ManagementGroup
    Optional management-group scope, matching Start-AZSCGraphExtraction's own -ManagementGroup.

.PARAMETER SubscriptionId
    Optional subscription-id scope. Without it, every subscription the signed-in principal can
    see is queried, exactly as a normal inventory run would.

.PARAMETER ReScrub
    Re-anonymise the `captured-*.json` files ALREADY in -OutputPath, in place, instead of
    querying Azure. Requires no Azure connection and no Az modules. This exists so a fix to the
    anonymiser can be applied to fixtures that are already captured (and already committed)
    without a fresh tenant run -- anonymisation is a pure text-to-text transform, so re-running
    it over a previous output is both possible and, because the transform is deterministic,
    reproducible.

.OUTPUTS
    None. Writes `captured-resources.json`, `captured-networkresources.json`,
    `captured-resourcecontainers.json` and `captured-subscriptions.json` to -OutputPath, and
    prints a per-file row count.

.EXAMPLE
    ./scripts/Export-ScoutFixture.ps1
    Capture fresh fixtures from the signed-in tenant.

.EXAMPLE
    ./scripts/Export-ScoutFixture.ps1 -ReScrub
    Re-anonymise the committed fixtures offline after an anonymiser fix. No Azure needed.

.NOTES
    Tracks ADO AB#5667 (Epic AB#5638).

    Capture mode requires Az.Accounts and Az.ResourceGraph, and an already-authenticated
    context (Connect-AzAccount). This script only READS -- Search-AzGraph and Get-AzSubscription
    are both read-only Resource Manager operations. -ReScrub touches no network at all.
#>
[CmdletBinding(DefaultParameterSetName = 'Capture')]
param(
    [string] $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'tests', 'fixtures'),

    [Parameter(ParameterSetName = 'Capture')]
    [ValidateRange(1, 1000)]
    [int] $First = 1000,

    [Parameter(ParameterSetName = 'Capture')]
    [string] $ManagementGroup,

    [Parameter(ParameterSetName = 'Capture')]
    [string[]] $SubscriptionId,

    [Parameter(Mandatory, ParameterSetName = 'ReScrub')]
    [switch] $ReScrub
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OutputPath = (New-Item -Path $OutputPath -ItemType Directory -Force).FullName

# The four files this script owns. -ReScrub walks exactly this list; the hand-authored
# `edge-case-*.json` fixtures are deliberately NOT included -- they contain no tenant data (their
# ids are 1111...-shaped placeholders), and tokenising their deliberately-meaningful names
# ("vm-nodisk-01") would destroy the documentation value that is the whole reason they are
# hand-written rather than captured.
$script:CapturedFixtureFiles = @(
    'captured-resources.json'
    'captured-networkresources.json'
    'captured-resourcecontainers.json'
    'captured-subscriptions.json'
)

# ============================================================================
# Deterministic tokenisation
# ============================================================================

# RFC 5737 TEST-NET-3 -- reserved for documentation, never a real routable address.
$script:AnonIpPrefix = '203.0.113'

function Get-ScoutAnonymizedToken {
    <#
    .SYNOPSIS
        Turn one value into a stable, deterministic replacement.

    .DESCRIPTION
        The replacement is derived from a SHA-256 hash of "$Kind|$Value", so the same input
        always produces the same output (no lookup table needed, and no state to persist
        between runs) while different inputs -- even ones that only differ by $Kind -- hash to
        different outputs.

        The distinct $Kind values exist so a replacement stays VALID where its position demands
        a particular shape: a subscription id segment must still parse as a GUID, an IP field
        must still parse as an address. Everywhere else 'Name' is used.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value,
        [Parameter(Mandatory)] [ValidateSet('Guid', 'Ipv4', 'Name', 'Key')] [string] $Kind
    )

    $bytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$Kind|$Value"))

    switch ($Kind) {
        'Guid' {
            $hex = -join ($bytes[0..15] | ForEach-Object { $_.ToString('x2') })
            return ([guid]$hex).Guid
        }
        'Ipv4' {
            return "$script:AnonIpPrefix.$($bytes[0] % 255)"
        }
        'Name' {
            $hex = -join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') })
            return "res$hex"
        }
        'Key' {
            $hex = -join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') })
            return "key$hex"
        }
    }
}

$script:GuidRegex = [regex]'(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$script:Ipv4Regex = [regex]'^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

# ---------------------------------------------------------------------------
# The allow-list. This is the ENTIRE set of ways a captured string can survive
# anonymisation, and it is deliberately tiny enough to audit by eye.
# ---------------------------------------------------------------------------

# Property keys whose values are ARM platform vocabulary, not tenant data. `type` is the one
# collectors genuinely branch on (every collector's first line filters `$_.TYPE -eq '<type>'`),
# so tokenising it would make every collector match zero rows and render the whole harness
# vacuous. `kind`, `location` and `zones` are the same class of value: a fixed vocabulary
# published by Azure, identical across every tenant, carrying no information about WHOSE
# tenant this is.
$script:SchemaValueKeys = @('type', 'kind', 'location', 'zones')

# ...and even under those keys the value must look like platform vocabulary. A resource type is
# `microsoft.compute/virtualmachines`; a region is `eastus2`. Neither contains whitespace, an
# `@`, a `:`, a `%` or a `/`-prefixed path. Anything under an allow-listed key that does NOT
# match this is tokenised anyway -- the allow-list narrows, it never widens.
$script:SchemaValuePattern = [regex]'^[A-Za-z][A-Za-z0-9._-]*(/[A-Za-z0-9._-]+)*$'

# A dictionary KEY is normally an ARM schema property name (`osProfile`, `provisioningState`)
# and carries no tenant data -- but not always. `identity.userAssignedIdentities` is keyed by the
# FULL ARM RESOURCE ID of each identity, so the key itself holds a subscription GUID, a resource
# group name and a resource name; `tags` is keyed by whatever the tenant owner typed. Keys are
# therefore allow-listed by shape too: a key survives verbatim only if it looks like a plain
# schema identifier (no slash, no whitespace, no colon, no `@`). Anything else goes through the
# same default-deny scalar anonymiser as a value.
$script:SchemaKeyPattern = [regex]'^[A-Za-z_][A-Za-z0-9_.-]*$'

# ARM structural keywords inside a resource id. Their POSITION carries meaning that several
# collectors depend on (a fixed-index split), so they are preserved verbatim.
$script:ArmKeywords = @('subscriptions', 'resourceGroups', 'providers', 'locations', 'tenants')

function Test-ScoutSchemaValue {
    <#
    .SYNOPSIS
        Is this key/value pair allow-listed platform vocabulary?

    .PARAMETER TopLevel
        The allow-list applies ONLY to a row's own top-level properties. A row's `type` is an ARM
        resource type; a `type` buried inside a `properties` config bag is whatever the resource
        provider felt like putting there (an observed example: a container-app scale rule with
        `"type": "github-runner"`), which is not platform vocabulary and gets no exemption.
    #>
    param(
        [AllowEmptyString()] [string] $KeyName,
        [AllowEmptyString()] [string] $Value,
        [switch] $TopLevel
    )

    if ([string]::IsNullOrEmpty($Value)) { return $true }
    if (-not $TopLevel) { return $false }
    if (-not $KeyName) { return $false }
    if ($script:SchemaValueKeys -notcontains $KeyName.ToLowerInvariant()) { return $false }
    return $script:SchemaValuePattern.IsMatch($Value)
}

function ConvertTo-ScoutAnonymizedArmId {
    <#
    .SYNOPSIS
        Anonymise an ARM resource id segment-by-segment, preserving its shape.

    .DESCRIPTION
        `/subscriptions/{guid}/resourceGroups/{rg}/providers/{Namespace}/{type}/{name}[/{type}/{name}]...`

        The SEGMENT COUNT is preserved exactly, because roughly thirty collectors read a fixed
        index out of `$id.split('/')` (the AB#5649 Defender `[7]`/`[8]` bug is precisely this),
        so changing the count would change collector behaviour and make the fixture lie.

        Structural keywords, the provider namespace and TYPE segments survive as schema. GUIDs
        are re-tokenised as GUIDs so they still parse. Every remaining segment -- resource-group
        names, resource names -- is tokenised.
    #>
    param([string] $Id)

    $segments = $Id -split '/'
    for ($i = 0; $i -lt $segments.Length; $i++) {
        $seg = $segments[$i]
        if ([string]::IsNullOrEmpty($seg)) { continue }

        # Structural keyword -- keep verbatim.
        if ($script:ArmKeywords -contains $seg) { continue }

        $prev = if ($i -gt 0) { $segments[$i - 1] } else { '' }

        # Provider namespace, e.g. Microsoft.Compute -- schema, keep verbatim.
        if ($prev -ieq 'providers') { continue }

        # A GUID is ALWAYS tenant data, whatever position it occupies -- tested before the
        # type-segment rule below, because $script:SchemaValuePattern happily matches a GUID that
        # happens to start with a letter ("be069ae1-fc96-..."), which would otherwise let a real
        # subscription or resource GUID survive in a type-segment slot.
        if ($script:GuidRegex.IsMatch($seg)) {
            $segments[$i] = Get-ScoutAnonymizedToken -Value $seg -Kind Guid
            continue
        }

        # After the provider namespace, segments alternate type / name. Even offsets from the
        # namespace are TYPES (schema, kept); odd offsets are NAMES (tenant data, tokenised).
        $providerIdx = -1
        for ($j = $i - 1; $j -ge 0; $j--) { if ($segments[$j] -ieq 'providers') { $providerIdx = $j; break } }
        if ($providerIdx -ge 0) {
            $offset = $i - ($providerIdx + 2) # +2 skips 'providers' and the namespace itself
            if ($offset -ge 0 -and ($offset % 2) -eq 0 -and $script:SchemaValuePattern.IsMatch($seg)) {
                continue # a type segment
            }
        }

        $segments[$i] = Get-ScoutAnonymizedToken -Value $seg -Kind Name
    }
    return ($segments -join '/')
}

function ConvertTo-ScoutAnonymizedScalar {
    <#
    .SYNOPSIS
        Anonymise ONE string leaf. Default-deny: the fall-through is a token, not the input.
    #>
    param(
        [AllowEmptyString()] [string] $Value,
        [AllowEmptyString()] [string] $KeyName,
        [switch] $TopLevel
    )

    # An empty string is not data; preserving it preserves the distinction between "" and a
    # missing key, which is exactly the kind of thing a StrictMode fixture must not blur.
    if ([string]::IsNullOrEmpty($Value)) { return $Value }

    # Allow-listed platform vocabulary (top-level row properties only).
    if (Test-ScoutSchemaValue -KeyName $KeyName -Value $Value -TopLevel:$TopLevel) { return $Value }

    # An ARM resource id -- shape and segment count preserved, contents tokenised.
    if ($Value.StartsWith('/subscriptions/') -or $Value.StartsWith('/providers/')) {
        return ConvertTo-ScoutAnonymizedArmId -Id $Value
    }

    # Shape-preserving replacements, so a value that must still PARSE as a GUID or an address
    # in some downstream consumer continues to.
    if ($script:GuidRegex.IsMatch($Value)) { return Get-ScoutAnonymizedToken -Value $Value -Kind Guid }
    if ($script:Ipv4Regex.IsMatch($Value)) { return Get-ScoutAnonymizedToken -Value $Value -Kind Ipv4 }

    # DEFAULT DENY. Free text, URLs, base64 blobs, secret names, image digests, tag values,
    # connection strings, anything at all that was not matched above: tokenised. This branch is
    # the one that makes the script safe, and it is deliberately the largest one.
    return Get-ScoutAnonymizedToken -Value $Value -Kind Name
}

function ConvertTo-ScoutAnonymizedGraph {
    <#
    .SYNOPSIS
        Recursively anonymise a deserialised JSON graph (ordered dictionaries, arrays, scalars
        -- the shape ConvertFrom-Json -AsHashtable produces).

    .PARAMETER TokenizeKeys
        Set for subtrees whose KEYS are customer-chosen rather than ARM schema -- the `tags`
        bag above all, where a key like "BusinessUnit" or "Contact:" is itself tenant data.
        Structure (how many keys, their nesting) is preserved; only the key TEXT changes.
    #>
    param(
        $InputObject,
        [AllowEmptyString()] [string] $KeyName,
        [switch] $TokenizeKeys,
        # 0 = the row object itself, so its own properties are visited at depth 1. Only depth-1
        # values are eligible for the schema allow-list (see Test-ScoutSchemaValue -TopLevel).
        [int] $Depth = 0
    )

    if ($null -eq $InputObject) { return $InputObject }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in $InputObject.Keys) {
            # `tags` is the canonical free-form bag: both halves of every pair are chosen by
            # the tenant owner, so both halves are tenant data.
            $childTokenizeKeys = $TokenizeKeys -or ($k -is [string] -and $k.ToLowerInvariant() -eq 'tags')

            $outKey = $k
            if ($k -is [string]) {
                if ($TokenizeKeys) {
                    # Inside `tags`: the key is tenant-authored text, always tokenised.
                    $outKey = Get-ScoutAnonymizedToken -Value $k -Kind Key
                } elseif (-not $script:SchemaKeyPattern.IsMatch($k)) {
                    # Not a plain schema identifier -- e.g. an `identity.userAssignedIdentities`
                    # key, which is a whole ARM resource id and carries a subscription GUID, a
                    # resource-group name and a resource name. Same default-deny path as a value.
                    $outKey = ConvertTo-ScoutAnonymizedScalar -Value $k -KeyName ''
                }
            }
            $out[$outKey] = ConvertTo-ScoutAnonymizedGraph -InputObject $InputObject[$k] -KeyName $k `
                -TokenizeKeys:$childTokenizeKeys -Depth ($Depth + 1)
        }
        return $out
    }
    if ($InputObject -is [string]) {
        return ConvertTo-ScoutAnonymizedScalar -Value $InputObject -KeyName $KeyName -TopLevel:($Depth -eq 1)
    }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        # `, @(...)` so a single-element or empty array survives the return unwrapped-into-scalar
        # / collapsed-to-nothing behaviour PowerShell would otherwise apply.
        #
        # -Depth is passed through UNCHANGED: an array is not a nesting level of its own, so
        # `zones: ["1","2"]` on a row stays depth-1 and keeps its allow-list eligibility.
        return , @($InputObject | ForEach-Object {
            ConvertTo-ScoutAnonymizedGraph -InputObject $_ -KeyName $KeyName -TokenizeKeys:$TokenizeKeys -Depth $Depth
        })
    }
    return $InputObject
}

# ============================================================================
# Fail-closed verification
# ============================================================================

function Test-ScoutFixtureAnonymity {
    <#
    .SYNOPSIS
        Walk an anonymised graph and return every string that is NOT provably anonymous.

    .DESCRIPTION
        This is the independent check on ConvertTo-ScoutAnonymizedGraph -- it re-derives what a
        safe value looks like rather than trusting that the anonymiser visited every node.
        A string is acceptable only if it is empty, a generated token (`res########` /
        `key########`), a GUID, a TEST-NET-3 address, allow-listed platform vocabulary, or an
        ARM id whose every segment is one of those.

        Returns a list of findings ("<path> = <value>"); an empty list means clean.
    #>
    param($InputObject, [string] $Path = '$')

    $findings = [System.Collections.Generic.List[string]]::new()

    function Test-ScoutSafeAtom {
        param([AllowEmptyString()] [string] $Value, [AllowEmptyString()] [string] $KeyName, [switch] $TopLevel)
        if ([string]::IsNullOrEmpty($Value)) { return $true }
        if ($Value -cmatch '^(res|key)[0-9a-f]{8}$') { return $true }
        # A GUID is accepted only in the SHAPE the tokeniser produces. Real GUIDs are
        # indistinguishable from generated ones by inspection, so this check cannot prove a GUID
        # is fake -- what makes it safe is that ConvertTo-ScoutAnonymizedScalar tokenises EVERY
        # GUID-shaped string it sees, at every position including dictionary keys and ARM id
        # segments, so no real GUID reaches the output to be judged here.
        if ($script:GuidRegex.IsMatch($Value)) { return $true }
        if ($Value -like "$script:AnonIpPrefix.*" -and $script:Ipv4Regex.IsMatch($Value)) { return $true }
        if (Test-ScoutSchemaValue -KeyName $KeyName -Value $Value -TopLevel:$TopLevel) { return $true }
        return $false
    }

    function Test-ScoutSafeString {
        param([AllowEmptyString()] [string] $Value, [AllowEmptyString()] [string] $KeyName, [switch] $TopLevel)
        if (Test-ScoutSafeAtom -Value $Value -KeyName $KeyName -TopLevel:$TopLevel) { return $true }
        if ($Value.StartsWith('/subscriptions/') -or $Value.StartsWith('/providers/')) {
            foreach ($seg in ($Value -split '/')) {
                if ([string]::IsNullOrEmpty($seg)) { continue }
                if ($script:ArmKeywords -contains $seg) { continue }
                # Provider namespaces and type segments are schema; check them against the same
                # narrow vocabulary pattern the anonymiser used to decide to keep them.
                if ($script:SchemaValuePattern.IsMatch($seg) -and $seg -notmatch '\s') { continue }
                if (Test-ScoutSafeAtom -Value $seg -KeyName '') { continue }
                return $false
            }
            return $true
        }
        return $false
    }

    function Invoke-ScoutAnonymityWalk {
        param(
            $Node,
            [string] $NodePath,
            [AllowEmptyString()] [string] $KeyName,
            [bool] $KeysAreData,
            [int] $Depth = 0
        )

        if ($null -eq $Node) { return }

        if ($Node -is [System.Collections.IDictionary]) {
            foreach ($k in $Node.Keys) {
                # Keys are audited as carefully as values: a dictionary keyed by ARM resource id
                # (identity.userAssignedIdentities) hides a subscription GUID and two resource
                # names in a position a value-only scan never looks at.
                if ($k -is [string]) {
                    $keyOk = if ($KeysAreData) {
                        [bool]($k -cmatch '^key[0-9a-f]{8}$')
                    } else {
                        $script:SchemaKeyPattern.IsMatch($k) -or (Test-ScoutSafeString -Value $k -KeyName '')
                    }
                    if (-not $keyOk) { $findings.Add("$NodePath.<key> = $k") }
                }
                $childKeysAreData = $KeysAreData -or ($k -is [string] -and $k.ToLowerInvariant() -eq 'tags')
                Invoke-ScoutAnonymityWalk -Node $Node[$k] -NodePath "$NodePath.$k" -KeyName $k `
                    -KeysAreData $childKeysAreData -Depth ($Depth + 1)
            }
            return
        }
        if ($Node -is [string]) {
            if (-not (Test-ScoutSafeString -Value $Node -KeyName $KeyName -TopLevel:($Depth -eq 1))) {
                $findings.Add("$NodePath = $Node")
            }
            return
        }
        if ($Node -is [System.Collections.IEnumerable]) {
            $i = 0
            foreach ($item in $Node) {
                Invoke-ScoutAnonymityWalk -Node $item -NodePath "$NodePath[$i]" -KeyName $KeyName `
                    -KeysAreData $KeysAreData -Depth $Depth
                $i++
            }
            return
        }
    }

    # The outer ARRAY does not advance the depth (only a dictionary does), so a row's own
    # properties are visited at depth 1 here -- the same depth ConvertTo-ScoutAnonymizedGraph
    # assigns them when called per-row. Both mean "a top-level property of a resource row".
    Invoke-ScoutAnonymityWalk -Node $InputObject -NodePath $Path -KeyName '' -KeysAreData $false -Depth 0
    return , $findings
}

# ============================================================================
# Write
# ============================================================================

function Export-ScoutAnonymizedFixture {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] $Rows,
        [Parameter(Mandatory)] [string] $FileName
    )

    # -AsHashtable so ConvertTo-ScoutAnonymizedGraph gets ordered dictionaries it can walk and
    # rebuild uniformly, rather than mixing PSCustomObject and Hashtable node types.
    #
    # NOTE the deliberately clunky `$graph = @(); if (...) { $graph = ... }` rather than
    # `$graph = if (...) { @() } else { ... }`: an `if` used as an EXPRESSION returns its body's
    # pipeline output, and an empty array contributes NOTHING to a pipeline, so the tidy version
    # silently yields $null on the zero-row path -- which is exactly the path this function has
    # to get right.
    $json  = @($Rows) | ConvertTo-Json -Depth 40
    $graph = @()
    if (-not [string]::IsNullOrWhiteSpace($json)) { $graph = @($json | ConvertFrom-Json -AsHashtable -Depth 40) }

    # Anonymise ROW BY ROW rather than handing the whole array to ConvertTo-ScoutAnonymizedGraph.
    # Its array branch returns `, @(...)` (needed so a nested empty array survives as an empty
    # array instead of collapsing to nothing); at the TOP level that extra wrapper is unrolled by
    # the output stream into a single object, and the whole fixture would be counted -- and
    # written -- as one row.
    $anonymous = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $graph) {
        $anonymous.Add((ConvertTo-ScoutAnonymizedGraph -InputObject $row -KeyName ''))
    }

    $findings = Test-ScoutFixtureAnonymity -InputObject $anonymous.ToArray() -Path $FileName
    if ($findings.Count -gt 0) {
        $sample = ($findings | Select-Object -First 20) -join [Environment]::NewLine
        # NOTE the extra parentheses around the concatenation: `-f` binds TIGHTER than `+`, so
        # `"a" + "b{0}" -f $x` formats only the "b{0}" fragment and leaves "a" alone.
        $message = ("Export-ScoutFixture: REFUSING to write {0} -- {1} value(s) are not provably " +
                    "anonymous. This is a fail-closed gate, not a warning; fix the anonymiser " +
                    "rather than the gate. First findings:{2}{3}")
        throw ($message -f $FileName, $findings.Count, [Environment]::NewLine, $sample)
    }

    # An EMPTY result must still be VALID JSON. `@() | ConvertTo-Json` emits nothing at all
    # (the pipeline never invokes the cmdlet for zero input), which previously produced a
    # zero-BYTE file -- unparseable, and indistinguishable from a capture that crashed. Emit a
    # literal `[]` and say so loudly instead.
    $path = Join-Path $OutputPath $FileName
    if ($anonymous.Count -eq 0) {
        # Parenthesised before -f for the same precedence reason as the throw above.
        $warning = ("[Export-ScoutFixture] {0}: the query returned ZERO rows. Writing an empty " +
                    "JSON array. This is a real, empty result -- not a failure -- but a fixture " +
                    "with no rows exercises nothing, so check the query scope if that is " +
                    "unexpected.")
        Write-Warning ($warning -f $FileName)
        '[]' | Out-File -LiteralPath $path -Encoding utf8
    } else {
        # NO -AsArray here. Passed via -InputObject (rather than the pipeline), an array already
        # serialises as a JSON array, and -AsArray then wraps it AGAIN: `[[ {...}, {...} ]]`.
        # That is silently destructive rather than merely ugly -- the harness reads a fixture
        # with `@($raw | ConvertFrom-Json)`, so a double-wrapped file becomes a ONE-element
        # array holding the real row array, every `Where-Object { $_.TYPE -eq ... }` in all 176
        # collectors matches nothing, and the whole capture stops contributing to the run while
        # still looking present and passing.
        ConvertTo-Json -InputObject $anonymous.ToArray() -Depth 40 |
            Out-File -LiteralPath $path -Encoding utf8
    }
    Write-Host ("[Export-ScoutFixture] Wrote {0} row(s) to {1}" -f $anonymous.Count, $path)
}

# ============================================================================
# Mode: re-scrub existing fixtures offline
# ============================================================================

if ($ReScrub) {
    foreach ($file in $script:CapturedFixtureFiles) {
        $path = Join-Path $OutputPath $file
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Warning "[Export-ScoutFixture] -ReScrub: $file not present, skipping."
            continue
        }
        $raw  = Get-Content -LiteralPath $path -Raw
        # See Export-ScoutAnonymizedFixture: an `if` expression whose body is `@()` yields $null,
        # so the empty case is assigned up front and only overwritten when there IS content.
        $rows = @()
        if (-not [string]::IsNullOrWhiteSpace($raw)) { $rows = @($raw | ConvertFrom-Json -AsHashtable -Depth 40) }

        # Normalise an accidentally DOUBLE-NESTED fixture (`[[ {...}, {...} ]]`) down to a flat
        # row array. An earlier version of this script produced one by piping an array that was
        # already an array through `ConvertTo-Json -AsArray`. It is not a cosmetic problem: the
        # test harness reads a fixture with `@($raw | ConvertFrom-Json)`, which turns `[[a,b]]`
        # into a ONE-element array whose single element is the inner array, so every
        # `$Subscriptions | Where-Object { $_.id -eq ... }` lookup silently matches nothing and
        # the fixture quietly stops testing what it claims to.
        while ($rows.Count -eq 1 -and $rows[0] -is [System.Collections.IEnumerable] -and
               $rows[0] -isnot [System.Collections.IDictionary] -and $rows[0] -isnot [string]) {
            $rows = @($rows[0])
        }

        Export-ScoutAnonymizedFixture -Rows $rows -FileName $file
    }
    Write-Host '[Export-ScoutFixture] Re-scrub complete.'
    return
}

# ============================================================================
# Mode: capture from Azure
# ============================================================================

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.ResourceGraph -ErrorAction Stop

if (-not (Get-AzContext)) {
    throw 'Export-ScoutFixture: no Azure context. Run Connect-AzAccount first.'
}

# The exact columns every query below projects. Az.ResourceGraph appends its own extra columns
# to the result object (observed: a duplicate 'ResourceId' carrying the UN-anonymised id) that
# are not part of the KQL projection and would otherwise leak real tenant data straight past the
# anonymiser. Re-selecting this fixed list after every page strips anything the module added.
$script:GraphColumns = @(
    'id', 'name', 'type', 'tenantId', 'kind', 'location', 'resourceGroup', 'subscriptionId',
    'managedBy', 'sku', 'plan', 'properties', 'identity', 'zones', 'extendedLocation', 'tags'
)

function Get-ScoutGraphAllPage {
    <#
    .SYNOPSIS
        Page a Resource Graph query to completion, mirroring Invoke-AZSCInventoryLoop's
        SkipToken loop without the job/runspace machinery this script has no need for.
    #>
    param([string] $Query, [string[]] $Subscription, [string] $ManagementGroupId, [int] $First)

    $params = @{ Query = $Query; First = $First }
    if ($Subscription) { $params.Subscription = $Subscription }
    if ($ManagementGroupId) { $params.ManagementGroup = $ManagementGroupId }

    $results = [System.Collections.Generic.List[object]]::new()
    $page = Search-AzGraph @params
    $results.AddRange(@($page))

    while ($page -and $page.PSObject.Properties['SkipToken'] -and $page.SkipToken) {
        $page = Search-AzGraph @params -SkipToken $page.SkipToken
        $results.AddRange(@($page))
    }
    if ($results.Count -eq 0) { return , @() }
    return , @($results | Select-Object -Property $script:GraphColumns)
}

$graphParams = @{ Subscription = $SubscriptionId; ManagementGroupId = $ManagementGroup; First = $First }
$projection  = 'project id,name,type,tenantId,kind,location,resourceGroup,subscriptionId,managedBy,sku,plan,properties,identity,zones,extendedLocation,tags'

Write-Host '[Export-ScoutFixture] Querying resources...'
$resources = Get-ScoutGraphAllPage -Query "resources | $projection | order by id asc" @graphParams

Write-Host '[Export-ScoutFixture] Querying networkresources...'
$networkResources = Get-ScoutGraphAllPage -Query "networkresources | $projection | order by id asc" @graphParams

Write-Host '[Export-ScoutFixture] Querying resourcecontainers...'
$resourceContainers = Get-ScoutGraphAllPage -Query "resourcecontainers | $projection | order by id asc" @graphParams

Write-Host '[Export-ScoutFixture] Querying subscriptions (Get-AzSubscription)...'
$subscriptionParams = @{}
if ($SubscriptionId) { $subscriptionParams.SubscriptionId = $SubscriptionId }
$subscriptions = @(Get-AzSubscription @subscriptionParams | ForEach-Object {
    [pscustomobject]@{ id = $_.Id; name = $_.Name; tenantId = $_.TenantId; state = $_.State }
})

Export-ScoutAnonymizedFixture -Rows $resources         -FileName 'captured-resources.json'
Export-ScoutAnonymizedFixture -Rows $networkResources  -FileName 'captured-networkresources.json'
Export-ScoutAnonymizedFixture -Rows $resourceContainers -FileName 'captured-resourcecontainers.json'
Export-ScoutAnonymizedFixture -Rows $subscriptions     -FileName 'captured-subscriptions.json'

Write-Host '[Export-ScoutFixture] Done.'
