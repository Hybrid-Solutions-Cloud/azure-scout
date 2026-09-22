#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Evaluate a rule whose condition spans two collected datasets (AB#6835).

.DESCRIPTION
    Scout's rule engine could only ever ask a question of ONE dataset: a JSONPath filter over
    `$.domains.<x>`, counted. That is enough for "which storage accounts allow public blobs" and
    useless for the questions consultants actually hand-write after reading Scout's output --
    "which VMs have no backup", "which key vault has no private endpoint", "which snapshot's source
    disk is gone". Every one of those needs two datasets correlated, and Scout collected both
    halves of each pair while joining none of them.

    A rule declares the correlation as DATA. The engine gained one evaluator; adding the fifth,
    tenth or fiftieth cross-resource rule needs no engine change, which is the property that makes
    this worth doing rather than hard-coding five special cases:

        - id: XR-BKP-01
          title: "Every virtual machine has a backup protected item"
          severity: high
          join:
            left:      "$.domains.compute.virtualMachines[*]"
            leftKey:   "id"
            right:     "$.domains.management.backupProtectedItems[*]"
            rightKey:  "sourceResourceId"
            mode:      leftOnly
            leftLabel: "virtual machine"
            rightLabel: "backup protected item"
          assert: { type: countEquals, value: 0 }

    MODES

      leftOnly     left rows with NO match on the right. The absence is the finding.
      leftMatched  left rows WITH a match. The pairing is the finding (an expiring certificate
                   that is actually bound to a live app, say).
      rightOnly    right rows with no match on the left -- the mirror image, for dangling
                   references such as a snapshot whose source disk no longer exists.

    KEY COMPARISON IS CASE-INSENSITIVE AND WHITESPACE-TRIMMED, because ARM resource ids are
    case-insensitive and the two sides of a join routinely come from different providers that
    disagree on the casing of `resourceGroups` vs `resourcegroups`. A case-sensitive join here
    would report every VM in the estate as unprotected, which is worse than reporting none.

    EVERY FINDING NAMES BOTH RESOURCES. Evidence rows carry the left resource, the right resource
    (null in the -Only modes, where the whole point is that there isn't one), the key that was
    compared, and the labels the rule supplied -- so a report can render "virtual machine
    <name> has no backup protected item" without knowing anything about this rule.

.PARAMETER Rule
    The rule, carrying a `join` block.

.PARAMETER Collect
    The collect object the JSONPaths resolve against.

.OUTPUTS
    PSCustomObject rows of evidence. The caller counts them and applies the rule's assert.

.NOTES
    Tracks ADO AB#6835 (Feature AB#6751, Epic AB#6741).
#>
function Resolve-RuleJoin {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] $Rule,
        [Parameter(Mandatory)] $Collect
    )

    function Get-JoinValue {
        param([AllowNull()]$Object, [AllowNull()][string]$Name)
        if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $null }
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($Name)) { return $Object[$Name] }
            return $null
        }
        $Property = $Object.PSObject.Properties[$Name]
        if ($null -eq $Property) { return $null }
        return $Property.Value
    }

    function ConvertTo-JoinRow {
        param([AllowNull()]$Tokens)
        foreach ($Token in @($Tokens)) {
            if ($null -eq $Token) { continue }
            # Already a plain object (unit tests build them directly, and so would any future
            # non-JSONPath source) -- pass it straight through rather than round-tripping.
            if ($Token -isnot [Newtonsoft.Json.Linq.JToken]) { $Token; continue }
            $Text = $Token.ToString()
            if ([string]::IsNullOrWhiteSpace($Text)) { continue }
            try { $Text | ConvertFrom-Json } catch { continue }
        }
    }

    function Get-JoinKeyText {
        param([AllowNull()]$Value)
        if ($null -eq $Value) { return $null }
        $Text = ([string]$Value).Trim()
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        return $Text.ToLowerInvariant()
    }

    $Join = $Rule.join
    foreach ($Required in @('left', 'leftKey', 'right', 'rightKey')) {
        $Present = if ($Join -is [System.Collections.IDictionary]) { $Join.Contains($Required) } else { $null -ne $Join.PSObject.Properties[$Required] }
        if (-not $Present) {
            throw "Rule $($Rule.id): join block is missing '$Required'."
        }
    }

    $Mode = [string](Get-JoinValue -Object $Join -Name 'mode')
    if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = 'leftOnly' }
    if (@('leftOnly', 'leftMatched', 'rightOnly') -notcontains $Mode) {
        throw "Rule $($Rule.id): join mode '$Mode' is not one of leftOnly, leftMatched, rightOnly."
    }

    $LeftLabel  = [string](Get-JoinValue -Object $Join -Name 'leftLabel')
    $RightLabel = [string](Get-JoinValue -Object $Join -Name 'rightLabel')
    if ([string]::IsNullOrWhiteSpace($LeftLabel))  { $LeftLabel  = 'left resource' }
    if ([string]::IsNullOrWhiteSpace($RightLabel)) { $RightLabel = 'right resource' }

    $LeftKeyName  = [string](Get-JoinValue -Object $Join -Name 'leftKey')
    $RightKeyName = [string](Get-JoinValue -Object $Join -Name 'rightKey')

    # Resolve-JsonPath returns Newtonsoft JTokens through a `Write-Output -NoEnumerate` boundary.
    # Two consequences, both of which produce a SILENTLY EMPTY join if ignored:
    #
    #   * wrapping the call in @() yields a one-element array holding the array, not the rows --
    #     every existing caller only ever took `.Count`, so nothing caught it before;
    #   * a JObject does not implement the non-generic IDictionary and carries no PSObject
    #     properties, so `$row.id` reads $null on every row.
    #
    # Round-tripping each token through ConvertFrom-Json gives ordinary PSCustomObjects that the
    # accessor above can read, and keeps this evaluator independent of the JSONPath engine.
    $LeftRows  = @(ConvertTo-JoinRow -Tokens (Resolve-JsonPath -InputObject $Collect -Path ([string](Get-JoinValue -Object $Join -Name 'left'))))
    $RightRows = @(ConvertTo-JoinRow -Tokens (Resolve-JsonPath -InputObject $Collect -Path ([string](Get-JoinValue -Object $Join -Name 'right'))))

    # A right-key value may itself be a scoped id with more segments than the left carries -- a
    # backup protected item's `sourceResourceId` is the VM id, but a lifecycle policy's parent is
    # the account id with a `/managementPolicies/default` suffix. `keySuffixTrim` lets a rule say
    # so declaratively instead of needing a bespoke evaluator.
    $SuffixTrim = [string](Get-JoinValue -Object $Join -Name 'rightKeySuffixTrim')

    $RightIndex = @{}
    foreach ($Row in $RightRows) {
        $Key = Get-JoinKeyText -Value (Get-JoinValue -Object $Row -Name $RightKeyName)
        if ($null -ne $Key -and -not [string]::IsNullOrWhiteSpace($SuffixTrim)) {
            $Trim = $SuffixTrim.ToLowerInvariant()
            if ($Key.EndsWith($Trim)) { $Key = $Key.Substring(0, $Key.Length - $Trim.Length) }
        }
        if ($null -eq $Key) { continue }
        if (-not $RightIndex.ContainsKey($Key)) { $RightIndex[$Key] = [System.Collections.Generic.List[object]]::new() }
        $RightIndex[$Key].Add($Row)
    }

    if ($Mode -eq 'rightOnly') {
        $LeftIndex = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Row in $LeftRows) {
            $Key = Get-JoinKeyText -Value (Get-JoinValue -Object $Row -Name $LeftKeyName)
            if ($null -ne $Key) { [void]$LeftIndex.Add($Key) }
        }
        foreach ($Row in $RightRows) {
            $Key = Get-JoinKeyText -Value (Get-JoinValue -Object $Row -Name $RightKeyName)
            # A right row whose key is missing entirely cannot be proven dangling -- it is
            # unjoinable, not unmatched. Reporting it would manufacture findings out of an
            # incomplete projection, so it is skipped and the count is honest.
            if ($null -eq $Key) { continue }
            if ($LeftIndex.Contains($Key)) { continue }
            [pscustomobject]@{
                JoinMode   = $Mode
                Key        = $Key
                Left       = $null
                Right      = $Row
                LeftLabel  = $LeftLabel
                RightLabel = $RightLabel
            }
        }
        return
    }

    foreach ($Row in $LeftRows) {
        $Key = Get-JoinKeyText -Value (Get-JoinValue -Object $Row -Name $LeftKeyName)
        # NOT $Matches: that is a PowerShell automatic variable populated by -match, and assigning
        # to it inside a function that also runs regex is a live foot-gun, not a style nit.
        $MatchedRows = @(if ($null -ne $Key -and $RightIndex.ContainsKey($Key)) { $RightIndex[$Key] } else { @() })

        if ($Mode -eq 'leftOnly') {
            # Same reasoning as above, mirrored: a left row with no key is unjoinable. Counting it
            # as unmatched would report "this VM has no backup" about a row whose id was never
            # projected -- a defect in the collect query dressed up as a customer finding.
            if ($null -eq $Key) { continue }
            if ($MatchedRows.Count -gt 0) { continue }
            [pscustomobject]@{
                JoinMode   = $Mode
                Key        = $Key
                Left       = $Row
                Right      = $null
                LeftLabel  = $LeftLabel
                RightLabel = $RightLabel
            }
            continue
        }

        foreach ($Match in $MatchedRows) {
            [pscustomobject]@{
                JoinMode   = $Mode
                Key        = $Key
                Left       = $Row
                Right      = $Match
                LeftLabel  = $LeftLabel
                RightLabel = $RightLabel
            }
        }
    }
}
