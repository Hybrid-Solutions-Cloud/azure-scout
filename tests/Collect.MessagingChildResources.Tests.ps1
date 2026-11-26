#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#9300, 3.18.20 -- the network rule sets, authorization rules and entities of Event Hubs and Service Bus namespaces.

    Resource Graph indexes a namespace but not these children, so Get-ScoutArmChildResource reads seven datasets with ARM GETs:
    per namespace the network rule set (Event Hubs Standard and above, Service Bus Premium only) and the authorization rules, and
    the event hubs, or the queues and topics. The shared contract is asserted by tests/helpers/DepthChildHarness.ps1; this file
    adds what is particular to messaging:

      - a Basic Event Hubs namespace and a Standard Service Bus namespace cannot have IP firewall rules and are not asked for
        a network rule set (the answer would be a 400 and a warning for something that is not a failure);
      - the allowed addresses and subnets are counted, never listed; an authorization rule becomes three booleans (rights) and
        its keys -- a POST (listKeys) -- are never asked;
      - a hub's capture destination (storage account and container) and a queue's forwarding targets are never read.

    No Azure connection, credential, tenant or subscription identifier is involved.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertTo-ScoutChildDiscoveryResource.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthChildHarness.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthFamilyCases.ps1')
    $script:Family = @(Get-DepthFamilyCase | Where-Object { $_.Name -eq 'Messaging' })[0]
}

AfterAll { Remove-DepthStub }

Describe 'Get-ScoutArmChildResource -- Event Hubs and Service Bus: what is asked and what is kept' {

    It 'asks nothing without an Event Hubs or Service Bus namespace' {
        Assert-DepthNothingAskedWithoutParent -Family $script:Family
    }

    It 'issues the documented request for every dataset, skipping the network rule set for tiers that cannot have one' {
        Assert-DepthDocumentedRequest -Family $script:Family
        $script:StubCalls | Where-Object { $_ -match '/ehbasic/networkRuleSets|/sbstd/networkRuleSets' } | Should -BeNullOrEmpty
    }

    It 'carries no IP address, subnet id, capture destination or forwarding target' {
        Assert-DepthNoSecret -Family $script:Family
    }

    It 'never lists or regenerates a key: no POST action is made for an authorization rule' {
        Install-DepthStub -Routes $script:Family.Routes
        $null = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets
        @($script:StubCalls | Where-Object { $_ -match '(?i)listKeys|regenerateKeys|/list\b' }).Count | Should -Be 0
    }

    It 'leaves every dataset empty and unmeasured when every GET is denied, so a rule reads NotAssessed' {
        Assert-DepthDeniedIsNotMeasured -Family $script:Family
    }

    It 'treats an empty list as an answer: measured, no rows' {
        Assert-DepthEmptyIsAnAnswer -Family $script:Family
    }

    It 'retries a throttled request and does not report it as a failure' {
        Assert-DepthRetriesAThrottledRequest -Family $script:Family
    }
}

Describe 'ConvertFrom-ScoutInventory -- Event Hubs and Service Bus datasets' {

    BeforeAll {
        Install-DepthStub -Routes $script:Family.Routes
        $script:Sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets
        $script:Shaped = Get-DepthShaped -Sweep $script:Sweep -Resources $script:Family.Parents
    }

    It 'sets every Measured flag when the datasets were answered' {
        foreach ($key in $script:Family.Keys) { $script:Shaped["${key}Measured"] | Should -BeTrue -Because $key }
    }

    It 'says whether a namespace accepts connections from any network, and counts the rules that restrict it' {
        $eh = @($script:Shaped.eventHubNetworkRuleSets)
        $eh.Count | Should -Be 1
        $eh[0].defaultAction | Should -Be 'Deny'
        $eh[0].allowsAllNetworks | Should -BeFalse
        $eh[0].ipRuleCount | Should -Be 1
        $eh[0].virtualNetworkRuleCount | Should -Be 1
        $eh[0].trustedServiceAccess | Should -BeTrue
        $sb = @($script:Shaped.serviceBusNetworkRuleSets)
        $sb.Count | Should -Be 1
        $sb[0].allowsAllNetworks | Should -BeTrue -Because 'default action Allow with public network access Enabled'
        $sb[0].ipRuleCount | Should -Be 0
    }

    It 'summarises authorization rules per namespace, apart from the namespace''s own root rule' {
        $rules = @($script:Shaped.eventHubAuthorization)
        $rules.Count | Should -Be 2 -Because 'one summary row per namespace whose list answered'
        $standard = @($rules | Where-Object name -eq 'ehstd')[0]
        $standard.ruleCount | Should -Be 3
        $standard.manageRuleCount | Should -Be 2
        $standard.nonRootManageRuleCount | Should -Be 1 -Because 'ops-admin carries Manage beside RootManageSharedAccessKey'
        $standard.sendListenOnlyCount | Should -Be 1
        @($script:Shaped.serviceBusAuthorization).Count | Should -Be 2
    }

    It 'shapes event hubs with partitions, retention and whether Capture is on' {
        $hubs = @($script:Shaped.eventHubEntities)
        $hubs.Count | Should -Be 2
        $hub = @($hubs | Where-Object namespaceName -eq 'ehstd')[0]
        $hub.name | Should -Be 'hub1'
        $hub.partitionCount | Should -Be 4
        $hub.messageRetentionInDays | Should -Be 7
        $hub.retentionTimeInHours | Should -Be 168
        $hub.cleanupPolicy | Should -Be 'Delete'
        $hub.captureEnabled | Should -BeTrue
        $hub.captureIntervalInSeconds | Should -Be 300
    }

    It 'shapes queues with dead-lettering, duplicate detection and delivery limit, and topics with their subscription count' {
        $queue = @($script:Shaped.serviceBusQueues | Where-Object namespaceName -eq 'sbprem')[0]
        $queue.name | Should -Be 'q1'
        $queue.maxDeliveryCount | Should -Be 10
        $queue.deadLetteringOnMessageExpiration | Should -BeTrue
        $queue.requiresDuplicateDetection | Should -BeFalse
        $queue.forwardsMessages | Should -BeTrue
        $queue.forwardsDeadLetteredMessages | Should -BeTrue
        $queue.lockDuration | Should -Be 'PT1M'
        $topic = @($script:Shaped.serviceBusTopics | Where-Object namespaceName -eq 'sbprem')[0]
        $topic.subscriptionCount | Should -Be 2
        $topic.requiresDuplicateDetection | Should -BeTrue
    }

    It 'mirrors every row under a real Event Hubs or Service Bus type for the discovery index' {
        $twins = @(ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Sweep.Rows))
        @($twins.type | Sort-Object -Unique) | Should -Be @(
            'microsoft.eventhub/namespaces/authorizationrules', 'microsoft.eventhub/namespaces/eventhubs', 'microsoft.eventhub/namespaces/networkrulesets',
            'microsoft.servicebus/namespaces/authorizationrules', 'microsoft.servicebus/namespaces/networkrulesets',
            'microsoft.servicebus/namespaces/queues', 'microsoft.servicebus/namespaces/topics')
    }
}
