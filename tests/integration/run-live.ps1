#Requires -Version 7.0
<#
.SYNOPSIS
    Opt-in live harness for the complete policy lifecycle example.

.DESCRIPTION
    Runs the published example root's documented commands against the
    authorised subscription, asserts observable Azure state between stages,
    and guarantees cleanup with authoritative absence read-back. The harness
    owns orchestration and assertions only; it contains no framework wiring.

    Test and cleanup exit statuses are preserved and reported separately
    (R12): a failed assertion followed by successful cleanup is a failed run,
    and a cleanup failure also fails the run. See tests/integration/README.md
    for usage, polling defaults and the cleanup-only resume command.
#>

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    # Example root to execute, relative to the repository root.
    [string]$ExampleRoot = 'examples/complete-policy-lifecycle',

    # Variable file handed to every Terraform command. Relative paths resolve
    # against the example root.
    [string]$VarFile = 'environments/uat/uat.tfvars',

    # Deterministic run identifier for artefacts and correlation with the
    # RUNID used in the variable file.
    [string]$RunId,

    # Explicit local approval tuple; required for live, preflight and cleanup.
    [string]$ApprovedContextPath,

    # Preflight and inventory capture only; no applies, no cleanup.
    [switch]$SkipApply,

    # Resume cleanup for a recorded run, then verify absence by read-back.
    [switch]$CleanupOnly,

    # Deterministic self-test of the status logic; touches no Azure and no
    # Terraform state.
    [switch]$StatusPathDemo,

    # Deterministic contract/recovery fixture checks. Never calls az or
    # Terraform and does not read credentials or state.
    [switch]$HarnessFixtureDemo,

    # Real read-only Terraform CLI probe for paths with spaces. Uses an isolated
    # local fixture root and never calls Azure or creates managed resources.
    [switch]$TerraformArgumentProbe,

    # Explicit live recovery exercise. Creates only the target and policy
    # content stages, records an intentional assertion failure, deletes exact
    # policy IDs, then pauses before destroy so CleanupOnly must resume.
    [switch]$RecoveryProbe,

    # Override the run status file location used for cleanup-only resume.
    [string]$StatusPath,

    # Expected policy-written tag on the storage account target.
    [string]$ExpectedTagName = 'CostCentre',
    [string]$ExpectedTagValue = 'zctfp-uat',
    [string]$ExpectedOwnerTagValue = 'terraform',

    # Renewal expiry for the renewal stage. Computed once per run when
    # omitted, then persisted in the run status so repeated plans converge.
    [string]$RenewalExpiry,

    # Root for run directories, logs, the mutation lock and recovery files. It
    # defaults outside the working tree so artefacts never enter the package.
    [string]$ArtifactRoot = (Join-Path ([System.IO.Path]::GetTempPath()) 'terraform-azurerm-policy-framework-integration')
)

Set-StrictMode -Version Latest

# Functions live in run-live.functions.ps1 and share this script scope.
. (Join-Path $PSScriptRoot 'run-live.functions.ps1')

$script:testFailed = $false
$script:cleanupFailed = $false
$script:cleanupPaused = $false
$script:mutationStarted = $false

# Bounded polling defaults. Exceeding a bound fails the assertion rather than
# hanging the run; the intervals, retry limits and deadlines are documented in
# tests/integration/README.md.
$script:Polling = @{
    RoleGrantPropagation = @{ IntervalSeconds = 15; RetryLimit = 20; DeadlineSeconds = 300 }
    PolicyState          = @{ IntervalSeconds = 30; RetryLimit = 30; DeadlineSeconds = 900 }
    Remediation          = @{ IntervalSeconds = 30; RetryLimit = 20; DeadlineSeconds = 600 }
    TagReadBack          = @{ IntervalSeconds = 30; RetryLimit = 10; DeadlineSeconds = 300 }
    Absence              = @{ IntervalSeconds = 15; RetryLimit = 20; DeadlineSeconds = 300 }
}

# Public example and composite output names accepted by the capture boundary.
$script:OutputCandidates = [ordered]@{
    lifecycle_resource_ids = @('lifecycle_resource_ids')
    assignment_review     = @('resolved_assignment_review', 'resolved_assignments')
    assignment_id         = @('resolved_assignment_id', 'exemption_assignment_id')
    definition_ids        = @('policy_definition_ids', 'definition_ids')
    set_definition_id     = @('set_definition_id')
}

# Subscription-scoped classes whose absence cannot be inferred from the
# resource group deletion, so the harness fails closed when they were never
# captured from the example outputs.
$script:SubscriptionScopedClasses = @('definition_ids', 'set_definition_id')

