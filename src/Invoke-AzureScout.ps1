<#
.SYNOPSIS
    This script creates Excel file to Analyze Azure Resources inside a Tenant

.DESCRIPTION
    Do you want to analyze your Azure Advisories in a table format? Document it in xlsx format.

.PARAMETER TenantID
    Specify the tenant ID you want to create a Resource Inventory.

    >>> IMPORTANT: YOU NEED TO USE THIS PARAMETER FOR TENANTS WITH MULTI-FACTOR AUTHENTICATION. <<<

.PARAMETER SubscriptionID
    Use this parameter to collect a specific Subscription in a Tenant

.PARAMETER ManagementGroup
    Use this parameter to collect all Subscriptions in a Specific Management Group in a Tenant

.PARAMETER Lite
    Use this parameter to use only the Import-Excel module and don't create the charts (using Excel's API)

.PARAMETER SecurityCenter
    Use this parameter to collect Security Center Advisories

.PARAMETER SkipAdvisory
    Use this parameter to skip the capture of Azure Advisories

.PARAMETER SkipPolicy
    Use this parameter to skip the capture of Azure Policies

.PARAMETER QuotaUsage
    Use this parameter to include Quota information

.PARAMETER IncludeTags
    Use this parameter to include Tags of every Azure Resources

.PARAMETER Debug
    Output detailed debug information.

.PARAMETER AzureEnvironment
    Specifies the Azure Cloud Environment to use. Default is 'AzureCloud'.

.PARAMETER Overview
    Specifies the Excel overview sheet design. Each value will change the main charts in the Overview sheet. Valid values are 1, 2, or 3. Default is 1.

.PARAMETER AppId
    Specifies the Application (client) ID for service principal authentication. Requires TenantID and either Secret or CertificatePath.

.PARAMETER Secret
    Specifies the client secret for SPN + Secret authentication. Requires TenantID and AppId.

.PARAMETER CertificatePath
    Specifies the path to a PKCS#12 certificate file for SPN + Certificate authentication. Requires TenantID and AppId.

.PARAMETER CertificatePassword
    Specifies the password protecting the certificate file. Optional — only needed if the certificate is password-protected.

.PARAMETER Scope
    Controls which data sources are queried.
    - ArmOnly (default): Scans Azure Resource Manager resources (subscriptions, VMs, networks, etc.). Requires subscription Reader role.
    - EntraOnly: Scans Microsoft Entra ID only (users, groups, Conditional Access, PIM, etc.). Requires Microsoft Graph permissions.
    - All: Scans both ARM and Entra ID. Requires both subscription Reader AND Graph permissions.

    NOTE: By default, Entra ID is NOT scanned. Use -Scope All or -Scope EntraOnly to include Entra ID resources.

.PARAMETER CheckResourceProviders
    When specified, validates that required Azure resource providers are registered in each subscription
    before running the inventory. Unregistered providers produce warnings but do not block execution;
    modules that depend on unregistered providers are silently skipped for that subscription.

.PARAMETER PermissionAudit
    Runs a dedicated permissions audit only. No inventory is collected, no Excel or JSON report is
    generated. Outputs a colour-coded console report showing ARM/RBAC access across all visible
    subscriptions and resource provider registration status. Add -IncludeEntraPermissions to also
    audit Microsoft Graph / Entra ID permissions.

    Compatible with all existing authentication parameters (-TenantID, -AppId, -Secret,
    -CertificatePath, -DeviceLogin) so you can audit a service principal before a scheduled run.

.PARAMETER IncludeEntraPermissions
    Used with -PermissionAudit. Extends the audit to include Microsoft Graph permission checks
    required for Entra ID scanning (-Scope All or -Scope EntraOnly). Tests actual Graph API calls
    to verify real access rather than relying solely on token claims.
    Requires a Graph-capable token (interactive user with Directory Reader role, or SPN with Graph
    API application permissions and admin consent).

.PARAMETER Category
    Limits inventory collection to one or more declarative collector categories.
    Default is 'All', which processes every category. When one or more specific categories are provided,
    only modules in those folders are executed — speeding up targeted runs.

    Valid values: All, AI, Analytics, Compute, Containers, Databases, Hybrid, Identity, Integration,
    IoT, Management, Monitor, Networking, Security, Storage, Web.

    Microsoft's official long category names are accepted as aliases and normalised to the short
    value before filtering:

      Alias (accepted input)          Resolves to    Report section heading
      ------------------------------  -------------  ------------------------------
      AI + machine learning           AI             AI + machine learning
      AI+machine learning             AI             AI + machine learning
      Machine Learning                AI             AI + machine learning
      Internet of Things              IoT            Internet of Things
      Monitoring                      Monitor        Monitor
      Management and governance       Management     Management and governance
      Management & governance         Management     Management and governance
      DevOps                          Management     Management and governance
      Migration                       Management     Management and governance
      Web & Mobile                    Web            Web and mobile
      Hybrid + multicloud             Hybrid         Hybrid + multicloud
      Hybrid+multicloud               Hybrid         Hybrid + multicloud

    Note that 'Monitor' is the canonical value, not 'Monitoring'. The full reference — every
    heading, its collector folder, and its module count — is on the docs site under
    "Category reference".

.PARAMETER IncludeDevOps
    Also inventory Azure DevOps: projects, pipelines, service connections, repositories, and
    agent pools. Adds five worksheets (ADO Projects, ADO Pipelines, ADO Service Connections,
    ADO Repositories, ADO Agent Pools).

    Authentication reuses the current Azure sign-in by requesting an Entra token for the Azure
    DevOps resource, so no personal access token is needed in the common case. Supply
    -DevOpsPat when the Azure identity and the Azure DevOps identity differ.

    The ADO Service Connections sheet cross-references each Azure Resource Manager connection
    against the subscriptions in scope, so you can see which of your subscriptions are
    reachable from a pipeline.

.PARAMETER DevOpsOrganization
    One or more Azure DevOps organization names to inventory (the 'contoso' in
    dev.azure.com/contoso). When omitted, organizations are discovered from the signed-in
    profile. Service principals cannot enumerate organizations, so an unattended run must
    name them explicitly.

.PARAMETER DevOpsPat
    Azure DevOps personal access token, used instead of the current Azure sign-in. Needs read
    scopes for Project and Team, Build, Release, Code, Service Connections, and Agent Pools.

.PARAMETER RunName
    Friendly name for this run's output folder instead of the generated timestamp, for example
    -RunName 'Production-TenantA'. Invalid path characters are replaced with '-'.

.PARAMETER Force
    Write output directly into the base report directory, overwriting any previous run in place.
    Without it, every run gets its own timestamped folder underneath the base directory so a
    rerun — or a scan of a second tenant — cannot destroy the previous run's cache or report.

