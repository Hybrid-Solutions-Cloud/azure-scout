<#
.SYNOPSIS
    Guided, interactive setup wizard for Azure Scout.

.DESCRIPTION
    Walks an operator through a Scout run without them having to know a single
    switch. A bare `Invoke-AzureScout` in an interactive session opens this
    wizard automatically; you can also call it directly.

    The wizard runs five steps:

        1. Tenant      — show the signed-in context, or sign in / pick a tenant.
        2. Permissions — verify the account actually holds the rights the run
                         needs, and let the operator bail out before a long scan
                         fails halfway through.
        3. What to run — inventory, assessment, or both, then a checklist of the
                         individual categories/assessments. Everything is
                         pre-selected; the operator unchecks what they don't want.
        4. Output      — report formats and the report directory (Enter accepts
                         the default).
        5. Confirm     — echo the equivalent one-line command, then run it.

    Step 5 prints the exact `Invoke-AzureScout` command the answers map to, so
    the wizard doubles as a way to learn the parameters for later automation.

.PARAMETER AzureEnvironment
    Azure cloud environment to sign in against. Defaults to 'AzureCloud'.

.PARAMETER PlatOS
    Host platform as detected by Test-AZSCPS. Used to skip the interactive
    sign-in prompt in Azure Cloud Shell, which is already authenticated.

.OUTPUTS
    A hashtable with two keys:
      Answers — parameter name/value pairs to splat onto Invoke-AzureScout.
      RunBoth — $true when the operator asked for inventory *and* assessment.
    Returns $null if the operator cancels at any step.

.EXAMPLE
    PS C:\> Invoke-AzureScout
    Opens the wizard (interactive sessions only).

.EXAMPLE
    PS C:\> Invoke-AzureScout -NoWizard
    Skips the wizard and runs the default full ARM inventory.

.NOTES
    Tracks AB#5541. Never prompts in a non-interactive host — Invoke-AzureScout
    gates the call on Test-AZSCInteractiveHost so CI and scheduled runs can
    never block waiting for input.
