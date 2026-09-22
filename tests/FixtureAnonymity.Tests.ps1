#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5667 -- the committed `tests/fixtures/captured-*.json` files were captured from a REAL
    Azure tenant. The repo's hard rules forbid committing secrets, tokens, passwords,
    subscription / tenant / client IDs or connection strings in ANY file, and a test fixture is
    not an exception to that.

    scripts/Export-ScoutFixture.ps1 anonymises on the way out and refuses to write a file that
    still contains anything unrecognised. That gate only fires when somebody RUNS the capture
    script, though, so on its own it does nothing about a fixture edited by hand afterwards, a
    fixture restored from an older commit, or a fixture produced by a future version of the
    script whose anonymiser has regressed. This file re-runs the same verification against
    whatever is actually committed, on every CI run.

    WHY THIS IS WORTH A DEDICATED TEST FILE
    The first version of these fixtures passed a "does it look anonymised?" eyeball check and
    still shipped, among other things: a real subscription GUID, the resource-group and
    application names of a live estate, container image repositories and digests, and the
    complete NAME LIST of a Key Vault's secrets. Every one of those sat in a position the
    anonymiser of the day did not visit -- inside a URL path, inside a base64-encoded shell
    command, inside a tag value, and (the one that survived two rounds of fixing) inside a
    DICTIONARY KEY, because `identity.userAssignedIdentities` is keyed by full ARM resource id.

    A leak of that class is invisible to review and permanent once pushed. It gets a machine
    check, not a habit.
#>

Describe 'Committed capture fixtures are provably anonymous (AB#5667)' {

    BeforeAll {
        $script:RepoRoot    = Split-Path -Parent $PSScriptRoot
        $script:FixtureRoot = Join-Path $script:RepoRoot 'tests' 'fixtures'
        $script:ScriptPath  = Join-Path $script:RepoRoot 'scripts' 'Export-ScoutFixture.ps1'

        # Export-ScoutFixture.ps1 is a SCRIPT, not a module: running it would try to capture. Its
        # anonymisation half is pulled in here by parsing the file and executing only its
        # function definitions and script-scope variable assignments, so the verifier under test
        # is literally the same code the capture path uses -- not a second copy that could drift
        # away from it.
        $ast    = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $wanted = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                 $node.Left.Extent.Text -like '$script:*')
            }, $false)

        $source = ($wanted | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine
        . ([ScriptBlock]::Create($source))

        $script:CapturedFiles = @(
            Get-ChildItem -Path $script:FixtureRoot -Filter 'captured-*.json' -File | Sort-Object Name
        )
    }

    It 'finds the capture fixtures at all' {
        # Guards against this whole file silently passing because a rename made the glob match
        # nothing -- a test that checks zero files would otherwise be green forever.
        $script:CapturedFiles.Count | Should -BeGreaterThan 0
    }

    It 'loaded the anonymiser out of Export-ScoutFixture.ps1' {
        Get-Command Test-ScoutFixtureAnonymity -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command ConvertTo-ScoutAnonymizedGraph -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'every captured-*.json parses as JSON' {
        # A zero-BYTE file is not valid JSON. An earlier build wrote one for a query that
        # returned no rows, which is both unparseable and indistinguishable from a crashed
        # capture; the empty case must be a literal `[]`.
        foreach ($file in $script:CapturedFiles) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            $raw | Should -Not -BeNullOrEmpty -Because "$($file.Name) must not be empty; a zero-row capture is written as []"
            { $raw | ConvertFrom-Json -AsHashtable -Depth 40 } | Should -Not -Throw -Because "$($file.Name) must be valid JSON"
        }
    }

    It 'no captured-*.json contains a value that is not provably anonymous' {
        $allFindings = [System.Collections.Generic.List[string]]::new()

        foreach ($file in $script:CapturedFiles) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $graph = @($raw | ConvertFrom-Json -AsHashtable -Depth 40)
            if ($graph.Count -eq 0) { continue }

            foreach ($finding in (Test-ScoutFixtureAnonymity -InputObject $graph -Path $file.Name)) {
                $allFindings.Add($finding)
            }
        }

        $detail = ($allFindings | Select-Object -First 25) -join [Environment]::NewLine
        $allFindings.Count | Should -Be 0 -Because "committed fixtures must carry no tenant data. Findings:$([Environment]::NewLine)$detail"
    }

    It 'contains no IPv4 address outside the RFC 5737 documentation range' {
        # Belt-and-braces, independent of the walker above: a flat text scan cannot be fooled by
        # a node type the recursive walk fails to descend into.
        $pattern = [regex]'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
        foreach ($file in $script:CapturedFiles) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $bad  = @($pattern.Matches($text) | ForEach-Object { $_.Value } | Where-Object { -not $_.StartsWith('203.0.113.') })
            $bad.Count | Should -Be 0 -Because "$($file.Name) leaked address(es): $($bad -join ', ')"
        }
    }

    It 'contains no email address' {
        $pattern = [regex]'(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
        foreach ($file in $script:CapturedFiles) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $bad  = @($pattern.Matches($text) | ForEach-Object { $_.Value })
            $bad.Count | Should -Be 0 -Because "$($file.Name) leaked address(es): $($bad -join ', ')"
        }
    }

    It 'contains no long base64 blob, and no long free string at all' {
        # Base64-encoded startup commands were the sneakiest leak in the first capture: a
        # plaintext scanner sees noise, but a `base64 -d` reveals real client IDs, database
        # FQDNs and usernames.
        #
        # Checked per STRING LEAF rather than by scanning the raw file text: `/` is in the
        # base64 alphabet, so a raw-text scan matches a 40-character slice of any ARM resource
        # id and reports it as a blob. Walking leaves also lets the check be much stricter than
        # "is it base64" -- after anonymisation every leaf is a `res########` token, a GUID, an
        # ARM id or a short schema word, so ANY long free-standing string is a finding
        # regardless of its alphabet.
        $maxLeafLength = 40

        function Get-ScoutStringLeaf {
            param($Node)
            if ($null -eq $Node) { return }
            if ($Node -is [System.Collections.IDictionary]) {
                foreach ($k in $Node.Keys) {
                    if ($k -is [string]) { $k }
                    Get-ScoutStringLeaf -Node $Node[$k]
                }
                return
            }
            if ($Node -is [string]) { $Node; return }
            if ($Node -is [System.Collections.IEnumerable]) {
                foreach ($item in $Node) { Get-ScoutStringLeaf -Node $item }
            }
        }

        foreach ($file in $script:CapturedFiles) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $graph = @($raw | ConvertFrom-Json -AsHashtable -Depth 40)

            $bad = @(Get-ScoutStringLeaf -Node $graph |
                Where-Object { $_.Length -ge $maxLeafLength } |
                Where-Object { -not ($_.StartsWith('/subscriptions/') -or $_.StartsWith('/providers/')) } |
                # Allow-listed platform vocabulary can legitimately be long -- the resource type
                # 'microsoft.resources/subscriptions/resourcegroups' is 47 characters. It is
                # still constrained to the narrow schema pattern (no whitespace, no punctuation
                # beyond . _ - /), so it cannot smuggle free text through this exemption.
                Where-Object { -not $script:SchemaValuePattern.IsMatch($_) })

            $bad.Count | Should -Be 0 -Because "$($file.Name) has over-long string leaf/leaves: $(($bad | Select-Object -First 3) -join ' | ')"
        }
    }
}