$script:repoRoot = (Resolve-Path -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
$script:logPath = $null
$script:subscriptionId = $null
$script:tenantId = $null
$script:offlineContext = [bool]($HarnessFixtureDemo -or $StatusPathDemo -or $TerraformArgumentProbe)
$script:approvedContextFile = $null
$script:approvedContextHash = $null
# Synthetic defaults are used only by the offline fixture modes.
$script:approvedSubscriptionId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$script:approvedTenantId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
$script:approvedCloud = 'AzureCloud'
$script:approvedUserName = 'operator@example.invalid'
$script:approvedUserType = 'user'
$script:mutationLockStream = $null
$script:mutationLockPath = Join-Path $ArtifactRoot '.live-mutation.lock'

if ($TerraformArgumentProbe) {
    $probeRoot = Join-Path $ArtifactRoot ('terraform argument probe ' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
    if (Test-Path -LiteralPath $probeRoot) { throw "Terraform argument probe path already exists: $probeRoot" }
    New-Item -ItemType Directory -Path (Join-Path $probeRoot 'plans') -Force | Out-Null
    $script:logPath = Join-Path $probeRoot 'argument-probe.log'
    $mainConfiguration = @'
terraform {
  required_version = ">= 1.12.0"
}

variable "probe_value" {
  type = string
}

variable "evaluation_time" {
  type = string
}

output "probe_value" {
  value = var.probe_value
}
'@
    [System.IO.File]::WriteAllText((Join-Path $probeRoot 'main.tf'), $mainConfiguration, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $probeRoot 'probe values.tfvars'), 'probe_value = "argument probe passed"', [System.Text.UTF8Encoding]::new($false))
    $probeStatus = @{
        profile = 'complete'
        exampleRoot = $probeRoot
        varFile = Join-Path $probeRoot 'probe values.tfvars'
        evaluationTime = '2026-10-02T00:00:00Z'
        terraformVars = @{ create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '' }
    }
    $init = Invoke-Terraform -TerraformArguments (Get-BackendDisabledInitArguments -ExampleRoot $probeRoot)
    if ($init.ExitCode -ne 0) { throw 'Terraform argument probe init failed' }
    $validate = Invoke-Terraform -TerraformArguments @(( '-chdir=' + $probeRoot ), 'validate', '-no-color')
    if ($validate.ExitCode -ne 0) { throw 'Terraform argument probe validate failed' }
    $output = Invoke-Terraform -TerraformArguments (Get-TerraformOutputArguments -Status $probeStatus)
    if ($output.Output -match 'chdir .* output -json') { throw 'Terraform argument probe output arguments were combined with the chdir value' }
    $planPath = Join-Path $probeRoot 'plans/probe plan.tfplan'
    $planArgs = Get-TerraformReviewedPlanArguments -Status $probeStatus -PlanPath $planPath
    $plan = Invoke-Terraform -TerraformArguments $planArgs
    if ($plan.ExitCode -notin @(0, 2) -or $plan.Output -match 'Too many command line arguments|Failed to read variables file|Error handling -chdir option') { throw 'Terraform argument probe plan did not accept its spaced chdir, variable-file and output paths' }
    $version = Invoke-Terraform -TerraformArguments @('version', '-json')
    if ($version.ExitCode -ne 0) { throw 'Terraform argument probe version invocation failed' }
    Write-Host 'TerraformArgumentProbe: real read-only CLI accepted spaced chdir, variable-file and saved-plan paths; no Azure or managed-resource commands were run'
    exit 0
}

if ($HarnessFixtureDemo) {
    # Exercise the harness contracts with checked-in responses only. Command
    # adapters are replaced in this isolated branch; only checked-in state
    # fixtures are read, and live CLI commands and credentials are unused.
    function Assert-Fixture {
        param([bool]$Condition, [string]$Message)
        if (-not $Condition) { throw "HarnessFixtureDemo failed: $Message" }
        Write-Host "  [ok] $Message"
    }

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $script:fixtureOutputs = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-output-complete.json') -Raw | ConvertFrom-Json
    $script:fixtureMinimalOutputs = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-output-minimal.json') -Raw | ConvertFrom-Json
    $script:fixtureCompleteExampleOutputs = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-output-complete-example.json') -Raw | ConvertFrom-Json
    $script:fixtureCompleteState = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-state-complete.json') -Raw | ConvertFrom-Json
    $script:fixtureMinimalState = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-state-minimal.json') -Raw | ConvertFrom-Json
    $script:fixtureAssignment = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-policy-assignment-userassigned.json') -Raw | ConvertFrom-Json
    $script:fixtureMinimalAssignment = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-policy-assignment-minimal.json') -Raw | ConvertFrom-Json
    $script:fixtureGrants = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-role-assignment-list.json') -Raw | ConvertFrom-Json
    $script:fixturePolicyState = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-policy-state-storage-noncompliant.json') -Raw | ConvertFrom-Json
    $script:fixtureRemediation = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-remediation-list-succeeded.json') -Raw | ConvertFrom-Json
    $script:fixtureExemptions = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-policy-exemption-list.json') -Raw | ConvertFrom-Json
    $script:fixtureTaggedStorage = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-storage-account-tagged.json') -Raw | ConvertFrom-Json
    $script:fixtureUntaggedStorage = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-storage-account-untagged.json') -Raw | ConvertFrom-Json
    $script:fixtureInventoryBaseline = Get-Content -LiteralPath (Join-Path $fixtureRoot 'azure-inventory-preservation.json') -Raw | ConvertFrom-Json
    $script:fixtureAzResponses = @{}
    $script:fixtureTerraformCalls = @()
    $script:fixtureApplyExitCode = 0
    $script:fixtureWorkspaceShow = 'uat-fixture01'
    $script:fixtureWorkspaceList = @('default', 'uat-fixture01')
    $script:fixtureStateList = @()
    $originalInvokeAz = (Get-Command Invoke-Az).ScriptBlock
    Set-Item -Path Function:script:Invoke-Az -Value { param([string[]]$Arguments) return @{ ExitCode = 0; StdOut = '[]'; StdErr = '' } }
        $emptyInventoryResult = Invoke-AzJson @('fixture', 'empty-inventory')
        Set-Item -Path Function:script:Invoke-Az -Value $originalInvokeAz
        Assert-Fixture ($emptyInventoryResult.ExitCode -eq 0 -and $emptyInventoryResult.Data -is [array] -and $emptyInventoryResult.Data.Count -eq 0) 'empty Azure inventory JSON remains a verified empty collection, not an inconclusive null'
        $initArgs = Get-BackendDisabledInitArguments -ExampleRoot 'examples/minimal-audit-assignment'
        Assert-Fixture ($initArgs.Count -eq 5 -and $initArgs[1] -ceq 'init' -and $initArgs[2] -ceq '-backend=false' -and $initArgs[3] -ceq '-input=false' -and $initArgs[4] -ceq '-no-color' -and ($initArgs -notcontains '-var') -and @($initArgs | Where-Object { $_ -like '-var-file=*' }).Count -eq 0) 'Terraform init receives five separate backend flags, with no variable or stage arguments'
        $argumentStatus = @{
            profile = 'minimal'
            exampleRoot = 'C:\workspace path with spaces\minimal example'
            varFile = 'C:\workspace path with spaces\inputs\run input.tfvars'
            assignmentScopeId = '/subscriptions/00000000-0000-0000-0000-000000000000'
            terraformVars = @{ assignment_key = 'audit-sub'; assignment_owner = 'platform-governance'; create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '2027-01-31T00:00:00Z' }
        }
        $argumentPlanPath = 'C:\workspace path with spaces\artifacts\owner update.tfplan'
        $baseArguments = Get-TerraformBaseArguments -Status $argumentStatus
        $argumentTfRoot = '-chdir=' + $argumentStatus['exampleRoot']
        $applyArguments = @($argumentTfRoot, 'apply', '-auto-approve') + $baseArguments
        $outputArguments = Get-TerraformOutputArguments -Status $argumentStatus
        $reviewedPlanArguments = Get-TerraformReviewedPlanArguments -Status $argumentStatus -PlanPath $argumentPlanPath -AdditionalPlanArguments @('-replace=module.example.resource.this["audit"]')
        $convergenceArguments = Get-TerraformConvergenceArguments -Status $argumentStatus -ExtraVars @()
        $destroyArguments = Get-TerraformDestroyArguments -Status $argumentStatus -FinalVars (Get-StageVarArguments -Status $argumentStatus)
        $expectedVarArgument = '-var-file=' + $argumentStatus['varFile']
        $expectedOutArgument = '-out=' + $argumentPlanPath
        $completeArgumentStatus = @{
            profile = 'complete'
            exampleRoot = $argumentStatus['exampleRoot']
            varFile = $argumentStatus['varFile']
            evaluationTime = '2026-10-02T00:00:00Z'
            terraformVars = @{ assignment_key = 'audit-sub'; assignment_owner = 'platform-governance'; create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '2027-01-31T00:00:00Z' }
        }
        $completeBaseArguments = Get-TerraformBaseArguments -Status $completeArgumentStatus
        $fixturePlanActions = Get-ChangedResourceActions -Plan ([pscustomobject]@{ resource_changes = @(
            [pscustomobject]@{ address = 'unchanged'; change = [pscustomobject]@{ actions = @('no-op') } },
            [pscustomobject]@{ address = 'storage'; change = [pscustomobject]@{ actions = @('update') } }
        ) })
        Assert-Fixture ($fixturePlanActions.Count -eq 1 -and $fixturePlanActions['storage'] -ceq 'update') 'reviewed provider plans exclude no-op entries from changing resource actions'
        $loadedTimestampStatus = ConvertTo-Hashtable -Object ('{"profile":"complete","evaluationTime":"2026-10-02T00:00:00Z","terraformVars":{"create_exemption":"false","exemption_expiry":"2027-01-31T00:00:00Z"}}' | ConvertFrom-Json)
        $loadedTimestampArguments = Get-StageVarArguments -Status $loadedTimestampStatus
        Assert-Fixture (@($loadedTimestampArguments | Where-Object { $_ -ceq 'evaluation_time=2026-10-02T00:00:00Z' }).Count -eq 1 -and @($loadedTimestampArguments | Where-Object { $_ -ceq 'exemption_expiry=2027-01-31T00:00:00Z' }).Count -eq 1) 'JSON-loaded timestamps retain invariant RFC3339 Terraform arguments'
        Assert-Fixture ($baseArguments.Count -eq 9 -and $baseArguments[2] -ceq $expectedVarArgument -and @($baseArguments | Where-Object { $_ -ceq $expectedVarArgument }).Count -eq 1 -and @($baseArguments | Where-Object { $_ -match 'exemption_expiry' }).Count -eq 0) 'minimal apply arguments preserve the spaced variable file and omit complete-only exemption variables'
        Assert-Fixture ($completeBaseArguments.Count -eq 7 -and @($completeBaseArguments | Where-Object { $_ -ceq $expectedVarArgument }).Count -eq 1 -and @($completeBaseArguments | Where-Object { $_ -ceq '-var' }).Count -eq 2 -and @($completeBaseArguments | Where-Object { $_ -match '^exemption_expiry=' }).Count -eq 1) 'complete apply arguments include declared evaluation and exemption expiry variables'
        Assert-Fixture ($applyArguments.Count -eq 12 -and $applyArguments[0] -ceq ('-chdir=' + $argumentStatus['exampleRoot']) -and $applyArguments[5] -ceq $expectedVarArgument) 'actual apply argument builder keeps the example path and variable file as single arguments'
        Assert-Fixture ($outputArguments.Count -eq 3 -and $outputArguments[0] -ceq ('-chdir=' + $argumentStatus['exampleRoot']) -and $outputArguments[1] -ceq 'output' -and $outputArguments[2] -ceq '-json') 'actual output argument builder keeps chdir separate from output subcommand flags'
        Assert-Fixture ($reviewedPlanArguments.Count -eq 13 -and $reviewedPlanArguments[0] -ceq ('-chdir=' + $argumentStatus['exampleRoot']) -and $reviewedPlanArguments[4] -ceq $expectedOutArgument -and $reviewedPlanArguments[6] -ceq $expectedVarArgument -and $reviewedPlanArguments[5] -ceq '-replace=module.example.resource.this["audit"]') 'reviewed plan builder preserves chdir, replace, plan output and variable-file arguments'
        Assert-Fixture ($convergenceArguments.Count -eq 12 -and $convergenceArguments[0] -ceq ('-chdir=' + $argumentStatus['exampleRoot']) -and $convergenceArguments[5] -ceq $expectedVarArgument) 'convergence plan builder preserves one chdir and one variable-file argument'
        Assert-Fixture ($destroyArguments.Count -eq 12 -and $destroyArguments[0] -ceq ('-chdir=' + $argumentStatus['exampleRoot']) -and $destroyArguments[5] -ceq $expectedVarArgument) 'destroy builder preserves one chdir and one variable-file argument'
        $originalInvokeTerraform = (Get-Command Invoke-Terraform).ScriptBlock
        $script:capturedTerraformArguments = @()
        Set-Item -Path Function:script:Invoke-Terraform -Value {
            param([string[]]$TerraformArguments, [switch]$FullLog)
            $script:capturedTerraformArguments += ,@($TerraformArguments)
            return @{ ExitCode = 0; Output = @('{}') }
        }
        foreach ($argumentSet in @($applyArguments, $outputArguments, $reviewedPlanArguments, $convergenceArguments, $destroyArguments)) {
            $null = Invoke-Terraform -TerraformArguments $argumentSet
        }
        Set-Item -Path Function:script:Invoke-Terraform -Value $originalInvokeTerraform
        $capturedMatches = $script:capturedTerraformArguments.Count -eq 5
        if ($capturedMatches) {
            $expectedArgumentSets = @($applyArguments, $outputArguments, $reviewedPlanArguments, $convergenceArguments, $destroyArguments)
            for ($argumentIndex = 0; $argumentIndex -lt $expectedArgumentSets.Count; $argumentIndex++) {
                if ((ConvertTo-Json -InputObject @($script:capturedTerraformArguments[$argumentIndex]) -Compress) -cne (ConvertTo-Json -InputObject @($expectedArgumentSets[$argumentIndex]) -Compress)) { $capturedMatches = $false }
            }
        }
        Assert-Fixture $capturedMatches 'Invoke-Terraform receives the exact captured arrays from all live apply/output/plan/convergence/destroy builders'
    Set-Item -Path Function:script:Invoke-Terraform -Value {
        param([string[]]$TerraformArguments, [switch]$FullLog)
        $argumentText = $TerraformArguments -join ' '
        $script:fixtureTerraformCalls += ,@($TerraformArguments)
        if ($argumentText -match 'workspace show') { return @{ ExitCode = 0; Output = @($script:fixtureWorkspaceShow) } }
        if ($argumentText -match 'workspace list') { return @{ ExitCode = 0; Output = @($script:fixtureWorkspaceList) } }
        if ($argumentText -match 'state list') { return @{ ExitCode = 0; Output = @($script:fixtureStateList) } }
        if ($argumentText -match 'show -json') { return @{ ExitCode = 0; Output = @((ConvertTo-Json -InputObject $script:fixtureStateJson -Depth 20)) } }
        if ($argumentText -match '(^|\s)apply(\s|$)') { return @{ ExitCode = $script:fixtureApplyExitCode; Output = @('fixture apply result') } }
        return @{ ExitCode = 0; Output = @((ConvertTo-Json -InputObject $script:fixtureOutputs -Depth 20)) }
    }
    Set-Item -Path Function:script:Invoke-AzJson -Value {
        param([string[]]$Arguments)
        $key = $Arguments -join ' '
        $script:fixtureAzureCalls += ,@($Arguments)
        if ($script:fixtureAzResponses.ContainsKey($key)) { return $script:fixtureAzResponses[$key] }
        if ($key -eq 'account show') { return @{ ExitCode = 0; Data = $script:fixtureAccount; Text = '' } }
        if ($key -like 'policy state trigger-scan*') { return @{ ExitCode = 0; Data = $null; Text = '' } }
        if ($key -like 'policy state list*') { return @{ ExitCode = 0; Data = $script:fixturePolicyState; Text = '' } }
        if ($key -like 'policy assignment show*') {
            $completeName = ($script:fixtureAssignment.id -split '/')[-1]
            $completeScope = $script:fixtureAssignment.scope
            $minimalName = $script:fixtureMinimalAssignment.name
            $minimalScope = $script:fixtureMinimalAssignment.scope
            if ($key -ceq "policy assignment show --name $completeName --scope $completeScope --subscription $($script:approvedSubscriptionId)") { return @{ ExitCode = 0; Data = $script:fixtureAssignment; Text = '' } }
            if ($key -ceq "policy assignment show --name $minimalName --scope $minimalScope --subscription $($script:approvedSubscriptionId)") { return @{ ExitCode = 0; Data = $script:fixtureMinimalAssignment; Text = '' } }
            throw "unexpected fixture assignment read: $key"
        }
        if ($key -like 'role assignment list*') { return @{ ExitCode = 0; Data = $script:fixtureGrants; Text = '' } }
        if ($key -like 'policy remediation list*') { return @{ ExitCode = 0; Data = $script:fixtureRemediation; Text = '' } }
        if ($key -like 'policy exemption list*') { return @{ ExitCode = 0; Data = $script:fixtureExemptions; Text = '' } }
        if ($key -like 'storage account show*') {
            if ($script:fixtureStorageState -eq 'tagged') { return @{ ExitCode = 0; Data = $script:fixtureTaggedStorage; Text = '' } }
            return @{ ExitCode = 0; Data = $script:fixtureUntaggedStorage; Text = '' }
        }
        throw "unexpected fixture Azure read: $key"
    }

    try {
        $runDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('policy-harness-fixture-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $runDirectory | Out-Null

        # Exercise the real Terraform adapter with a synthetic state document.
        # Its raw JSON must remain available to the ID parser and absent from
        # both Write-Host output and the run log.
        $fixtureInvokeTerraform = (Get-Command Invoke-Terraform).ScriptBlock
        $priorTerraformFunction = Get-Item -Path Function:script:terraform -ErrorAction SilentlyContinue
        $priorTerraformLogPath = $script:logPath
        $priorTerraformSubscriptionId = $script:subscriptionId
        $priorTerraformTestFailed = $script:testFailed
        $sensitiveStateSentinel = 'fixture-sensitive-state-sentinel'
        $sensitiveStateId = [string]$script:fixtureMinimalAssignment.id
        $script:fixtureTerraformShowJson = ConvertTo-Json -InputObject @{
            values = @{
                root_module = @{
                    resources = @(
                        @{
                            mode = 'managed'
                            type = 'azurerm_subscription_policy_assignment'
                            address = 'module.framework.module.assignments.azurerm_subscription_policy_assignment.this["audit-sub"]'
                            values = @{ id = $sensitiveStateId; synthetic_sensitive_value = $sensitiveStateSentinel }
                        }
                    )
                }
            }
        } -Depth 10 -Compress
        $script:fixtureSensitiveStateStatus = @{
            profile = 'minimal'
            exampleRoot = 'synthetic-example-root'
            subscriptionId = $script:approvedSubscriptionId
            createdResourceIds = @{ assignments = @() }
        }
        $script:fixtureSensitiveStateCaptureSucceeded = $false
        $script:subscriptionId = $script:approvedSubscriptionId
        $script:testFailed = $false
        $script:logPath = Join-Path $runDirectory 'terraform-json-redaction.log'
        try {
            Set-Item -Path Function:script:terraform -Value {
                $global:LASTEXITCODE = 0
                Write-Output $script:fixtureTerraformShowJson
            }
            Set-Item -Path Function:script:Invoke-Terraform -Value $originalInvokeTerraform
            $terraformConsoleRecords = @(& {
                $script:fixtureSensitiveStateCaptureSucceeded = Update-CapturedStateIds -Status $script:fixtureSensitiveStateStatus
            } 6>&1)
            $terraformConsoleText = ($terraformConsoleRecords | ForEach-Object {
                if ($_ -is [System.Management.Automation.InformationRecord]) { [string]$_.MessageData }
                else { [string]$_ }
            }) -join "`n"
            $terraformLogText = Get-Content -LiteralPath $script:logPath -Raw
            $terraformStateIdCaptured = @($script:fixtureSensitiveStateStatus.createdResourceIds.assignments | Where-Object { $_ -ceq $sensitiveStateId }).Count -eq 1
            Assert-Fixture (
                $script:fixtureSensitiveStateCaptureSucceeded -and $terraformStateIdCaptured -and
                $terraformConsoleText.Contains('[Terraform JSON output suppressed; it may contain sensitive values]') -and
                -not $terraformConsoleText.Contains($sensitiveStateSentinel) -and
                -not $terraformLogText.Contains($sensitiveStateSentinel)
            ) 'Terraform state JSON remains parseable for ID capture while sensitive payloads stay out of console and run logs'
        }
        finally {
            Set-Item -Path Function:script:Invoke-Terraform -Value $fixtureInvokeTerraform
            if ($priorTerraformFunction) { Set-Item -Path Function:script:terraform -Value $priorTerraformFunction.ScriptBlock }
            else { Remove-Item -Path Function:script:terraform -ErrorAction SilentlyContinue }
            $script:logPath = $priorTerraformLogPath
            $script:subscriptionId = $priorTerraformSubscriptionId
            $script:testFailed = $priorTerraformTestFailed
        }

        $contextFixturePath = Join-Path $runDirectory 'approved-context.json'
        $contextFixture = @{ subscriptionId = $script:approvedSubscriptionId; tenantId = $script:approvedTenantId; cloud = 'AzureCloud'; userName = $script:approvedUserName; userType = 'user' }
        $contextJson = ConvertTo-Json $contextFixture -Compress
        [System.IO.File]::WriteAllText($contextFixturePath, $contextJson)
        $validContext = Read-ApprovedContext -Path $contextFixturePath
        Assert-Fixture ($validContext.subscriptionId -ceq $script:approvedSubscriptionId -and $validContext.userName -ceq $script:approvedUserName) 'explicit synthetic approved context parses without credentials'
        $missingContextRejected = $false
        try { Read-ApprovedContext -Path '' | Out-Null } catch { $missingContextRejected = $true }
        Assert-Fixture $missingContextRejected 'missing explicit approved context is rejected'
        $invalidContexts = @(
            'null', '[]', '"scalar"', '{}', '{malformed',
            $contextJson.Replace('"AzureCloud"', 'null'),
            $contextJson.Replace('"AzureCloud"', '42'),
            $contextJson.Replace('"AzureCloud"', '"AzureUSGovernment"'),
            $contextJson.Replace('"user"', '"servicePrincipal"'),
            $contextJson.Replace($script:approvedSubscriptionId, 'not-a-guid'),
            $contextJson.Replace($script:approvedTenantId, '00000000-0000-0000-0000-000000000000'),
            $contextJson.Replace($script:approvedUserName, ' '),
            $contextJson.Replace($script:approvedUserName, 'not-a-upn'),
            $contextJson.Replace('}', ',"extra":"unexpected"}'),
            $contextJson.Replace('}', ',"cloud":"AzureCloud"}')
        )
        foreach ($invalidContext in $invalidContexts) {
            [System.IO.File]::WriteAllText($contextFixturePath, $invalidContext)
            $invalidRejected = $false
            try { Read-ApprovedContext -Path $contextFixturePath | Out-Null } catch { $invalidRejected = $true }
            Assert-Fixture $invalidRejected 'malformed approved context is rejected before any Azure command'
        }
        [System.IO.File]::WriteAllText($contextFixturePath, $contextJson)
        $script:approvedContextFile = $contextFixturePath
        $script:approvedContextHash = (Get-FileHash -LiteralPath $contextFixturePath -Algorithm SHA256).Hash
        $contextStatus = @{ runDirectory = $runDirectory; approvedContextPath = $contextFixturePath; approvedContextSha256 = $script:approvedContextHash }
        $script:offlineContext = $false
        try {
            Assert-RecordedApprovedContext -Status $contextStatus
            Assert-Fixture $true 'matching explicit and pinned contexts permit the recovery boundary'
            $outsideContextStatus = $contextStatus.Clone()
            $outsideContextStatus.approvedContextPath = Join-Path $runDirectory 'foreign.json'
            $outsideRejected = $false
            try { Assert-RecordedApprovedContext -Status $outsideContextStatus } catch { $outsideRejected = $true }
            Assert-Fixture $outsideRejected 'cleanup rejects a context path outside its exact protected snapshot'
            $missingContextStatus = $contextStatus.Clone()
            $missingContextStatus.Remove('approvedContextSha256')
            $missingHashRejected = $false
            try { Assert-RecordedApprovedContext -Status $missingContextStatus } catch { $missingHashRejected = $true }
            Assert-Fixture $missingHashRejected 'cleanup rejects missing context fingerprint'
            $suppliedContextFile = Join-Path $runDirectory 'supplied-context.json'
            $otherUserContext = $contextFixture.Clone()
            $otherUserContext.userName = 'different@example.invalid'
            [System.IO.File]::WriteAllText($suppliedContextFile, (ConvertTo-Json $otherUserContext -Compress))
            $script:approvedContextFile = $suppliedContextFile
            $script:approvedContextHash = (Get-FileHash -LiteralPath $suppliedContextFile -Algorithm SHA256).Hash
            $originalApprovedUser = $script:approvedUserName
            $script:approvedUserName = $otherUserContext.userName
            $wrongContextRejected = $false
            try { Assert-RecordedApprovedContext -Status $contextStatus } catch { $wrongContextRejected = $true }
            finally { $script:approvedUserName = $originalApprovedUser }
            Assert-Fixture $wrongContextRejected 'cleanup rejects a valid supplied context for a different approved user'
            $script:approvedContextFile = $contextFixturePath
            $script:approvedContextHash = $contextStatus.approvedContextSha256
            [System.IO.File]::AppendAllText($contextFixturePath, "`n")
            $changedContextRejected = $false
            try { Assert-RecordedApprovedContext -Status $contextStatus } catch { $changedContextRejected = $true }
            Assert-Fixture $changedContextRejected 'changed approved context bytes block mutation and cleanup'
            Remove-Item -LiteralPath $contextFixturePath
            $removedContextRejected = $false
            try { Assert-ApprovedContextPinned } catch { $removedContextRejected = $true }
            Assert-Fixture $removedContextRejected 'missing pinned approved context blocks mutation'
        }
        finally {
            $script:offlineContext = $true
            $script:approvedContextFile = $null
            $script:approvedContextHash = $null
        }
        $script:statusPath = Join-Path $runDirectory 'status.json'
        $script:fixtureAzureCalls = @()
        $script:fixtureAccount = [pscustomobject]@{
            id = $script:approvedSubscriptionId; tenantId = $script:approvedTenantId; environmentName = $script:approvedCloud
            user = [pscustomobject]@{ name = $script:approvedUserName; type = $script:approvedUserType }
        }
        Assert-ApprovedAzureContext
        Assert-Fixture $true 'approved Azure cloud, user, tenant and subscription pass the live context guard'
        $originalFixtureAccount = $script:fixtureAccount
        $script:fixtureAccount = [pscustomobject]@{ id = $script:approvedSubscriptionId; tenantId = $script:approvedTenantId; environmentName = $script:approvedCloud; user = [pscustomobject]@{ name = 'different@tenant.invalid'; type = 'user' } }
        $identityRejected = $false
        try { Assert-ApprovedAzureContext }
        catch { $identityRejected = $_.Exception.Message -like '*signed-in user*' }
        $script:fixtureAccount = [pscustomobject]@{ id = $script:approvedSubscriptionId; tenantId = $script:approvedTenantId; environmentName = 'AzureUSGovernment'; user = [pscustomobject]@{ name = $script:approvedUserName; type = 'user' } }
        $environmentRejected = $false
        try { Assert-ApprovedAzureContext }
        catch { $environmentRejected = $_.Exception.Message -like '*Azure cloud*' }
        $script:fixtureAccount = $originalFixtureAccount
        Assert-Fixture ($identityRejected -and $environmentRejected) 'unapproved Azure cloud and user identities fail closed'
        $previousArmSecret = [Environment]::GetEnvironmentVariable('ARM_CLIENT_SECRET')
        [Environment]::SetEnvironmentVariable('ARM_CLIENT_SECRET', 'fixture-secret-must-not-leak')
        $alternateAuthMessage = ''
        try { Assert-ApprovedAzureContext }
        catch { $alternateAuthMessage = $_.Exception.Message }
        [Environment]::SetEnvironmentVariable('ARM_CLIENT_SECRET', $previousArmSecret)
        Assert-Fixture ($alternateAuthMessage -like '*ARM_CLIENT_SECRET*' -and $alternateAuthMessage -notlike '*fixture-secret-must-not-leak*') 'alternate AzureRM credentials fail closed without exposing secret values'
        $fixtureVarFile = Join-Path $runDirectory 'run-input.tfvars'
        [System.IO.File]::WriteAllText($fixtureVarFile, '', [System.Text.UTF8Encoding]::new($false))
        $script:subscriptionId = $script:approvedSubscriptionId
        $script:tenantId = $script:approvedTenantId
        $script:fixtureAzureCalls = @()
        $originalFixtureLogPath = $script:logPath
        $redactionLogPath = Join-Path $runDirectory 'redaction.log'
        $script:logPath = $redactionLogPath
        Write-RunLog "fixture subscription ID $($script:subscriptionId)"
        $redactionLog = Get-Content -LiteralPath $redactionLogPath -Raw
        Assert-Fixture (-not $redactionLog.Contains($script:subscriptionId) -and $redactionLog.Contains('[redacted-subscription]')) 'run log redacts the subscription ID while retaining a useful marker'
        $script:logPath = $originalFixtureLogPath
        $script:fixtureOutputs = $script:fixtureMinimalOutputs
        $script:fixtureStateJson = $script:fixtureMinimalState
        $trackedStatusFixture = @{
            profile = 'minimal'; exampleRoot = Join-Path $script:repoRoot 'examples/minimal-audit-assignment'; varFile = $fixtureVarFile
            sourceFingerprint = Get-SourceFingerprint -Root $script:repoRoot; varFileSha256 = (Get-FileHash -LiteralPath $fixtureVarFile -Algorithm SHA256).Hash
            subscriptionId = $script:approvedSubscriptionId; tenantId = $script:approvedTenantId; assignmentScopeId = "/subscriptions/$($script:approvedSubscriptionId)"
            terraformVars = @{ assignment_key = 'audit-sub'; assignment_owner = 'platform-governance'; create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '' }
            createdResourceIds = @{}; appliedStages = @(); mutationStarted = $false
        }
        $trackedResult = @(Invoke-TrackedApply -Status $trackedStatusFixture -Stage 'fixture-minimal-apply' -TerraformArguments @('apply', '-auto-approve'))
        Assert-Fixture ($trackedResult.Count -eq 1 -and $trackedResult[0] -is [hashtable] -and $trackedResult[0].ExitCode -eq 0) 'tracked apply emits exactly one Terraform result hashtable after input/context guards'
        Assert-Fixture ($trackedStatusFixture['createdResourceIds']['assignments'].Count -eq 1 -and $trackedStatusFixture['resolvedAssignmentReview']['audit-sub']['assignment_id'] -eq $script:fixtureMinimalOutputs.resolved_assignment_review.value.'audit-sub'.assignment_id) 'minimal public outputs populate the assignment cleanup manifest and review map'

        $inputMismatchStatus = $trackedStatusFixture.Clone()
        $inputMismatchStatus['sourceFingerprint'] = '0' * 64
        $inputMismatchStatus['mutationStarted'] = $false
        $script:mutationStarted = $false
        $script:fixtureTerraformCalls = @()
        $sourceMismatchRejected = $false
        try { $null = Invoke-TrackedApply -Status $inputMismatchStatus -Stage 'fixture-source-mismatch' -TerraformArguments @('apply', '-auto-approve') }
        catch { $sourceMismatchRejected = $_.Exception.Message -like '*source or the protected variable file changed*' }
        Assert-Fixture ($sourceMismatchRejected -and -not $script:mutationStarted -and $script:fixtureTerraformCalls.Count -eq 0) 'changed source fingerprint refuses the next apply before Terraform or mutation state'

        $inputMismatchStatus = $trackedStatusFixture.Clone()
        $inputMismatchStatus['varFileSha256'] = '0' * 64
        $inputMismatchStatus['mutationStarted'] = $false
        $script:mutationStarted = $false
        $script:fixtureTerraformCalls = @()
        $varFileMismatchRejected = $false
        try { $null = Invoke-TrackedApply -Status $inputMismatchStatus -Stage 'fixture-varfile-mismatch' -TerraformArguments @('apply', '-auto-approve') }
        catch { $varFileMismatchRejected = $_.Exception.Message -like '*source or the protected variable file changed*' }
        Assert-Fixture ($varFileMismatchRejected -and -not $script:mutationStarted -and $script:fixtureTerraformCalls.Count -eq 0) 'changed protected variable fingerprint refuses the next apply before Terraform or mutation state'

        $hashGuardDirectory = Join-Path $runDirectory 'delete-hash-guard'
        New-Item -ItemType Directory -Path $hashGuardDirectory | Out-Null
        $hashGuardStatusPath = Join-Path $hashGuardDirectory 'run-status.json'
        $hashGuardLogPath = Join-Path $hashGuardDirectory 'run.log'
        $hashGuardVarFile = Join-Path $hashGuardDirectory 'run-input.tfvars'
        [System.IO.File]::WriteAllText($hashGuardVarFile, 'stable fixture input', [System.Text.UTF8Encoding]::new($false))
        $hashGuardSourceFingerprint = Get-SourceFingerprint -Root $script:repoRoot
        $hashGuardVarFileSha256 = (Get-FileHash -LiteralPath $hashGuardVarFile -Algorithm SHA256).Hash
        $hashGuardAssignmentId = "/subscriptions/$($script:approvedSubscriptionId)/providers/Microsoft.Authorization/policyAssignments/fixture-assignment"
        $hashGuardStatus = @{
            runId = 'hashguard01'; profile = 'minimal'; runDirectory = $hashGuardDirectory
            varFile = $hashGuardVarFile; sourceFingerprint = $hashGuardSourceFingerprint; varFileSha256 = $hashGuardVarFileSha256
            subscriptionId = $script:approvedSubscriptionId; createdResourceIds = @{ assignments = @($hashGuardAssignmentId) }
            appliedStages = @('minimal-apply'); activeStage = $null; deletedPolicyResourceIds = @()
        }
        $originalHashGuardStatusPath = $script:statusPath
        $originalHashGuardLogPath = $script:logPath
        $originalHashGuardCleanupFailed = $script:cleanupFailed
        $originalHashGuardDefaultState = (Get-Command Assert-DefaultStateUnchanged).ScriptBlock
        $originalHashGuardContext = (Get-Command Assert-ApprovedAzureContext).ScriptBlock
        $originalHashGuardPresence = (Get-Command Test-ResourceAbsentNow).ScriptBlock
        $originalHashGuardWait = (Get-Command Wait-Absence).ScriptBlock
        $originalHashGuardInvokeAz = (Get-Command Invoke-Az).ScriptBlock
        $script:statusPath = $hashGuardStatusPath
        $script:logPath = $hashGuardLogPath
        Set-Item -Path Function:script:Assert-DefaultStateUnchanged -Value { param([hashtable]$Status) return $true }
        Set-Item -Path Function:script:Assert-ApprovedAzureContext -Value { return $true }
        Set-Item -Path Function:script:Test-ResourceAbsentNow -Value { param([string]$ResourceId) return 'Present' }
        Set-Item -Path Function:script:Wait-Absence -Value { param([string]$Label, [string]$ProbeKind, [string]$Target, [hashtable]$Settings) return $true }
        $script:fixturePolicyDeleteCalls = @()
        Set-Item -Path Function:script:Invoke-Az -Value {
            param([string[]]$Arguments)
            $script:fixturePolicyDeleteCalls += ,@($Arguments)
            return @{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }

        try {
            $script:cleanupFailed = $false
            $staleSourceStatus = $hashGuardStatus.Clone()
            $staleSourceStatus['sourceFingerprint'] = '0' * 64
            $staleSourceRemoved = Remove-ExactPolicyResources -Status $staleSourceStatus
            Assert-Fixture (-not $staleSourceRemoved -and $script:cleanupFailed -and $script:fixturePolicyDeleteCalls.Count -eq 0) 'changed source fingerprint blocks exact Azure CLI deletion during cleanup'

            $script:cleanupFailed = $false
            [System.IO.File]::WriteAllText($hashGuardVarFile, 'changed fixture input', [System.Text.UTF8Encoding]::new($false))
            $staleInputRemoved = Remove-ExactPolicyResources -Status $hashGuardStatus
            Assert-Fixture (-not $staleInputRemoved -and $script:cleanupFailed -and $script:fixturePolicyDeleteCalls.Count -eq 0) 'changed protected input fingerprint blocks exact Azure CLI deletion during cleanup'

            [System.IO.File]::WriteAllText($hashGuardVarFile, 'stable fixture input', [System.Text.UTF8Encoding]::new($false))
            $hashGuardStatus['varFileSha256'] = (Get-FileHash -LiteralPath $hashGuardVarFile -Algorithm SHA256).Hash
            $hashGuardStatus['sourceFingerprint'] = Get-SourceFingerprint -Root $script:repoRoot
            $script:cleanupFailed = $false
            $validHashGuardRemoved = Remove-ExactPolicyResources -Status $hashGuardStatus
            $expectedHashGuardDelete = @('policy', 'assignment', 'delete', '--name', 'fixture-assignment', '--scope', "/subscriptions/$($script:approvedSubscriptionId)", '--subscription', $script:approvedSubscriptionId, '--output', 'none')
            $validHashGuardCommand = $script:fixturePolicyDeleteCalls.Count -eq 1 -and (($script:fixturePolicyDeleteCalls[0] -join ' ') -ceq ($expectedHashGuardDelete -join ' '))
            Assert-Fixture ($validHashGuardRemoved -and -not $script:cleanupFailed -and $validHashGuardCommand) 'unchanged source and protected input fingerprints permit only the captured exact policy ID cleanup command'
        }
        finally {
            Set-Item -Path Function:script:Assert-DefaultStateUnchanged -Value $originalHashGuardDefaultState
            Set-Item -Path Function:script:Assert-ApprovedAzureContext -Value $originalHashGuardContext
            Set-Item -Path Function:script:Test-ResourceAbsentNow -Value $originalHashGuardPresence
            Set-Item -Path Function:script:Wait-Absence -Value $originalHashGuardWait
            Set-Item -Path Function:script:Invoke-Az -Value $originalHashGuardInvokeAz
            $script:statusPath = $originalHashGuardStatusPath
            $script:logPath = $originalHashGuardLogPath
            $script:cleanupFailed = $originalHashGuardCleanupFailed
        }

        $partialApplyStatus = @{
            profile = 'minimal'; exampleRoot = Join-Path $script:repoRoot 'examples/minimal-audit-assignment'; varFile = $fixtureVarFile
            sourceFingerprint = Get-SourceFingerprint -Root $script:repoRoot; varFileSha256 = (Get-FileHash -LiteralPath $fixtureVarFile -Algorithm SHA256).Hash
            subscriptionId = $script:approvedSubscriptionId; tenantId = $script:approvedTenantId; assignmentScopeId = "/subscriptions/$($script:approvedSubscriptionId)"
            terraformVars = @{ assignment_key = 'audit-sub'; assignment_owner = 'platform-governance'; create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '' }
            createdResourceIds = @{}; appliedStages = @(); mutationStarted = $false
        }
        $script:fixtureApplyExitCode = 1
        $script:fixtureTerraformCalls = @()
        $partialApplyResult = Invoke-TrackedApply -Status $partialApplyStatus -Stage 'fixture-partial-apply' -TerraformArguments @('apply', '-auto-approve')
        $script:fixtureApplyExitCode = 0
        $partialApplyDelete = Get-PolicyDeleteArguments -ResourceId $partialApplyStatus['createdResourceIds']['assignments'][0] -Status @{ profile = 'minimal'; subscriptionId = $script:approvedSubscriptionId }
        Assert-Fixture ($partialApplyResult.ExitCode -eq 1 -and $partialApplyStatus['createdResourceIds']['assignments'].Count -eq 1 -and $partialApplyStatus['appliedStages'].Count -eq 0 -and ($partialApplyDelete -join ' ') -ceq "policy assignment delete --name audit-sub-subscription-built-in-audit --scope /subscriptions/$($script:approvedSubscriptionId) --subscription $($script:approvedSubscriptionId) --output none") 'failed partial apply retains its exact assignment ID and cleanup command without recording a completed stage'

        $inventoryFixturePath = Join-Path $runDirectory 'inventory-before-groups.json'
        Set-Content -LiteralPath $inventoryFixturePath -Value (ConvertTo-Json -InputObject @($script:fixtureInventoryBaseline.groups) -Depth 10) -Encoding utf8
        $script:fixtureAzResponses.Clear()
        $script:fixtureAzResponses['group list'] = @{ ExitCode = 0; Data = @($script:fixtureInventoryBaseline.groups); Text = '' }
        Assert-Fixture (Test-InventoryMatchesBaseline -BaselinePath $inventoryFixturePath -Arguments @('group', 'list') -Label 'fixture existing groups') 'unchanged unrelated resource group IDs match the pre-run inventory baseline'
        $inventoryCases = @(
            @{ Class = 'assignments'; File = 'inventory-before-policy-assignments.json'; Arguments = @('policy', 'assignment', 'list') },
            @{ Class = 'definitions'; File = 'inventory-before-definitions.json'; Arguments = @('policy', 'definition', 'list', '--query', "[?policyType=='Custom']") },
            @{ Class = 'initiatives'; File = 'inventory-before-initiatives.json'; Arguments = @('policy', 'set-definition', 'list', '--query', "[?policyType=='Custom']") }
        )
        $allInventoryClassesPreserved = $true
        foreach ($inventoryCase in $inventoryCases) {
            $inventoryItems = Get-JsonProperty -Object $script:fixtureInventoryBaseline -Name $inventoryCase.Class
            $caseBaselinePath = Join-Path $runDirectory $inventoryCase.File
            Set-Content -LiteralPath $caseBaselinePath -Value (ConvertTo-Json -InputObject @($inventoryItems) -Depth 10) -Encoding utf8
            $script:fixtureAzResponses[($inventoryCase.Arguments -join ' ')] = @{ ExitCode = 0; Data = @($inventoryItems); Text = '' }
            if (-not (Test-InventoryMatchesBaseline -BaselinePath $caseBaselinePath -Arguments $inventoryCase.Arguments -Label ('fixture ' + $inventoryCase.Class))) { $allInventoryClassesPreserved = $false }
        }
        Assert-Fixture $allInventoryClassesPreserved 'unrelated assignments, custom definitions and initiatives retain their baseline ID sets'
        $script:fixtureAzResponses['group list'] = @{ ExitCode = 0; Data = @($script:fixtureInventoryBaseline.groups) + @([pscustomobject]@{ id = "/subscriptions/$($script:approvedSubscriptionId)/resourceGroups/rg-unrelated-added" }); Text = '' }
        $ownedGroupId = "/subscriptions/$($script:approvedSubscriptionId)/resourceGroups/rg-owned-fixture"
        $driftStatus = @{ runId = 'r12345'; subscriptionId = $script:approvedSubscriptionId; targetResourceGroupName = 'rg-owned-fixture'; createdResourceIds = @{ resource_groups = @($ownedGroupId) } }
        Assert-Fixture (-not (Test-InventoryMatchesBaseline -BaselinePath $inventoryFixturePath -Arguments @('group', 'list') -Label 'resource groups' -Status $driftStatus)) 'new groups cannot bypass missing owned-absence verification'
        Assert-Fixture (Test-InventoryMatchesBaseline -BaselinePath $inventoryFixturePath -Arguments @('group', 'list') -Label 'resource groups' -Status $driftStatus -OwnedAbsenceVerified) 'additional unrelated group is accepted only after owned absence is verified'
        Assert-Fixture ($driftStatus.environmentalDrift.Count -eq 1 -and $driftStatus.environmentalDrift[0].additionalIds[0] -ceq "/subscriptions/$($script:approvedSubscriptionId)/resourcegroups/rg-unrelated-added" -and $driftStatus.environmentalDrift[0].ownedAbsenceVerified) 'accepted unrelated group is explicitly recorded as environmental drift'
        $script:fixtureAzResponses['group list'] = @{ ExitCode = 0; Data = @($script:fixtureInventoryBaseline.groups) + @([pscustomobject]@{ id = $ownedGroupId }); Text = '' }
        Assert-Fixture (-not (Test-InventoryMatchesBaseline -BaselinePath $inventoryFixturePath -Arguments @('group', 'list') -Label 'resource groups' -Status $driftStatus -OwnedAbsenceVerified)) 'additional owned group remains a cleanup failure even if the earlier absence check passed'
        $uncapturedStatus = $driftStatus.Clone()
        $uncapturedStatus.createdResourceIds = @{}
        Assert-Fixture (-not (Test-InventoryMatchesBaseline -BaselinePath $inventoryFixturePath -Arguments @('group', 'list') -Label 'resource groups' -Status $uncapturedStatus -OwnedAbsenceVerified)) 'expected owned group is rejected even when partial creation left no captured ID'
        $script:fixtureAzResponses['group list'] = @{ ExitCode = 0; Data = @($script:fixtureInventoryBaseline.groups) + @([pscustomobject]@{ id = "/subscriptions/$($script:approvedSubscriptionId)/resourceGroups/rg-zctfp-r12345-extra" }); Text = '' }
        Assert-Fixture (-not (Test-InventoryMatchesBaseline -BaselinePath $inventoryFixturePath -Arguments @('group', 'list') -Label 'resource groups' -Status $uncapturedStatus -OwnedAbsenceVerified)) 'additional group carrying the run ID is never treated as unrelated drift'
        $policyBaselinePath = Join-Path $runDirectory 'inventory-before-policy-assignments.json'
        $script:fixtureAzResponses['policy assignment list'] = @{ ExitCode = 0; Data = @($script:fixtureInventoryBaseline.assignments) + @([pscustomobject]@{ id = "/subscriptions/$($script:approvedSubscriptionId)/providers/Microsoft.Authorization/policyAssignments/foreign-new" }); Text = '' }
        Assert-Fixture (-not (Test-InventoryMatchesBaseline -BaselinePath $policyBaselinePath -Arguments @('policy', 'assignment', 'list') -Label 'policy assignments' -Status $driftStatus -OwnedAbsenceVerified)) 'additional policy inventory IDs remain a cleanup failure'
        $script:fixtureAzResponses['group list'] = @{ ExitCode = 0; Data = @($script:fixtureInventoryBaseline.groups | Select-Object -First 1); Text = '' }
        Assert-Fixture (-not (Test-InventoryMatchesBaseline -BaselinePath $inventoryFixturePath -Arguments @('group', 'list') -Label 'resource groups' -Status $driftStatus -OwnedAbsenceVerified)) 'inventory comparison detects a pre-existing unrelated resource missing after cleanup'

        $collisionRejected = $false
        $script:fixtureAzureCalls = @()
        try {
            Assert-NoPreexistingResourceCollisions -Profile complete -TargetResourceGroupName 'rg-fixture-collision' -TargetStorageAccountName 'fixturecollision' -AssignmentsBaseline @() -DefinitionsBaseline @([pscustomobject]@{ name = 'ADD-COSTCENTRE-TAG' }) -InitiativesBaseline @()
        }
        catch { $collisionRejected = $_.Exception.Message -like '*policy definition name add-costcentre-tag already exists*' }
        Assert-Fixture ($collisionRejected -and $script:fixtureAzureCalls.Count -eq 0) 'existing custom definition collision refuses the complete run before Azure name probes'

        $collisionRejected = $false
        try {
            Assert-NoPreexistingResourceCollisions -Profile complete -TargetResourceGroupName 'rg-fixture-collision' -TargetStorageAccountName 'fixturecollision' -AssignmentsBaseline @() -DefinitionsBaseline @() -InitiativesBaseline @([pscustomobject]@{ name = 'TAG-GOVERNANCE' })
        }
        catch { $collisionRejected = $_.Exception.Message -like '*policy set name tag-governance already exists*' }
        Assert-Fixture ($collisionRejected -and $script:fixtureAzureCalls.Count -eq 0) 'existing custom initiative collision refuses the complete run before Azure name probes'

        $script:fixtureAzResponses.Clear()
        $script:fixtureAzResponses['group show --name rg-fixture-collision'] = @{ ExitCode = 0; Data = [pscustomobject]@{ id = "/subscriptions/$($script:approvedSubscriptionId)/resourceGroups/rg-fixture-collision" }; Text = '' }
        $script:fixtureAzResponses['storage account check-name --name fixturecollision'] = @{ ExitCode = 0; Data = [pscustomobject]@{ nameAvailable = $true }; Text = '' }
        $collisionRejected = $false
        try { Assert-NoPreexistingResourceCollisions -Profile complete -TargetResourceGroupName 'rg-fixture-collision' -TargetStorageAccountName 'fixturecollision' -AssignmentsBaseline @() -DefinitionsBaseline @() -InitiativesBaseline @() }
        catch { $collisionRejected = $_.Exception.Message -like '*target resource group*exists or its absence is inconclusive*' }
        Assert-Fixture ($collisionRejected -and $script:fixtureAzureCalls.Count -eq 1) 'an existing target resource group refuses the complete run before storage-name checks'

        $script:fixtureAzResponses['group show --name rg-fixture-collision'] = @{ ExitCode = 1; Data = $null; Text = 'ResourceGroupNotFound' }
        $script:fixtureAzResponses['storage account check-name --name fixturecollision'] = @{ ExitCode = 0; Data = [pscustomobject]@{ nameAvailable = $false }; Text = '' }
        $collisionRejected = $false
        try { Assert-NoPreexistingResourceCollisions -Profile complete -TargetResourceGroupName 'rg-fixture-collision' -TargetStorageAccountName 'fixturecollision' -AssignmentsBaseline @() -DefinitionsBaseline @() -InitiativesBaseline @() }
        catch { $collisionRejected = $_.Exception.Message -like '*storage account name*unavailable or could not be checked*' }
        Assert-Fixture ($collisionRejected -and $script:fixtureAzureCalls.Count -eq 3) 'an unavailable storage account name refuses the complete run after authoritative group absence'

        $collisionRejected = $false
        try {
            Assert-NoPreexistingResourceCollisions -Profile minimal -AssignmentScopeId "/subscriptions/$($script:approvedSubscriptionId)" -AssignmentsBaseline @([pscustomobject]@{ name = 'AUDIT-SUB-SUBSCRIPTION-BUILT-IN-AUDIT'; scope = "/subscriptions/$($script:approvedSubscriptionId)" }) -DefinitionsBaseline @() -InitiativesBaseline @()
        }
        catch { $collisionRejected = $_.Exception.Message -like '*subscription policy assignment*already exists at the approved scope*' }
        Assert-Fixture ($collisionRejected -and $script:fixtureAzureCalls.Count -eq 3) 'existing subscription assignment collision refuses the minimal run without Azure mutation'

        $script:fixtureWorkspaceShow = 'default'
        $script:fixtureWorkspaceList = @('default', 'uat-fixture01')
        $script:fixtureStateList = @()
        $script:fixtureTerraformCalls = @()
        $workspaceCollisionStatus = @{ exampleRoot = Join-Path $script:repoRoot 'examples/minimal-audit-assignment'; runId = 'fixture01'; defaultStateSnapshot = @(Get-DefaultStateSnapshot -ExampleRoot (Join-Path $script:repoRoot 'examples/minimal-audit-assignment')) }
        $workspaceCollisionRejected = $false
        try { Initialize-RunWorkspace -Status $workspaceCollisionStatus }
        catch { $workspaceCollisionRejected = $_.Exception.Message -like '*workspace*already exists*' }
        $workspaceNewCalls = 0
        foreach ($terraformCall in $script:fixtureTerraformCalls) { if (($terraformCall -join ' ') -match 'workspace new') { $workspaceNewCalls++ } }
        Assert-Fixture ($workspaceCollisionRejected -and $workspaceNewCalls -eq 0) 'an existing per-run Terraform workspace refuses reuse before workspace creation'

        $script:fixtureWorkspaceShow = 'uat-fixture01'
        $script:fixtureWorkspaceList = @('default', 'uat-fixture01')
        $script:fixtureStateList = @()

        $script:fixtureOutputs = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-output-complete.json') -Raw | ConvertFrom-Json
        $script:fixtureStateJson = $script:fixtureCompleteState
        $workspaceName = 'uat-fixture01'
        $recordedContext = @{
            runId = 'fixture01'; profile = 'complete'
            exampleRoot = Join-Path $script:repoRoot 'examples/complete-policy-lifecycle'
            runDirectory = $runDirectory; varFile = $fixtureVarFile
            sourceFingerprint = ('A' * 64); varFileSha256 = (Get-FileHash -LiteralPath $fixtureVarFile -Algorithm SHA256).Hash
            defaultStateSnapshot = @(Get-DefaultStateSnapshot -ExampleRoot (Join-Path $script:repoRoot 'examples/complete-policy-lifecycle'))
            mutationStarted = $true; terraformWorkspace = $workspaceName
            terraformStatePath = Join-Path (Join-Path (Join-Path $script:repoRoot 'examples/complete-policy-lifecycle') 'terraform.tfstate.d') (Join-Path $workspaceName 'terraform.tfstate')
        }
        Assert-RecordedCleanupContext -Status $recordedContext -StatusFilePath $script:statusPath
        Assert-Fixture $true 'cleanup recovery accepts only the recorded example, protected inputs and canonical per-run state path'
        $tamperedContext = $recordedContext.Clone()
        $tamperedContext['terraformStatePath'] = Join-Path $script:repoRoot 'terraform.tfstate'
        $statePathRejected = $false
        try { Assert-RecordedCleanupContext -Status $tamperedContext -StatusFilePath $script:statusPath }
        catch { $statePathRejected = $_.Exception.Message -like '*state path does not match*' }
        Assert-Fixture $statePathRejected 'cleanup recovery rejects a state path outside its isolated workspace'
        $pauseStatus = @{ recoveryProbe = $true; recoveryPausePending = $true; cleanupOnlyResume = $false; cleanupCompleted = $true }
        $script:cleanupFailed = $false
        $script:cleanupPaused = $false
        Assert-Fixture (Stop-BeforeDestroyForRecoveryProbe -Status $pauseStatus) 'recovery probe persists an interruption boundary before destroy'
        $persistedPause = Get-Content -LiteralPath $script:statusPath -Raw | ConvertFrom-Json
        Assert-Fixture ($persistedPause.cleanupPhase -eq 'policy-resources-absent-state-inventoried-awaiting-cleanup-only' -and -not $persistedPause.cleanupCompleted) 'recovery interruption marker is stored for CleanupOnly resume'
        $pauseStatus['cleanupOnlyResume'] = $true
        $script:cleanupFailed = $false
        $script:cleanupPaused = $false
        Assert-Fixture (-not (Stop-BeforeDestroyForRecoveryProbe -Status $pauseStatus)) 'CleanupOnly resume passes the intentional pause and can continue to destroy'
        $script:cleanupFailed = $false
        $script:cleanupPaused = $false
        $status = @{
            exampleRoot = 'examples/complete-policy-lifecycle'
            profile = 'complete'
            subscriptionId = $script:approvedSubscriptionId
            targetResourceGroupName = 'rg-zctfp-fixture'
            runDirectory = $runDirectory
            runId = 'fixture01'
            terraformVars = @{ create_exemption = 'true'; exemption_assignment_id = '/fixture/assignment'; exemption_expiry = '2030-01-01T00:00:00Z' }
            evaluationTime = '2026-10-01T12:00:00Z'
            assignmentScopeId = $null
            createdResourceIds = @{
                assignments = @(); identities = @(); principals = @(); role_assignments = @(); remediations = @(); exemptions = @(); definition_ids = @(); set_definition_id = @()
            }
        }
        Assert-Fixture (Update-CapturedOutputs -Status $status) 'legacy lifecycle output fixture captures only IDs accepted by the exact run-scope rules'
        $statusJson = Get-Content -LiteralPath $script:statusPath -Raw
        Assert-Fixture ($status['createdResourceIds']['assignments'].Count -eq 1) 'capture records the assignment resource ID'
        Assert-Fixture ($status['createdResourceIds']['role_assignments'].Count -eq 1) 'capture flattens nested role assignment ID maps'
        Assert-Fixture ($script:fixtureOutputs.lifecycle_resource_ids.value.assignments.'planned-assignment' -eq $null -and $status['createdResourceIds']['assignments'] -notcontains '') 'planned null IDs are not misreported as created or verified-absent resources'
        Assert-Fixture ($status['createdResourceIds']['remediations'].Count -eq 1 -and $status['createdResourceIds']['exemptions'].Count -eq 1) 'capture records remediation and exemption resource IDs'
        Assert-Fixture ($statusJson.Contains('/subscriptions/' + $script:approvedSubscriptionId)) 'protected recovery status preserves real IDs for cleanup'

        $legacyFixtureOutputs = $script:fixtureOutputs
        $script:fixtureOutputs = $script:fixtureCompleteExampleOutputs
        $script:fixtureStateJson = $script:fixtureCompleteState
        $completeExampleStatus = @{
            exampleRoot = Join-Path $script:repoRoot 'examples/complete-policy-lifecycle'
            profile = 'complete'
            subscriptionId = $script:approvedSubscriptionId
            targetResourceGroupName = 'rg-zctfp-fixture'
            createdResourceIds = @{
                assignments = @(); identities = @(); principals = @(); role_assignments = @(); remediations = @(); exemptions = @(); definition_ids = @(); set_definition_id = @()
            }
        }
        Assert-Fixture (Update-CapturedOutputs -Status $completeExampleStatus) 'current complete-example outputs and Terraform state capture a scope-validated cleanup manifest without lifecycle_resource_ids'
        $expectedCompleteIds = @{
            assignments = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-fixture/providers/Microsoft.Authorization/policyAssignments/modify-tag-rg'
            identities = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-fixture/providers/Microsoft.ManagedIdentity/userAssignedIdentities/irb-fixture'
            role_assignments = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-fixture/providers/Microsoft.Authorization/roleAssignments/88888888-8888-8888-8888-888888888888'
            remediations = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-fixture/providers/Microsoft.PolicyInsights/remediations/remediate-tag-rg'
            exemptions = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-fixture/providers/Microsoft.Authorization/policyExemptions/exempt-tag-rg-uat'
            definition_ids = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/policyDefinitions/add-costcentre-tag'
            set_definition_id = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/policySetDefinitions/tag-governance'
        }
        $completeIdsMatch = $true
        foreach ($class in $expectedCompleteIds.Keys) {
            $captured = @($completeExampleStatus['createdResourceIds'][$class])
            if ($captured.Count -ne 1 -or $captured[0] -cne $expectedCompleteIds[$class]) { $completeIdsMatch = $false }
        }
        $completeIdsMatch = $completeIdsMatch -and $completeExampleStatus['createdResourceIds']['principals'][0] -ceq '77777777-7777-7777-7777-777777777777'
        Assert-Fixture $completeIdsMatch 'complete public outputs and state preserve exact assignment and content IDs for cleanup'
        $completeCleanupExpected = @{
            assignments = "policy assignment delete --name modify-tag-rg --scope /subscriptions/$($script:approvedSubscriptionId)/resourceGroups/rg-zctfp-fixture --subscription $($script:approvedSubscriptionId) --output none"
            role_assignments = "role assignment delete --ids $($completeExampleStatus['createdResourceIds']['role_assignments'][0]) --subscription $($script:approvedSubscriptionId) --output none"
            remediations = "policy remediation delete --name remediate-tag-rg --resource-group rg-zctfp-fixture --subscription $($script:approvedSubscriptionId) --output none"
            exemptions = "policy exemption delete --name exempt-tag-rg-uat --resource-group rg-zctfp-fixture --subscription $($script:approvedSubscriptionId) --output none"
            set_definition_id = "policy set-definition delete --name tag-governance --subscription $($script:approvedSubscriptionId) --output none"
            definition_ids = "policy definition delete --name add-costcentre-tag --subscription $($script:approvedSubscriptionId) --output none"
        }
        $completeCleanupMatches = $true
        foreach ($class in $completeCleanupExpected.Keys) {
            $id = @($completeExampleStatus['createdResourceIds'][$class])[0]
            $arguments = Get-PolicyDeleteArguments -ResourceId $id -Status @{ profile = 'complete'; subscriptionId = $script:approvedSubscriptionId; targetResourceGroupName = 'rg-zctfp-fixture' }
            if (($arguments -join ' ') -cne $completeCleanupExpected[$class]) { $completeCleanupMatches = $false }
        }
        Assert-Fixture $completeCleanupMatches 'complete-example output and state IDs map to their exact allowlisted cleanup CLI commands'

        $script:fixtureOutputs = $script:fixtureMinimalOutputs
        $script:fixtureStateJson = $script:fixtureMinimalState
        $minimalExampleStatus = @{
            exampleRoot = Join-Path $script:repoRoot 'examples/minimal-audit-assignment'
            profile = 'minimal'
            subscriptionId = $script:approvedSubscriptionId
            targetResourceGroupName = $null
            createdResourceIds = @{ assignments = @() }
        }
        Assert-Fixture (Update-CapturedOutputs -Status $minimalExampleStatus) 'current minimal-example review output captures a scope-validated assignment ID'
        $minimalOutputId = $script:fixtureMinimalOutputs.resolved_assignment_review.value.'audit-sub'.assignment_id
        $minimalCleanup = Get-PolicyDeleteArguments -ResourceId $minimalExampleStatus['createdResourceIds']['assignments'][0] -Status @{ profile = 'minimal'; subscriptionId = $script:approvedSubscriptionId }
        Assert-Fixture ($minimalExampleStatus['createdResourceIds']['assignments'].Count -eq 1 -and $minimalExampleStatus['createdResourceIds']['assignments'][0] -ceq $minimalOutputId -and ($minimalCleanup -join ' ') -ceq "policy assignment delete --name audit-sub-subscription-built-in-audit --scope /subscriptions/$($script:approvedSubscriptionId) --subscription $($script:approvedSubscriptionId) --output none") 'minimal-example output ID maps to the exact subscription assignment cleanup command'

        $invalidOutput = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-output-minimal.json') -Raw | ConvertFrom-Json
        $invalidOutput.resolved_assignment_review.value.'audit-sub'.assignment_id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/foreign'
        $script:fixtureOutputs = $invalidOutput
        $script:testFailed = $false
        $invalidOutputStatus = @{
            exampleRoot = Join-Path $script:repoRoot 'examples/minimal-audit-assignment'
            profile = 'minimal'
            subscriptionId = $script:approvedSubscriptionId
            targetResourceGroupName = $null
            createdResourceIds = @{ assignments = @() }
        }
        $invalidOutputRejected = -not (Update-CapturedOutputs -Status $invalidOutputStatus) -and $script:testFailed -and $invalidOutputStatus['createdResourceIds']['assignments'] -notcontains $invalidOutput.resolved_assignment_review.value.'audit-sub'.assignment_id
        Assert-Fixture $invalidOutputRejected 'foreign-subscription assignment output fails closed and is excluded from the cleanup manifest'
        $script:testFailed = $false
        $script:fixtureOutputs = $legacyFixtureOutputs
        $script:fixtureStateJson = $script:fixtureCompleteState

        $recoveryDirectory = Join-Path $runDirectory 'destroy-recovery'
        New-Item -ItemType Directory -Path $recoveryDirectory | Out-Null
        $recoveryVarFile = Join-Path $recoveryDirectory 'run-input.tfvars'
        [System.IO.File]::WriteAllText($recoveryVarFile, '', [System.Text.UTF8Encoding]::new($false))
        $recoveryStatePath = Join-Path $recoveryDirectory 'terraform.tfstate'
        [System.IO.File]::WriteAllText($recoveryStatePath, '{}', [System.Text.UTF8Encoding]::new($false))
        $recoveryStatusPath = Join-Path $recoveryDirectory 'run-status.json'
        $originalRecoveryStatusPath = $script:statusPath
        $originalRecoveryLogPath = $script:logPath
        $originalMutationLockPath = $script:mutationLockPath
        $script:statusPath = $recoveryStatusPath
        $script:logPath = Join-Path $recoveryDirectory 'run.log'
        $recoveryStatus = @{
            runId = 'fixture01'; profile = 'complete'; exampleRoot = Join-Path $script:repoRoot 'examples/complete-policy-lifecycle'
            runDirectory = $recoveryDirectory; varFile = $recoveryVarFile
            sourceFingerprint = Get-SourceFingerprint -Root $script:repoRoot; varFileSha256 = (Get-FileHash -LiteralPath $recoveryVarFile -Algorithm SHA256).Hash
            subscriptionId = $script:approvedSubscriptionId; tenantId = $script:approvedTenantId
            targetResourceGroupName = 'rg-zctfp-fixture'; targetStorageAccountName = 'zctfpfixturestore'
            terraformWorkspace = 'uat-fixture01'; terraformStatePath = $recoveryStatePath
            defaultStateSnapshot = @(); terraformVars = @{ create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '' }
            evaluationTime = '2026-10-01T12:00:00Z'; mutationStarted = $true; appliedStages = @('stage-0a'); activeStage = 'stage-0a'
            createdResourceIds = @{}; recoveryProbe = $true; recoveryPausePending = $false; cleanupOnlyResume = $false; intentionalFailure = $true
        }
        $originalCleanupTerraform = (Get-Command Invoke-Terraform).ScriptBlock
        $originalCleanupRemoveExact = (Get-Command Remove-ExactPolicyResources).ScriptBlock
        $originalCleanupWorkspaceState = (Get-Command Test-RunWorkspaceState).ScriptBlock
        $originalCleanupDefaultState = (Get-Command Assert-DefaultStateUnchanged).ScriptBlock
        $originalCleanupContext = (Get-Command Assert-ApprovedAzureContext).ScriptBlock
        $originalCleanupAbsence = (Get-Command Wait-Absence).ScriptBlock
        $originalCleanupInventory = (Get-Command Test-InventoryMatchesBaseline).ScriptBlock
        Set-Item -Path Function:script:Remove-ExactPolicyResources -Value { param([hashtable]$Status) return $true }
        Set-Item -Path Function:script:Test-RunWorkspaceState -Value { param([hashtable]$Status) return $true }
        Set-Item -Path Function:script:Assert-DefaultStateUnchanged -Value { param([hashtable]$Status) return $true }
        Set-Item -Path Function:script:Assert-ApprovedAzureContext -Value { return $true }
        Set-Item -Path Function:script:Wait-Absence -Value { param([string]$Label, [string]$ProbeKind, [string]$Target, [hashtable]$Settings) return $true }
        Set-Item -Path Function:script:Test-InventoryMatchesBaseline -Value { param([string]$BaselinePath, [string[]]$Arguments, [string]$Label, [hashtable]$Status, [switch]$OwnedAbsenceVerified) return $true }
        $script:fixtureDestroyExitCode = 1
        $script:fixtureDestroyAttempts = 0
        $script:fixtureTerraformCalls = @()
        Set-Item -Path Function:script:Invoke-Terraform -Value {
            param([string[]]$TerraformArguments, [switch]$FullLog)
            $argumentText = $TerraformArguments -join ' '
            $script:fixtureTerraformCalls += ,@($TerraformArguments)
            if ($argumentText -match 'destroy') {
                $script:fixtureDestroyAttempts++
                return @{ ExitCode = $script:fixtureDestroyExitCode; Output = @('fixture destroy result') }
            }
            if ($argumentText -match 'state list') {
                if ($script:fixtureDestroyAttempts -gt 0 -and $script:fixtureDestroyExitCode -eq 0) { return @{ ExitCode = 0; Output = @() } }
                return @{ ExitCode = 0; Output = @('azurerm_resource_group.target') }
            }
            if ($argumentText -match 'workspace show') { return @{ ExitCode = 0; Output = @('uat-fixture01') } }
            return @{ ExitCode = 0; Output = @() }
        }
        $script:cleanupFailed = $false
        $script:cleanupPaused = $false
        Invoke-Cleanup -Status $recoveryStatus
        $failedDestroyRecord = ConvertTo-Hashtable -Object (Get-Content -LiteralPath $recoveryStatusPath -Raw | ConvertFrom-Json)
        Assert-Fixture ($script:cleanupFailed -and -not $failedDestroyRecord['cleanupCompleted'] -and $script:fixtureDestroyAttempts -eq 1) 'failed Terraform destroy remains an incomplete cleanup boundary with its recovery status preserved'

        $recoveryStatus = $failedDestroyRecord
        $recoveryStatus['cleanupOnlyResume'] = $true
        $script:fixtureDestroyExitCode = 0
        $script:fixtureDestroyAttempts = 0
        $script:cleanupFailed = $false
        $script:cleanupPaused = $false
        Invoke-Cleanup -Status $recoveryStatus
        $completedRecoveryRecord = ConvertTo-Hashtable -Object (Get-Content -LiteralPath $recoveryStatusPath -Raw | ConvertFrom-Json)
        Assert-Fixture (-not $script:cleanupFailed -and $completedRecoveryRecord['cleanupCompleted'] -and $completedRecoveryRecord['workspaceRemoved'] -and $completedRecoveryRecord['cleanupPhase'] -eq 'recovery-probe-cleanup-complete') 'CleanupOnly retry completes destroy, workspace removal and the recorded recovery boundary'
        [System.IO.File]::WriteAllText($recoveryStatePath, '{"version":4,"resources":[]}', [System.Text.UTF8Encoding]::new($false))
        $completedRecoveryRecord['preDestroyStatePath'] = $recoveryStatePath
        $completedRecoveryRecord['preDestroyStateAddresses'] = @('azurerm_resource_group.target')
        Assert-Fixture (Test-PostDestroyWorkspaceState -Status $completedRecoveryRecord) 'interrupted post-destroy cleanup recognises its recorded empty isolated state'
        $completedRecoveryRecord['preDestroyStateAddresses'] = @()
        Assert-Fixture (-not (Test-PostDestroyWorkspaceState -Status $completedRecoveryRecord)) 'empty state without a recorded pre-destroy inventory cannot bypass the isolation gate'

        Set-Item -Path Function:script:Invoke-Terraform -Value $originalCleanupTerraform
        Set-Item -Path Function:script:Remove-ExactPolicyResources -Value $originalCleanupRemoveExact
        Set-Item -Path Function:script:Test-RunWorkspaceState -Value $originalCleanupWorkspaceState
        Set-Item -Path Function:script:Assert-DefaultStateUnchanged -Value $originalCleanupDefaultState
        Set-Item -Path Function:script:Assert-ApprovedAzureContext -Value $originalCleanupContext
        Set-Item -Path Function:script:Wait-Absence -Value $originalCleanupAbsence
        Set-Item -Path Function:script:Test-InventoryMatchesBaseline -Value $originalCleanupInventory

        $cleanupOnlyDirectory = Join-Path $runDirectory 'cleanup-only-completion'
        New-Item -ItemType Directory -Path $cleanupOnlyDirectory | Out-Null
        $cleanupOnlyVarFile = Join-Path $cleanupOnlyDirectory 'run-input.tfvars'
        [System.IO.File]::WriteAllText($cleanupOnlyVarFile, '', [System.Text.UTF8Encoding]::new($false))
        $cleanupOnlyStatusPath = Join-Path $cleanupOnlyDirectory 'run-status.json'
        $cleanupOnlyStatus = @{
            runId = 'fixture02'; profile = 'minimal'; exampleRoot = Join-Path $script:repoRoot 'examples/minimal-audit-assignment'
            runDirectory = $cleanupOnlyDirectory; varFile = $cleanupOnlyVarFile
            sourceFingerprint = Get-SourceFingerprint -Root $script:repoRoot; varFileSha256 = (Get-FileHash -LiteralPath $cleanupOnlyVarFile -Algorithm SHA256).Hash
            subscriptionId = $script:approvedSubscriptionId; tenantId = $script:approvedTenantId
            assignmentScopeId = "/subscriptions/$($script:approvedSubscriptionId)"; terraformVars = @{ assignment_key = 'audit-sub'; assignment_owner = 'platform-governance'; create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '' }
            defaultStateSnapshot = @(Get-DefaultStateSnapshot -ExampleRoot (Join-Path $script:repoRoot 'examples/minimal-audit-assignment'))
            mutationStarted = $false; appliedStages = @(); createdResourceIds = @{}
            recoveryProbe = $true; recoveryPausePending = $true; cleanupOnlyResume = $false; cleanupCompleted = $false; intentionalFailure = $true
        }
        $script:statusPath = $cleanupOnlyStatusPath
        $script:mutationLockPath = Join-Path $cleanupOnlyDirectory 'mutation.lock'
        $script:subscriptionId = $script:approvedSubscriptionId
        $script:tenantId = $script:approvedTenantId
        $script:fixtureAzResponses.Clear()
        $script:fixtureAzResponses['group list'] = @{ ExitCode = 0; Data = @(); Text = '' }
        $script:fixtureAzResponses['policy assignment list'] = @{ ExitCode = 0; Data = @(); Text = '' }
        $script:fixtureAzResponses["policy definition list --query [?policyType=='Custom']"] = @{ ExitCode = 0; Data = @(); Text = '' }
        $script:fixtureAzResponses["policy set-definition list --query [?policyType=='Custom']"] = @{ ExitCode = 0; Data = @(); Text = '' }
        $script:cleanupFailed = $false
        $script:testFailed = $false
        Save-RunStatus -Status $cleanupOnlyStatus
        [System.IO.File]::WriteAllText($script:mutationLockPath, "$($cleanupOnlyStatus['runId'])`n$($script:approvedTenantId)`n$($script:approvedSubscriptionId)")
        $cleanupOnlyExitCode = Invoke-RecordedCleanup -Path $cleanupOnlyStatusPath
        $cleanupOnlyRecord = ConvertTo-Hashtable -Object (Get-Content -LiteralPath $cleanupOnlyStatusPath -Raw | ConvertFrom-Json)
        Assert-Fixture ($cleanupOnlyExitCode -eq 1 -and $cleanupOnlyRecord['cleanupCompleted'] -and $cleanupOnlyRecord['cleanupPhase'] -eq 'recovery-probe-cleanup-complete' -and -not (Test-Path -LiteralPath $script:mutationLockPath)) 'CleanupOnly status-file resume completes its recorded recovery boundary and releases the mutation lock while retaining the intentional test failure'
        $cleanupOnlyRecord['intentionalFailure'] = $false
        $cleanupOnlyRecord['testFailed'] = $true
        Save-RunStatus -Status $cleanupOnlyRecord
        $ordinaryFailedResumeExitCode = Invoke-RecordedCleanup -Path $cleanupOnlyStatusPath
        Assert-Fixture ($ordinaryFailedResumeExitCode -eq 1 -and -not (Test-Path -LiteralPath $script:mutationLockPath)) 'CleanupOnly retains an ordinary persisted test failure after successful cleanup'
        $cleanupOnlyRecord['testFailed'] = $false
        $cleanupOnlyRecord['testCompleted'] = $false
        Save-RunStatus -Status $cleanupOnlyRecord
        $interruptedResumeExitCode = Invoke-RecordedCleanup -Path $cleanupOnlyStatusPath
        Assert-Fixture ($interruptedResumeExitCode -eq 1 -and -not (Test-Path -LiteralPath $script:mutationLockPath)) 'CleanupOnly does not report an interrupted, incomplete test as passed after cleanup'
        $script:fixtureAzResponses.Clear()
        $script:statusPath = $originalRecoveryStatusPath
        $script:logPath = $originalRecoveryLogPath
        $script:mutationLockPath = $originalMutationLockPath

        $stageArgs = Get-StageVarArguments -Status $status
        Assert-Fixture (($stageArgs -join ' ') -match 'evaluation_time=2026-10-01T12:00:00Z' -and ($stageArgs -join ' ') -match 'exemption_expiry=2030-01-01T00:00:00Z') 'cleanup variables retain persisted evaluation and exemption times'

        $assignmentId = $status['createdResourceIds']['assignments'][0]
        $identityId = $status['createdResourceIds']['identities'][0]
        $setId = $status['createdResourceIds']['set_definition_id'][0]
        $script:testFailed = $false
        Assert-Fixture (Assert-AssignmentBinding -Label 'fixture assignment' -AssignmentId $assignmentId -ExpectedScope '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-fixture' -ExpectedIdentityId $identityId -ExpectedPolicySetId $setId -ExpectedParameters @{ costCentreTagName = 'CostCentre'; costCentreTagValue = 'zctfp-uat' }) 'assignment binding, managed identity and parameters match fixture contract'
        $completeAssignmentRead = @($script:fixtureAzureCalls | Where-Object { ($_ -join ' ') -like 'policy assignment show*' } | Select-Object -Last 1)[0]
        Assert-Fixture (($completeAssignmentRead -join ' ') -ceq "policy assignment show --name $(($assignmentId -split '/')[-1]) --scope $($script:fixtureAssignment.scope) --subscription $($script:approvedSubscriptionId)") 'complete assignment read uses its exact name, scope and subscription'
        Assert-Fixture (Assert-RoleGrantSet -PrincipalId $status['createdResourceIds']['principals'][0] -Scope '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-fixture' -ExpectedIds $status['createdResourceIds']['role_assignments'] -Settings @{ IntervalSeconds = 0; RetryLimit = 1 }) 'role grant readback matches captured role IDs'
        $fixtureRemediationId = $status['createdResourceIds']['remediations'][0]
        Assert-Fixture (Wait-RemediationSuccess -ResourceGroupName 'rg-zctfp-fixture' -RemediationId $fixtureRemediationId -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 }) 'remediation requires successful deployments for its captured task'
        Assert-Fixture (-not (Wait-RemediationSuccess -ResourceGroupName 'rg-zctfp-fixture' -RemediationId '/fixture/foreign-remediation' -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 })) 'a different successful remediation task cannot satisfy the run'
        $firstExecution = Get-RemediationCreationObservation -ResourceGroupName 'rg-zctfp-fixture' -RemediationId $status['createdResourceIds']['remediations'][0]
        $script:fixtureRemediation[0].createdOn = '2026-10-01T22:05:00Z'
        Assert-Fixture ($firstExecution -and (Wait-RemediationSuccess -ResourceGroupName 'rg-zctfp-fixture' -RemediationId $fixtureRemediationId -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 } -PreviousCreatedOn $firstExecution.CreatedOn)) 'repeat remediation requires a newer createdOn timestamp as well as successful deployment'
        $script:fixtureRemediation[0].createdOn = $firstExecution.CreatedOn
        Assert-Fixture (-not (Wait-RemediationSuccess -ResourceGroupName 'rg-zctfp-fixture' -RemediationId $fixtureRemediationId -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 } -PreviousCreatedOn $firstExecution.CreatedOn)) 'an unchanged successful remediation task cannot count as a repeat execution'

        # az output passes through ConvertFrom-Json, which returns [datetime] for ISO timestamps. A live
        # repeat remediation failed when such a value was rendered month-first and parsed back under a
        # day-first culture, so run typed values under en-GB, including a pair that a silent day and
        # month swap would put in the wrong order.
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-GB')
            foreach ($case in @(
                    @{ Previous = '2026-10-18T14:30:12Z'; Newer = '2026-10-18T14:45:50Z' },
                    @{ Previous = '2026-10-12T09:00:00Z'; Newer = '2026-11-02T09:00:00Z' })) {
                $script:fixtureRemediation[0].createdOn = ('{"createdOn":"' + $case.Previous + '"}' | ConvertFrom-Json).createdOn
                $typedPrevious = Get-RemediationCreationObservation -ResourceGroupName 'rg-zctfp-fixture' -RemediationId $fixtureRemediationId
                $script:fixtureRemediation[0].createdOn = ('{"createdOn":"' + $case.Newer + '"}' | ConvertFrom-Json).createdOn
                Assert-Fixture ($typedPrevious -and (Wait-RemediationSuccess -ResourceGroupName 'rg-zctfp-fixture' -RemediationId $fixtureRemediationId -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 } -PreviousCreatedOn $typedPrevious.CreatedOn)) "repeat remediation accepts a newer typed createdOn ($($case.Newer)) under a day-first culture"
                $script:fixtureRemediation[0].createdOn = ('{"createdOn":"' + $case.Previous + '"}' | ConvertFrom-Json).createdOn
                Assert-Fixture (-not (Wait-RemediationSuccess -ResourceGroupName 'rg-zctfp-fixture' -RemediationId $fixtureRemediationId -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 } -PreviousCreatedOn $typedPrevious.CreatedOn)) "an unchanged typed createdOn ($($case.Previous)) cannot count as a repeat execution under a day-first culture"
            }
        }
        finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture }
        $script:fixtureRemediation[0].createdOn = $firstExecution.CreatedOn

        # The status records the variable file's expiry because -var overrides the file. A live run once
        # recorded a fixed value instead, so the file path is exercised here with a full instant, a
        # date-only value and a file that omits the key.
        $expiryVarFile = Join-Path $runDirectory 'expiry-input.tfvars'
        foreach ($case in @(
                @{ Content = 'exemption_expiry = "2031-05-06T07:08:09Z"'; Expected = '2031-05-06T07:08:09Z' },
                @{ Content = 'exemption_expiry = "2031-05-06"'; Expected = '2031-05-06T00:00:00Z' },
                @{ Content = 'target_resource_group_name = "rg-zctfp-fixture"'; Expected = '2027-01-31T00:00:00Z' })) {
            [System.IO.File]::WriteAllText($expiryVarFile, $case.Content, [System.Text.UTF8Encoding]::new($false))
            Assert-Fixture ((Get-VarFileExpiry -Path $expiryVarFile -Default '2027-01-31T00:00:00Z') -ceq $case.Expected) "variable file expiry is recorded as $($case.Expected)"
        }

        $fixtureStorageId = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-fixture/providers/Microsoft.Storage/storageAccounts/zctfpfixturestore'
        $fixtureAssignmentId = $status['createdResourceIds']['assignments'][0]
        $fixtureScanOk = Wait-TargetNonCompliantPolicyState -ResourceGroupName 'rg-zctfp-fixture' -StorageAccountName 'zctfpfixturestore' -ResourceId $fixtureStorageId -AssignmentId $fixtureAssignmentId -MemberReferenceId 'add-costcentre-tag-member' -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 }
        $scanCall = @($script:fixtureAzureCalls | Where-Object { $_ -join ' ' -like 'policy state trigger-scan*' } | Select-Object -First 1)[0]
        $stateCall = @($script:fixtureAzureCalls | Where-Object { $_ -join ' ' -like 'policy state list*' } | Select-Object -First 1)[0]
        Assert-Fixture ($fixtureScanOk -and ($scanCall -join ' ') -ceq "policy state trigger-scan --resource-group rg-zctfp-fixture --no-wait --subscription $($script:approvedSubscriptionId)" -and ($stateCall -join ' ') -ceq "policy state list --resource $fixtureStorageId --filter policyAssignmentId eq '$fixtureAssignmentId' and policyDefinitionReferenceId eq 'add-costcentre-tag-member' --subscription $($script:approvedSubscriptionId)") 'complete profile scans only its run-owned resource group and reads the exact resource, assignment and initiative member state'
        Assert-Fixture (Wait-TargetNonCompliantPolicyState -ResourceGroupName 'rg-zctfp-fixture' -StorageAccountName 'zctfpfixturestore' -ResourceId $fixtureStorageId -AssignmentId $fixtureAssignmentId -MemberReferenceId 'add-costcentre-tag-member' -NotBeforeUtc '2026-10-01T21:00:00Z' -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 }) 'fresh exact policy state is accepted after its mutation boundary'
        $script:testFailed = $false
        Assert-Fixture (-not (Wait-TargetNonCompliantPolicyState -ResourceGroupName 'rg-zctfp-fixture' -StorageAccountName 'zctfpfixturestore' -ResourceId $fixtureStorageId -AssignmentId $fixtureAssignmentId -MemberReferenceId 'add-costcentre-tag-member' -NotBeforeUtc '2026-10-01T23:00:00Z' -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 })) 'stale policy state is rejected after a newer mutation boundary'
        $script:testFailed = $false
        $script:fixturePolicyState[0].complianceState = 'Compliant'
        $script:testFailed = $false
        $compliantRejected = -not (Wait-TargetNonCompliantPolicyState -ResourceGroupName 'rg-zctfp-fixture' -StorageAccountName 'zctfpfixturestore' -ResourceId $fixtureStorageId -AssignmentId $fixtureAssignmentId -MemberReferenceId 'add-costcentre-tag-member' -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 })
        Assert-Fixture ($compliantRejected -and $script:testFailed) 'a Compliant or unrelated policy state blocks remediation'
        $script:testFailed = $false
        Assert-Fixture (Wait-TargetNonCompliantPolicyState -ResourceGroupName 'rg-zctfp-fixture' -StorageAccountName 'zctfpfixturestore' -ResourceId $fixtureStorageId -AssignmentId $fixtureAssignmentId -MemberReferenceId 'add-costcentre-tag-member' -ExpectedComplianceState Compliant -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 }) 'the same exact target and initiative member can verify post-remediation Compliant state'
        $script:fixturePolicyState[0].complianceState = 'NonCompliant'
        $script:testFailed = $false

        $script:fixtureStorageState = 'untagged'
        Assert-Fixture (Assert-StorageTagInitiallyAbsent -StorageAccountName 'fixture' -ResourceGroupName 'rg-zctfp-fixture' -TagName 'CostCentre' -OwnerValue 'terraform') 'pre-remediation storage has no CostCentre and retains Owner'
        Assert-Fixture (Assert-StorageTagAbsent -StorageAccountName 'fixture' -ResourceGroupName 'rg-zctfp-fixture' -TagName 'CostCentre' -OwnerValue 'terraform') 'policy re-enforcement fixture keeps Owner while the policy tag is deliberately absent'
        $script:fixtureStorageState = 'tagged'
        $script:testFailed = $false
        Assert-Fixture (-not (Assert-StorageTagAbsent -StorageAccountName 'fixture' -ResourceGroupName 'rg-zctfp-fixture' -TagName 'CostCentre' -OwnerValue 'terraform') -and $script:testFailed) 'policy tag re-enforcement rejects a target that remains tagged before the repeat remediation'
        $script:testFailed = $false
        $script:fixtureStorageState = 'tagged'
        Assert-Fixture (Wait-StorageTagValue -StorageAccountName 'fixture' -ResourceGroupName 'rg-zctfp-fixture' -Settings @{ IntervalSeconds = 0; RetryLimit = 1; DeadlineSeconds = 0 }) 'post-remediation storage has policy CostCentre and retained Owner'

        $fixtureExemptionId = $status['createdResourceIds']['exemptions'][0]
        Assert-Fixture (Assert-ExemptionState -Label 'fixture exemption' -ResourceGroupName 'rg-zctfp-fixture' -AssignmentId $assignmentId -ExemptionId $fixtureExemptionId -ExpectedExpiryDate '2027-05-01T00:00:00Z') 'exemption read-back requires captured ID, assignment, exact expiry and governance metadata'
        $script:fixtureExemptions[0].expiresOn = '2027-05-01T01:00:00Z'
        $script:testFailed = $false
        Assert-Fixture (-not (Assert-ExemptionState -Label 'fixture exemption' -ResourceGroupName 'rg-zctfp-fixture' -AssignmentId $assignmentId -ExemptionId $fixtureExemptionId -ExpectedExpiryDate '2027-05-01T00:00:00Z') -and $script:testFailed) 'same-date but different exemption expiry is rejected'
        $script:fixtureExemptions[0].expiresOn = '2027-05-01T00:00:00Z'
        $script:testFailed = $false
        $script:fixtureExemptions = @()
        Assert-Fixture (Assert-ExemptionAbsent -ResourceGroupName 'rg-zctfp-fixture' -AssignmentId $assignmentId -ExemptionId $status['createdResourceIds']['exemptions'][0]) 'removed exemption read-back accepts an empty resource-group exemption list'
        $script:fixtureExemptions = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-policy-exemption-list.json') -Raw | ConvertFrom-Json
        $script:testFailed = $false
        Assert-Fixture (-not (Assert-ExemptionAbsent -ResourceGroupName 'rg-zctfp-fixture' -AssignmentId $assignmentId -ExemptionId $status['createdResourceIds']['exemptions'][0]) -and $script:testFailed) 'removed exemption check rejects the captured exemption or assignment when it remains present'
        $script:testFailed = $false

        $deleteMap = @{
            exemptions = 'policy exemption delete'
            remediations = 'policy remediation delete'
            assignments = 'policy assignment delete'
            role_assignments = 'role assignment delete'
            set_definition_id = 'policy set-definition delete'
            definition_ids = 'policy definition delete'
        }
        foreach ($class in $deleteMap.Keys) {
            $id = @($status['createdResourceIds'][$class])[0]
            if (-not $id) { continue }
            $command = (Get-PolicyDeleteArguments -ResourceId $id -Status @{ subscriptionId = $script:approvedSubscriptionId; targetResourceGroupName = 'rg-zctfp-fixture'; profile = 'complete' }) -join ' '
            Assert-Fixture ($command.StartsWith($deleteMap[$class] + ' ', [System.StringComparison]::Ordinal)) "captured $class ID maps to its exact allowlisted CLI delete command"
        }
        $minimalAssignment = Get-Content -LiteralPath (Join-Path $fixtureRoot 'az-policy-assignment-minimal.json') -Raw | ConvertFrom-Json
        $minimalDelete = Get-PolicyDeleteArguments -ResourceId $minimalAssignment.id -Status @{ subscriptionId = $script:approvedSubscriptionId; targetResourceGroupName = $null; profile = 'minimal' }
        Assert-Fixture (($minimalDelete -join ' ') -match '^policy assignment delete --name audit-sub-subscription-built-in-audit --scope /subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa ') 'minimal subscription-scoped assignment cleanup uses its exact name and scope'
        $supplementalStorageId = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-zctfp-r1234567890a-sup/providers/Microsoft.Storage/storageAccounts/zctfpr1234567890asup'
        $supplementalStatus = @{ subscriptionId = $script:approvedSubscriptionId; targetResourceGroupName = 'rg-zctfp-r1234567890a-sup'; targetResourceId = $supplementalStorageId; profile = 'supplemental' }
        $resourceAssignmentId = "$supplementalStorageId/providers/Microsoft.Authorization/policyAssignments/dine-resource-resource-storage-dine-storage-tag"
        $resourceAssignmentDelete = Get-PolicyDeleteArguments -ResourceId $resourceAssignmentId -Status $supplementalStatus
        Assert-Fixture (($resourceAssignmentDelete -join ' ') -ceq "policy assignment delete --name dine-resource-resource-storage-dine-storage-tag --scope $supplementalStorageId --subscription $($script:approvedSubscriptionId) --output none") 'supplemental resource-scope assignment cleanup uses only the exact target resource scope'
        $resourceRemediationId = "$supplementalStorageId/providers/Microsoft.PolicyInsights/remediations/dine-resource-remediate"
        $resourceRemediationDelete = Get-PolicyDeleteArguments -ResourceId $resourceRemediationId -Status $supplementalStatus
        Assert-Fixture (($resourceRemediationDelete -join ' ') -ceq "policy remediation delete --name dine-resource-remediate --resource $supplementalStorageId --subscription $($script:approvedSubscriptionId) --output none") 'supplemental resource-scope remediation cleanup uses the exact resource argument'
        $foreignResourceScopeRejected = $false
        try { Get-PolicyDeleteArguments -ResourceId ($supplementalStorageId.Replace('zctfpr1234567890asup', 'foreignstorage') + '/providers/Microsoft.Authorization/policyAssignments/foreign') -Status $supplementalStatus | Out-Null }
        catch { $foreignResourceScopeRejected = $_.Exception.Message -like '*unsupported subscription-scoped delete contract*' }
        Assert-Fixture $foreignResourceScopeRejected 'supplemental resource-scope cleanup rejects assignments outside the captured target resource'
        Assert-Fixture (Test-MinimalAssignmentDocument -Document $minimalAssignment -AssignmentId $minimalAssignment.id -ExpectedScope '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -ExpectedName 'audit-sub-subscription-built-in-audit' -ExpectedOwner 'platform-governance') 'minimal assignment read-back fixture covers stable name, default owner and scope'
        Assert-Fixture (Assert-MinimalAssignment -AssignmentId $minimalAssignment.id -ExpectedScope '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -ExpectedName 'audit-sub-subscription-built-in-audit' -ExpectedOwner 'platform-governance') 'minimal assignment CLI read-back matches the document contract'
        $minimalAssignmentRead = @($script:fixtureAzureCalls | Where-Object { ($_ -join ' ') -like 'policy assignment show*' } | Select-Object -Last 1)[0]
        Assert-Fixture (($minimalAssignmentRead -join ' ') -ceq "policy assignment show --name audit-sub-subscription-built-in-audit --scope /subscriptions/$($script:approvedSubscriptionId) --subscription $($script:approvedSubscriptionId)") 'minimal assignment read uses its exact name, scope and subscription'
        Assert-Fixture (-not (Test-MinimalAssignmentDocument -Document $minimalAssignment -AssignmentId $minimalAssignment.id -ExpectedScope '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -ExpectedName 'audit-sub-subscription-built-in-audit' -ExpectedOwner 'security-governance')) 'minimal assignment owner read-back detects drift until update is applied'
        $minimalStatus = @{ profile = 'minimal'; assignmentScopeId = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; terraformVars = @{ assignment_key = 'audit-sub-replacement'; assignment_owner = 'security-governance'; create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '' } }
        $minimalArgs = Get-StageVarArguments -Status $minimalStatus
        Assert-Fixture (($minimalArgs -join ' ') -match 'assignment_key=audit-sub-replacement' -and ($minimalArgs -join ' ') -match 'assignment_owner=security-governance') 'minimal lifecycle passes its replacement key and owner through provider plans/applies'

        $script:fixtureStateJson = @{
            values = @{
                root_module = @{
                    resources = @(
                        @{ mode = 'managed'; type = 'terraform_data'; address = 'module.framework.module.assignments.terraform_data.contract_guard["audit-sub"]'; values = @{ id = '11111111-1111-1111-1111-111111111111' } },
                        @{ mode = 'managed'; type = 'azurerm_subscription_policy_assignment'; address = 'module.framework.module.assignments.azurerm_subscription_policy_assignment.this["audit-sub"]'; values = @{ id = $minimalAssignment.id } }
                    )
                    child_modules = @()
                }
            }
        }
        $minimalStateStatus = @{
            exampleRoot = Join-Path $script:repoRoot 'examples/minimal-audit-assignment'
            profile = 'minimal'; terraformWorkspace = $workspaceName; subscriptionId = $script:approvedSubscriptionId
            createdResourceIds = @{ assignments = @($minimalAssignment.id) }
        }
        Assert-Fixture (Test-RunWorkspaceState -Status $minimalStateStatus) 'minimal state accepts only its reviewed assignment and contract guard addresses'
        $replacementMinimalId = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/policyAssignments/audit-sub-replacement-subscription-built-in-audit'
        $script:fixtureStateJson.values.root_module.resources[0].address = 'module.framework.module.assignments.terraform_data.contract_guard["audit-sub-replacement"]'
        $script:fixtureStateJson.values.root_module.resources[1].address = 'module.framework.module.assignments.azurerm_subscription_policy_assignment.this["audit-sub-replacement"]'
        $script:fixtureStateJson.values.root_module.resources[1].values.id = $replacementMinimalId
        $minimalStateStatus['createdResourceIds']['assignments'] += $replacementMinimalId
        Assert-Fixture (Test-RunWorkspaceState -Status $minimalStateStatus) 'minimal state allowlist accepts the explicit key-migration replacement address and ID'
        $script:fixtureStateJson.values.root_module.resources[0].address = 'module.framework.module.assignments.terraform_data.contract_guard["audit-sub"]'
        $script:fixtureStateJson.values.root_module.resources[1].address = 'module.framework.module.assignments.azurerm_subscription_policy_assignment.this["audit-sub"]'
        $script:fixtureStateJson.values.root_module.resources[1].values.id = $minimalAssignment.id
        $script:fixtureStateJson.values.root_module.resources[1].type = 'azurerm_management_group_policy_assignment'
        $script:fixtureStateJson.values.root_module.resources[1].address = 'module.framework.module.assignments.azurerm_management_group_policy_assignment.this["foreign"]'
        $script:fixtureStateJson.values.root_module.resources[1].values.id = '/providers/Microsoft.Management/managementGroups/foreign/providers/Microsoft.Authorization/policyAssignments/foreign'
        Assert-Fixture (-not (Test-RunWorkspaceState -Status $minimalStateStatus)) 'unsupported management-group state resource and ID are rejected'
        $script:fixtureStateJson.values.root_module.resources[1].type = 'azurerm_subscription_policy_assignment'
        $script:fixtureStateJson.values.root_module.resources[1].address = 'module.framework.module.assignments.azurerm_subscription_policy_assignment.this["audit-sub"]'
        $script:fixtureStateJson.values.root_module.resources[1].values.id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/audit-sub-subscription-built-in-audit'
        Assert-Fixture (-not (Test-RunWorkspaceState -Status $minimalStateStatus)) 'reviewed Azure resource address with a foreign subscription ID is rejected'
        # Complete profile: the reviewed content, identity, assignment and operations
        # addresses and every contract guard are accepted; a retired module address is not.
        $savedFixtureState = $script:fixtureStateJson
        $script:fixtureStateJson = $script:fixtureCompleteState
        $completeStateResources = [System.Collections.Generic.List[object]]::new()
        Add-StateModuleResources -Module $script:fixtureCompleteState.values.root_module -Resources $completeStateResources
        $completeStateIds = @($completeStateResources | ForEach-Object { "$($_.values.id)" } | Where-Object { $_ -like '/subscriptions/*' })
        $completeStateStatus = @{
            exampleRoot = Join-Path $script:repoRoot 'examples/complete-policy-lifecycle'
            profile = 'complete'; terraformWorkspace = $workspaceName; subscriptionId = $script:approvedSubscriptionId
            createdResourceIds = @{ fixture = $completeStateIds }
        }
        Assert-Fixture (Test-RunWorkspaceState -Status $completeStateStatus) 'complete state accepts only its reviewed module addresses and contract guards'
        $retiredGuard = @($completeStateResources | Where-Object { $_.address -like '*exemption_contract_guard' })[0]
        $retiredGuard.address = 'module.framework.module.exemptions.terraform_data.contract_guard'
        Assert-Fixture (-not (Test-RunWorkspaceState -Status $completeStateStatus)) 'complete state rejects a guard address from the retired exemptions module'
        $retiredGuard.address = 'module.framework.module.operations.terraform_data.exemption_contract_guard'
        $script:fixtureStateJson = $savedFixtureState
        $invalidResourceIds = @(
            @{ Id = '/subscriptions/other/resourceGroups/rg-zctfp-fixture/providers/Microsoft.Authorization/policyAssignments/x'; Expected = '*out-of-scope*' },
            @{ Id = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/foreign/providers/Microsoft.Authorization/policyAssignments/x'; Expected = '*unsupported subscription-scoped delete contract*' },
            @{ Id = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/unknownResources/x'; Expected = '*unsupported subscription-scoped delete contract*' }
        )
        $invalidIdsRejected = $true
        foreach ($invalid in $invalidResourceIds) {
            try {
                Get-PolicyDeleteArguments -ResourceId $invalid.Id -Status @{ subscriptionId = $script:approvedSubscriptionId; targetResourceGroupName = 'rg-zctfp-fixture'; profile = 'complete' } | Out-Null
                $invalidIdsRejected = $false
            }
            catch {
                if ($_.Exception.Message -notlike $invalid.Expected) { $invalidIdsRejected = $false }
            }
        }
        Assert-Fixture $invalidIdsRejected 'unsupported resource types, foreign resource groups and other subscriptions fail closed with scope-specific diagnostics'
        $partialStateResources = [System.Collections.Generic.List[object]]::new()
        $partialState = [pscustomobject]@{ child_modules = @([pscustomobject]@{ address = 'module.framework'; resources = @([pscustomobject]@{ mode = 'managed'; type = 'terraform_data'; address = 'module.framework.module.assignments.terraform_data.contract_guard["audit-sub"]' }) }) }
        Add-StateModuleResources -Module $partialState -Resources $partialStateResources
        Assert-Fixture ($partialStateResources.Count -eq 1 -and $partialStateResources[0].type -eq 'terraform_data') 'Terraform state modules tolerate omitted root resources and omitted leaf child_modules properties'
        $priorArmSubscription = $env:ARM_SUBSCRIPTION_ID
        try {
            $env:ARM_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000000'
            $providerContextRejected = $false
            try { Assert-ApprovedAzureContext }
            catch { $providerContextRejected = $_.Exception.Message -like '*ARM_SUBSCRIPTION_ID*' }
            Assert-Fixture $providerContextRejected 'Terraform provider subscription override outside the approved UAT is rejected'
        }
        finally { $env:ARM_SUBSCRIPTION_ID = $priorArmSubscription }

        $fingerprintRoot = Join-Path $runDirectory 'fingerprint-source'
        foreach ($dir in @('modules/policy', 'examples/demo', 'tests/integration/artifacts')) { New-Item -ItemType Directory -Force -Path (Join-Path $fingerprintRoot $dir) | Out-Null }
        $payloadPath = Join-Path $fingerprintRoot 'modules/policy/payload.json'
        $orchestrationPath = Join-Path $fingerprintRoot 'tests/integration/run-live.ps1'
        $ignoredArtifactPath = Join-Path $fingerprintRoot 'tests/integration/artifacts/runtime.json'
        [System.IO.File]::WriteAllText($payloadPath, '{"effect":"Modify"}')
        [System.IO.File]::WriteAllText($orchestrationPath, 'Write-Output one')
        [System.IO.File]::WriteAllText($ignoredArtifactPath, 'runtime one')
        $fingerprintBefore = Get-SourceFingerprint -Root $fingerprintRoot
        [System.IO.File]::WriteAllText($payloadPath, '{"effect":"Audit"}')
        $fingerprintAfterPayload = Get-SourceFingerprint -Root $fingerprintRoot
        [System.IO.File]::WriteAllText($orchestrationPath, 'Write-Output two')
        $fingerprintAfterOrchestration = Get-SourceFingerprint -Root $fingerprintRoot
        [System.IO.File]::WriteAllText($ignoredArtifactPath, 'runtime two')
        $fingerprintAfterArtifact = Get-SourceFingerprint -Root $fingerprintRoot
        Assert-Fixture ($fingerprintBefore -ne $fingerprintAfterPayload -and $fingerprintAfterPayload -ne $fingerprintAfterOrchestration -and $fingerprintAfterOrchestration -eq $fingerprintAfterArtifact) 'source fingerprint includes policy JSON and orchestration but excludes runtime artifacts'

        $emptyStateFixture = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-empty-state.json') -Raw | ConvertFrom-Json
        $nonemptyStateFixture = Get-Content -LiteralPath (Join-Path $fixtureRoot 'terraform-nonempty-state.json') -Raw | ConvertFrom-Json
        Assert-Fixture (Test-EmptyTerraformStateDocument -StateDocument $emptyStateFixture) 'valid empty default state is distinguished from a populated state'
        Assert-Fixture (-not (Test-EmptyTerraformStateDocument -StateDocument $nonemptyStateFixture)) 'nonempty default state fails the isolated workspace preflight'
        $freshWorkspaceStatePath = Join-Path $runDirectory 'fresh-workspace/terraform.tfstate'
        $noStateListResult = @{ ExitCode = 1; Output = @('No state file was found!', 'System.Management.Automation.RemoteException', 'State management commands require a state file. Run this command', 'in a directory where Terraform has been run or use the -state flag', 'to point the command to a specific state location.') }
        Assert-Fixture (Test-NewWorkspaceEmpty -WorkspaceCreated $true -StatePath $freshWorkspaceStatePath -StateListResult $noStateListResult) 'newly-created workspace with the exact Terraform 1.15.9 no-state diagnostic and absent canonical state file is accepted'
        Assert-Fixture (Test-MissingLocalStateDiagnostic -StatePath $freshWorkspaceStatePath -StateListResult $noStateListResult) 'a fresh default workspace may have no local state file when Terraform reports its exact no-state diagnostic'
        $legacyNoStateListResult = @{ ExitCode = 1; Output = @('No state file was found!', 'System.Management.Automation.RemoteException', 'State management commands require a state file. Run this command', 'in a directory where Terraform has been run or use the -state flag', 'to point to a specific state location.') }
        Assert-Fixture (Test-NewWorkspaceEmpty -WorkspaceCreated $true -StatePath $freshWorkspaceStatePath -StateListResult $legacyNoStateListResult) 'previously captured exact no-state diagnostic variant remains accepted'
        Assert-Fixture (-not (Test-NewWorkspaceEmpty -WorkspaceCreated $false -StatePath $freshWorkspaceStatePath -StateListResult $noStateListResult)) 'stale or recovery workspace cannot use the new-workspace no-state exception'
        Assert-Fixture (-not (Test-NewWorkspaceEmpty -WorkspaceCreated $true -StatePath $freshWorkspaceStatePath -StateListResult @{ ExitCode = 1; Output = @('No state file was found!', 'Unexpected state backend error') })) 'unknown state-list failure is not treated as an empty workspace'
        Assert-Fixture (-not (Test-NewWorkspaceEmpty -WorkspaceCreated $true -StatePath $freshWorkspaceStatePath -StateListResult @{ ExitCode = 0; Output = @('module.foreign.azurerm_resource_group.this') })) 'nonempty newly-created workspace is rejected'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $freshWorkspaceStatePath) | Out-Null
        [System.IO.File]::WriteAllText($freshWorkspaceStatePath, '{}')
        Assert-Fixture (-not (Test-NewWorkspaceEmpty -WorkspaceCreated $true -StatePath $freshWorkspaceStatePath -StateListResult $noStateListResult)) 'exact no-state error is rejected when the canonical state file exists'
        $stateDemoRoot = Join-Path $runDirectory 'default-state-preservation'
        New-Item -ItemType Directory -Path $stateDemoRoot | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'terraform-empty-state.json') -Destination (Join-Path $stateDemoRoot 'terraform.tfstate')
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'terraform-nonempty-state.json') -Destination (Join-Path $stateDemoRoot 'terraform.tfstate.backup')
        $stateSnapshotStatus = @{ exampleRoot = $stateDemoRoot; defaultStateSnapshot = @(Get-DefaultStateSnapshot -ExampleRoot $stateDemoRoot) }
        Assert-Fixture (Assert-DefaultStateUnchanged -Status $stateSnapshotStatus) 'default state and prior backup hashes establish a preserved baseline'
        [System.IO.File]::AppendAllText((Join-Path $stateDemoRoot 'terraform.tfstate.backup'), "`n")
        $backupChangeRejected = $false
        try { Assert-DefaultStateUnchanged -Status $stateSnapshotStatus | Out-Null }
        catch { $backupChangeRejected = $_.Exception.Message -like '*changed*' }
        Assert-Fixture $backupChangeRejected 'changed prior Terraform backup hash blocks workspace cleanup'
        Remove-Item -LiteralPath $runDirectory -Recurse -Force
        Write-Host 'HarnessFixtureDemo: all deterministic harness contracts passed; no Azure or Terraform commands were run'
        exit 0
    }
    catch {
        Write-Host $_
        exit 1
    }
}

# StatusPathDemo: deterministic self-test of the R12 status logic. It runs the
# shipped mapping function without touching Azure or Terraform state.
if ($StatusPathDemo) {
    $cases = @(
        @{ TestFailed = $false; CleanupFailed = $false; Expected = 0; Description = 'all passed' }
        @{ TestFailed = $true;  CleanupFailed = $false; Expected = 1; Description = 'failed test with successful cleanup must fail the run' }
        @{ TestFailed = $false; CleanupFailed = $true;  Expected = 2; Description = 'cleanup failure must fail the run' }
        @{ TestFailed = $true;  CleanupFailed = $true;  Expected = 3; Description = 'both failed' }
    )
    $allPassed = $true
    foreach ($case in $cases) {
        $code = ConvertTo-ExitCode -TestFailed:$case.TestFailed -CleanupFailed:$case.CleanupFailed
        $passed = $code -eq $case.Expected
        if (-not $passed) { $allPassed = $false }
        $mark = 'ok'; if (-not $passed) { $mark = 'MISMATCH' }
        Write-Host ("  [{0}] test={1} cleanup={2} -> exit {3} (expected {4}): {5}" -f $mark, $case.TestFailed, $case.CleanupFailed, $code, $case.Expected, $case.Description)
    }
    if ($allPassed) {
        Write-Host 'StatusPathDemo: all status paths behaved as documented'
        exit 0
    }
    Write-Host 'StatusPathDemo: status logic mismatch'
    exit 1
}

# Live path from here on.
try {
    $approved = Read-ApprovedContext -Path $ApprovedContextPath
    $script:approvedContextFile = (Resolve-Path -LiteralPath $ApprovedContextPath).Path
    $script:approvedContextHash = (Get-FileHash -LiteralPath $script:approvedContextFile -Algorithm SHA256).Hash
    $script:approvedSubscriptionId = $approved.subscriptionId
    $script:approvedTenantId = $approved.tenantId
    $script:approvedCloud = $approved.cloud
    $script:approvedUserName = $approved.userName
    $script:approvedUserType = $approved.userType
}
catch { Write-Host "approved context rejected: $($_.Exception.Message)"; exit 1 }

if ($RunId) {
    if ($RunId -notmatch '^[a-z0-9]{1,14}$') {
        Write-Host "RunId '$RunId' must be 1 to 14 lowercase letters or digits so the published UAT names stay valid and attributable"
        exit 1
    }
}
else {
    $RunId = 'r{0:yyMMddHHmmss}' -f (Get-Date).ToUniversalTime()
}

foreach ($tool in @('terraform', 'az')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "required tool '$tool' was not found on PATH"
        exit 1
    }
}