#>
function Start-AZSCWizard {
    # The 'Start' verb trips PSUseShouldProcessForStateChangingFunctions, but this
    # function only prompts and returns a hashtable — it changes nothing. The
    # caller (Invoke-AzureScout) is what acts on the answers.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [string]$AzureEnvironment = 'AzureCloud',
        [string]$PlatOS
    )

    # Microsoft's eighteen published service categories (AB#6741). Kept in the same order and
    # spelling as Invoke-AzureScout's -Category ValidateSet so the wizard cannot offer a value the
    # command would then reject.
    $inventoryCategories = @(
        'AI', 'Analytics', 'Compute', 'Containers', 'Databases', 'DevOps', 'General', 'Hybrid',
        'Identity', 'Integration', 'IoT', 'Management', 'Migration', 'Monitor', 'Networking',
        'Security', 'Storage', 'Web'
    )
    $inventoryFormats = @('Excel', 'Json', 'Markdown', 'AsciiDoc', 'PowerBI')
    $assessmentFormats = @('Html', 'PowerBI', 'Excel', 'Json', 'React', 'Pptx', 'Word', 'Pdf')

    Write-AZSCWizardBanner

    # ── Step 1: tenant ───────────────────────────────────────────────────────
    Write-AZSCWizardStep -Number 1 -Total 5 -Title 'Tenant'

    $tenantId = $null
    $context = $null
    try { $context = Get-AzContext -ErrorAction Stop } catch { $context = $null }

    if ($context -and $context.Tenant) {
        Write-Host "  Signed in as : " -NoNewline -ForegroundColor DarkGray
        Write-Host $context.Account.Id -ForegroundColor Cyan
        Write-Host "  Tenant       : " -NoNewline -ForegroundColor DarkGray
        Write-Host $context.Tenant.Id -ForegroundColor Cyan
        Write-Host ''
        if (Read-AZSCWizardConfirm -Prompt 'Use this account and tenant?' -Default $true) {
            $tenantId = $context.Tenant.Id
        }
    }
    else {
        Write-Host '  No active Azure session found.' -ForegroundColor Yellow
        Write-Host ''
    }

    if (-not $tenantId) {
        if ($PlatOS -eq 'Azure CloudShell') {
            Write-Host '  Running in Cloud Shell — using the ambient session.' -ForegroundColor DarkGray
            try { $tenantId = (Get-AzContext -ErrorAction Stop).Tenant.Id } catch { $tenantId = $null }
        }
        else {
            $useDeviceLogin = Read-AZSCWizardConfirm -Prompt 'Sign in with a device code (needed on headless/SSH hosts)?' -Default $false
            Write-Host '  Opening Azure sign-in...' -ForegroundColor DarkGray
            try {
                $tenantId = Connect-AZSCLoginSession -AzureEnvironment $AzureEnvironment -DeviceLogin:$useDeviceLogin
            }
            catch {
                Write-Host "  Sign-in failed: $_" -ForegroundColor Red
                return $null
            }
        }
    }

    # If the account can see more than one tenant, let the operator choose.
    $tenants = @()
    try { $tenants = @(Get-AzTenant -ErrorAction Stop) } catch { $tenants = @() }
    if ($tenants.Count -gt 1) {
        Write-Host ''
        Write-Host '  This account has access to multiple tenants:' -ForegroundColor DarkGray
        $tenantChoice = Read-AZSCWizardChoice -Title 'Select the tenant to scan' -Items @(
            $tenants | ForEach-Object {
                $label = if ($_.Name) { "$($_.Name)  ($($_.Id))" } else { $_.Id }
                [pscustomobject]@{ Label = $label; Value = $_.Id }
            }
        )
        if ($null -eq $tenantChoice) { return $null }
        $tenantId = $tenantChoice
    }

    if (-not $tenantId) {
        Write-Host '  Could not determine a tenant to scan.' -ForegroundColor Red
        return $null
    }

    # ── Step 2: permissions ──────────────────────────────────────────────────
    Write-AZSCWizardStep -Number 2 -Total 5 -Title 'Permissions'
    Write-Host '  Checking that this account holds the rights the run needs...' -ForegroundColor DarkGray
    Write-Host ''

    $blocked = $false
    $perm = $null
    try {
        $perm = Test-AZSCPermissions -TenantID $tenantId -Scope 'All'
        foreach ($detail in $perm.Details) {
            switch ($detail.Status) {
                'Pass' { Write-Host "   [PASS] $($detail.Check)" -ForegroundColor Green }
                'Warn' { Write-Host "   [WARN] $($detail.Check): $($detail.Message)" -ForegroundColor Yellow }
                'Fail' { Write-Host "   [FAIL] $($detail.Check): $($detail.Message)" -ForegroundColor Red
                         Write-Host "          $($detail.Remediation)" -ForegroundColor DarkGray
                         $blocked = $true }
                default { Write-Host "   [INFO] $($detail.Check): $($detail.Message)" -ForegroundColor DarkGray }
            }
        }
    }
    catch {
        Write-Host "   [WARN] Permission pre-flight could not complete: $_" -ForegroundColor Yellow
    }

    Write-Host ''
    if ($blocked) {
        Write-Host '  One or more permission checks failed. The run will be incomplete.' -ForegroundColor Yellow
        if (-not (Read-AZSCWizardConfirm -Prompt 'Continue anyway?' -Default $false)) { return $null }
    }

    # The audit above always checks Entra ID (-Scope 'All'), but the actual run defaults to
    # ArmOnly unless told otherwise. Without this, a fully-permissioned account silently gets
    # zero Entra ID data because nothing here ever carried the audit's own recommendation
    # forward into the assembled command. See ADO Bug 6736.
    $scopeAnswer = 'ArmOnly'
    if ($perm -and $perm.OverallReadiness -eq 'FullARMAndEntra') {
        Write-Host '  This account has full Microsoft Graph / Entra ID permissions.' -ForegroundColor DarkGray
        if (Read-AZSCWizardConfirm -Prompt 'Also collect Entra ID data (users, groups, conditional access, etc.)?' -Default $true) {
            $scopeAnswer = 'All'
        }
    }

    # ── Step 3: what to run ──────────────────────────────────────────────────
    Write-AZSCWizardStep -Number 3 -Total 5 -Title 'What to run'

    $mode = Read-AZSCWizardChoice -Title 'Choose a run type' -Items @(
        [pscustomobject]@{ Label = 'Inventory  — list everything in the tenant';                      Value = 'Inventory' }
        [pscustomobject]@{ Label = 'Assessment — score the tenant against CAF/WAF';                   Value = 'Assessment' }
        [pscustomobject]@{ Label = 'Both       — inventory first, then the scored assessment';        Value = 'Both' }
    )
    if ($null -eq $mode) { return $null }

    $answers = @{ TenantID = $tenantId }
    if ($scopeAnswer -eq 'All') { $answers.Scope = 'All' }
    $runBoth = ($mode -eq 'Both')
    $wantsInventory = ($mode -in @('Inventory', 'Both'))
    $wantsAssessment = ($mode -in @('Assessment', 'Both'))

    if ($wantsInventory) {
        Write-Host ''
        $categories = Read-AZSCWizardChecklist -Title 'Resource categories to inventory' -Items $inventoryCategories
        if ($null -eq $categories) { return $null }
        # All 15 selected is exactly what -Category All means — keep the command
        # line short and let the default sentinel through instead.
        $answers.Category = if ($categories.Count -eq $inventoryCategories.Count) { @('All') } else { $categories }

        Write-Host ''
        $extras = Read-AZSCWizardChecklist -Title 'Optional inventory data (slower, but richer)' -Items @(
            'Resource tags', 'Security Center findings', 'Cost data', 'Quota usage', 'Network diagrams'
        ) -DefaultSelected @('Resource tags')
        if ($null -eq $extras) { return $null }
        if ($extras -contains 'Resource tags')             { $answers.IncludeTags = [switch]$true }
        if ($extras -contains 'Security Center findings')  { $answers.SecurityCenter = [switch]$true }
        if ($extras -contains 'Cost data') {
            # Cost data silently comes back empty later in the run if Az.CostManagement isn't
            # installed -- catch that here, at the point of choice, instead. Scout never installs
            # Az modules automatically (a past Az.Accounts version conflict bricked module import),
            # so any install is an explicit, user-confirmed action. See ADO Task 6738.
            if (-not (Get-Module -ListAvailable -Name Az.CostManagement)) {
                Write-Host ''
                Write-Host '  Cost data requires the Az.CostManagement module, which is not installed.' -ForegroundColor Yellow
                if (Read-AZSCWizardConfirm -Prompt 'Install Az.CostManagement now (CurrentUser scope)?' -Default $true) {
                    try {
                        Install-Module -Name Az.CostManagement -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                        Write-Host '  Installed Az.CostManagement.' -ForegroundColor Green
                        $answers.IncludeCosts = [switch]$true
                    }
                    catch {
                        Write-Host "  Install failed: $_ -- continuing without cost data." -ForegroundColor Red
                    }
                }
                else {
                    Write-Host '  Continuing without cost data.' -ForegroundColor DarkGray
                }
            }
            else {
                $answers.IncludeCosts = [switch]$true
            }
        }
        if ($extras -contains 'Quota usage')               { $answers.QuotaUsage = [switch]$true }
        if ($extras -notcontains 'Network diagrams')       { $answers.SkipDiagram = [switch]$true }
    }

    if ($wantsAssessment) {
        Write-Host ''
        # $PSScriptRoot is <module>/src, so the manifest is ONE level up. It used to climb three,
        # which lands outside the repository entirely -- the path never existed, the try block
        # never ran, and the wizard silently offered a hard-coded list of one assessment on every
        # release. Found while adding the SMART entry below (AB#6832).
        $moduleRoot = Split-Path $PSScriptRoot -Parent
        $manifestPath = Join-Path $moduleRoot 'manifests/assessments.psd1'
        $assessmentNames = @('LandingZone')
        $assessmentManifest = $null
        if (Test-Path $manifestPath) {
            try {
                $assessmentManifest = Import-PowerShellDataFile $manifestPath
                # AB#6763 -- the menu lists only what Scout can actually run: an entry with no
                # rule file behind it runs and returns nothing, which reads as "no findings".
                # ('Estate' used to be the example that motivated this — it declared Rules = @()
                # and scored nothing. AB#6795 removed it from the registry entirely rather than
                # leaving it to this gate to hide, because a full-inventory pull is a different
                # product from an assessment, not a broken one.)
                $assessmentNames = @(Get-ScoutAvailableAssessment -Manifest $assessmentManifest)
                if ($assessmentNames.Count -eq 0) {
                    Write-Warning 'Start-AZSCWizard: no assessment has rules behind it — offering LandingZone only.'
                    $assessmentNames = @('LandingZone')
                }
            }
            catch { Write-Verbose "Start-AZSCWizard: could not read the assessment manifest, falling back to LandingZone: $_" }
        }
        else {
            # AB#6754 -- this used to be reached on every run, because the path climbed three
            # directory levels to a file one level up. Test-Path returned false, the fallback
            # ran, and the wizard offered a hard-coded list of one. It was silent, so nobody
            # noticed for several releases. It is a warning now: reaching it means the module
            # layout is wrong, and the operator should see a short menu explained rather than a
            # short menu asserted.
            Write-Warning "Start-AZSCWizard: the assessment registry was not found at '$manifestPath' — offering LandingZone only. This is a packaging fault, not an empty catalogue."
        }

        # An assessment declaring RequiresData is hidden until the data it scores actually exists
        # (AB#6832). SMART is the case that forced this: an estate with no Azure Migrate project
        # has nothing for it to read, and offering it there invites a score built on nothing.
        # The check reads the most recent collect.json this machine produced; with none, the entry
        # stays hidden, which is the safe direction. `Invoke-Assessment` enforces the same
        # prerequisite independently, so a user naming -Assessment SMART explicitly still gets an
        # honest Unknown rather than a fabricated pass.
        if ($assessmentManifest) {
            $latestCollect = $null
            try {
                $latestCollect = Get-ChildItem -Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AzureScout') `
                    -Filter 'collect.json' -Recurse -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
            }
            catch { $latestCollect = $null }

            $collectObject = $null
            if ($latestCollect) {
                try { $collectObject = Get-Content -LiteralPath $latestCollect.FullName -Raw | ConvertFrom-Json }
                catch { $collectObject = $null }
            }

            $assessmentNames = @($assessmentNames | Where-Object {
                $entry = $assessmentManifest[$_]
                if ($null -eq $entry -or -not $entry.ContainsKey('RequiresData')) { return $true }
                if ($null -eq $collectObject) { return $false }
                foreach ($path in @($entry.RequiresData)) {
                    # Not wrapped in @() — Resolve-JsonPath returns via Write-Output -NoEnumerate,
                    # so @() would count the wrapper and every gate would read as satisfied.
                    try { $rows = Resolve-JsonPath -InputObject $collectObject -Path $path; if ($null -ne $rows -and $rows.Count -gt 0) { return $true } }
                    catch { }
                }
                return $false
            })
        }
        $chosen = Read-AZSCWizardChecklist -Title 'Assessments to run' -Items $assessmentNames -DefaultSelected @('LandingZone')
        if ($null -eq $chosen) { return $null }
        $answers.Assessment = $chosen
    }

    # ── Step 4: output ───────────────────────────────────────────────────────
    Write-AZSCWizardStep -Number 4 -Total 5 -Title 'Output'

    $formatPool = if ($wantsAssessment -and -not $wantsInventory) { $assessmentFormats } else { $inventoryFormats }
    $defaultFormats = if ($wantsAssessment -and -not $wantsInventory) { @('Html') } else { $inventoryFormats }
    $formats = Read-AZSCWizardChecklist -Title 'Report formats' -Items $formatPool -DefaultSelected $defaultFormats
    if ($null -eq $formats) { return $null }
    if ($formats.Count -eq $formatPool.Count) { $formats = @('All') }
    $answers.OutputFormat = $formats

    # Build the fallback folder based on OS
    if ($IsWindows) {
        $defaultDir = 'C:\AzureScout'
    } else {
        $defaultDir = Join-Path "$HOME" 'AzureScout'
    }
    $dir = Read-AZSCWizardText -Prompt 'Report directory' -Default $defaultDir
    if ($dir) { $answers.ReportDir = $dir }

    # AB#6930 -- report identity, wizard parity with -ReportIdentity. Only asked for an
    # assessment run: the identity block is the React report's cover/header, and inventory-only
    # runs never reach that renderer. Every prompt defaults to blank (Enter accepts it), and a
    # blank answer is simply never added to the hashtable -- Export-React's own neutral defaults
    # (Get-ScoutReportIdentityDefault) fill anything the operator skipped, so this step can be
    # skipped in full with four Enters and the report still reads as neutral, never as this
    # product's own name.
    if ($wantsAssessment) {
        Write-Host ''
        Write-Host '  Report identity (optional -- blank uses a neutral default; Enter to skip)' -ForegroundColor White
        $reportIdentity = @{}
        $clientName = Read-AZSCWizardText -Prompt '  Client / organization name' -Default ''
        if ($clientName) { $reportIdentity.clientName = $clientName }
        $engagementName = Read-AZSCWizardText -Prompt '  Engagement name' -Default ''
        if ($engagementName) { $reportIdentity.engagementName = $engagementName }
        $classification = Read-AZSCWizardText -Prompt '  Classification banner' -Default ''
        if ($classification) { $reportIdentity.classification = $classification }
        $preparedBy = Read-AZSCWizardText -Prompt '  Prepared by' -Default ''
        if ($preparedBy) { $reportIdentity.preparedBy = $preparedBy }
        if ($reportIdentity.Count -gt 0) { $answers.ReportIdentity = $reportIdentity }
    }

    # ── Step 5: confirm ──────────────────────────────────────────────────────
    Write-AZSCWizardStep -Number 5 -Total 5 -Title 'Confirm'
    Write-Host '  Equivalent command:' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "    $(Format-AZSCWizardCommand -Answers $answers)" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Save that line to skip the wizard next time.' -ForegroundColor DarkGray
    Write-Host ''

    if (-not (Read-AZSCWizardConfirm -Prompt 'Start the run?' -Default $true)) { return $null }
    Write-Host ''

    return @{ Answers = $answers; RunBoth = $runBoth }
}