Describe 'The fixture anonymiser is default-deny (AB#5667)' {

    BeforeAll {
        $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
        $script:ScriptPath = Join-Path $script:RepoRoot 'scripts' 'Export-ScoutFixture.ps1'

        $ast    = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $wanted = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                 $node.Left.Extent.Text -like '$script:*')
            }, $false)
        . ([ScriptBlock]::Create((($wanted | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine)))
    }

    # These are the exact shapes the first capture leaked. Each one is a regression test for a
    # value that a pattern-matching (allow-by-default) anonymiser passed straight through.
    It 'tokenises <Name>' -ForEach @(
        @{ Name = 'a free-text tag value';       Key = 'BusinessUnit'; Value = 'Hybrid Cloud Solutions' }
        @{ Name = 'a Key Vault secret name';     Key = 'keyVaultUrl';  Value = 'https://kv-real-01.vault.azure.net/secrets/github-app-private-key' }
        @{ Name = 'a container image digest';    Key = 'image';        Value = 'realregistry.azurecr.io/realproduct/api@sha256:48ac84adf36a6d4d95c2600512a9119907109af684a75f825aa19cda3dd3dbe1' }
        @{ Name = 'a base64 startup command';    Key = 'command';      Value = 'echo Q0lEPTg3ODczNWI1LWIwMGQtNDFmNS04MDU3LWYyNmI0MmRjMWFhNTsK | base64 -d | sh' }
        @{ Name = 'an App Insights conn string'; Key = 'ConnectionString'; Value = 'InstrumentationKey=f883d49f-822c-0b8f-1b5d-8500813aea5e;IngestionEndpoint=https://real.example.com/' }
        @{ Name = 'a URL with a real path';      Key = 'eventStreamEndpoint'; Value = 'https://realhost.azurecontainerapps.io/subscriptions/x/resourceGroups/rg-real-01/containerApps/ca-real-01/eventstream' }
        @{ Name = 'a domain verification id';    Key = 'customDomainVerificationId'; Value = 'BCC771B05CBAAAA58D77940588A284468792640642B37F71DCCF35E877A24EDA' }
        @{ Name = 'a nested type value';         Key = 'type';         Value = 'github-runner' }
    ) {
        # -TopLevel deliberately NOT set: everything here lives inside a `properties` bag, and a
        # nested value gets no allow-list exemption at all.
        $result = ConvertTo-ScoutAnonymizedScalar -Value $Value -KeyName $Key
        $result | Should -Not -Be $Value
        $result | Should -Match '^res[0-9a-f]{8}$'
    }

    It 'keeps a top-level resource type, because every collector filters on it' {
        ConvertTo-ScoutAnonymizedScalar -Value 'microsoft.compute/virtualmachines' -KeyName 'type' -TopLevel |
            Should -Be 'microsoft.compute/virtualmachines'
    }

    It 'keeps a top-level location and kind' {
        ConvertTo-ScoutAnonymizedScalar -Value 'eastus2'  -KeyName 'location' -TopLevel | Should -Be 'eastus2'
        ConvertTo-ScoutAnonymizedScalar -Value 'StorageV2' -KeyName 'kind'    -TopLevel | Should -Be 'StorageV2'
    }

    It 'preserves ARM id segment COUNT, because ~30 collectors index a split id by fixed position' {
        $id  = '/subscriptions/be069ae1-fc96-4a07-9f8e-5994d83a137d/resourceGroups/rg-real-01/providers/Microsoft.Compute/virtualMachines/vm-real-01'
        $out = ConvertTo-ScoutAnonymizedScalar -Value $id -KeyName 'id' -TopLevel

        ($out -split '/').Count | Should -Be ($id -split '/').Count
        $out | Should -Not -Match 'rg-real-01'
        $out | Should -Not -Match 'vm-real-01'
        $out | Should -Not -Match 'be069ae1'
        # Schema survives so collectors can still route on it.
        $out | Should -Match '/providers/Microsoft.Compute/virtualMachines/'
        # The subscription slot still has to parse as a GUID.
        ($out -split '/')[2] | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    }

    It 'anonymises a dictionary KEY that is itself an ARM resource id' {
        # identity.userAssignedIdentities is keyed by resource id. This survived two rounds of
        # anonymiser fixes because both only ever looked at values.
        $graph = [ordered]@{
            identity = [ordered]@{
                userAssignedIdentities = [ordered]@{
                    '/subscriptions/be069ae1-fc96-4a07-9f8e-5994d83a137d/resourcegroups/rg-real-01/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-real-01' = [ordered]@{ principalId = '23e7be03-a45f-452b-bb2f-e7edd12194d7' }
                }
            }
        }

        $out  = ConvertTo-ScoutAnonymizedGraph -InputObject $graph -KeyName ''
        $text = $out | ConvertTo-Json -Depth 20

        $text | Should -Not -Match 'be069ae1'
        $text | Should -Not -Match 'rg-real-01'
        $text | Should -Not -Match 'id-real-01'
    }

    It 'anonymises tag KEYS as well as tag values' {
        $graph = [ordered]@{ tags = [ordered]@{ 'BusinessUnit' = 'Real Company Ltd' } }
        $text  = (ConvertTo-ScoutAnonymizedGraph -InputObject $graph -KeyName '') | ConvertTo-Json -Depth 10

        $text | Should -Not -Match 'BusinessUnit'
        $text | Should -Not -Match 'Real Company'
    }

    It 'is deterministic, so cross-references between rows survive' {
        $a = ConvertTo-ScoutAnonymizedScalar -Value 'vm-real-01' -KeyName 'name'
        $b = ConvertTo-ScoutAnonymizedScalar -Value 'vm-real-01' -KeyName 'name'
        $a | Should -Be $b
    }

    It 'preserves structure: nesting, array length and non-string types are untouched' {
        $graph = [ordered]@{
            properties = [ordered]@{
                dataDisks  = @()
                diskSizeGB = 127
                enabled    = $true
                nested     = [ordered]@{ list = @('a', 'b', 'c') }
                absent     = $null
            }
        }
        $out = ConvertTo-ScoutAnonymizedGraph -InputObject $graph -KeyName ''

        @($out.properties.dataDisks).Count   | Should -Be 0
        $out.properties.diskSizeGB           | Should -Be 127
        $out.properties.enabled              | Should -BeTrue
        @($out.properties.nested.list).Count | Should -Be 3
        $out.properties.absent               | Should -BeNullOrEmpty
    }

    It 'flags a leak that the anonymiser did not produce' {
        # Proves the verifier has teeth: hand it something obviously real and it must object.
        # Without this, "zero findings" could equally mean "the walker never descended".
        $dirty    = @([ordered]@{ properties = [ordered]@{ note = 'contact ops@realcompany.com about rg-real-01' } })
        $findings = Test-ScoutFixtureAnonymity -InputObject $dirty -Path 'test'
        $findings.Count | Should -BeGreaterThan 0
    }
}