$account = Invoke-AzJson @('account', 'show')
if ($account.ExitCode -ne 0 -or $null -eq $account.Data) {
    Write-Host 'az account show failed; log in with az login and set the authorised subscription first'
    exit 1
}
$script:subscriptionId = "$($account.Data.id)"
$script:tenantId = "$($account.Data.tenantId)"
if ($script:subscriptionId -ine $script:approvedSubscriptionId -or $script:tenantId -ine $script:approvedTenantId) {
    Write-Host "active Azure context rejected: expected tenant $($script:approvedTenantId) and subscription $($script:approvedSubscriptionId)"
    exit 1
}
try { Assert-ApprovedAzureContext }
catch {
    Write-Host "active Azure context rejected: $($_.Exception.Message)"
    exit 1
}

if ($CleanupOnly) {
    if (-not $StatusPath) {
        # RunId was defaulted above, so only a caller-supplied value counts here.
        if (-not $PSBoundParameters.ContainsKey('RunId')) { Write-Host 'CleanupOnly requires RunId or an explicit StatusPath'; exit 2 }
        $StatusPath = Join-Path $ArtifactRoot (Join-Path $RunId 'run-status.json')
    }
    elseif (-not [System.IO.Path]::IsPathRooted($StatusPath)) { $StatusPath = Join-Path $script:repoRoot $StatusPath }
    exit (Invoke-RecordedCleanup -Path $StatusPath)
}

