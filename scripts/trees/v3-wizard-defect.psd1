@{
    # Feature + Bug for the guided-wizard defect found on v2.11.0.
    #
    # The wizard is skipped whenever any PowerShell common parameter is supplied, because the
    # trigger tests $PSBoundParameters.Count -eq 0 and common parameters land in that collection.
    #
    # GitHub is master for Bugs (work-items standard), so issue #189 was opened first and this
    # Bug carries the Hyperlink relation back to it. The conformance audit requires Bug -> Feature,
    # and Scout has no open non-web Feature, so the Feature below holds it. It sits under the v3
    # epic because the fix must ship in v3.0.0.

    Tree = @(
        @{
            Key      = 'f-interactive'
            Type     = 'Feature'
            ParentId = 5917
            Priority = 3
            Title    = 'Fix defects in the guided wizard and interactive command line surface'
            Tags     = 'azure-scout; thisismydemo; powershell; cli'
            Description = @'
<p>A bare Invoke-AzureScout opens a guided wizard that signs the operator in, verifies their rights and presents a pre-selected checklist of everything Scout can run. Defects in that surface make the product look broken to a first-time user, because the wizard is the first thing they see.</p>
<p>Why now: the wizard is silently skipped whenever any PowerShell common parameter is supplied, so an operator adding -Debug to diagnose a problem loses the very interface they were trying to diagnose. The fix must ship in v3.0.0 alongside the rest of the entry-point work.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The wizard trigger condition in Modules/Public/PublicFunctions/Invoke-AzureScout.ps1.</li>
<li>Any other defect in Start-AZSCWizard or the interactive host detection found while fixing it.</li>
<li>Regression tests covering the trigger under common parameters.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what the wizard asks or the order it asks it.</li>
<li>The non-interactive and automation paths, which already behave correctly.</li>
<li>Removing Invoke-ScoutAssessment, which is tracked separately under this epic.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'Invoke-AzureScout -Debug presents the guided wizard on an interactive host.'
                'Every PowerShell common parameter is covered by a test asserting the wizard still appears.'
                'Invoke-AzureScout -NoWizard still bypasses the wizard, and a non-interactive host still falls through without prompting.'
            )
        }

        @{
            Key         = 'bug-wizard-debug'
            Type        = 'Bug'
            Parent      = 'f-interactive'
            Priority    = 3
            GitHubIssue = 189
            Title       = 'Fix the guided wizard being skipped when a common parameter such as -Debug is supplied'
            Tags        = 'azure-scout; thisismydemo; powershell; cli'
            Description = @'
<p>Invoke-AzureScout with no parameters opens the guided wizard, which works. Invoke-AzureScout -Debug skips the wizard entirely and falls through to a non-interactive run. The operator expects the full guided experience regardless of -Debug; debug output should be additive rather than a mode switch.</p>
<p>Why now: reported against v2.11.0 by the product owner. It affects the first interaction a new user has with the product, and it defeats the ordinary act of adding -Debug to investigate something.</p>
<p><strong>Cause:</strong> Modules/Public/PublicFunctions/Invoke-AzureScout.ps1 line 491 gates the wizard on $PSBoundParameters.Count -eq 0. A common parameter is present in $PSBoundParameters, so the count is one rather than zero and the branch is skipped.</p>
<p><strong>Broader than -Debug:</strong> every common parameter suppresses the wizard identically -- Debug, Verbose, ErrorAction, WarningAction, InformationAction, ErrorVariable, WarningVariable, InformationVariable, OutVariable, OutBuffer, PipelineVariable and ProgressAction.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Counting only explicitly supplied, non-common parameters when deciding whether to open the wizard.</li>
<li>A regression test per common parameter.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing the wizard content or flow.</li>
<li>Changing what -NoWizard does; it must remain the deliberate opt-out.</li>
</ul>
<p><strong>Repro:</strong> Invoke-AzureScout shows the wizard. Invoke-AzureScout -Debug does not. Invoke-AzureScout -Verbose does not. Observed on v2.11.0. GitHub issue 189 is the master record.</p>
'@
            AcceptanceCriteria = @(
                'Repro confirmed: on v2.11.0, Invoke-AzureScout opens the wizard and Invoke-AzureScout -Debug does not.'
                'Fix verified: Invoke-AzureScout -Debug opens the wizard, and a test asserts the same for every PowerShell common parameter.'
                'Invoke-AzureScout -NoWizard still bypasses the wizard and a non-interactive host still falls through without prompting.'
            )
        }
    )
}