.PARAMETER OutputFormat
    Controls which report formats are generated. Valid values:
    - All (default): Generate Excel (.xlsx), JSON (.json), Markdown (.md), AsciiDoc (.adoc), and Power BI CSV bundle
    - Excel: Generate only the Excel report
    - Json: Generate only the JSON report
    - Markdown (MD): Generate only the Markdown report
    - AsciiDoc (Adoc): Generate only the AsciiDoc report
    - PowerBI: Generate only the Power BI CSV bundle (flat CSVs + _relationships.json in a PowerBI/ subfolder)

.PARAMETER SkipPermissionCheck
    Skip the pre-flight permission validation. By default, AZSC checks ARM and Graph
    permissions before running and displays warnings for any missing access.

.PARAMETER ResourceGroup
    Specifies one or more unique Resource Groups to be inventoried. Requires SubscriptionID.

.PARAMETER TagKey
    Specifies the tag key to be inventoried. Requires SubscriptionID.

.PARAMETER TagValue
    Specifies the tag value to be inventoried. Requires SubscriptionID.

.PARAMETER Heavy
    Use this parameter to enable heavy mode. This will force the job's load to be split into smaller batches. Avoiding CPU overload.

.PARAMETER SkipAPIs
    Use this parameter to skip the capture of resources trough REST API.

.PARAMETER Automation
    Use this parameter to run in automation mode.

.PARAMETER StorageAccount
    Specifies the Storage Account name for storing the report.

.PARAMETER StorageContainer
    Specifies the Storage Container name for storing the report.

.PARAMETER Help
    Use this parameter to display the help information.

.PARAMETER DeviceLogin
    Use this parameter to enable device login.

.PARAMETER DiagramFullEnvironment
    Use this parameter to include the full environment in the diagram. By default the Network Topology Diagram will only include VNETs that are peered with other VNETs, this parameter will force the diagram to include all VNETs.

.PARAMETER ReportName
    Specifies the name of the report. Default is 'AzureScout'.

.PARAMETER ReportDir
    Specifies the directory where the report will be saved.

.EXAMPLE
    Default utilization. Read all tenants you have privileges, select a tenant in menu and collect from all subscriptions:
    PS C:\> Invoke-AzureScout

    Define the Tenant ID:
    PS C:\> Invoke-AzureScout -TenantID <your-Tenant-Id>

    Define the Tenant ID and for a specific Subscription:
    PS C:\> Invoke-AzureScout -TenantID <your-Tenant-Id> -SubscriptionID <your-Subscription-Id>

    Run a permission audit (ARM only) before a full inventory run:
    PS C:\> Invoke-AzureScout -TenantID <your-Tenant-Id> -PermissionAudit

    Run a full permission audit including Entra ID / Microsoft Graph:
    PS C:\> Invoke-AzureScout -TenantID <your-Tenant-Id> -PermissionAudit -IncludeEntraPermissions

    Audit permissions for a service principal (ARM + Entra):
    PS C:\> Invoke-AzureScout -TenantID <your-Tenant-Id> -AppId <appId> -Secret <secret> -PermissionAudit -IncludeEntraPermissions

    Save the permission audit as a JSON file:
    PS C:\> Invoke-AzureScout -TenantID <your-Tenant-Id> -PermissionAudit -OutputFormat Json

    Save the permission audit as a Markdown report:
    PS C:\> Invoke-AzureScout -TenantID <your-Tenant-Id> -PermissionAudit -OutputFormat Markdown

.EXAMPLE
    ARM/RBAC audit for the current logged-in user:
    PS C:\> Invoke-AzureScout -PermissionAudit

.EXAMPLE
    ARM + Microsoft Graph / Entra ID audit for the current user:
    PS C:\> Invoke-AzureScout -PermissionAudit -IncludeEntraPermissions

.EXAMPLE
    Full ARM + Graph audit using a service principal (SPN):
    PS C:\> Invoke-AzureScout -TenantID <id> -AppId <id> -Secret <secret> -PermissionAudit -IncludeEntraPermissions

.EXAMPLE
    Check permissions for a specific tenant before running a full inventory:
    PS C:\> Invoke-AzureScout -TenantID <id> -PermissionAudit

.NOTES
    AUTHORS: Claudio Merola and Renato Gregio | Azure Infrastucture/Automation/Devops/Governance

    Copyright (c) 2018 Microsoft Corporation. All rights reserved.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.

.LINK
    Official Repository: https://github.com/thisismydemo/azure-scout
#>
function Test-AZSCWizardEligible {
    <#
    .SYNOPSIS
    Determines whether the guided wizard should open for an invocation.

    .DESCRIPTION
    PowerShell adds common parameters such as -Debug and -Verbose to
    $PSBoundParameters. They are diagnostics, not operator choices, so they
    must not suppress the guided wizard. The list comes from the runtime so a
    future PowerShell common parameter is handled without editing this module.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$BoundParameters,

        [Parameter(Mandatory)]
        [bool]$NoWizard,

        [Parameter(Mandatory)]
        [bool]$Interactive
    )

    if ($NoWizard -or -not $Interactive) {
        return $false
    }

    $commonParameters = @(
        [System.Management.Automation.PSCmdlet]::CommonParameters
        [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    )
    $explicitProductParameters = @($BoundParameters.Keys | Where-Object {
        $_ -notin $commonParameters
    })

    return $explicitProductParameters.Count -eq 0
}