if ([System.IO.Path]::IsPathRooted($ExampleRoot)) {
    $exampleRootResolved = (Resolve-Path -LiteralPath $ExampleRoot).Path
}
else {
    $exampleRootResolved = (Resolve-Path -LiteralPath (Join-Path $script:repoRoot $ExampleRoot)).Path
}
if (-not (Test-Path -LiteralPath (Join-Path $exampleRootResolved 'main.tf'))) {
    Write-Host "example root '$exampleRootResolved' does not contain main.tf"
    exit 1
}
$profileName = [System.IO.Path]::GetFileName($exampleRootResolved)
if ($profileName -eq 'complete-policy-lifecycle') { $runProfile = 'complete' }
elseif ($profileName -eq 'minimal-audit-assignment') { $runProfile = 'minimal' }
else {
    Write-Host "unsupported live example '$profileName'; only the published minimal and complete examples have reviewed lifecycle contracts"
    exit 1
}
if ($RecoveryProbe -and ($runProfile -ne 'complete' -or $SkipApply)) {
    Write-Host 'RecoveryProbe requires the complete-policy-lifecycle profile and cannot be combined with SkipApply'
    exit 1
}

if ($runProfile -eq 'minimal' -and ($VarFile -eq 'environments/uat/uat.tfvars' -or [string]::IsNullOrWhiteSpace($VarFile))) {
    $varFileResolved = $null
}
elseif ([System.IO.Path]::IsPathRooted($VarFile)) {
    $varFileResolved = (Resolve-Path -LiteralPath $VarFile).Path
}
else {
    $varFileResolved = (Resolve-Path -LiteralPath (Join-Path $exampleRootResolved $VarFile)).Path
}
if ($runProfile -eq 'complete' -and -not (Test-Path -LiteralPath $varFileResolved)) {
    Write-Host "variable file '$varFileResolved' does not exist; prepare it from the uat terraform.tfvars.example template"
    exit 1
}
if ($runProfile -eq 'minimal' -and $varFileResolved -and -not (Test-Path -LiteralPath $varFileResolved)) {
    Write-Host "variable file '$varFileResolved' does not exist"
    exit 1
}