<#
.SYNOPSIS
    Returns $true when the current host can safely prompt the operator.

.DESCRIPTION
    Guards the wizard. A prompt in a non-interactive host hangs the process
    forever, which would break every CI job, scheduled task, and container that
    calls Invoke-AzureScout with no arguments — so this returns $false unless
    the session is genuinely interactive.

    Checked, in order: the -NonInteractive host switch, redirected stdin, an
    explicit CI environment variable, and finally [Environment]::UserInteractive.
#>
function Test-AZSCInteractiveHost {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # PowerShell launched with -NonInteractive.
    if ($null -ne $Host.UI -and $null -ne $Host.UI.RawUI) {
        try { if (-not [Environment]::UserInteractive) { return $false } }
        catch { return $false }
    }
    else { return $false }

    # stdin redirected from a file or pipe — no operator on the other end.
    try { if ([Console]::IsInputRedirected) { return $false } }
    catch { Write-Verbose "Test-AZSCInteractiveHost: console stdin state unavailable in this host, continuing: $_" }

    # Common CI signals. Any of these means an automated runner, not a person.
    foreach ($var in @('CI', 'TF_BUILD', 'GITHUB_ACTIONS', 'JENKINS_URL', 'SYSTEM_TEAMPROJECTID')) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($var))) { return $false }
    }

    return $true
}

