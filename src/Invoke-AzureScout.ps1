#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Inventory and assess Azure resources, producing React, Json, and JsonEvidence outputs.

.DESCRIPTION
    Runs a tenant-wide Azure inventory, an assessment, or both from one entry point. Live outputs
    are the self-contained React report, the inventory/assessment Json export, and JsonEvidence.
    Use -Scope All or -Scope EntraOnly when Microsoft Entra ID data is required.

.PARAMETER TenantID
    Specify the tenant ID you want to create a Resource Inventory.

    >>> IMPORTANT: YOU NEED TO USE THIS PARAMETER FOR TENANTS WITH MULTI-FACTOR AUTHENTICATION. <<<

.PARAMETER SubscriptionID
    Use this parameter to collect a specific Subscription in a Tenant

.PARAMETER ManagementGroup
    Use this parameter to collect all Subscriptions in a Specific Management Group in a Tenant

.PARAMETER Lite
    Legacy compatibility switch for the held Excel renderer. It does not change the live React,
    Json, or JsonEvidence outputs.

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
    Legacy compatibility setting for the held Excel overview design. It does not change the live
    React, Json, or JsonEvidence outputs.

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
    Runs a dedicated permissions audit only. No inventory or standard live report is generated.
    Outputs a colour-coded console report showing ARM/RBAC access across all visible
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

    Valid values: All, AI, Analytics, Compute, Containers, Databases, DevOps, General, Hybrid,
    Identity, Integration, IoT, Management, Migration, Monitor, Networking, Security, Storage, Web.

    These are Microsoft's eighteen published service categories (portal → All services).

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
    - All (default): Generate every live format: React, Json, and JsonEvidence
    - React: Generate the self-contained interactive report
    - Json: Generate the inventory JSON export
    - JsonEvidence: Generate the resources-only evidence.json export
    Legacy renderer names remain accepted for compatibility, warn that they are on hold, and are
    skipped. If every explicitly requested format is held, React is generated as the fallback.
    PermissionAudit is a specialized exception and retains its Console/Json/Markdown/AsciiDoc
    output contract.

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
    Official Repository: https://github.com/Hybrid-Solutions-Cloud/azure-scout
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CertificatePassword',
        Justification = 'Headless SPN/cert auth: arrives as a plain string from CI env vars / callers and is forwarded as-is to Connect-AZSCLoginSession; changing the parameter type is a breaking change for every existing caller.')]
    param (
        [ValidateSet(1, 2, 3)]
        [int]$Overview = 1,
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
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
            # Live formats plus compatibility names for held legacy renderers.
            'All', 'Excel', 'Json', 'Markdown', 'AsciiDoc', 'MD', 'Adoc', 'PowerBI',
            'Html', 'Pptx', 'JsonEvidence', 'React', 'Pdf', 'Word', 'EChartsDashboard')]
        [string[]]$OutputFormat = @('All'),
        # ── Assessment mode (AB#5540, per AB#5024) ───────────────────────────
        # Supplying -Assessment switches this command from inventory to the
        # CAF/WAF assessment platform. Same command, same sign-in, same module.
        [Alias('Assess')]
        [string[]]$Assessment,
        # Run the inventory pass AND the assessment from one collection (AB#6775). Without
        # this, -Assessment returns the assessment alone and the only way to reach the
        # collect-once path was to answer the wizard's "both?" prompt -- unreachable from a
        # script or a pipeline, which had to invoke the command twice and pay for two
        # collections. The assessment runs second and is handed the inventory's rows.
        [Alias('Both')]
        [switch]$InventoryAndAssessment,
        [switch]$CollectOnly,
        [string]$FromCollect,
        # Suppress the guided wizard that a bare, interactive `Invoke-AzureScout`
        # opens, and run the default full ARM inventory instead.
        [Alias('NonInteractive')]
        [switch]$NoWizard,
        # Suppress all interactive progress rendering. CI/unattended hosts also suppress the
        # Spectre TUI automatically and retain log-friendly phase records.
        [switch]$NoProgress,
        [ValidateSet('All', 'AI', 'Analytics', 'Compute', 'Containers', 'Databases', 'DevOps', 'General', 'Hybrid', 'Identity', 'Integration', 'IoT', 'Management', 'Migration', 'Monitor', 'Networking', 'Security', 'Storage', 'Web')]
        [string[]]$Category = @('All'),
        [string]$RunName,
        [switch]$Force,
        [Alias('IncludeADO','DevOps')]
        [switch]$IncludeDevOps,
        [Alias('ADOOrganization')]
        [string[]]$DevOpsOrganization,
        [Alias('ADOPat')]
        [string]$DevOpsPat,
        # AB#6930 -- operator-supplied report identity for the React report (clientName,
        # engagementName, classification, preparedBy, etc.). Only meaningful with -Assessment
        # (or -CollectOnly/-FromCollect, which route to the same assessment core below); unset
        # keys fall back to neutral defaults, never a vendor name or URL. See
        # Get-ScoutReportIdentityDefault in src/report/renderers/Export-React.ps1.
        [hashtable]$ReportIdentity = @{},
        # AB#6928 follow-up -- which view lens the React report opens on first (Executive/
        # Consultant/Data) when the browser has nothing persisted yet. Default Consultant.
        [ValidateSet('Executive', 'Consultant', 'Data')]
        [string]$DefaultReportMode = 'Consultant'
        )

    if ($NoProgress.IsPresent) { $ProgressPreference = 'SilentlyContinue' }

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
        # 'DevOps' and 'Migration' used to alias to 'Management'. Both are now real categories of
        # their own (AB#6741) with their own manifests/collectors folders, so folding them into
        # Management would silently run the wrong collectors. They were also unreachable before
        # this change -- neither string was in the ValidateSet, so the map entries never fired.
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
                    throw 'Storage Account and Container are required for Automation mode.'
                }
        }
    elseif ($StorageAccount -and -not $StorageContainer)
        {
            throw 'StorageContainer is required when StorageAccount is specified.'
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
        Write-Host " -OutputFormat            :  Live formats: All (default), React, Json, JsonEvidence. Legacy names bind but are on hold. "
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
        return
    }

    $previousAzBreakingChangeWarningSetting = [Environment]::GetEnvironmentVariable('SuppressAzurePowerShellBreakingChangeWarnings', 'Process')
    $restoreAzBreakingChangeWarningSetting = $false
    $runLogStarted = $false
    $bufferedWarnings = [System.Collections.Generic.List[string]]::new()
    try {

    # ── Console verbosity (AB#5410) ───────────────────────────────────────────
    # If the user did not explicitly request -Verbose or -Debug, we silently continue
    # warnings so the console remains clean of 400/429 ARC errors. However, we hook
    # Write-Warning to explicitly forward the messages to our structured log, guaranteeing
    # no diagnostics are lost in the background.
    if (-not ($PSBoundParameters.ContainsKey('Debug') -or $PSBoundParameters.ContainsKey('Verbose'))) {
        $WarningPreference = 'SilentlyContinue'
        $env:SuppressAzurePowerShellBreakingChangeWarnings = 'true'
        $restoreAzBreakingChangeWarningSetting = $true
        function Write-Warning {
            # Deliberately shadows the built-in: every existing Write-Warning call in this
            # call tree (collectors, modules, this function itself) must be redirected to the
            # structured log without touching every call site individually (AB#5410).
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Deliberate shadow (AB#5410): redirects every Write-Warning call in this call tree to the structured log instead of the console, without editing every call site.')]
            param([Parameter(Mandatory=$true, ValueFromPipeline=$true)][string]$Message)
            process {
                if ($runLogStarted -and (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue)) {
                    Write-AZSCLog -Level Warn -Message $Message
                }
                else {
                    $bufferedWarnings.Add($Message)
                }
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
    $deferredInventoryOutputArgs = $null
    $ReactFile = $null
    $EvidenceFile = $null
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

    # One global output contract for inventory, assessment, and combined runs. Legacy names stay
    # in the ValidateSet so existing automation still binds, but they are held rather than run.
    # `All` silently means every live format. An explicit held-only request falls back to React;
    # a mixed request skips held formats and produces only the live formats the operator named.
    $requestedFormats = @($OutputFormat)
    if (-not $PermissionAudit.IsPresent) {
        $liveFormats = @('React', 'Json', 'JsonEvidence')
        $heldFormats = @($requestedFormats | Where-Object { $_ -ne 'All' -and $_ -notin $liveFormats } | Select-Object -Unique)
        if ($heldFormats.Count -gt 0) {
            Write-Warning ("Invoke-AzureScout: {0} report format(s) are on hold and will not be rendered: {1}. Live formats: React, Json, JsonEvidence." -f
                $heldFormats.Count, ($heldFormats -join ', '))
        }

        $effectiveFormats = if ($requestedFormats -contains 'All') {
            $liveFormats
        }
        else {
            @($requestedFormats | Where-Object { $_ -in $liveFormats } | Select-Object -Unique)
        }
        if (@($effectiveFormats).Count -eq 0) {
            Write-Warning 'Invoke-AzureScout: every requested report format is on hold; rendering the React report instead so the run still produces a deliverable.'
            $effectiveFormats = @('React')
        }
        $OutputFormat = @($effectiveFormats)
    }

    # ── Assessment mode (AB#5540, per AB#5024) ───────────────────────────────
    # One command, two modes. -Assessment routes this run to the CAF/WAF
    # assessment platform instead of the inventory collector. Everything else —
    # sign-in, tenant selection, report directory, category filtering — is the
    # same surface the inventory mode uses.
    if ($Assessment -or $CollectOnly.IsPresent -or $FromCollect) {
        # -FromCollect re-assesses an existing collect.json offline, so it must
        # not force a sign-in the run doesn't need.
        if (-not $FromCollect -and -not ($wizardRunBoth -or $InventoryAndAssessment.IsPresent) -and
            $PlatOS -ne 'Azure CloudShell' -and !$Automation.IsPresent) {
            $TenantID = Connect-AZSCLoginSession -AzureEnvironment $AzureEnvironment -TenantID $TenantID -DeviceLogin:$DeviceLogin -AppId $AppId -Secret $Secret -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword
        }

        # AB#6795 -- 'Estate' no longer exists in the registry; 'CAF: Azure Landing Zone' is the
        # same default used everywhere else an assessment name is needed and none was given.
        $assessArgs = @{ Assessment = if ($Assessment) { $Assessment } else { @('CAF: Azure Landing Zone') } }
        if ($PSBoundParameters.ContainsKey('Scope'))        { $assessArgs.Scope = $Scope }
        $assessArgs.OutputFormat = @($OutputFormat)
        if ($ReportDir)                                     { $assessArgs.OutputPath = $ReportDir }
        # 'All' is the inventory default sentinel, not a real assessment category —
        # passing it through would filter the collect down to nothing.
        if ($Category -and $Category -notcontains 'All')    { $assessArgs.Category = $Category }
        if ($ManagementGroup)                               { $assessArgs.ManagementGroupId = $ManagementGroup[0] }
        if ($PermissionAudit.IsPresent)                     { $assessArgs.PermissionAudit = $true }
        if ($CollectOnly.IsPresent)                         { $assessArgs.CollectOnly = $true }
        if ($FromCollect)                                   { $assessArgs.FromCollect = $FromCollect }
        # AB#6827 -- a standalone `-Assessment 'Microsoft: DevOps Capability' -IncludeDevOps` run
        # (no -InventoryAndAssessment) needs these threaded through too, not just the deferred/
        # combined path below.
        if ($IncludeDevOps.IsPresent)                       { $assessArgs.IncludeDevOps = $true }
        if ($DevOpsOrganization)                            { $assessArgs.DevOpsOrganization = $DevOpsOrganization }
        if ($DevOpsPat)                                     { $assessArgs.DevOpsPat = $DevOpsPat }
        if ($TenantID)                                      { $assessArgs.TenantID = $TenantID }
        if ($ReportIdentity -and $ReportIdentity.Count -gt 0) { $assessArgs.ReportIdentity = $ReportIdentity }
        if ($PSBoundParameters.ContainsKey('DefaultReportMode')) { $assessArgs.DefaultReportMode = $DefaultReportMode }

        # "Both" from the wizard or command line: DEFER the assessment until after the inventory
        # pass instead of running it now (AB#5543). Running the assessment here made the command
        # collect from Azure twice —
        # the assessment issued its own Resource Graph pack, then the inventory re-fetched the
        # same resource types moments later. Inventory already projects the full `properties`
        # bag, so running it first and handing those rows to the assessment collects once.
        # AB#6775 -- the public switch keeps the collect-once path reachable from scripted callers
        # as well as the wizard, without collecting from Azure twice to get both reports.
        if ($wizardRunBoth -or $InventoryAndAssessment.IsPresent) { $deferredAssessArgs = $assessArgs }
        else {
            $standaloneAssessmentOperation = {
                Invoke-ScoutAssessmentCore @assessArgs
            }
            if (Get-Command Invoke-ScoutProgressOperation -ErrorAction SilentlyContinue) {
                $standaloneRunPath = Invoke-ScoutProgressOperation -Activity 'Azure assessment' `
                    -Status 'Collecting, scoring, and rendering' -PercentComplete 1 -Id 1 `
                    -Operation $standaloneAssessmentOperation
            }
            else {
                $standaloneRunPath = & $standaloneAssessmentOperation
            }
            # AB#7224 -- same discoverability pointer as the combined path below.
            if ($standaloneRunPath) {
                $reactFile = Join-Path ([string]$standaloneRunPath) 'report-react.html'
                if (Test-Path $reactFile) {
                    Write-Host ''
                    Write-Host "  React report : $reactFile" -ForegroundColor Cyan
                    Write-Host ''
                }
            }

            # Standalone assessment returns before the inventory pipeline's shared upload block.
            # Upload exactly the selected live artifacts here so -Assessment -Automation does not
            # validate storage settings and then silently leave every deliverable on local disk.
            if ($StorageAccount -and $standaloneRunPath -and -not $CollectOnly.IsPresent) {
                $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccount -UseConnectedAccount
                $assessmentArtifacts = [ordered]@{
                    React       = 'report-react.html'
                    Json        = 'findings.json'
                    JsonEvidence = 'evidence.json'
                }
                foreach ($format in @($OutputFormat)) {
                    if (-not $assessmentArtifacts.Contains($format)) { continue }
                    $artifactPath = Join-Path ([string]$standaloneRunPath) $assessmentArtifacts[$format]
                    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { continue }
                    Write-Verbose "Uploading standalone assessment artifact: $artifactPath"
                    Set-AzStorageBlobContent -File $artifactPath -Container $StorageContainer `
                        -Context $StorageContext -Force | Out-Null
                }
            }
            return $standaloneRunPath
        }
    }

    # ── Inventory mode ───────────────────────────────────────────────────────
    # -OutputFormat is [string[]] so assessment mode can request several
    # renderers in one run. The inventory report writers below were written
    # against a scalar, so resolve the requested formats to flags once here.
    $requestedFormats = @($OutputFormat)
    $WantExcel    = [bool](@('All', 'Excel')              | Where-Object { $_ -in $requestedFormats })
    $WantJson     = [bool](@('All', 'Json')               | Where-Object { $_ -in $requestedFormats })
    $WantMarkdown = [bool](@('All', 'Markdown', 'MD')     | Where-Object { $_ -in $requestedFormats })
    $WantAsciiDoc = [bool](@('All', 'AsciiDoc', 'Adoc')   | Where-Object { $_ -in $requestedFormats })
    $WantPowerBI  = [bool](@('All', 'PowerBI')            | Where-Object { $_ -in $requestedFormats })

    # Inventory-only React and JsonEvidence are rendered from the already-collected rows through
    # the assessment core's rule-free/offline mode. Combined runs deliberately do not set this:
    # their single deferred assessment render owns React and JsonEvidence.
    if (-not $PermissionAudit.IsPresent -and -not $deferredAssessArgs) {
        $inventoryOutputFormats = @($requestedFormats | Where-Object { $_ -in @('React', 'JsonEvidence') })
        if ($inventoryOutputFormats.Count -gt 0) {
            $deferredInventoryOutputArgs = @{
                InventoryOnly = $true
                OutputFormat  = $inventoryOutputFormats
                Scope         = $Scope
            }
            if ($ReportDir) { $deferredInventoryOutputArgs.OutputPath = $ReportDir }
            if ($TenantID) { $deferredInventoryOutputArgs.TenantID = $TenantID }
            if ($ReportIdentity -and $ReportIdentity.Count -gt 0) { $deferredInventoryOutputArgs.ReportIdentity = $ReportIdentity }
            if ($PSBoundParameters.ContainsKey('DefaultReportMode')) { $deferredInventoryOutputArgs.DefaultReportMode = $DefaultReportMode }
        }
    }

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
                throw "Failed to set Automation Account requirements: $($_.Exception.Message)"
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
            $AuthIdentity = Resolve-AZSCContextIdentity -Context $AuthCtx
            $AuthUpn = $AuthIdentity.AccountDisplayName
            $AuthSub = if ($AuthCtx.Subscription -and $AuthCtx.Subscription.Name) {
                "$($AuthCtx.Subscription.Name) ($($AuthCtx.Subscription.Id))"
            } else { 'none selected' }
            Write-Host ''
            Write-Host '  Signed in as : ' -NoNewline -ForegroundColor DarkGray; Write-Host $AuthUpn -ForegroundColor Cyan
            Write-Host '  Subscription : ' -NoNewline -ForegroundColor DarkGray; Write-Host $AuthSub -ForegroundColor Cyan
            Write-Host '  Tenant       : ' -NoNewline -ForegroundColor DarkGray; Write-Host $AuthIdentity.TenantDisplayName -ForegroundColor Cyan

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

    # Run isolation (AB#331): each invocation gets its own timestamped folder so a rerun -
    # or a scan of a second tenant - cannot destroy the previous run's cache or report.
    # -Force restores the pre-2.3.0 overwrite-in-place behaviour.
    $ReportingPath = Set-AZSCReportPath -ReportDir $ReportDir -RunName $RunName -ScopeId $TenantID -Force:$Force

    $DefaultPath = $ReportingPath.DefaultPath
    $DiagramCache = $ReportingPath.DiagramCache
    $ReportCache = $ReportingPath.ReportCache

    # AB#7185 -- $deferredAssessArgs.OutputPath was captured back at the "-Assessment" block
    # (line ~601) as the bare $ReportDir, before this timestamped per-run folder existed.
    # Invoke-ScoutAssessmentCore then created ITS OWN run folder directly under that bare root
    # instead of writing into the folder the inventory pass (React/Json/JsonEvidence)
    # just wrote to -- a "Both" run produced two sibling output folders, with the React report
    # (the only renderer the assessment side of a combined run actually produces) landing in the
    # one the operator had no reason to go looking in. Retarget it to the real run folder now
    # that Set-AZSCReportPath has created it.
    if ($deferredAssessArgs) { $deferredAssessArgs.OutputPath = $DefaultPath }
    if ($deferredInventoryOutputArgs) { $deferredInventoryOutputArgs.OutputPath = $DefaultPath }

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
    $runLogStarted = $true
    foreach ($bufferedWarning in $bufferedWarnings) {
        Write-AZSCLog -Level Warn -Message $bufferedWarning
    }
    $bufferedWarnings.Clear()

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

    # --- Pre-flight permission check ---
    # The audit is intentionally after run-log initialization and the failure trap. A token,
    # RBAC, or Graph-probe failure is one of the most useful diagnostics to persist, and before
    # this ordering it could terminate before scout-run.log existed. Test-AZSCPermissions calls
    # the underlying audit quietly; this loop is the sole pre-flight renderer.
    if (-not $SkipPermissionCheck.IsPresent) {
        Write-Host 'Running pre-flight permission checks...' -ForegroundColor Cyan
        $permissionOperation = {
            Test-AZSCPermissions -TenantID $TenantID -SubscriptionID $SubscriptionID -Scope $Scope
        }
        if (Get-Command Invoke-ScoutProgressOperation -ErrorAction SilentlyContinue) {
            $permResult = Invoke-ScoutProgressOperation -Activity 'Azure Scout' `
                -Status 'Validating tenant permissions' -PercentComplete 0 -Id 1 `
                -Operation $permissionOperation
        }
        else {
            $permResult = & $permissionOperation
        }
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

    Clear-AZSCCacheFolder -ReportCache $ReportCache

    # The ResourceJob_* sweep that stood here is gone with the jobs themselves (AB#5649). The
    # processing phase runs collectors in-process, so there is no leftover job state from a
    # previous run in this session to clear.

    $ExtractionRuntime = [System.Diagnostics.Stopwatch]::StartNew()
    Write-AZSCLog -Level 'VERBOSE' -Message (
        'Extraction orchestration started: scope={0}; subscriptions={1}; categories={2}' -f
            $Scope, @($Subscriptions).Count, @($Category).Count
    )

    # AB#6776 -- the collect-once handoff silently lost tags.
    #
    # Invoke-Collect forces IncludeTags on its OWN raw pass and documents why: the canonical
    # contract's top-level `tags` key is aggregated from the raw container row, and the raw pass
    # omits the `tags` column unless asked. The inventory pass had no such rule -- it passed
    # `-IncludeTags $IncludeTags`, defaulting to false -- so a combined run WITHOUT -IncludeTags
    # handed the assessment rows with no tags column and produced an empty `collect.tags`
    # aggregation. The assessment-only path got tags; the collect-once path did not, which is
    # the worst shape for a defect to have: the cheaper path was the wrong one.
    $extractionIncludeTags = $IncludeTags
    if ($deferredAssessArgs -and -not $IncludeTags) {
        Write-Verbose 'Invoke-AzureScout: forcing -IncludeTags on the inventory pass because an assessment will consume its rows (AB#6776).'
        $extractionIncludeTags = [switch]$true
    }

    $extractionOperation = {
        # Keep the named call explicit: these parameters are a safety contract for the
        # collect-once tag handoff and category/dependency extraction plan.
        Start-AZSCExtractionOrchestration -ManagementGroup $ManagementGroup -Subscriptions $Subscriptions `
            -SubscriptionID $SubscriptionID -ResourceGroup $ResourceGroup -SecurityCenter $SecurityCenter `
            -SkipAdvisory $SkipAdvisory -SkipPolicy $SkipPolicy -IncludeTags $extractionIncludeTags `
            -TagKey $TagKey -TagValue $TagValue -SkipAPIs $SkipAPIs -SkipVMDetails $SkipVMDetails `
            -IncludeCosts $IncludeCosts -Automation $Automation -AzureEnvironment $AzureEnvironment `
            -Scope $Scope -TenantID $TenantID -IncludeDevOps:$IncludeDevOps `
            -DevOpsOrganization $DevOpsOrganization -DevOpsPat $DevOpsPat -Category $Category `
            -PreserveAssessmentDependencies:($null -ne $deferredAssessArgs)
    }
    if (Get-Command Invoke-ScoutProgressOperation -ErrorAction SilentlyContinue) {
        $ExtractionData = Invoke-ScoutProgressOperation -Activity 'Azure Inventory' `
            -Status 'Starting extraction' -PercentComplete 1 -Id 1 `
            -Operation $extractionOperation
    }
    else {
        $ExtractionData = & $extractionOperation
    }

    $ExtractionRuntime.Stop()

    # AB#6764 — dump everything that was collected, before any manifest gets to decide what is
    # worth rendering. Roughly 40% of what the unfiltered Resource Graph pass returns reaches no
    # worksheet, and until now it was discarded without being written anywhere. This runs here,
    # ahead of the processing phase, precisely so "before any filtering" is a property of the
    # call site rather than a claim in a comment.
    $RawDumpTimer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-AZSCLog -Level 'DEBUG' -Message 'Raw inventory dump started.'
    $RawDumpPath = Export-ScoutRawInventoryDump -ExtractionData $ExtractionData -DefaultPath $DefaultPath
    $RawDumpTimer.Stop()
    Write-AZSCLog -Level 'VERBOSE' -Message (
        'Raw inventory dump finished: status={0}; rows={1}; elapsed={2}' -f
            $(if ($RawDumpPath) { 'Written' } else { 'Empty' }),
            @($ExtractionData.Resources).Count,
            $RawDumpTimer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
    )

    # AB#5543 — the wizard asked for both modes. The inventory pass above has now fetched the
    # resource rows, so hand them to the assessment instead of letting it collect from Azure a
    # second time over the same resource types.
    #
    # AB#6737 -- this call used to fire HERE, before $DDFile even exists (below) and before
    # Start-AZSCExtraJobs (further below) has built it. In the wizard's "Both" mode -- the only
    # mode where a diagram and a PDF are both reachable in one run -- the deferred assessment
    # (and therefore its PDF, AB#379) always rendered before the diagram existed, so there was
    # never a point in the run where a diagram was even available to embed. The call is moved
    # past the diagram build below; $ExtractionData is kept alive for it (its
    # Remove-Variable moved down to match) instead of being freed here. Keeping it alive costs
    # little: $Resources/$Advisories/etc. below are reference copies of $ExtractionData's own
    # properties, not deep copies, so the underlying arrays are already held open by those
    # variables regardless of whether $ExtractionData itself is freed now or later.
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
    $CollectionHealth = if ($ExtractionData.PSObject.Properties['CollectionHealth']) { @($ExtractionData.CollectionHealth) } else { @() }

    $ExtractionTotalTime = $ExtractionRuntime.Elapsed.ToString("dd\:hh\:mm\:ss\:fff")

    Write-AZSCLogPhase -Name 'Extraction finished' -Elapsed $ExtractionTotalTime -Detail @{
        'Resources'          = @($Resources).Count
        'ResourceContainers' = @($ResourceContainers).Count
        'Advisories'         = @($Advisories).Count
        'Security findings'  = @($Security).Count
        'Retirements'        = @($Retirements).Count
        'Entra objects'      = @($EntraResources).Count
        'Raw dump'           = $RawDumpPath
        'Quotas'             = @($Quotas).Count
        'Policy assignments' = @($PolicyAssign).Count
        'Policy definitions' = @($PolicyDef).Count
        'Policy set defs'    = @($PolicySetDef).Count
        'Cost rows'          = @($CostData).Count
        'Unavailable datasets' = @($CollectionHealth).Count
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
        $ExtraProcessingTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-AZSCLog -Level 'DEBUG' -Message 'Processing subphase for diagram and supplemental datasets started.'
        $extraProcessingOperation = {
            Start-AZSCExtraJobs -SkipDiagram $SkipDiagram -SkipAdvisory $SkipAdvisory `
                -SkipPolicy $SkipPolicy -SecurityCenter $Security -Subscriptions $Subscriptions `
                -Resources $Resources -Advisories $Advisories -DDFile $DDFile `
                -DiagramCache $DiagramCache -FullEnv $FullEnv `
                -ResourceContainers $ResourceContainers -Security $Security `
                -PolicyAssign $PolicyAssign -PolicySetDef $PolicySetDef -PolicyDef $PolicyDef `
                -IncludeCosts $IncludeCosts -CostData $CostData -Automation $Automation
        }
        if (Get-Command Invoke-ScoutProgressOperation -ErrorAction SilentlyContinue) {
            $ExtraData = Invoke-ScoutProgressOperation -Activity 'Processing inventory' `
                -Status 'Building diagrams and supplemental datasets' -PercentComplete 55 -Id 1 `
                -Operation $extraProcessingOperation
        }
        else {
            $ExtraData = & $extraProcessingOperation
        }
        $ExtraProcessingTimer.Stop()
        Write-AZSCLog -Level 'VERBOSE' -Message (
            'Processing subphase for diagram and supplemental datasets finished: elapsed={0}' -f
                $ExtraProcessingTimer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
        )

        # AB#6737 -- moved here (from immediately after the extraction call above) so the
        # deferred assessment -- and the PDF it may render -- runs AFTER Start-AZSCExtraJobs has
        # built $DDFile. Start-AZSCExtraJobs's diagram step (Invoke-AZSCDrawIOJob ->
        # Start-AZSCDrawIODiagram) is synchronous as of AB#5649 (it Wait-Jobs its own internal
        # fan-out before returning), so by the time this line runs $DDFile is a complete,
        # on-disk .drawio document, not a build still in flight. $ExtractionData still holds the
        # same object graph read below (nothing between its assignment and here reassigns or
        # mutates $Resources/$Advisories/etc.), so this is a pure reordering, not a data change.
        #
        # The stopwatch is PAUSED across this call. It measures the inventory processing phase,
        # and the assessment is a whole second pipeline -- collect, score, render -- that would
        # otherwise be counted as processing time and make 'Processing finished' report a number
        # several times its real value. A run log that overstates a phase is the same class of
        # defect as a report that overstates coverage, which is what this Epic exists to fix.
        # Stopwatch.Start() resumes rather than restarting, so the elapsed total stays correct.
        if ($deferredAssessArgs) {
            $ProcessingRunTime.Stop()
            try {
                $AssessmentRunTime = [System.Diagnostics.Stopwatch]::StartNew()
                Write-AZSCLog -Level 'VERBOSE' -Message 'Deferred assessment started from the in-memory inventory.'
                $deferredAssessmentOperation = {
                    Invoke-ScoutAssessmentCore @deferredAssessArgs -FromInventory $ExtractionData
                }
                if (Get-Command Invoke-ScoutProgressOperation -ErrorAction SilentlyContinue) {
                    $deferredRunPath = Invoke-ScoutProgressOperation -Activity 'Azure assessment' `
                        -Status 'Scoring and rendering selected assessments' -PercentComplete 70 -Id 1 `
                        -Operation $deferredAssessmentOperation
                }
                else {
                    $deferredRunPath = & $deferredAssessmentOperation
                }
                Write-Output $deferredRunPath
                # AB#7224 -- the React report is the assessment's deliverable, and on a combined
                # run it lands in a dated subfolder the operator has no reason to know about
                # (observed live: the owner searched the run root and concluded it was missing).
                # Name the exact file on the console at the moment it exists.
                if ($deferredRunPath) {
                    $reactFile = Join-Path ([string]$deferredRunPath) 'report-react.html'
                    if (Test-Path $reactFile) {
                        $ReactFile = $reactFile
                        Write-Host ''
                        Write-Host "  React report : $reactFile" -ForegroundColor Cyan
                        Write-Host ''
                    }
                    $evidenceCandidate = Join-Path ([string]$deferredRunPath) 'evidence.json'
                    if (Test-Path $evidenceCandidate) { $EvidenceFile = $evidenceCandidate }
                }
                $AssessmentRunTime.Stop()
                Write-AZSCLogPhase -Name 'Deferred assessment finished' -Elapsed $AssessmentRunTime.Elapsed.ToString('dd\:hh\:mm\:ss\:fff') -Detail @{
                    'Ran after' = 'diagram build (AB#6737)'
                }
            }
            catch {
                if ([string]$_.Exception.Data['AzureScoutFailureKind'] -ne 'AssessmentSourceUnavailable') { throw }
                if ($AssessmentRunTime -and $AssessmentRunTime.IsRunning) { $AssessmentRunTime.Stop() }
                $assessmentGap = $_.Exception.Message
                Write-Warning "Azure Scout skipped the scored assessment because required source data was unavailable. The inventory run will continue. $assessmentGap"
                Write-AZSCLog -Level 'WARN' -Message "Deferred assessment skipped; inventory continues. $assessmentGap" -Exception $_.Exception
            }
            finally {
                $ProcessingRunTime.Start()
            }
        }
        elseif ($deferredInventoryOutputArgs) {
            $ProcessingRunTime.Stop()
            try {
                $InventoryOutputRunTime = [System.Diagnostics.Stopwatch]::StartNew()
                Write-AZSCLog -Level 'VERBOSE' -Message 'Inventory React/evidence rendering started from the in-memory inventory; assessment rules are disabled.'
                $inventoryOutputOperation = {
                    Invoke-ScoutAssessmentCore @deferredInventoryOutputArgs -FromInventory $ExtractionData
                }
                if (Get-Command Invoke-ScoutProgressOperation -ErrorAction SilentlyContinue) {
                    $inventoryOutputRunPath = Invoke-ScoutProgressOperation -Activity 'Inventory report' `
                        -Status 'Rendering React and evidence outputs' -PercentComplete 70 -Id 1 `
                        -Operation $inventoryOutputOperation
                }
                else {
                    $inventoryOutputRunPath = & $inventoryOutputOperation
                }
                Write-Output $inventoryOutputRunPath
                if ($inventoryOutputRunPath -and $deferredInventoryOutputArgs.OutputFormat -contains 'React') {
                    $reactFile = Join-Path ([string]$inventoryOutputRunPath) 'report-react.html'
                    if (Test-Path $reactFile) {
                        $ReactFile = $reactFile
                        Write-Host ''
                        Write-Host "  React report : $reactFile" -ForegroundColor Cyan
                        Write-Host ''
                    }
                }
                if ($inventoryOutputRunPath) {
                    $evidenceCandidate = Join-Path ([string]$inventoryOutputRunPath) 'evidence.json'
                    if (Test-Path $evidenceCandidate) { $EvidenceFile = $evidenceCandidate }
                }
                $InventoryOutputRunTime.Stop()
                Write-AZSCLogPhase -Name 'Inventory React/evidence rendering finished' `
                    -Elapsed $InventoryOutputRunTime.Elapsed.ToString('dd\:hh\:mm\:ss\:fff') -Detail @{
                        'Formats' = $deferredInventoryOutputArgs.OutputFormat
                    }
            }
            finally {
                $ProcessingRunTime.Start()
            }
        }
        Remove-Variable -Name ExtractionData -ErrorAction SilentlyContinue

        $collectorProcessingOperation = {
            Start-AZSCProcessOrchestration -Subscriptions $Subscriptions -Resources $Resources `
                -Advisories $Advisories -Retirements $Retirements -DefaultPath $DefaultPath `
                -Heavy $Heavy -File $File -InTag $InTag -Automation $Automation `
                -Category $Category -CollectionHealth $CollectionHealth
        }
        if (Get-Command Invoke-ScoutProgressOperation -ErrorAction SilentlyContinue) {
            $null = Invoke-ScoutProgressOperation -Activity 'Processing inventory' `
                -Status 'Running collectors' -PercentComplete 75 -Id 1 `
                -Operation $collectorProcessingOperation
        }
        else {
            $null = & $collectorProcessingOperation
        }

    $ProcessingRunTime.Stop()

    $ProcessingTotalTime = $ProcessingRunTime.Elapsed.ToString("dd\:hh\:mm\:ss\:fff")

    Write-AZSCLogPhase -Name 'Processing finished' -Elapsed $ProcessingTotalTime -Detail @{
        'Cache files' = @(Get-ChildItem -Path $ReportCache -Filter '*.json' -ErrorAction SilentlyContinue).Count
        'Output root' = $DefaultPath
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

    # These values are consumed by the shared completion and upload paths even when their
    # renderer is not selected, or when a renderer fails and its catch block keeps the run
    # alive. Initialise them before branching so StrictMode preserves that best-effort design.
    $TotalRes = 0
    $JsonFile = $null

    # ── Excel Report ─────────────────────────────────────────────────────
    if ($WantExcel)
    {
        try {
            Start-AZSCReporOrchestration -ReportCache $ReportCache -SecurityCenter $SecurityCenter -File $File -Quotas $Quotas -SkipPolicy $SkipPolicy -SkipAdvisory $SkipAdvisory -IncludeCosts $IncludeCosts -Automation $Automation -TableStyle $TableStyle -ExtraData $ExtraData

            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Generating Overview sheet (Charts).')

            $TotalRes = Start-AZSCExcelCustomization -File $File -TableStyle $TableStyle -PlatOS $PlatOS -Subscriptions $Subscriptions -ExtractionRunTime $ExtractionRuntime -ProcessingRunTime $ProcessingRunTime -ReportingRunTime $ReportingRunTime -IncludeCosts $IncludeCosts -RunLite $RunLite -Overview $Overview -Category $Category

            if (Get-Command -Name 'Write-ScoutProgress' -ErrorAction SilentlyContinue) {
                Write-ScoutProgress -Activity 'Azure Inventory' -Status '95% Complete.' -PercentComplete 95 `
                    -CurrentOperation "Excel customization complete. Total resources inventoried: $TotalRes"
            }
            else {
                Write-Progress -Activity 'Azure Inventory' -Status '95% Complete.' -PercentComplete 95 `
                    -CurrentOperation "Excel customization complete. Total resources inventoried: $TotalRes"
            }
        }
        catch {
            Write-Warning "Excel report generation failed: $($_.Exception.Message)"
            Write-AZSCLog -Level Error -Message "Excel report generation failed: $($_.Exception.Message)" -Exception $_.Exception
        }
    }
    else
    {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Skipping Excel report (OutputFormat = Json).')
    }

    # ── JSON Report ──────────────────────────────────────────────────────
    if ($WantJson)
    {
        try {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting JSON report export.')
            $JsonFile = Export-AZSCJsonReport -ReportCache $ReportCache -File $File -TenantID $TenantID -Subscriptions $Subscriptions -Scope $Scope -Quotas $Quotas -SecurityCenter:$SecurityCenter -SkipAdvisory:$SkipAdvisory -SkipPolicy:$SkipPolicy -IncludeCosts:$IncludeCosts
        }
        catch {
            Write-Warning "JSON report generation failed: $($_.Exception.Message)"
            Write-AZSCLog -Level Error -Message "JSON report generation failed: $($_.Exception.Message)" -Exception $_.Exception
        }
    }

    # ── Markdown Report ──────────────────────────────────────────────────
    if ($WantMarkdown)
    {
        try {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Markdown report export.')
            Export-AZSCMarkdownReport -ReportCache $ReportCache -File $File -TenantID $TenantID -Subscriptions $Subscriptions -Scope $Scope | Out-Null
        }
        catch {
            Write-Warning "Markdown report generation failed: $($_.Exception.Message)"
            Write-AZSCLog -Level Error -Message "Markdown report generation failed: $($_.Exception.Message)" -Exception $_.Exception
        }
    }

    # ── AsciiDoc Report ──────────────────────────────────────────────────
    if ($WantAsciiDoc)
    {
        try {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting AsciiDoc report export.')
            Export-AZSCAsciiDocReport -ReportCache $ReportCache -File $File -TenantID $TenantID -Subscriptions $Subscriptions -Scope $Scope | Out-Null
        }
        catch {
            Write-Warning "AsciiDoc report generation failed: $($_.Exception.Message)"
            Write-AZSCLog -Level Error -Message "AsciiDoc report generation failed: $($_.Exception.Message)" -Exception $_.Exception
        }
    }

    # ── Power BI CSV Report ───────────────────────────────────────────────
    if ($WantPowerBI)
    {
        try {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Power BI CSV export.')
            Export-AZSCPowerBIReport -ReportCache $ReportCache -File $File -TenantID $TenantID -Subscriptions $Subscriptions -Scope $Scope | Out-Null
        }
        catch {
            Write-Warning "Power BI report generation failed: $($_.Exception.Message)"
            Write-AZSCLog -Level Error -Message "Power BI report generation failed: $($_.Exception.Message)" -Exception $_.Exception
        }
    }

    $ReportingRunTime.Stop()

    $ReportingTotalTime = $ReportingRunTime.Elapsed.ToString("dd\:hh\:mm\:ss\:fff")

    Write-AZSCLogPhase -Name 'Reporting finished' -Elapsed $ReportingTotalTime -Detail @{
        'Inventory JSON' = $JsonFile
        'React report'   = $ReactFile
        'JSON evidence'  = $EvidenceFile
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

        # Keep every per-run discovery and processing artifact. Operators can intentionally
        # prune old run folders with Clear-AZSCCacheFolder -OlderThan, but a successful scan
        # must never delete the data that produced its reports.
        Write-AZSCLog -Level 'VERBOSE' -Message (
            'Run evidence retained: raw inventory={0}; report cache={1}; diagram cache={2}' -f
                $RawDumpPath, $ReportCache, $DiagramCache
        )


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
            foreach ($liveArtifact in @($ReactFile, $EvidenceFile) | Where-Object { $_ } | Select-Object -Unique) {
                Write-Output "Sending live report artifact to Storage Account:"
                Write-Output $liveArtifact
                Set-AzStorageBlobContent -File $liveArtifact -Container $StorageContainer -Context $StorageContext -Force | Out-Null
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

if (Get-Command -Name 'Write-ScoutProgress' -ErrorAction SilentlyContinue) {
    Write-ScoutProgress -Activity 'Azure Inventory' -Status '100% Complete.' -Completed
}
else {
    Write-Progress -Activity 'Azure Inventory' -Status '100% Complete.' -Completed
}

Write-AZSCLogPhase -Name 'Run complete' -Elapsed $Measure -Detail @{
    'Resources on Azure' = $ResourcesCount
    'Output root'        = $DefaultPath
}

Out-AZSCReportResults -Measure $Measure -ResourcesCount $ResourcesCount -TotalRes $TotalRes -SkipAdvisory $SkipAdvisory -AdvisoryData $AdvisoryCount -SkipPolicy $SkipPolicy -SkipAPIs $SkipAPIs -PolicyData $PolicyCount -SecurityCenter $SecurityCenter -SecurityCenterData $SecCenterCount -File $File -ExcelRendered:$WantExcel -SkipDiagram $SkipDiagram -DDFile $DDFile

# Closed last so the transcript captures the run summary above, and so the operator is told
# where the log is on a successful run as well as a failed one (AB#5635).
$null = Stop-AZSCRunLog -Status 'COMPLETED'

    }
    finally {
        # A normal success or the trap above closes and clears the active log path. If control
        # reaches finally with a log still active (for example, a terminating path outside the
        # main body), leave a durable terminal marker instead of an apparently frozen log.
        if ($runLogStarted -and (Get-AZSCRunLogPath)) {
            try {
                Write-AZSCLog -Level 'ERROR' -Message 'Run ended without reaching the normal completion or failure handler.'
                $null = Stop-AZSCRunLog -Status 'FAILED' -Quiet
            }
            catch {
                # Logging is diagnostic-only and must never replace the original error.
                Write-Debug ('Invoke-AzureScout: unfinished run-log closure failed: ' + $_.Exception.Message)
            }
        }
        if ($restoreAzBreakingChangeWarningSetting) {
            if ($null -eq $previousAzBreakingChangeWarningSetting) {
                [Environment]::SetEnvironmentVariable('SuppressAzurePowerShellBreakingChangeWarnings', $null, 'Process')
            }
            else {
                [Environment]::SetEnvironmentVariable('SuppressAzurePowerShellBreakingChangeWarnings', $previousAzBreakingChangeWarningSetting, 'Process')
            }
        }
    }
}