if (-not $StatusPath) {
    $StatusPath = Join-Path (Join-Path $ArtifactRoot $RunId) 'run-status.json'
}
elseif (-not [System.IO.Path]::IsPathRooted($StatusPath)) {
    $StatusPath = Join-Path $script:repoRoot $StatusPath
}

$runDir = Split-Path -Parent $StatusPath
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$script:logPath = Join-Path $runDir 'run.log'
$script:statusPath = $StatusPath

if (Test-Path -LiteralPath $StatusPath) {
    Write-Host "a run status record already exists at '$StatusPath'; choose a new RunId or resume cleanup with -CleanupOnly"
    exit 1
}

$protectedVarFile = Join-Path $runDir 'run-input.tfvars'
if ($varFileResolved -and [System.IO.Path]::GetFullPath($varFileResolved) -ieq [System.IO.Path]::GetFullPath($protectedVarFile)) {
    # Input preparation may place the new ignored source directly in the
    # run's artifact directory. Treat it as the protected source snapshot and
    # never copy a file onto itself or overwrite a prior snapshot.
    $varFileResolved = $protectedVarFile
}
elseif ($varFileResolved) {
    if (Test-Path -LiteralPath $protectedVarFile) { Write-Host "protected run input already exists at '$protectedVarFile'; refusing to overwrite it"; exit 1 }
    Copy-Item -LiteralPath $varFileResolved -Destination $protectedVarFile -ErrorAction Stop
}
else { [System.IO.File]::WriteAllText($protectedVarFile, "", [System.Text.UTF8Encoding]::new($false)) }
$varFileResolved = $protectedVarFile