# ── Wizard UI primitives ─────────────────────────────────────────────────────
# Small, dependency-free console helpers. Kept private to the module (they are
# not exported) so they can change shape without breaking anyone's script.

function Write-AZSCWizardBanner {
    Write-Host ''
    Write-Host '  ╭────────────────────────────────────────────────────────╮' -ForegroundColor Cyan
    Write-Host '  │  Azure Scout — guided setup                            │' -ForegroundColor Cyan
    Write-Host '  │  Press Enter to accept the default shown in [brackets] │' -ForegroundColor Cyan
    Write-Host '  ╰────────────────────────────────────────────────────────╯' -ForegroundColor Cyan
}

function Write-AZSCWizardStep {
    param([int]$Number, [int]$Total, [string]$Title)
    Write-Host ''
    Write-Host "  Step $Number/$Total — $Title" -ForegroundColor White
    Write-Host "  $('─' * 56)" -ForegroundColor DarkGray
}

function Read-AZSCWizardConfirm {
    param([string]$Prompt, [bool]$Default = $true)
    $hint = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $raw = (Read-Host "  $Prompt [$hint]").Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        switch -Regex ($raw) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Host '   Enter y or n.' -ForegroundColor Yellow }
        }
    }
}

function Read-AZSCWizardText {
    param([string]$Prompt, [string]$Default)
    $raw = (Read-Host "  $Prompt [$Default]").Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
    return $raw
}