Function Invoke-AzureScout {
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [ValidateSet(1, 2, 3)]
        [int]$Overview = 1,
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud', 'AzureGermanCloud')]
        [string]$AzureEnvironment = 'AzureCloud',
        [string]$TenantID,
        [string]$AppId,
        [string]$Secret,
        [string]$CertificatePath,
        [string]$CertificatePassword,
        [string]$ReportName = 'AzureScout',
        [string]$ReportDir,
        [string]$StorageAccount,
        [string]$StorageContainer,
        [String[]]$SubscriptionID,
        [string[]]$ManagementGroup,
        [string[]]$ResourceGroup,
        [string[]]$TagKey,
        [string[]]$TagValue,
        [switch]$SecurityCenter,
        [switch]$Heavy,
        [Alias("SkipAdvisories","NoAdvisory","SkipAdvisor")]
        [switch]$SkipAdvisory,
        [Alias("NoPolicy","SkipPolicies")]
        [switch]$SkipPolicy,
        [Alias("NoAPI","SkipAPI")]
        [switch]$SkipAPIs,
        [Alias("IncludeTag","AddTags")]
        [switch]$IncludeTags,
        [Alias("SkipVMDetail","NoVMDetails")]
        [switch]$SkipVMDetails,
        [Alias("Costs","IncludeCost")]
        [switch]$IncludeCosts,
        [switch]$QuotaUsage,
        [switch]$SkipDiagram,
        [switch]$Automation,
        [Alias("Low","Light")]
        [switch]$Lite,
        [switch]$Help,
        [switch]$DeviceLogin,
        [switch]$DiagramFullEnvironment,
        [ValidateSet('All', 'ArmOnly', 'EntraOnly')]
        [string]$Scope = 'ArmOnly',
        [switch]$SkipPermissionCheck,
        [switch]$CheckResourceProviders,
        [Alias('AuditPermissions','CheckPermissions')]
        [switch]$PermissionAudit,
        [Alias('EntraAudit','CheckEntraPermissions')]
        [switch]$IncludeEntraPermissions,
        [ValidateSet(
            # Inventory-mode formats
            'All', 'Excel', 'Json', 'Markdown', 'AsciiDoc', 'MD', 'Adoc', 'PowerBI',
            # Assessment-mode formats (-Assessment)
            'Html', 'Pptx', 'JsonEvidence', 'React', 'Pdf', 'Word', 'EChartsDashboard')]
        [string[]]$OutputFormat = @('All'),
        # ── Assessment mode (AB#5540, per AB#5024) ───────────────────────────
        # Supplying -Assessment switches this command from inventory to the
        # CAF/WAF assessment platform. Same command, same sign-in, same module.
        [Alias('Assess')]
        [string[]]$Assessment,
        [switch]$CollectOnly,
        [string]$FromCollect,
        # Suppress the guided wizard that a bare, interactive `Invoke-AzureScout`
        # opens, and run the default full ARM inventory instead.
        [Alias('NonInteractive')]
        [switch]$NoWizard,
        [ValidateSet('All', 'AI', 'Analytics', 'Compute', 'Containers', 'Databases', 'Hybrid', 'Identity', 'Integration', 'IoT', 'Management', 'Monitor', 'Networking', 'Security', 'Storage', 'Web')]
        [string[]]$Category = @('All'),
        [string]$RunName,
        [switch]$Force,
        [Alias('IncludeADO','DevOps')]
        [switch]$IncludeDevOps,
        [Alias('ADOOrganization')]
        [string[]]$DevOpsOrganization,
        [Alias('ADOPat')]
        [string]$DevOpsPat
        )

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Debugging Mode: On. ErrorActionPreference was set to "Continue", every error will be presented.')

    if ($DebugPreference -eq 'SilentlyContinue')
        {
            Write-Host 'Debugging Mode: ' -nonewline
            Write-Host 'Off' -ForegroundColor Yellow
            Write-Host 'Use the parameter ' -nonewline
            Write-Host '-Debug' -nonewline -ForegroundColor Yellow
            Write-Host ' to see debugging information during the inventory execution.'
            Write-Host 'For large environments, it is recommended to use the -Debug parameter to monitor the progress.' -ForegroundColor Yellow
        }

    if ($IncludeTags.IsPresent) { $InTag = $true } else { $InTag = $false }

    # ── Category alias normalization (18.2.5) ────────────────────────────────────
    # Map official long names AND alternate spellings → folder-name short values
    $_categoryAliasMap = @{
        'AI + machine learning'     = 'AI'
        'AI+machine learning'       = 'AI'
        'Machine Learning'          = 'AI'
        'Internet of Things'        = 'IoT'
        'Monitoring'                = 'Monitor'
        'Management and governance' = 'Management'
        'Management & governance'   = 'Management'
        'Web & Mobile'              = 'Web'
        'Web and mobile'            = 'Web'
        'Mobile'                    = 'Web'
        'Hybrid + multicloud'       = 'Hybrid'
        'Hybrid+multicloud'         = 'Hybrid'
        'Networking + CDN'          = 'Networking'   # documented alias — portal groups CDN under Networking
        'Networking+CDN'            = 'Networking'
        'DevOps'                    = 'Management'   # DevOps lives under Management folder
        'Migration'                 = 'Management'   # Migration lives under Management folder
    }
    $Category = $Category | ForEach-Object {
        if ($_categoryAliasMap.ContainsKey($_)) { $_categoryAliasMap[$_] } else { $_ }
    }
    $Category = $Category | Select-Object -Unique
    # ─────────────────────────────────────────────────────────────────────────────

    if ($Lite.IsPresent) { $RunLite = $true }else { $RunLite = $false }
    if ($DiagramFullEnvironment.IsPresent) {$FullEnv = $true}else{$FullEnv = $false}
    if ($Automation.IsPresent)
        {
            $SkipAPIs = $true
            $RunLite = $true
            if (!$StorageAccount -or !$StorageContainer)
                {
                    Write-Output "Storage Account and Container are required for Automation mode. Aborting."
                    exit
                }
        }
    if ($Overview -eq 1 -and $SkipAPIs)
        {
            $Overview = 2
        }
    $TableStyle = "Light19"

    <#########################################################          Help          ######################################################################>

    Function Get-AZSCUsageMode() {
        Write-Host ""
        Write-Host "Parameters"
        Write-Host ""
        Write-Host " -TenantID <ID>           :  Specifies the Tenant to be inventoried. "
        Write-Host " -SubscriptionID <ID>     :  Specifies Subscription(s) to be inventoried. "
        Write-Host " -ResourceGroup <NAME>    :  Specifies one (or more) unique Resource Group to be inventoried, This parameter requires the -SubscriptionID to work. "
        Write-Host " -AppId <ID>              :  Specifies the ApplicationID that is used to connect to Azure as service principal. This parameter requires the -TenantID and -Secret to work. "
        Write-Host " -Secret <VALUE>          :  Specifies the Secret that is used with the Application ID to connect to Azure as service principal. This parameter requires the -TenantID and -AppId to work. If -CertificatePath is also used the Secret value should be the Certifcate password instead of the Application secret. "
        Write-Host " -CertificatePath <PATH>  :  Specifies the Certificate path that is used with the Application ID to connect to Azure as service principal. This parameter requires the -TenantID, -AppId and -Secret to work. The required certificate format is pkcs#12. "
        Write-Host " -TagKey <NAME>           :  Specifies the tag key to be inventoried, This parameter requires the -SubscriptionID to work. "
        Write-Host " -TagValue <NAME>         :  Specifies the tag value be inventoried, This parameter requires the -SubscriptionID to work. "
        Write-Host " -SkipAdvisory            :  Do not collect Azure Advisory. "
        Write-Host " -SkipPolicy              :  Do not collect Azure Policies. "
        Write-Host " -SecurityCenter          :  Include Security Center Data. "
        Write-Host " -IncludeTags             :  Include Resource Tags. "
        Write-Host " -Online                  :  Use Online Modules. "
        Write-Host " -Debug                   :  Run in a Debug mode. "
        Write-Host " -AzureEnvironment        :  Change the Azure Cloud Environment. "
        Write-Host " -ReportName              :  Change the Default Name of the report. "
        Write-Host " -ReportDir               :  Change the Default Path of the report. "
        Write-Host " -OutputFormat            :  Choose report format: All (default), Excel, Json, Markdown, AsciiDoc, PowerBI. "
        Write-Host " -Scope                   :  Data scope. ArmOnly (default), EntraOnly, All. Use -Scope All to include Entra ID. "
        Write-Host " -CheckResourceProviders  :  Warn if required Azure resource providers are not registered. "
        Write-Host " -SkipPermissionCheck     :  Skip pre-flight permission validation. "
        Write-Host " -PermissionAudit         :  Run a standalone permission audit only (no inventory). Aliases: -AuditPermissions, -CheckPermissions. "
        Write-Host " -IncludeEntraPermissions :  With -PermissionAudit, also audit Microsoft Graph / Entra ID access. Alias: -EntraAudit. "
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host "Usage Mode and Examples: "
        Write-Host "If you do not specify Resource Inventory will be performed on all subscriptions for the selected tenant. "
        Write-Host "e.g. /> Invoke-AzureScout"
        Write-Host ""
        Write-Host "To perform the inventory in a specific Tenant and subscription use <-TenantID> and <-SubscriptionID> parameter "
        Write-Host "e.g. /> Invoke-AzureScout -TenantID <Azure Tenant ID> -SubscriptionID <Subscription ID>"
        Write-Host ""
        Write-Host "Including Tags:"
        Write-Host " By Default Azure Resource inventory do not include Resource Tags."
        Write-Host " To include Tags at the inventory use <-IncludeTags> parameter. "
        Write-Host "e.g. /> Invoke-AzureScout -TenantID <Azure Tenant ID> -IncludeTags"
        Write-Host ""
        Write-Host "Skipping Azure Advisor:"
        Write-Host " By Default Azure Resource inventory collects Azure Advisor Data."
        Write-Host " To ignore this  use <-SkipAdvisory> parameter. "
        Write-Host "e.g. /> Invoke-AzureScout -TenantID <Azure Tenant ID> -SubscriptionID <Subscription ID> -SkipAdvisory"
        Write-Host ""
        Write-Host "Using the latest modules :"
        Write-Host " You can use the latest modules. For this use <-Online> parameter."
        Write-Host " It's a pre-requisite to have internet access for AZSC GitHub repo"
        Write-Host "e.g. /> Invoke-AzureScout -TenantID <Azure Tenant ID> -Online"
        Write-Host ""
        Write-Host "Running in Debug Mode :"
        Write-Host " To run in a Debug Mode use <-Debug> parameter."
        Write-Host ".e.g. /> Invoke-AzureScout -TenantID <Azure Tenant ID> -Debug"
        Write-Host ""
    }

    $TotalRunTime = [System.Diagnostics.Stopwatch]::StartNew()

    if ($Help.IsPresent) {
        Get-AZSCUsageMode
        Exit
    }

    # ── Console verbosity (AB#5410) ───────────────────────────────────────────
    # If the user did not explicitly request -Verbose or -Debug, we silently continue
    # warnings so the console remains clean of 400/429 ARC errors. However, we hook
    # Write-Warning to explicitly forward the messages to our structured log, guaranteeing
    # no diagnostics are lost in the background.
    if (-not ($PSBoundParameters.ContainsKey('Debug') -or $PSBoundParameters.ContainsKey('Verbose'))) {
        $WarningPreference = 'SilentlyContinue'
        function Write-Warning {
            param([Parameter(Mandatory=$true, ValueFromPipeline=$true)][string]$Message)
            if (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue) {
                Write-AZSCLog -Level Warn -Message $Message
            }
        }
    }

    # ── PowerShell edition guard ──────────────────────────────────────────────
    # Fail fast and clearly here rather than letting Windows PowerShell 5.1 (Desktop)
    # run deep into the permission audit / Entra-Graph code path and crash on a
    # strict-mode member-resolution error (e.g. ".Count" on a scalar) that PowerShell 7
    # tolerates silently. AzureScout.psd1 also declares PowerShellVersion = '7.0' so
    # Import-Module rejects Desktop up front, but this guard covers callers that
    # dot-source the function directly or import with -SkipEditionCheck.
    if ($PSVersionTable.PSEdition -ne 'Core') {
        throw "AzureScout requires PowerShell 7+. You are on Windows PowerShell $($PSVersionTable.PSVersion). Run in 'pwsh'."
    }

    $PlatOS = Test-AZSCPS

    # ── Wizard mode (AB#5541) ────────────────────────────────────────────────
    # A bare `Invoke-AzureScout` in an interactive session opens the guided
    # wizard: it signs in, verifies the account actually holds the rights the
    # run needs, then presents a checklist of everything Scout can do (both
    # inventory and assessment) with sensible defaults pre-selected.
    #
    # Non-interactive callers are untouched. Automation, CI, and any host that
    # can't prompt fall straight through to the pre-wizard behaviour (full ARM
    # inventory), so a scheduled `Invoke-AzureScout` in a pipeline can never
    # block on a prompt. -NoWizard forces that same path interactively.
    $wizardRunBoth = $false
    # AB#5543 — holds the assessment arguments when the wizard asked for both modes, so the
    # assessment can run AFTER the inventory pass and reuse its rows. Declared here so the
    # reference below is always set under StrictMode.
    $deferredAssessArgs = $null
    if (Test-AZSCWizardEligible -BoundParameters $PSBoundParameters -NoWizard $NoWizard.IsPresent -Interactive (Test-AZSCInteractiveHost)) {
        $wizard = Start-AZSCWizard -AzureEnvironment $AzureEnvironment -PlatOS $PlatOS
        if (-not $wizard) { return }   # operator cancelled

        # The wizard hands back a parameter set; rebind and continue as though
        # the operator had typed those switches. $PSBoundParameters is updated
        # too because the branches below test it to distinguish "explicitly
        # asked for" from "left at the default".
        foreach ($key in $wizard.Answers.Keys) {
            Set-Variable -Name $key -Value $wizard.Answers[$key] -Scope Local
            $PSBoundParameters[$key] = $wizard.Answers[$key]
        }
        $wizardRunBoth = $wizard.RunBoth
    }

    # ── Assessment mode (AB#5540, per AB#5024) ───────────────────────────────
    # One command, two modes. -Assessment routes this run to the CAF/WAF
    # assessment platform instead of the inventory collector. Everything else —
    # sign-in, tenant selection, report directory, category filtering — is the
    # same surface the inventory mode uses.
    if ($Assessment -or $CollectOnly.IsPresent -or $FromCollect) {
        $inventoryOnlyFormats = @($OutputFormat) | Where-Object { $_ -in @('Markdown', 'MD', 'AsciiDoc', 'Adoc') }
        if ($inventoryOnlyFormats) {
            throw "-OutputFormat $($inventoryOnlyFormats -join ', ') is inventory-only and cannot be used with -Assessment. Assessment formats: Html, Pptx, PowerBI, Excel, Json, JsonEvidence, React, Pdf, Word, EChartsDashboard, All."
        }

        # -FromCollect re-assesses an existing collect.json offline, so it must
        # not force a sign-in the run doesn't need.
        if (-not $FromCollect -and $PlatOS -ne 'Azure CloudShell' -and !$Automation.IsPresent) {
            $TenantID = Connect-AZSCLoginSession -AzureEnvironment $AzureEnvironment -TenantID $TenantID -DeviceLogin:$DeviceLogin -AppId $AppId -Secret $Secret -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword
        }

        $assessArgs = @{ Assessment = if ($Assessment) { $Assessment } else { @('Estate') } }
        if ($PSBoundParameters.ContainsKey('Scope'))        { $assessArgs.Scope = $Scope }
        if ($PSBoundParameters.ContainsKey('OutputFormat')) { $assessArgs.OutputFormat = @($OutputFormat) }
        if ($ReportDir)                                     { $assessArgs.OutputPath = $ReportDir }
        # 'All' is the inventory default sentinel, not a real assessment category —
        # passing it through would filter the collect down to nothing.
        if ($Category -and $Category -notcontains 'All')    { $assessArgs.Category = $Category }
        if ($ManagementGroup)                               { $assessArgs.ManagementGroupId = $ManagementGroup[0] }
        if ($PermissionAudit.IsPresent)                     { $assessArgs.PermissionAudit = $true }
        if ($CollectOnly.IsPresent)                         { $assessArgs.CollectOnly = $true }
        if ($FromCollect)                                   { $assessArgs.FromCollect = $FromCollect }

        # "Both" from the wizard: DEFER the assessment until after the inventory pass instead of
        # running it now (AB#5543). Running it here made the command collect from Azure twice —
        # the assessment issued its own Resource Graph pack, then the inventory re-fetched the
        # same resource types moments later. Inventory already projects the full `properties`
        # bag, so running it first and handing those rows to the assessment collects once.
        if ($wizardRunBoth) { $deferredAssessArgs = $assessArgs }
        else { return Invoke-ScoutAssessmentCore @assessArgs }
    }

    # ── Inventory mode ───────────────────────────────────────────────────────
    # -OutputFormat is [string[]] so assessment mode can request several
    # renderers in one run. The inventory report writers below were written
    # against a scalar, so resolve the requested formats to flags once here.
    $requestedFormats = @($OutputFormat)
    $assessmentOnlyFormats = $requestedFormats | Where-Object { $_ -in @('Html', 'Pptx', 'JsonEvidence', 'React', 'Pdf', 'Word', 'EChartsDashboard') }
    if ($assessmentOnlyFormats) {
        throw "-OutputFormat $($assessmentOnlyFormats -join ', ') is an assessment format. Add -Assessment to run the CAF/WAF assessment, or choose an inventory format: All, Excel, Json, Markdown, AsciiDoc, PowerBI."
    }
    $WantExcel    = [bool](@('All', 'Excel')              | Where-Object { $_ -in $requestedFormats })
    $WantJson     = [bool](@('All', 'Json')               | Where-Object { $_ -in $requestedFormats })
    $WantMarkdown = [bool](@('All', 'Markdown', 'MD')     | Where-Object { $_ -in $requestedFormats })
    $WantAsciiDoc = [bool](@('All', 'AsciiDoc', 'Adoc')   | Where-Object { $_ -in $requestedFormats })
    $WantPowerBI  = [bool](@('All', 'PowerBI')            | Where-Object { $_ -in $requestedFormats })

    # ── Permission Audit mode (early exit — no inventory collected) ──────────
    if ($PermissionAudit.IsPresent)
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'PermissionAudit mode: connecting and running audit then exiting.')

            if ($PlatOS -ne 'Azure CloudShell' -and !$Automation.IsPresent)
                {
                    $TenantID = Connect-AZSCLoginSession -AzureEnvironment $AzureEnvironment -TenantID $TenantID -DeviceLogin:$DeviceLogin -AppId $AppId -Secret $Secret -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword
                }

            # The audit writer takes a single format. -OutputFormat is a list, so
            # pick the first requested value rather than letting `switch` iterate
            # the array and silently keep whichever element happened to be last.
            $auditOutputFormat = switch (@($OutputFormat)[0]) {
                'Json'      { 'Json' }
                'Markdown'  { 'Markdown' }
                'MD'        { 'Markdown' }
                'AsciiDoc'  { 'AsciiDoc' }
                'Adoc'      { 'AsciiDoc' }
                'All'       { 'All' }
                default     { 'Console' }
            }

            $auditResult = Invoke-AZSCPermissionAudit `
                -IncludeEntraPermissions:$IncludeEntraPermissions `
                -TenantID $TenantID `
                -SubscriptionID $SubscriptionID `
                -OutputFormat $auditOutputFormat `
                -ReportDir $ReportDir

            return $auditResult
        }

    if ($PlatOS -ne 'Azure CloudShell' -and !$Automation.IsPresent)
        {
            $TenantID = Connect-AZSCLoginSession -AzureEnvironment $AzureEnvironment -TenantID $TenantID -DeviceLogin:$DeviceLogin -AppId $AppId -Secret $Secret -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword


        }
    elseif ($Automation.IsPresent)
        {
            try {
                $AzureConnection = (Connect-AzAccount -Identity).context

                Set-AzContext -SubscriptionName $AzureConnection.Subscription -DefaultProfile $AzureConnection
            }
            catch {
                Write-Output "Failed to set Automation Account requirements. Aborting."
                exit
            }
        }

    if ($PlatOS -eq 'Azure CloudShell')
        {
            $Heavy = $true
            $SkipAPIs = $true
        }

    # --- Auth status banner: signed-in identity + active subscription (AB#349) ---
    # Non-fatal: a missing/oddly-shaped context must never abort a run.
    try {
        $AuthCtx = Get-AzContext -ErrorAction SilentlyContinue
        if ($AuthCtx -and $AuthCtx.Account) {
            $AuthUpn = $AuthCtx.Account.Id
            $AuthSub = if ($AuthCtx.Subscription -and $AuthCtx.Subscription.Name) {
                "$($AuthCtx.Subscription.Name) ($($AuthCtx.Subscription.Id))"
            } else { 'none selected' }
            Write-Host ''
            Write-Host '  Signed in as : ' -NoNewline -ForegroundColor DarkGray; Write-Host $AuthUpn -ForegroundColor Cyan
            Write-Host '  Subscription : ' -NoNewline -ForegroundColor DarkGray; Write-Host $AuthSub -ForegroundColor Cyan
            Write-Host '  Tenant       : ' -NoNewline -ForegroundColor DarkGray; Write-Host $TenantID -ForegroundColor Cyan

            # Management group access probe (AB#351). Runs here, not at collection time,
            # so a missing tenant-root role is reported while the operator is still
            # watching the login rather than as a silently empty worksheet an hour later.
            $MgProbe = Test-AZSCManagementGroupAccess
            Write-Host '  Mgmt groups  : ' -NoNewline -ForegroundColor DarkGray
            if ($MgProbe.HasAccess) {
                Write-Host $MgProbe.Count -ForegroundColor Cyan
            } else {
                Write-Host 'none visible' -ForegroundColor Yellow
            }

            Write-Host ''
        }
    }
    catch {
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Auth banner skipped: ' + $_.Exception.Message)
    }

    if ($StorageAccount)
        {
            $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccount -UseConnectedAccount
        }

    $Subscriptions = Get-AZSCSubscriptions -TenantID $TenantID -SubscriptionID $SubscriptionID -PlatOS $PlatOS

    # --- Resource provider pre-flight check ---
    if ($CheckResourceProviders.IsPresent) {
        Write-Host 'Checking resource provider registration...' -ForegroundColor Cyan
        $criticalProviders = @(
            'Microsoft.Security',
            'Microsoft.Insights',
            'Microsoft.Maintenance',
            'Microsoft.DesktopVirtualization',
            'Microsoft.HybridCompute',
            'Microsoft.AzureStackHCI',
            'Microsoft.MachineLearningServices',
            'Microsoft.CognitiveServices',
            'Microsoft.Search',
            'Microsoft.BotService'
        )
        # AB#368 - the caller's subscription context is restored after the sweep, including
        # when a provider lookup throws part way through.
        Invoke-AZSCInSubscriptionContext -Subscription $Subscriptions -Process {
            param($sub)
            foreach ($provider in $criticalProviders) {
                $reg = Get-AzResourceProvider -ProviderNamespace $provider -ErrorAction SilentlyContinue
                if ($reg -and $reg.RegistrationState -ne 'Registered') {
                    Write-Host "  [INFO] [$($sub.Name)] $provider is not registered — modules for this service will be skipped (this is expected if you don't use this service)." -ForegroundColor DarkGray
                }
            }
        }
        Write-Host ''
    }

    # --- Pre-flight permission check ---
    if (-not $SkipPermissionCheck.IsPresent) {
        Write-Host 'Running pre-flight permission checks...' -ForegroundColor Cyan
        $permResult = Test-AZSCPermissions -TenantID $TenantID -SubscriptionID $SubscriptionID -Scope $Scope
        foreach ($detail in $permResult.Details) {
            switch ($detail.Status) {
                'Pass' { Write-Host "  [PASS] $($detail.Check): $($detail.Message)" -ForegroundColor Green }
                'Warn' { Write-Warning "[WARN] $($detail.Check): $($detail.Message). $($detail.Remediation)" }
                'Fail' { Write-Warning "[FAIL] $($detail.Check): $($detail.Message). $($detail.Remediation)" }
                'Info' { Write-Host "  [INFO] $($detail.Check): $($detail.Message)" -ForegroundColor DarkGray }
            }
        }
        Write-Host ''
    }

    # Run isolation (AB#331): each invocation gets its own timestamped folder so a rerun -
    # or a scan of a second tenant - cannot destroy the previous run's cache or report.
    # -Force restores the pre-2.3.0 overwrite-in-place behaviour.
    $ReportingPath = Set-AZSCReportPath -ReportDir $ReportDir -RunName $RunName -ScopeId $TenantID -Force:$Force

    $DefaultPath = $ReportingPath.DefaultPath
    $DiagramCache = $ReportingPath.DiagramCache
    $ReportCache = $ReportingPath.ReportCache

    if (-not $Force.IsPresent)
        {
            Write-Host '  Run folder   : ' -NoNewline -ForegroundColor DarkGray
            Write-Host $DefaultPath -ForegroundColor Cyan
        }

    if ($Automation.IsPresent)
        {
            $ReportName = 'AZSC_Automation'
        }

    Set-AZSCFolder -DefaultPath $DefaultPath -DiagramCache $DiagramCache -ReportCache $ReportCache

    # Run log (AB#5635). Started as soon as the run folder exists so that everything from here
    # on -- including a failure -- leaves a durable record next to the report instead of a
    # single red line on a console nobody kept.
    $LogContext = Get-AzContext -ErrorAction SilentlyContinue
    Start-AZSCRunLog -DefaultPath $DefaultPath -NoTranscript:$Automation -Metadata @{
        'Module'        = (Get-Module -Name 'AzureScout' | Select-Object -First 1).Version
        'PowerShell'    = ('{0} ({1})' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
        'OS'            = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        'Account'       = if ($LogContext) { $LogContext.Account.Id } else { '<unknown>' }
        'Tenant'        = $TenantID
        'Subscriptions' = @($Subscriptions).Count
        'Scope'         = $Scope
        'Category'      = $Category
        'Environment'   = $AzureEnvironment
        'RunFolder'     = $DefaultPath
        'Switches'      = @(
            if ($SkipAPIs) { 'SkipAPIs' }
            if ($SkipPolicy) { 'SkipPolicy' }
            if ($SkipAdvisory) { 'SkipAdvisory' }
            if ($SkipVMDetails) { 'SkipVMDetails' }
            if ($SkipDiagram) { 'SkipDiagram' }
            if ($SecurityCenter) { 'SecurityCenter' }
            if ($IncludeCosts) { 'IncludeCosts' }
            if ($IncludeTags) { 'IncludeTags' }
            if ($IncludeDevOps) { 'IncludeDevOps' }
            if ($Automation) { 'Automation' }
        ) -join ' '
    }

    foreach ($LogSub in @($Subscriptions)) {
        Write-AZSCLog -Message ('  subscription in scope : {0} ({1})' -f $LogSub.Name, $LogSub.Id)
    }

    # A trap rather than a try/catch around 200 lines: it covers the whole function scope
    # wherever the failure lands, and rethrows so the caller's behaviour is unchanged. Without
    # it the operator sees the message but never the script, line or stack trace (AB#5635).
    trap {
        Write-AZSCLogError -ErrorRecord $_
        $FailedLog = Stop-AZSCRunLog -Status 'FAILED' -Quiet
        if ($FailedLog) {
            Write-Host ''
            Write-Host '  The run failed. Full detail written to: ' -NoNewline -ForegroundColor Yellow
            Write-Host $FailedLog -ForegroundColor Cyan
        }
        # `break`, NOT `throw`. A bare `throw` inside a trap does not rethrow -- it raises a
        # brand new "ScriptHalted" error and destroys the original message, script, line and
        # stack trace, which is exactly the diagnostic this trap exists to preserve. `break`
        # propagates the original ErrorRecord to the caller untouched.
        break
    }

    Clear-AZSCCacheFolder -ReportCache $ReportCache

    # The ResourceJob_* sweep that stood here is gone with the jobs themselves (AB#5649). The
    # processing phase runs collectors in-process, so there is no leftover job state from a
    # previous run in this session to clear.

    $ExtractionRuntime = [System.Diagnostics.Stopwatch]::StartNew()

        $ExtractionData = Start-AZSCExtractionOrchestration -ManagementGroup $ManagementGroup -Subscriptions $Subscriptions -SubscriptionID $SubscriptionID -ResourceGroup $ResourceGroup -SecurityCenter $SecurityCenter -SkipAdvisory $SkipAdvisory -SkipPolicy $SkipPolicy -IncludeTags $IncludeTags -TagKey $TagKey -TagValue $TagValue -SkipAPIs $SkipAPIs -SkipVMDetails $SkipVMDetails -IncludeCosts $IncludeCosts -Automation $Automation -AzureEnvironment $AzureEnvironment -Scope $Scope -TenantID $TenantID -IncludeDevOps:$IncludeDevOps -DevOpsOrganization $DevOpsOrganization -DevOpsPat $DevOpsPat

    $ExtractionRuntime.Stop()

    # AB#5543 — the wizard asked for both modes. The inventory pass above has now fetched the
    # resource rows, so hand them to the assessment instead of letting it collect from Azure a
    # second time over the same resource types.
    if ($deferredAssessArgs) {
        Write-Output (Invoke-ScoutAssessmentCore @deferredAssessArgs -FromInventory $ExtractionData)
    }

    $Resources = $ExtractionData.Resources
    $EntraResources = $ExtractionData.EntraResources
    $Quotas = $ExtractionData.Quotas
    $CostData = $ExtractionData.Costs
    $ResourceContainers = $ExtractionData.ResourceContainers
    $Advisories = $ExtractionData.Advisories
    $ResourcesCount = $ExtractionData.ResourcesCount
    $AdvisoryCount = $ExtractionData.AdvisoryCount
    $SecCenterCount = $ExtractionData.SecCenterCount
    $Security = $ExtractionData.Security
    $Retirements = $ExtractionData.Retirements
    $PolicyCount = $ExtractionData.PolicyCount
    $PolicyAssign = $ExtractionData.PolicyAssign
    $PolicyDef = $ExtractionData.PolicyDef
    $PolicySetDef = $ExtractionData.PolicySetDef

    Remove-Variable -Name ExtractionData -ErrorAction SilentlyContinue

    $ExtractionTotalTime = $ExtractionRuntime.Elapsed.ToString("dd\:hh\:mm\:ss\:fff")

    Write-AZSCLogPhase -Name 'Extraction finished' -Elapsed $ExtractionTotalTime -Detail @{
        'Resources'          = @($Resources).Count
        'ResourceContainers' = @($ResourceContainers).Count
        'Advisories'         = @($Advisories).Count
        'Security findings'  = @($Security).Count
        'Retirements'        = @($Retirements).Count
        'Entra objects'      = @($EntraResources).Count
        'Quotas'             = @($Quotas).Count
        'Policy assignments' = @($PolicyAssign).Count
        'Policy definitions' = @($PolicyDef).Count
        'Policy set defs'    = @($PolicySetDef).Count
        'Cost rows'          = @($CostData).Count
    }

    if ($Automation.IsPresent)
        {
            Write-Output "Extraction Phase Finished"
            Write-Output ('Total Extraction Time: ' + $ExtractionTotalTime)
        }
    else
        {
            Write-Host "Extraction Phase Finished: " -ForegroundColor Green -NoNewline
            Write-Host $ExtractionTotalTime -ForegroundColor Cyan
        }

    #### Creating Excel file variable:
    $FileName = ($ReportName + "_Report_" + (get-date -Format "yyyy-MM-dd_HH_mm") + ".xlsx")
    $File = Join-Path $DefaultPath $FileName
    #$DFile = ($DefaultPath + $Global:ReportName + "_Diagram_" + (get-date -Format "yyyy-MM-dd_HH_mm") + ".vsdx")
    $DDName = ($ReportName + "_Diagram_" + (get-date -Format "yyyy-MM-dd_HH_mm") + ".drawio")
    $DDFile = Join-Path $DefaultPath $DDName

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Excel file: ' + $File)

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Default Jobs.')

    $ProcessingRunTime = [System.Diagnostics.Stopwatch]::StartNew()

        # Returns the Security / Policy / Advisory / Subscriptions results directly. These were
        # background jobs the reporting phase harvested with Receive-Job; that harvest carried
        # the AB#5629 NotStarted race in four more places, so it is now a plain value handed to
        # Start-AZSCReporOrchestration below. (AB#5649)
        $ExtraData = Start-AZSCExtraJobs -SkipDiagram $SkipDiagram -SkipAdvisory $SkipAdvisory -SkipPolicy $SkipPolicy -SecurityCenter $Security -Subscriptions $Subscriptions -Resources $Resources -Advisories $Advisories -DDFile $DDFile -DiagramCache $DiagramCache -FullEnv $FullEnv -ResourceContainers $ResourceContainers -Security $Security -PolicyAssign $PolicyAssign -PolicySetDef $PolicySetDef -PolicyDef $PolicyDef -IncludeCosts $IncludeCosts -CostData $CostData -Automation $Automation

        Start-AZSCProcessOrchestration -Subscriptions $Subscriptions -Resources $Resources -Retirements $Retirements -DefaultPath $DefaultPath -Heavy $Heavy -File $File -InTag $InTag -Automation $Automation -Category $Category

    $ProcessingRunTime.Stop()

    $ProcessingTotalTime = $ProcessingRunTime.Elapsed.ToString("dd\:hh\:mm\:ss\:fff")

    Write-AZSCLogPhase -Name 'Processing finished' -Elapsed $ProcessingTotalTime -Detail @{
        'Cache files'  = @(Get-ChildItem -Path $ReportCache -Filter '*.json' -ErrorAction SilentlyContinue).Count
        'Excel target' = $File
    }

    if ($Automation.IsPresent)
        {
            Write-Output "Processing Phase Finished"
            Write-Output ('Total Processing Time: ' + $ProcessingTotalTime)
        }
    else
        {
            Write-Host "Processing Phase Finished: " -ForegroundColor Green -NoNewline
            Write-Host $ProcessingTotalTime -ForegroundColor Cyan
        }

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Resources Report Function.')
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Excel Table Style used: ' + $TableStyle)

    $ReportingRunTime = [System.Diagnostics.Stopwatch]::StartNew()

    # ── Excel Report ─────────────────────────────────────────────────────
    if ($WantExcel)
    {
        Start-AZSCReporOrchestration -ReportCache $ReportCache -SecurityCenter $SecurityCenter -File $File -Quotas $Quotas -SkipPolicy $SkipPolicy -SkipAdvisory $SkipAdvisory -IncludeCosts $IncludeCosts -Automation $Automation -TableStyle $TableStyle -ExtraData $ExtraData

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Generating Overview sheet (Charts).')

        $TotalRes = Start-AZSCExcelCustomization -File $File -TableStyle $TableStyle -PlatOS $PlatOS -Subscriptions $Subscriptions -ExtractionRunTime $ExtractionRuntime -ProcessingRunTime $ProcessingRunTime -ReportingRunTime $ReportingRunTime -IncludeCosts $IncludeCosts -RunLite $RunLite -Overview $Overview -Category $Category

        Write-Progress -activity 'Azure Inventory' -Status "95% Complete." -PercentComplete 95 -CurrentOperation "Excel Customization Completed. Total resources inventoried: $TotalRes"
    }
    else
    {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Skipping Excel report (OutputFormat = Json).')
    }

    # ── JSON Report ──────────────────────────────────────────────────────
    if ($WantJson)
    {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting JSON report export.')
        $JsonFile = Export-AZSCJsonReport -ReportCache $ReportCache -File $File -TenantID $TenantID -Subscriptions $Subscriptions -Scope $Scope -Quotas $Quotas -SecurityCenter:$SecurityCenter -SkipAdvisory:$SkipAdvisory -SkipPolicy:$SkipPolicy -IncludeCosts:$IncludeCosts
    }

    # ── Markdown Report ──────────────────────────────────────────────────
    if ($WantMarkdown)
    {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Markdown report export.')
        $MarkdownFile = Export-AZSCMarkdownReport -ReportCache $ReportCache -File $File -TenantID $TenantID -Subscriptions $Subscriptions -Scope $Scope
    }

    # ── AsciiDoc Report ──────────────────────────────────────────────────
    if ($WantAsciiDoc)
    {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting AsciiDoc report export.')
        $AsciiDocFile = Export-AZSCAsciiDocReport -ReportCache $ReportCache -File $File -TenantID $TenantID -Subscriptions $Subscriptions -Scope $Scope
    }

    # ── Power BI CSV Report ───────────────────────────────────────────────
    if ($WantPowerBI)
    {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Power BI CSV export.')
        $PowerBIDir = Export-AZSCPowerBIReport -ReportCache $ReportCache -File $File -TenantID $TenantID -Subscriptions $Subscriptions -Scope $Scope
    }

    $ReportingRunTime.Stop()

    $ReportingTotalTime = $ReportingRunTime.Elapsed.ToString("dd\:hh\:mm\:ss\:fff")

    Write-AZSCLogPhase -Name 'Reporting finished' -Elapsed $ReportingTotalTime -Detail @{
        'Excel rows written' = $TotalRes
        'Report file'        = $File
    }

    if ($Automation.IsPresent)
        {
            Write-Output "Report Building Finished"
            Write-Output ('Total Processing Time: ' + $ReportingTotalTime)
        }
    else
        {
            Write-Host "Report Building Finished: " -ForegroundColor Green -NoNewline
            Write-Host $ReportingTotalTime -ForegroundColor Cyan
        }

        # Clear memory to remove as many memory footprint as possible
        Clear-AZSCMemory

        # Clear Cache Folder for future runs
        Clear-AZSCCacheFolder -ReportCache $ReportCache


    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Finished Charts Phase.')

    # AB#5649 — the 'DrawDiagram' wait stood here. Invoke-AZSCDrawIOJob no longer starts a
    # background job, so the diagram is already built by the time control reaches this point and
    # there is nothing to wait for or destroy. This was the last Wait-AZSCJob caller in the
    # product; the function itself is gone with it.


    if ($StorageAccount)
        {
            # -Force on every upload (AB#343): a scheduled runbook uploads to the same blob
            # names on every run, and without it the second run fails with
            # "blob already exists" and the report never lands.
            if ($WantExcel)
            {
                Write-Output "Sending Excel file to Storage Account:"
                Write-Output $File
                Set-AzStorageBlobContent -File $File -Container $StorageContainer -Context $StorageContext -Force | Out-Null
            }
            if ($WantJson -and $JsonFile)
            {
                Write-Output "Sending JSON file to Storage Account:"
                Write-Output $JsonFile
                Set-AzStorageBlobContent -File $JsonFile -Container $StorageContainer -Context $StorageContext -Force | Out-Null
            }
            if(!$SkipDiagram.IsPresent -and $DDFile -and (Test-Path -Path $DDFile))
                {
                    Write-Output "Sending Diagram file to Storage Account:"
                    Write-Output $DDFile
                    Set-AzStorageBlobContent -File $DDFile -Container $StorageContainer -Context $StorageContext -Force | Out-Null
                }

            # $Debug is not a declared parameter — -Debug is a common parameter, so the old
            # `$Debug.IsPresent` test was always $null/false and the diagnostic log never
            # uploaded from a runbook. $DebugPreference is what -Debug actually sets.
            if ($DebugPreference -ne 'SilentlyContinue')
                {
                    $LogFilePath = Join-Path $DefaultPath 'DiagramLogFile.log'
                    if (Test-Path -Path $LogFilePath)
                        {
                            Write-Output "Sending diagnostic log to Storage Account:"
                            Write-Output $LogFilePath
                            Set-AzStorageBlobContent -File $LogFilePath -Container $StorageContainer -Context $StorageContext -Force | Out-Null
                        }
                }
        }

    $TotalRunTime.Stop()

    $Measure = $TotalRunTime.Elapsed.ToString("dd\:hh\:mm\:ss\:fff")

Write-Progress -activity 'Azure Inventory' -Status "100% Complete." -Completed

Write-AZSCLogPhase -Name 'Run complete' -Elapsed $Measure -Detail @{
    'Resources on Azure' = $ResourcesCount
    'Rows on Excel'      = $TotalRes
    'Report file'        = $File
}

Out-AZSCReportResults -Measure $Measure -ResourcesCount $ResourcesCount -TotalRes $TotalRes -SkipAdvisory $SkipAdvisory -AdvisoryData $AdvisoryCount -SkipPolicy $SkipPolicy -SkipAPIs $SkipAPIs -PolicyData $PolicyCount -SecurityCenter $SecurityCenter -SecurityCenterData $SecCenterCount -File $File -SkipDiagram $SkipDiagram -DDFile $DDFile

# Closed last so the transcript captures the run summary above, and so the operator is told
# where the log is on a successful run as well as a failed one (AB#5635).
$null = Stop-AZSCRunLog -Status 'COMPLETED'

}