$protectedContextFile = Join-Path $runDir 'approved-context.json'
if (Test-Path -LiteralPath $protectedContextFile) { Write-Host 'protected approved context already exists; refusing to overwrite it'; exit 1 }
Assert-ApprovedContextPinned
Copy-Item -LiteralPath $script:approvedContextFile -Destination $protectedContextFile -ErrorAction Stop
if ((Get-FileHash -LiteralPath $protectedContextFile -Algorithm SHA256).Hash -cne $script:approvedContextHash) { throw 'approved context changed during snapshot capture' }
$script:approvedContextFile = [System.IO.Path]::GetFullPath($protectedContextFile)

$runStatus = @{
    approvedContextPath      = $script:approvedContextFile
    approvedContextSha256    = $script:approvedContextHash
    runId                    = $RunId
    profile                  = $runProfile
    exampleRoot              = $exampleRootResolved
    varFile                  = $varFileResolved
    # Fixed once per run: timestamp() is unknown at plan time, so the status
    # outputs would churn on every plan without a deterministic evaluation
    # instant. Every terraform invocation passes -var evaluation_time with it.
    evaluationTime           = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    terraformVars            = @{ create_exemption = 'false'; exemption_assignment_id = ''; exemption_expiry = '2027-01-31T00:00:00Z'; assignment_scope_id = ''; assignment_key = 'audit-sub'; assignment_owner = 'platform-governance' }
    createdResourceIds       = @{}
    appliedStages            = @()
    mutationStarted          = $false
    recoveryProbe            = [bool]$RecoveryProbe
    recoveryPausePending     = [bool]$RecoveryProbe
    intentionalFailure       = $false
    testCompleted            = $false
    cleanupOnlyResume        = $false
    targetResourceGroupName  = $null
    targetStorageAccountName = $null
    renewalExpiry            = $null
    subscriptionId           = $script:subscriptionId
    tenantId                 = $script:tenantId
    sourceFingerprint        = Get-SourceFingerprint -Root $script:repoRoot
    varFileSha256            = (Get-FileHash -LiteralPath $varFileResolved -Algorithm SHA256).Hash
    expectedResourceClasses  = @()
    providerPlanEvidence     = @()
    resolvedAssignmentReview = @{}
    defaultStateSnapshot     = @()
    runDirectory             = $runDir
    assignmentScopeId        = $null
}