<#
.SYNOPSIS
    Single-select menu. Returns the chosen item's Value, or $null if cancelled.
#>
function Read-AZSCWizardChoice {
    param([string]$Title, [object[]]$Items)

    Write-Host ''
    Write-Host "  $Title" -ForegroundColor White
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ("    {0}. {1}" -f ($i + 1), $Items[$i].Label)
    }
    Write-Host ''

    while ($true) {
        $raw = (Read-Host '  Selection (number, or q to quit)').Trim()
        if ($raw -match '^(q|quit)$') { return $null }
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '1' }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) {
            return $Items[$n - 1].Value
        }
        Write-Host "   Enter a number between 1 and $($Items.Count)." -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Multi-select checklist. Everything is selected by default; the operator
    unchecks what they don't want. Returns the selected items, or $null if
    cancelled.
#>
function Read-AZSCWizardChecklist {
    param(
        [string]$Title,
        [string[]]$Items,
        [string[]]$DefaultSelected
    )

    $selected = [System.Collections.Generic.HashSet[string]]::new()
    $initial = if ($PSBoundParameters.ContainsKey('DefaultSelected')) { $DefaultSelected } else { $Items }
    foreach ($item in $initial) { [void]$selected.Add($item) }

    while ($true) {
        Write-Host ''
        Write-Host "  $Title" -ForegroundColor White
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($selected.Contains($Items[$i])) { 'x' } else { ' ' }
            $colour = if ($selected.Contains($Items[$i])) { 'Green' } else { 'DarkGray' }
            Write-Host ("    [{0}] {1,2}. {2}" -f $mark, ($i + 1), $Items[$i]) -ForegroundColor $colour
        }
        Write-Host ''
        Write-Host '   Toggle with numbers (e.g. "3" or "3,5,9"), a = all, n = none,' -ForegroundColor DarkGray
        Write-Host '   Enter = accept, q = quit' -ForegroundColor DarkGray

        $raw = (Read-Host '  >').Trim()

        if ([string]::IsNullOrWhiteSpace($raw)) {
            if ($selected.Count -eq 0) {
                Write-Host '   Select at least one item.' -ForegroundColor Yellow
                continue
            }
            # Preserve the caller's original ordering rather than hash order.
            return @($Items | Where-Object { $selected.Contains($_) })
        }
        if ($raw -match '^(q|quit)$') { return $null }
        if ($raw -match '^a(ll)?$')   { foreach ($item in $Items) { [void]$selected.Add($item) }; continue }
        if ($raw -match '^n(one)?$')  { $selected.Clear(); continue }

        foreach ($token in ($raw -split '[,\s]+' | Where-Object { $_ })) {
            $n = 0
            if ([int]::TryParse($token, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) {
                $item = $Items[$n - 1]
                if ($selected.Contains($item)) { [void]$selected.Remove($item) } else { [void]$selected.Add($item) }
            }
            else {
                Write-Host "   Ignored '$token' — not a number between 1 and $($Items.Count)." -ForegroundColor Yellow
            }
        }
    }
}

<#
.SYNOPSIS
    Renders the wizard's answers as the equivalent Invoke-AzureScout command so
    the operator can copy it into a script and skip the wizard next time.
#>
function Format-AZSCWizardCommand {
    param([hashtable]$Answers)

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add('Invoke-AzureScout')
    foreach ($key in ($Answers.Keys | Sort-Object)) {
        $value = $Answers[$key]
        if ($value -is [switch] -or $value -is [bool]) {
            if ($value) { $parts.Add("-$key") }
        }
        elseif ($value -is [hashtable]) {
            # AB#6930 -- -ReportIdentity. Too free-form to inline as command-line syntax (values
            # commonly contain spaces/punctuation); name it and point at the wizard instead of
            # emitting something that would not actually parse if pasted back in.
            if ($value.Count -gt 0) { $parts.Add("-$key <see wizard prompts -- re-run the wizard to set this>") }
        }
        elseif ($value -is [array]) {
            $parts.Add("-$key $((@($value) | ForEach-Object { if ($_ -match '[\s]') { "'$_'" } else { $_ } }) -join ',')")
        }
        elseif ($value -match '\s') { $parts.Add("-$key '$value'") }
        else { $parts.Add("-$key $value") }
    }
    return ($parts -join ' ')
}