if ($runProfile -eq 'complete') {
    # R9 sequencing guard: the harness enables exemptions only after
    # remediation has been observed, so a user file cannot pre-enable it.
    if (Get-VarFileSwitch -Path $varFileResolved -Name 'create_exemption') {
        Write-Host "create_exemption must be false in the variable file; the harness creates the exemption in stage 2"
        exit 1
    }
    if (Get-VarFileValue -Path $varFileResolved -Name 'exemption_assignment_id') {
        Write-Host "exemption_assignment_id must be absent from the variable file; the harness resolves it from stage 1 outputs"
        exit 1
    }

    $targetRgName = Get-VarFileValue -Path $varFileResolved -Name 'target_resource_group_name'
    $targetStorage = Get-VarFileValue -Path $varFileResolved -Name 'target_storage_account_name'
    $targetRgId = Get-VarFileValue -Path $varFileResolved -Name 'target_resource_group_id'
    $policySubscriptionId = Get-VarFileValue -Path $varFileResolved -Name 'policy_subscription_id'
    $runStatus['terraformVars']['exemption_expiry'] = Get-VarFileExpiry -Path $varFileResolved -Default '2027-01-31T00:00:00Z'
    if (-not $targetRgName -or -not $targetStorage -or -not $targetRgId) {
        Write-Host 'the variable file must set target_resource_group_name, target_storage_account_name and target_resource_group_id'
        exit 1
    }
    if ($policySubscriptionId -ine $script:subscriptionId) {
        Write-Host 'policy_subscription_id must exactly match the active approved UAT subscription'
        exit 1
    }
    if ($targetRgName -cne "rg-zctfp-$RunId" -or $targetStorage -cne "zctfp${RunId}store" -or (Get-VarFileValue -Path $varFileResolved -Name 'identity_resource_group_name') -cne $targetRgName) {
        Write-Host 'target group, storage account and identity group names must exactly match this RunId profile (rg-zctfp-<RunId>, zctfp<RunId>store, same group for identity)'
        exit 1
    }
    if ($targetRgId.TrimEnd('/') -ine "/subscriptions/$($script:subscriptionId)/resourceGroups/$targetRgName") {
        Write-Host 'target_resource_group_id must identify this run-owned resource group in the approved subscription'
        exit 1
    }
    $runStatus['targetResourceGroupName'] = $targetRgName
    $runStatus['targetStorageAccountName'] = $targetStorage
    $runStatus['expectedResourceClasses'] = @('assignments', 'identities', 'role_assignments', 'remediations', 'exemptions', 'definition_ids', 'set_definition_id')
}
else {
    $targetRgName = $null
    $targetStorage = $null
    $targetRgId = "/subscriptions/$($script:subscriptionId)"
    $configuredScope = Get-VarFileValue -Path $varFileResolved -Name 'assignment_scope_id'
    if ($configuredScope -and $configuredScope.TrimEnd('/') -ine $targetRgId) {
        Write-Host 'minimal example assignment_scope_id must exactly match the approved subscription scope'
        exit 1
    }
    $runStatus['assignmentScopeId'] = $targetRgId
    $configuredDefinitionId = Get-VarFileValue -Path $varFileResolved -Name 'built_in_audit_definition_id'
    $definitionIdDeclared = Select-String -LiteralPath $varFileResolved -Pattern '^\s*built_in_audit_definition_id\s*=' -Quiet
    if ($definitionIdDeclared -and -not $configuredDefinitionId) {
        Write-Host 'minimal example built_in_audit_definition_id must be a quoted literal in the protected variable file for live read-back'
        exit 1
    }
    $runStatus['builtInAuditDefinitionId'] = if ($configuredDefinitionId) { $configuredDefinitionId } else { '/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d' }
    $runStatus['terraformVars']['assignment_scope_id'] = $targetRgId
    $runStatus['expectedResourceClasses'] = @('assignments')
}

try { $defaultStateSnapshot = @(Get-DefaultStateSnapshot -ExampleRoot $exampleRootResolved) }
catch {
    Write-Host "default Terraform state preflight failed: $($_.Exception.Message)"
    exit 1
}
$runStatus['defaultStateSnapshot'] = $defaultStateSnapshot
if ($RenewalExpiry) {
    $runStatus['renewalExpiry'] = ConvertTo-Rfc3339Expiry $RenewalExpiry
}
else {
    # Computed once per run and persisted so repeated plans converge on it,
    # and never moved backward relative to the persisted input (J8): a
    # candidate earlier than the current expiry renews the current expiry
    # forward by a further 90 days instead.
    $candidateRenewal = (Get-Date).ToUniversalTime().Date.AddDays(90)
    try { $currentExpiry = [datetimeoffset]::Parse($fileExpiry).UtcDateTime } catch { $currentExpiry = $candidateRenewal }
    if ($candidateRenewal -gt $currentExpiry) {
        $runStatus['renewalExpiry'] = $candidateRenewal.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    else {
        $runStatus['renewalExpiry'] = $currentExpiry.AddDays(90).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}

try {
    Write-RunLog "harness run '$RunId' against example root '$exampleRootResolved'"

    try {
        $script:mutationLockStream = [System.IO.File]::Open($script:mutationLockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $lockText = [System.Text.Encoding]::UTF8.GetBytes("$RunId`n$($script:tenantId)`n$($script:subscriptionId)")
        $script:mutationLockStream.Write($lockText, 0, $lockText.Length)
        $script:mutationLockStream.Flush()
    }
    catch {
        throw 'another live run holds the UAT mutation lock; no Azure changes were started'
    }

    # Pre-test inventory: baseline for preservation claims and cleanup
    # attribution; written locally, redacted, never committed.
    foreach ($inventory in @(
            @{ Name = 'inventory-before-groups.json'; Args = @('group', 'list') },
            @{ Name = 'inventory-before-policy-assignments.json'; Args = @('policy', 'assignment', 'list') }
        )) {
        $snapshot = Invoke-AzJson $inventory.Args
        $path = Join-Path $runDir $inventory.Name
        if ($snapshot.ExitCode -ne 0 -or $null -eq $snapshot.Data) { throw "pre-run $($inventory.Name) inventory failed; refusing to mutate without a baseline" }
        Set-Content -LiteralPath $path -Value (ConvertTo-Json -InputObject @($snapshot.Data) -Depth 30) -Encoding utf8
        Write-RunLog "pre-test inventory written to $path"
    }
    foreach ($inventory in @(
            @{ Name = 'inventory-before-definitions.json'; Args = @('policy', 'definition', 'list', '--query', "[?policyType=='Custom']") },
            @{ Name = 'inventory-before-initiatives.json'; Args = @('policy', 'set-definition', 'list', '--query', "[?policyType=='Custom']") }
        )) {
        $snapshot = Invoke-AzJson $inventory.Args
        if ($snapshot.ExitCode -ne 0 -or $null -eq $snapshot.Data) { throw "pre-run $($inventory.Name) inventory failed; refusing to mutate without a baseline" }
        Set-Content -LiteralPath (Join-Path $runDir $inventory.Name) -Value (ConvertTo-Json -InputObject @($snapshot.Data) -Depth 30) -Encoding utf8
        Write-RunLog "pre-test inventory written to $($inventory.Name)"
    }

    $assignmentsBaseline = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $runDir 'inventory-before-policy-assignments.json') -Raw) -NoEnumerate
    $definitionsBaseline = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $runDir 'inventory-before-definitions.json') -Raw) -NoEnumerate
    $initiativesBaseline = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $runDir 'inventory-before-initiatives.json') -Raw) -NoEnumerate
    Assert-NoPreexistingResourceCollisions `
        -Profile $runProfile `
        -AssignmentScopeId $runStatus['assignmentScopeId'] `
        -TargetResourceGroupName $targetRgName `
        -TargetStorageAccountName $targetStorage `
        -AssignmentsBaseline $assignmentsBaseline `
        -DefinitionsBaseline $definitionsBaseline `
        -InitiativesBaseline $initiativesBaseline
    Save-RunStatus -Status $runStatus

    if ($SkipApply) {
        Write-RunLog 'SkipApply: preflight and inventory only; no applies, no assertions, no cleanup'
        return
    }

    $tfRoot = '-chdir=' + $exampleRootResolved
    $runStatus['varFile'] = $varFileResolved
    $baseArgs = Get-TerraformBaseArguments -Status $runStatus

    $init = Invoke-Terraform -TerraformArguments (Get-BackendDisabledInitArguments -ExampleRoot $exampleRootResolved)
    if ($init.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog 'terraform init failed'
        return
    }
    Initialize-RunWorkspace -Status $runStatus

    if ($runProfile -eq 'minimal') {
        Write-RunLog 'minimal example: create the subscription Audit assignment'
        $applyMinimal = Invoke-TrackedApply -Status $runStatus -Stage 'minimal-apply' -TerraformArguments (@($tfRoot, 'apply', '-auto-approve') + $baseArgs)
        if ($applyMinimal.ExitCode -ne 0) {
            $script:testFailed = $true
            Write-RunLog "minimal apply failed with exit code $($applyMinimal.ExitCode)"
            return
        }
        $initialKey = "$($runStatus['terraformVars']['assignment_key'])"
        $initialReview = Get-ResolvedMinimalAssignment -Status $runStatus -AssignmentKey $initialKey
        $initialId = if ($initialReview) { "$($initialReview['assignment_id'])" } else { '' }
        $initialName = if ($initialReview) { "$($initialReview['assignment_name'])" } else { '' }
        if (-not $initialId -or -not $initialName -or -not (Assert-MinimalAssignment -AssignmentId $initialId -ExpectedScope $runStatus['assignmentScopeId'] -ExpectedName $initialName -ExpectedOwner $runStatus['terraformVars']['assignment_owner'] -ExpectedDefinitionId $runStatus['builtInAuditDefinitionId'])) { $script:testFailed = $true; return }
        $runStatus['minimalAssignmentHistory'] = @([ordered]@{ assignmentKey = $initialKey; assignmentId = $initialId; assignmentName = $initialName; owner = $runStatus['terraformVars']['assignment_owner'] })

        # An owner metadata change is an in-place update. Save and inspect the
        # real AzureRM provider plan JSON before applying that exact plan.
        $runStatus['terraformVars']['assignment_owner'] = 'security-governance'
        Save-RunStatus -Status $runStatus
        $assignmentAddress = 'module.framework.module.assignments.azurerm_subscription_policy_assignment.this["audit-sub"]'
        $ownerPlan = Invoke-ReviewedTerraformPlan -Status $runStatus -Stage 'minimal-owner-update' -ExpectedAddressActions @{ $assignmentAddress = @('update') }
        if (-not $ownerPlan) { return }
        $applyOwner = Invoke-TrackedApply -Status $runStatus -Stage 'minimal-owner-update' -TerraformArguments @($tfRoot, 'apply', '-auto-approve', $ownerPlan.Path)
        if ($applyOwner.ExitCode -ne 0) { $script:testFailed = $true; Write-RunLog 'minimal Owner metadata update apply failed'; return }
        $updatedReview = Get-ResolvedMinimalAssignment -Status $runStatus -AssignmentKey $initialKey
        $updatedId = if ($updatedReview) { "$($updatedReview['assignment_id'])" } else { '' }
        $updatedName = if ($updatedReview) { "$($updatedReview['assignment_name'])" } else { '' }
        if ($updatedId -ine $initialId -or -not (Assert-MinimalAssignment -AssignmentId $initialId -ExpectedScope $runStatus['assignmentScopeId'] -ExpectedName $updatedName -ExpectedOwner $runStatus['terraformVars']['assignment_owner'] -ExpectedDefinitionId $runStatus['builtInAuditDefinitionId'])) { $script:testFailed = $true; return }
        $runStatus['minimalAssignmentHistory'] += [ordered]@{ assignmentKey = $initialKey; assignmentId = $updatedId; assignmentName = $updatedName; owner = $runStatus['terraformVars']['assignment_owner'] }
        $convergedUpdate = Invoke-ReviewedTerraformPlan -Status $runStatus -Stage 'minimal-owner-converged' -ExpectedAddressActions @{}
        if (-not $convergedUpdate) { return }

        # Changing the example map key changes both Terraform address and
        # deterministic Azure assignment name. Keep the old ID in the cleanup
        # manifest and verify that Azure removes it after applying the plan.
        $replacementKey = 'audit-sub-replacement'
        $oldAddress = 'module.framework.module.assignments.azurerm_subscription_policy_assignment.this["audit-sub"]'
        $newAddress = 'module.framework.module.assignments.azurerm_subscription_policy_assignment.this["audit-sub-replacement"]'
        $oldGuardAddress = 'module.framework.module.assignments.terraform_data.contract_guard["audit-sub"]'
        $newGuardAddress = 'module.framework.module.assignments.terraform_data.contract_guard["audit-sub-replacement"]'
        $runStatus['terraformVars']['assignment_key'] = $replacementKey
        Save-RunStatus -Status $runStatus
        $resolutionGuardAddress = 'module.framework.module.behaviour_resolution.terraform_data.contract_guard'
        $replacementPlan = Invoke-ReviewedTerraformPlan -Status $runStatus -Stage 'minimal-key-replacement' -ExpectedAddressActions @{ $oldAddress = @('delete'); $newAddress = @('create'); $oldGuardAddress = @('delete'); $newGuardAddress = @('create'); $resolutionGuardAddress = @('update') }
        if (-not $replacementPlan) { return }
        $applyReplacement = Invoke-TrackedApply -Status $runStatus -Stage 'minimal-key-replacement' -TerraformArguments @($tfRoot, 'apply', '-auto-approve', $replacementPlan.Path)
        if ($applyReplacement.ExitCode -ne 0) { $script:testFailed = $true; Write-RunLog 'minimal assignment key replacement apply failed'; return }
        $replacementReview = Get-ResolvedMinimalAssignment -Status $runStatus -AssignmentKey $replacementKey
        $replacementId = if ($replacementReview) { "$($replacementReview['assignment_id'])" } else { '' }
        $replacementName = if ($replacementReview) { "$($replacementReview['assignment_name'])" } else { '' }
        if (-not $replacementId -or -not (Assert-MinimalAssignment -AssignmentId $replacementId -ExpectedScope $runStatus['assignmentScopeId'] -ExpectedName $replacementName -ExpectedOwner $runStatus['terraformVars']['assignment_owner'] -ExpectedDefinitionId $runStatus['builtInAuditDefinitionId'])) { $script:testFailed = $true; return }
        if (-not (Wait-Absence -Label 'replaced minimal assignment old ID' -ProbeKind 'ResourceId' -Target $initialId -Settings $script:Polling.Absence)) { $script:testFailed = $true; return }
        $runStatus['minimalAssignmentHistory'] += [ordered]@{ assignmentKey = $replacementKey; assignmentId = $replacementId; assignmentName = $replacementName; owner = $runStatus['terraformVars']['assignment_owner'] }
        $convergedReplacement = Invoke-ReviewedTerraformPlan -Status $runStatus -Stage 'minimal-replacement-converged' -ExpectedAddressActions @{}
        if (-not $convergedReplacement) { return }
        Write-RunLog 'minimal lifecycle verified: create, Owner in-place update, assignment-key replacement, old-ID absence and converged replacement'
        $runStatus['testCompleted'] = $true
        Save-RunStatus -Status $runStatus
        return
    }

    # Stage 0: create the target resource group, then the policy content
    # layer, before the full apply. The identity and RBAC modules reference
    # the group by name and cannot depend on the example's own resource group
    # resource, and the role grant address derives from created definition and
    # initiative resource IDs, so a for_each address over those values cannot
    # be planned in the same apply that creates them.
    Write-RunLog 'stage 0a: target resource group'
    $apply0a = Invoke-TrackedApply -Status $runStatus -Stage 'stage-0a' -TerraformArguments (@($tfRoot, 'apply', '-auto-approve', '-target=azurerm_resource_group.target') + $baseArgs)
    if ($apply0a.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog "stage 0 resource group apply failed with exit code $($apply0a.ExitCode)"
        return
    }
    $apply0b = Invoke-TrackedApply -Status $runStatus -Stage 'stage-0b' -TerraformArguments (@($tfRoot, 'apply', '-auto-approve', '-target=module.framework.module.content.azurerm_policy_definition.this', '-target=module.framework.module.content.azurerm_policy_set_definition.subscription') + $baseArgs)
    if ($apply0b.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog "stage 0 policy content apply failed with exit code $($apply0b.ExitCode)"
        return
    }
    # Stage 1a creates the target before assignment so its initial
    # non-compliance is read back independently.
    Write-RunLog 'stage 1a: target storage account, before policy assignment'
    $apply1a = Invoke-TrackedApply -Status $runStatus -Stage 'stage-1a' -TerraformArguments (@($tfRoot, 'apply', '-auto-approve', '-target=azurerm_storage_account.target') + $baseArgs)
    if ($apply1a.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog "stage 1a apply failed with exit code $($apply1a.ExitCode)"
        return
    }
    if (-not (Assert-StorageTagInitiallyAbsent -StorageAccountName $targetStorage -ResourceGroupName $targetRgName -TagName $ExpectedTagName -OwnerValue $ExpectedOwnerTagValue)) { return }

    if ($RecoveryProbe) {
        $runStatus['intentionalFailure'] = $true
        $runStatus['recoveryProbeStage'] = 'stage-1a'
        $runStatus['recoveryProbeFailure'] = 'intentional assertion failure after policy content and target baseline; cleanup-only resume is required'
        $runStatus['activeStage'] = 'recovery-probe-intentional-failure'
        Save-RunStatus -Status $runStatus
        $script:testFailed = $true
        Write-RunLog 'recovery probe injected its documented expected failure after stage 1a; exact-ID policy cleanup will pause before Terraform destroy'
        return
    }

    # Stage 1b creates assignment, identity and role grants only after the
    # target's untagged baseline has been recorded.
    Write-RunLog 'stage 1b: assignment, identity and role grant'
    $assignmentMutationStartedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
    $apply1b = Invoke-TrackedApply -Status $runStatus -Stage 'stage-1b' -TerraformArguments (@($tfRoot, 'apply', '-auto-approve', '-target=module.framework.module.assignments.azurerm_resource_group_policy_assignment.this', '-target=module.framework.module.assignments.terraform_data.contract_guard', '-target=module.framework.module.identity_rbac.azurerm_user_assigned_identity.this', '-target=module.framework.module.identity_rbac.azurerm_role_assignment.this') + $baseArgs)
    if ($apply1b.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog "stage 1b apply failed with exit code $($apply1b.ExitCode)"
        return
    }

    $stage1Verified = $true
    $assignmentId = "$(@($runStatus['createdResourceIds']['assignments'])[0])"
    $identityId = "$(@($runStatus['createdResourceIds']['identities'])[0])"
    if (-not $assignmentId) {
        $stage1Verified = $false
        $script:testFailed = $true
        Write-RunLog 'stage 1b assertion skipped: lifecycle_resource_ids exposed no assignment ID'
    }
    else {
        $setDefinitionId = "$(@($runStatus['createdResourceIds']['set_definition_id'])[0])"
        if (-not $setDefinitionId -or -not (Assert-AssignmentBinding -Label 'stage 1 assignment' -AssignmentId $assignmentId -ExpectedScope $targetRgId -ExpectedIdentityId $identityId -ExpectedPolicySetId $setDefinitionId -ExpectedParameters @{ costCentreTagName = 'CostCentre'; costCentreTagValue = 'zctfp-uat' })) {
            $stage1Verified = $false
            $script:testFailed = $true
        }

        $principalId = "$(@($runStatus['createdResourceIds']['principals'])[0])"
        if (-not $principalId -and $identityId) {
            $principalResult = Invoke-AzJson @('identity', 'show', '--ids', $identityId, '--query', 'principalId')
            if ($principalResult.ExitCode -eq 0 -and $principalResult.Data) { $principalId = "$($principalResult.Data)" }
        }
        if ($principalId) {
            if (-not (Assert-RoleGrantSet -PrincipalId $principalId -Scope $targetRgId -ExpectedIds @($runStatus['createdResourceIds']['role_assignments']) -Settings $script:Polling.RoleGrantPropagation)) {
                $stage1Verified = $false
                $script:testFailed = $true
            }
        }
        else {
            $stage1Verified = $false
            $script:testFailed = $true
            Write-RunLog 'stage 1b assertion FAILED: no principal id was available from lifecycle outputs or identity read-back'
        }
    }
    if (-not $stage1Verified) {
        Write-RunLog 'stage 1c remediation apply and later stages skipped: stage 1b assertions did not pass'
        return
    }

    # A resource-group-only scan establishes evaluation after assignment.
    # Require this exact target, assignment and initiative member to be
    # NonCompliant before creating a remediation task.
    $storageId = "/subscriptions/$($script:subscriptionId)/resourceGroups/$targetRgName/providers/Microsoft.Storage/storageAccounts/$targetStorage"
    $memberReferenceId = 'add-costcentre-tag-member'
    if (-not (Wait-TargetNonCompliantPolicyState -ResourceGroupName $targetRgName -StorageAccountName $targetStorage -ResourceId $storageId -AssignmentId $assignmentId -MemberReferenceId $memberReferenceId -NotBeforeUtc $assignmentMutationStartedAtUtc -Settings $script:Polling.PolicyState)) {
        Write-RunLog 'stage 1c remediation apply and later stages skipped: target compliance state was not verified'
        return
    }

    # Stage 1c creates remediation only after the assignment and actual
    # noncompliant target state have both been verified.
    Write-RunLog 'stage 1c: remediation apply and policy-effect verification'
    $apply1c = Invoke-TrackedApply -Status $runStatus -Stage 'stage-1c' -TerraformArguments (@($tfRoot, 'apply', '-auto-approve') + $baseArgs)
    if ($apply1c.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog "stage 1c apply failed with exit code $($apply1c.ExitCode)"
        return
    }
    $remediationId = "$(@($runStatus['createdResourceIds']['remediations'])[0])"
    if (-not $remediationId -or -not (Wait-RemediationSuccess -ResourceGroupName $targetRgName -RemediationId $remediationId -Settings $script:Polling.Remediation)) {
        $stage1Verified = $false
        $script:testFailed = $true
    }
    if (-not (Wait-StorageTagValue -StorageAccountName $targetStorage -ResourceGroupName $targetRgName -Settings $script:Polling.TagReadBack)) {
        $stage1Verified = $false
        $script:testFailed = $true
    }
    if (-not (Assert-Convergence -Label 'stage 1c' -Status $runStatus -ExtraVars @())) { return }
    if (-not $stage1Verified) {
        Write-RunLog 'stage 2 skipped: remediation or target read-back assertions did not pass'
        return
    }

    # Deliberately drift only the run-owned storage Owner tag through its
    # captured resource ID. The real provider plan must restore Owner while
    # retaining the policy-written CostCentre value excluded by ignore_changes.
    $storageId = "$(@($runStatus['createdResourceIds']['storage_accounts'])[0])"
    $expectedStorageId = "/subscriptions/$($script:approvedSubscriptionId)/resourceGroups/$targetRgName/providers/Microsoft.Storage/storageAccounts/$targetStorage"
    if ($storageId -ine $expectedStorageId) {
        $script:testFailed = $true
        Write-RunLog 'Owner drift probe refused: captured storage ID does not exactly match the run-owned target'
        return
    }
    Assert-ApprovedAzureContext
    $runStatus['activeStage'] = 'complete-owner-drift-mutation'
    Save-RunStatus -Status $runStatus
    $tagDrift = Invoke-Az @('tag', 'update', '--resource-id', $storageId, '--operation', 'Merge', '--tags', 'Owner=security-governance-drift')
    if ($tagDrift.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog 'exact run-owned Owner tag drift mutation failed; provider restoration check skipped'
        return
    }
    $driftReadback = Invoke-AzJson @('storage', 'account', 'show', '--name', $targetStorage, '--resource-group', $targetRgName)
    $driftTags = if ($driftReadback.Data) { Get-JsonProperty -Object $driftReadback.Data -Name 'tags' } else { $null }
    $driftOwner = "$(Get-JsonProperty -Object $driftTags -Name 'Owner')"
    $driftCostCentre = "$(Get-JsonProperty -Object $driftTags -Name 'CostCentre')"
    if ($driftReadback.ExitCode -ne 0 -or $driftOwner -cne 'security-governance-drift' -or $driftCostCentre -cne 'zctfp-uat') {
        $script:testFailed = $true
        Write-RunLog 'Owner drift read-back failed or changed the policy-owned CostCentre value'
        return
    }
    $ownerDriftAddress = 'azurerm_storage_account.target'
    $ownerDriftPlan = Invoke-ReviewedTerraformPlan -Status $runStatus -Stage 'complete-owner-drift-restore' -ExpectedAddressActions @{ $ownerDriftAddress = @('update') }
    if (-not $ownerDriftPlan) { return }
    $storagePlanChange = @($ownerDriftPlan.Plan.resource_changes | Where-Object address -ceq $ownerDriftAddress | Select-Object -First 1)[0]
    $beforeTags = Get-JsonProperty -Object $storagePlanChange.change.before -Name 'tags'
    $afterTags = Get-JsonProperty -Object $storagePlanChange.change.after -Name 'tags'
    if ((Get-JsonProperty -Object $beforeTags -Name 'Owner') -cne 'security-governance-drift' -or (Get-JsonProperty -Object $afterTags -Name 'Owner') -cne $ExpectedOwnerTagValue -or (Get-JsonProperty -Object $beforeTags -Name 'CostCentre') -cne 'zctfp-uat' -or (Get-JsonProperty -Object $afterTags -Name 'CostCentre') -cne 'zctfp-uat') {
        $script:testFailed = $true
        Write-RunLog 'provider Owner drift plan did not exclusively restore Owner while retaining ignored CostCentre'
        return
    }
    $restoreOwner = Invoke-TrackedApply -Status $runStatus -Stage 'complete-owner-drift-restore' -TerraformArguments @($tfRoot, 'apply', '-auto-approve', $ownerDriftPlan.Path)
    if ($restoreOwner.ExitCode -ne 0 -or -not (Wait-StorageTagValue -StorageAccountName $targetStorage -ResourceGroupName $targetRgName -Settings $script:Polling.TagReadBack)) {
        $script:testFailed = $true
        Write-RunLog 'Terraform did not restore the run-owned Owner tag while preserving policy CostCentre'
        return
    }
    if (-not (Assert-Convergence -Label 'complete Owner drift restored' -Status $runStatus -ExtraVars @())) { return }

    # Stage 2: exemption created only after the remediation assertion (R9).
    Write-RunLog 'stage 2: governed exemption bound to the resolved assignment'
    $runStatus['terraformVars']['create_exemption'] = 'true'
    $runStatus['terraformVars']['exemption_assignment_id'] = $assignmentId
    $runStatus['activeStage'] = 'stage-2'
    Save-RunStatus -Status $runStatus
    $stage2Args = Get-TerraformBaseArguments -Status $runStatus
    $apply2 = Invoke-TrackedApply -Status $runStatus -Stage 'stage-2' -TerraformArguments (@($tfRoot, 'apply', '-auto-approve') + $stage2Args)
    if ($apply2.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog "stage 2 apply failed with exit code $($apply2.ExitCode)"
        return
    }

    $exemptionAddress = 'module.framework.module.operations.azurerm_resource_group_policy_exemption.this["exempt-tag-rg-uat"]'
    $exemptionId = "$(@($runStatus['createdResourceIds']['exemptions'])[0])"
    if (-not $exemptionId -or -not (Assert-ExemptionState -Label 'stage 2 exemption' -ResourceGroupName $targetRgName -AssignmentId $assignmentId -ExemptionId $exemptionId -ExpectedExpiryDate $fileExpiry)) { return }
    if (-not (Assert-Convergence -Label 'stage 2' -Status $runStatus -ExtraVars @())) { return }

    # Renewal: explicit in-place expiry update with a persisted input.
    Write-RunLog "renewal: exemption expiry moved to $($runStatus['renewalExpiry'])"
    $runStatus['terraformVars']['exemption_expiry'] = "$($runStatus['renewalExpiry'])"
    $runStatus['activeStage'] = 'renewal'
    Save-RunStatus -Status $runStatus
    $renewalPlan = Invoke-ReviewedTerraformPlan -Status $runStatus -Stage 'exemption-renewal' -ExpectedAddressActions @{ $exemptionAddress = @('update') }
    if (-not $renewalPlan) { return }
    $apply3 = Invoke-TrackedApply -Status $runStatus -Stage 'renewal' -TerraformArguments @($tfRoot, 'apply', '-auto-approve', $renewalPlan.Path)
    if ($apply3.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog "renewal apply failed with exit code $($apply3.ExitCode)"
        return
    }

    if (-not (Assert-ExemptionState -Label 'renewal exemption' -ResourceGroupName $targetRgName -AssignmentId $assignmentId -ExemptionId $exemptionId -ExpectedExpiryDate "$($runStatus['renewalExpiry'])")) { return }
    if (-not (Assert-Convergence -Label 'renewal' -Status $runStatus -ExtraVars @())) { return }

    # Exemption resource read-back does not establish evaluation or request-time propagation.
    $exemptionEvaluationStartedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
    if (-not (Wait-TargetNonCompliantPolicyState -ResourceGroupName $targetRgName -StorageAccountName $targetStorage -ResourceId $storageId -AssignmentId $assignmentId -MemberReferenceId $memberReferenceId -ExpectedComplianceState Exempt -NotBeforeUtc $exemptionEvaluationStartedAtUtc -Settings $script:Polling.PolicyState)) { return }
    $runStatus['activeStage'] = 'policy-reenforcement-tag-removal-under-exemption'
    Save-RunStatus -Status $runStatus
    $tagRemovalStartedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
    if (-not (Remove-PolicyTagUnderExemption -Status $runStatus -ResourceId $storageId -StorageAccountName $targetStorage -ResourceGroupName $targetRgName -OwnerValue $ExpectedOwnerTagValue -Settings $script:Polling.PolicyState)) { return }

    # Remove the exemption through Terraform, confirm its exact absence, then
    # require a new non-compliant policy state before running remediation.
    $runStatus['terraformVars']['create_exemption'] = 'false'
    $runStatus['activeStage'] = 'exemption-removal'
    Save-RunStatus -Status $runStatus
    # The exemption guard carries no input, so removal plans only the delete.
    $removeExemptionPlan = Invoke-ReviewedTerraformPlan -Status $runStatus -Stage 'exemption-removal' -ExpectedAddressActions @{ $exemptionAddress = @('delete') }
    if (-not $removeExemptionPlan) { return }
    $removeExemptionApply = Invoke-TrackedApply -Status $runStatus -Stage 'exemption-removal' -TerraformArguments @($tfRoot, 'apply', '-auto-approve', $removeExemptionPlan.Path)
    if ($removeExemptionApply.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog 'exemption removal apply failed; policy re-enforcement was not started'
        return
    }
    if (-not (Assert-ExemptionAbsent -ResourceGroupName $targetRgName -AssignmentId $assignmentId -ExemptionId $exemptionId)) { return }
    if (-not (Wait-Absence -Label 'captured exemption' -ProbeKind ResourceId -Target $exemptionId -Settings $script:Polling.Absence)) { return }
    if (-not (Assert-Convergence -Label 'exemption removed' -Status $runStatus -ExtraVars @())) { return }

    if (-not (Wait-TargetNonCompliantPolicyState -ResourceGroupName $targetRgName -StorageAccountName $targetStorage -ResourceId $storageId -AssignmentId $assignmentId -MemberReferenceId $memberReferenceId -ExpectedComplianceState NonCompliant -NotBeforeUtc $tagRemovalStartedAtUtc -Settings $script:Polling.PolicyState)) {
        Write-RunLog 'repeat remediation skipped: target did not return to exact NonCompliant state'
        return
    }

    $remediationId = "$( @($runStatus['createdResourceIds']['remediations'])[0] )"
    $previousRemediation = Get-RemediationCreationObservation -ResourceGroupName $targetRgName -RemediationId $remediationId
    if (-not $previousRemediation) {
        $script:testFailed = $true
        Write-RunLog 'repeat remediation skipped: current task creation time could not be captured for distinct execution proof'
        return
    }
    $remediationAddress = 'module.framework.module.operations.azurerm_resource_group_policy_remediation.this["remediate-tag-rg"]'
    $runStatus['activeStage'] = 'remediation-repeat'
    Save-RunStatus -Status $runStatus
    $repeatRemediationPlan = Invoke-ReviewedTerraformPlan -Status $runStatus -Stage 'remediation-repeat' -ExpectedAddressActions @{ $remediationAddress = @('delete', 'create') } -AdditionalPlanArguments @(('-replace=' + $remediationAddress))
    if (-not $repeatRemediationPlan) { return }
    $repeatRemediationStartedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
    $repeatRemediationApply = Invoke-TrackedApply -Status $runStatus -Stage 'remediation-repeat' -TerraformArguments @($tfRoot, 'apply', '-auto-approve', $repeatRemediationPlan.Path)
    if ($repeatRemediationApply.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog 'repeat remediation apply failed'
        return
    }
    if (-not (Wait-RemediationSuccess -ResourceGroupName $targetRgName -RemediationId $remediationId -Settings $script:Polling.Remediation -PreviousCreatedOn $previousRemediation.CreatedOn) -or
        -not (Wait-StorageTagValue -StorageAccountName $targetStorage -ResourceGroupName $targetRgName -Settings $script:Polling.TagReadBack)) {
        $script:testFailed = $true
        Write-RunLog 'repeat remediation did not create a newer successful task and restore CostCentre while retaining Owner'
        return
    }
    if (-not (Wait-TargetNonCompliantPolicyState -ResourceGroupName $targetRgName -StorageAccountName $targetStorage -ResourceId $storageId -AssignmentId $assignmentId -MemberReferenceId $memberReferenceId -ExpectedComplianceState Compliant -NotBeforeUtc $repeatRemediationStartedAtUtc -Settings $script:Polling.PolicyState)) {
        $script:testFailed = $true
        Write-RunLog 'post-remediation policy scan did not confirm the target is Compliant'
        return
    }
    if (-not (Assert-Convergence -Label 'repeat remediation converged' -Status $runStatus -ExtraVars @())) { return }
    $runStatus['testCompleted'] = $true
    Save-RunStatus -Status $runStatus
}
catch {
    $script:testFailed = $true
    Write-RunLog ("run failed with an unexpected error: {0}" -f $_)
}
finally {
    if ($script:mutationStarted) {
        if (-not $runStatus['testCompleted']) { $script:testFailed = $true }
        try {
            Invoke-Cleanup -Status $runStatus
        }
        catch {
            $script:cleanupFailed = $true
            Write-RunLog ("cleanup handler failed with an unexpected error: {0}" -f $_)
        }
    }
    else {
        Write-RunLog 'cleanup skipped: this run started no Terraform mutation'
        if ($runStatus['terraformWorkspace'] -and $runStatus['workspaceInitiallyEmpty']) {
            $tfRoot = '-chdir=' + $runStatus['exampleRoot']
            $currentWorkspace = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'show')
            $currentState = Invoke-Terraform -TerraformArguments @($tfRoot, 'state', 'list', '-no-color')
            $stateStillEmpty = Test-NewWorkspaceEmpty -WorkspaceCreated $true -StatePath $runStatus['terraformStatePath'] -StateListResult $currentState
            try { Assert-DefaultStateUnchanged -Status $runStatus | Out-Null }
            catch { $stateStillEmpty = $false; Write-RunLog "empty workspace cleanup refused: $($_.Exception.Message)" }
            if ($currentWorkspace.ExitCode -eq 0 -and (($currentWorkspace.Output -join '').Trim() -ceq $runStatus['terraformWorkspace']) -and $stateStillEmpty) {
                $toDefault = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'select', 'default')
                $selectedDefault = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'show')
                if ($toDefault.ExitCode -eq 0 -and $selectedDefault.ExitCode -eq 0 -and (($selectedDefault.Output -join '').Trim() -ceq 'default')) {
                    $deletedEmptyWorkspace = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'delete', $runStatus['terraformWorkspace'])
                    $workspaceList = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'list', '-no-color')
                    $stillListed = @($workspaceList.Output | ForEach-Object { ([string]$_ -replace '^\s*\*?\s*', '').Trim() }) -contains $runStatus['terraformWorkspace']
                    try { Assert-DefaultStateUnchanged -Status $runStatus | Out-Null }
                    catch { $script:cleanupFailed = $true; Write-RunLog "default state changed during empty workspace cleanup: $($_.Exception.Message)" }
                    if ($deletedEmptyWorkspace.ExitCode -eq 0 -and $workspaceList.ExitCode -eq 0 -and -not $stillListed -and -not $script:cleanupFailed) {
                        $runStatus['workspaceRemoved'] = $true
                        Save-RunStatus -Status $runStatus
                        Write-RunLog 'verified empty pre-mutation Terraform workspace removed; default state and backup hashes remain unchanged'
                    }
                    else { $script:cleanupFailed = $true; Write-RunLog 'empty pre-mutation Terraform workspace could not be verified absent; recovery status and state are retained' }
                }
                else { $script:cleanupFailed = $true; Write-RunLog 'could not verify selection of default workspace before empty workspace cleanup' }
            }
            else { $script:cleanupFailed = $true; Write-RunLog 'empty workspace cleanup refused: active workspace/path or state inventory changed before removal' }
        }
        elseif ($runStatus['terraformWorkspace']) {
            $script:cleanupFailed = $true
            Write-RunLog 'workspace cleanup refused because its new-workspace empty-state preflight did not pass; inspect the preserved status and state before recovery'
        }
    }
    if ($script:mutationLockStream) {
        $script:mutationLockStream.Dispose()
        Remove-Item -LiteralPath $script:mutationLockPath -Force -ErrorAction SilentlyContinue
    }
    Write-StatusReport
    # Top-level failure branches return from the script after finally. Exit
    # here so the process status cannot disagree with the reported result.
    exit (ConvertTo-ExitCode -TestFailed:$script:testFailed -CleanupFailed:$script:cleanupFailed)
}
