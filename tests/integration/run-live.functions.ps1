# Function library for run-live.ps1. Dot-sourced by the entry script so the
# functions share its script scope: the run state ($script:testFailed,
# $script:approvedSubscriptionId and the fixture responses) is owned by the
# entry script and read or updated here. Do not run this file directly.


# The exemptions contract requires a full RFC3339 expiry; date-only values are
# rejected by the variable validation. Accept caller-supplied dates in either
# form and normalise to RFC3339.
function ConvertTo-Rfc3339Expiry {
    param([string]$Value)
    $trimmed = "$Value".Trim()
    if ($trimmed -match '^\d{4}-\d{2}-\d{2}$') { return "$($trimmed)T00:00:00Z" }
    return $trimmed
}

function ConvertTo-Rfc3339Argument {
    param($Value)
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) {
        return ([datetimeoffset]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return "$Value"
}

# Runtime status flags (R12): kept independent on purpose. $mutationStarted
# gates the cleanup handler so preflight-only runs never destroy anything.

function ConvertTo-Redacted {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    if ($script:subscriptionId) {
        return $Text.Replace($script:subscriptionId, '[redacted-subscription]')
    }
    return $Text
}

function Write-RunLog {
    param([AllowNull()][string]$Message)
    $line = '{0:u} {1}' -f (Get-Date).ToUniversalTime(), (ConvertTo-Redacted $Message)
    Write-Host $line
    if ($script:logPath) {
        Add-Content -LiteralPath $script:logPath -Value $line -Encoding utf8
    }
}

function Get-JsonProperty {
    # Strict-safe access to optional az CLI JSON fields; a missing property
    # is a distinct state from an empty one and both must not throw.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        $value = $Object[$Name]
        if ($value -is [array]) { return ,$value }
        return $value
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        if ($property.Value -is [array]) { return ,$property.Value }
        return $property.Value
    }
    return $null
}

function Invoke-Terraform {
    param([string[]]$TerraformArguments, [switch]$FullLog)
    $command = 'terraform ' + ($TerraformArguments -join ' ')
    $output = & terraform @TerraformArguments 2>&1
    $exitCode = $LASTEXITCODE
    $lines = @($output | ForEach-Object { "$_" })
    Write-RunLog "$command (exit $exitCode)"
    if ($TerraformArguments -contains '-json') {
        # Structured Terraform output can include state and output secrets.
        # Keep it in memory for the caller's parser, but never write it to logs.
        Write-RunLog '  [Terraform JSON output suppressed; it may contain sensitive values]'
    }
    else {
        $loggedLines = $lines
        if (-not $FullLog) { $loggedLines = @($lines | Select-Object -Last 12) }
        foreach ($line in $loggedLines) { Write-RunLog "  $line" }
    }
    return @{ ExitCode = $exitCode; Output = $lines }
}

function Invoke-Az {
    # Azure CLI output only: stdout carries JSON while warnings and errors go
    # to stderr, so JSON parsing stays deterministic.
    param([string[]]$Arguments)
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $stdout = & az @Arguments 2>$errFile
        $exitCode = $LASTEXITCODE
        $stdoutText = (@($stdout) | ForEach-Object { "$_" }) -join "`n"
        $stderrText = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        return @{ ExitCode = $exitCode; StdOut = $stdoutText; StdErr = "$stderrText" }
    }
    finally {
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }
}

function Invoke-AzJson {
    param([string[]]$Arguments)
    $result = Invoke-Az ($Arguments + @('-o', 'json'))
    $data = $null
    if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.StdOut)) {
        try {
            $data = ConvertFrom-Json -InputObject $result.StdOut -NoEnumerate
        }
        catch {
            Write-RunLog "az json parse failed for: $($Arguments -join ' ')"
            $result.ExitCode = 1
        }
    }
    return @{ ExitCode = $result.ExitCode; Data = $data; Text = "$($result.StdOut)`n$($result.StdErr)" }
}


function Read-ApprovedContext {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'ApprovedContextPath must identify an explicit local approved-context JSON file'
    }
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path))
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'approved context must be a JSON object' }
        $expected = @('subscriptionId', 'tenantId', 'cloud', 'userName', 'userType')
        $context = @{}
        foreach ($property in $document.RootElement.EnumerateObject()) {
            if ($property.Name -cnotin $expected -or $context.ContainsKey($property.Name) -or $property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                throw 'approved context requires exactly the five named string fields, without duplicates'
            }
            $value = $property.Value.GetString()
            if ([string]::IsNullOrWhiteSpace($value) -or $value -cne $value.Trim()) { throw 'approved context fields must be non-blank strings without surrounding whitespace' }
            $context[$property.Name] = $value
        }
        if ($context.Count -ne $expected.Count) { throw 'approved context is missing a required field' }
        foreach ($field in @('subscriptionId', 'tenantId')) {
            if ($context[$field] -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -or [guid]$context[$field] -eq [guid]::Empty) {
                throw "approved context $field must be a non-zero GUID"
            }
        }
        if ($context.cloud -cne 'AzureCloud' -or $context.userType -cne 'user' -or $context.userName -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') {
            throw 'approved context requires AzureCloud and an explicit user principal name with userType user'
        }
        return $context
    }
    finally { if ($document) { $document.Dispose() } }
}

function Assert-ApprovedContextPinned {
    if ($script:offlineContext) { return }
    if (-not $script:approvedContextFile -or -not (Test-Path -LiteralPath $script:approvedContextFile -PathType Leaf) -or
        (Get-FileHash -LiteralPath $script:approvedContextFile -Algorithm SHA256).Hash -cne $script:approvedContextHash) {
        throw 'approved context file changed or is missing; refusing further Azure operations'
    }
    $current = Read-ApprovedContext -Path $script:approvedContextFile
    if ($current.subscriptionId -ine $script:approvedSubscriptionId -or $current.tenantId -ine $script:approvedTenantId -or
        $current.cloud -cne $script:approvedCloud -or $current.userName -ine $script:approvedUserName -or $current.userType -cne $script:approvedUserType) {
        throw 'approved context file does not match the loaded approval tuple'
    }
}

function Assert-RecordedApprovedContext {
    param([hashtable]$Status)
    if ($script:offlineContext) { return }
    Assert-ApprovedContextPinned
    $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $Status['runDirectory'] 'approved-context.json'))
    if (-not $Status.ContainsKey('approvedContextPath') -or -not $Status.ContainsKey('approvedContextSha256') -or
        [string]$Status['approvedContextPath'] -ine $expectedPath -or
        "$($Status['approvedContextSha256'])" -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
        throw 'recorded approved context snapshot is missing or outside its run directory'
    }
    if ((Get-FileHash -LiteralPath $expectedPath -Algorithm SHA256).Hash -cne $Status['approvedContextSha256']) {
        throw 'recorded approved context snapshot changed'
    }
    $recorded = Read-ApprovedContext -Path $expectedPath
    if ($recorded.subscriptionId -ine $script:approvedSubscriptionId -or $recorded.tenantId -ine $script:approvedTenantId -or
        $recorded.cloud -cne $script:approvedCloud -or $recorded.userName -ine $script:approvedUserName -or $recorded.userType -cne $script:approvedUserType) {
        throw 'supplied approved context does not match the context pinned for this run'
    }
}

function Assert-ApprovedAzureContext {
    Assert-ApprovedContextPinned
    # Re-check immediately before each mutating boundary so a changed ambient
    # Azure CLI account cannot redirect an already-approved run.
    if ($env:ARM_SUBSCRIPTION_ID -and $env:ARM_SUBSCRIPTION_ID -ine $script:approvedSubscriptionId) {
        throw 'ARM_SUBSCRIPTION_ID does not match the approved UAT subscription'
    }
    if ($env:ARM_TENANT_ID -and $env:ARM_TENANT_ID -ine $script:approvedTenantId) {
        throw 'ARM_TENANT_ID does not match the approved UAT tenant'
    }
    $alternateCredentialNames = @(
        'ARM_CLIENT_ID', 'ARM_CLIENT_SECRET', 'ARM_CLIENT_CERTIFICATE', 'ARM_CLIENT_CERTIFICATE_PATH',
        'ARM_CLIENT_CERTIFICATE_PASSWORD', 'ARM_CLIENT_SECRET_FILE_PATH', 'ARM_OIDC_TOKEN',
        'ARM_OIDC_TOKEN_FILE_PATH', 'ARM_OIDC_REQUEST_TOKEN', 'ARM_OIDC_REQUEST_URL'
    )
    $alternateCredentials = @($alternateCredentialNames | Where-Object {
        $value = [Environment]::GetEnvironmentVariable($_)
        $null -ne $value -and $value -ne ''
    })
    $alternateAuthSwitches = @(@('ARM_USE_MSI', 'ARM_USE_OIDC') | Where-Object {
        $value = [Environment]::GetEnvironmentVariable($_)
        $null -ne $value -and $value -match '^(?i:true|1)$'
    })
    if ($alternateCredentials.Count -gt 0 -or $alternateAuthSwitches.Count -gt 0) {
        throw ('Terraform AzureRM alternate authentication variables are set: ' + (@($alternateCredentials) + @($alternateAuthSwitches) -join ', '))
    }
    if ($env:ARM_USE_CLI -and $env:ARM_USE_CLI -notmatch '^(?i:true|1)$') {
        throw 'ARM_USE_CLI must not disable Azure CLI authentication for the approved user context'
    }
    $account = Invoke-AzJson @('account', 'show')
    if ($account.ExitCode -ne 0 -or $null -eq $account.Data) { throw 'active Azure account could not be verified before mutation' }
    $activeSubscription = "$(Get-JsonProperty -Object $account.Data -Name 'id')"
    $activeTenant = "$(Get-JsonProperty -Object $account.Data -Name 'tenantId')"
    $activeCloud = "$(Get-JsonProperty -Object $account.Data -Name 'environmentName')"
    $activeUser = Get-JsonProperty -Object $account.Data -Name 'user'
    $activeUserName = "$(Get-JsonProperty -Object $activeUser -Name 'name')"
    $activeUserType = "$(Get-JsonProperty -Object $activeUser -Name 'type')"
    if ($activeSubscription -ine $script:approvedSubscriptionId -or $activeTenant -ine $script:approvedTenantId -or ($script:subscriptionId -and $activeSubscription -ine $script:subscriptionId) -or ($script:tenantId -and $activeTenant -ine $script:tenantId)) {
        throw 'active Azure tenant or subscription changed from the approved run context'
    }
    if ($activeCloud -cne $script:approvedCloud -or $activeUserName -ine $script:approvedUserName -or $activeUserType -cne $script:approvedUserType) {
        throw 'active Azure cloud or signed-in user does not match the approved UAT identity'
    }
}

function Test-NotFoundText {
    # Only provider not-found responses count as authoritative absence;
    # authorisation, token and network failures stay inconclusive.
    param([AllowNull()][string]$Text)
    return ($Text -match 'ResourceNotFound|ResourceGroupNotFound|NotFound|was not found|could not be found')
}

function Test-ResourceGroupAbsentNow {
    param([string]$Name)
    $result = Invoke-AzJson @('group', 'show', '--name', $Name)
    if ($result.ExitCode -eq 0) { return 'Present' }
    if (Test-NotFoundText $result.Text) { return 'Absent' }
    $firstLines = (@($result.Text -split "`n") | Select-Object -First 3) -join ' | '
    Write-RunLog "resource group read-back inconclusive for '${Name}': $(ConvertTo-Redacted $firstLines)"
    return 'Inconclusive'
}

function Test-ResourceAbsentNow {
    param([string]$ResourceId)
    $result = Invoke-AzJson @('resource', 'show', '--ids', $ResourceId)
    if ($result.ExitCode -eq 0) { return 'Present' }
    if (Test-NotFoundText $result.Text) { return 'Absent' }
    $firstLines = (@($result.Text -split "`n") | Select-Object -First 3) -join ' | '
    Write-RunLog "absence read-back inconclusive for ${ResourceId}: $(ConvertTo-Redacted $firstLines)"
    return 'Inconclusive'
}

function Wait-Absence {
    param([string]$Label, [ValidateSet('ResourceGroup', 'ResourceId')][string]$ProbeKind, [string]$Target, [hashtable]$Settings)
    $lastState = 'Unknown'
    for ($attempt = 1; $attempt -le $Settings.RetryLimit; $attempt++) {
        if ($ProbeKind -eq 'ResourceGroup') { $lastState = Test-ResourceGroupAbsentNow -Name $Target }
        else { $lastState = Test-ResourceAbsentNow -ResourceId $Target }
        if ($lastState -eq 'Absent') {
            Write-RunLog "${Label}: authoritative absence after $attempt probe(s)"
            return $true
        }
        if ($attempt -lt $Settings.RetryLimit) { Start-Sleep -Seconds $Settings.IntervalSeconds }
    }
    Write-RunLog "${Label}: absence not established, last state '$lastState' after $($Settings.RetryLimit) probes at $($Settings.IntervalSeconds) s intervals (deadline $($Settings.DeadlineSeconds) s)"
    return $false
}

function Wait-RemediationSuccess {
    param([string]$ResourceGroupName, [string]$RemediationId, [hashtable]$Settings, [string]$PreviousCreatedOn)
    for ($attempt = 1; $attempt -le $Settings.RetryLimit; $attempt++) {
        $result = Invoke-AzJson @('policy', 'remediation', 'list', '--resource-group', $ResourceGroupName)
        if ($result.ExitCode -eq 0 -and $null -ne $result.Data) {
            $tasks = @($result.Data)
            $states = @()
            $succeeded = $false
            foreach ($task in $tasks) {
                $taskId = "$(Get-JsonProperty -Object $task -Name 'id')"
                if ($taskId -ine $RemediationId) { continue }
                $state = "$(Get-JsonProperty -Object $task -Name 'ProvisioningState')"
                $states += $state
                $deploymentSummary = Get-JsonProperty -Object $task -Name 'deploymentSummary'
                if ($null -eq $deploymentSummary) { $deploymentSummary = Get-JsonProperty -Object $task -Name 'deploymentStatus' }
                $successfulDeployments = [int](Get-JsonProperty -Object $deploymentSummary -Name 'successfulDeployments')
                $failedDeployments = [int](Get-JsonProperty -Object $deploymentSummary -Name 'failedDeployments')
                $createdOn = Get-RemediationCreatedOn -Remediation $task
                $createdAfterPrevious = $true
                if ($PreviousCreatedOn) {
                    $createdAfterPrevious = $false
                    if ($createdOn) {
                        try { $createdAfterPrevious = [datetimeoffset]::Parse($createdOn, [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime -gt [datetimeoffset]::Parse($PreviousCreatedOn, [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime }
                        catch { $createdAfterPrevious = $false }
                    }
                }
                if ($state -in @('Succeeded', 'Complete') -and $successfulDeployments -gt 0 -and $failedDeployments -eq 0 -and $createdAfterPrevious) { $succeeded = $true }
            }
            if ($succeeded) {
                Write-RunLog "remediation: Succeeded after $attempt poll(s)"
                return $true
            }
            Write-RunLog "remediation poll $attempt/$($Settings.RetryLimit): no successful deployment (states $($states -join ','))"
        }
        else {
            Write-RunLog "remediation poll $attempt/$($Settings.RetryLimit): list read-back failed"
        }
        if ($attempt -lt $Settings.RetryLimit) { Start-Sleep -Seconds $Settings.IntervalSeconds }
    }
    Write-RunLog "remediation: no Succeeded task within $($Settings.DeadlineSeconds) s"
    return $false
}

function Get-RemediationCreatedOn {
    param($Remediation)
    $createdOn = Get-JsonProperty -Object $Remediation -Name 'createdOn'
    if (-not $createdOn) {
        $properties = Get-JsonProperty -Object $Remediation -Name 'properties'
        $createdOn = Get-JsonProperty -Object $properties -Name 'createdOn'
    }
    # PowerShell 7 returns [datetime] for ISO timestamps; "$value" renders it in the
    # invariant month-first form, which a day-first culture cannot parse back.
    return (ConvertTo-Rfc3339Argument $createdOn)
}

function Get-RemediationCreationObservation {
    param([string]$ResourceGroupName, [string]$RemediationId)
    $result = Invoke-AzJson @('policy', 'remediation', 'list', '--resource-group', $ResourceGroupName, '--subscription', $script:subscriptionId)
    if ($result.ExitCode -ne 0 -or $null -eq $result.Data) { return $null }
    foreach ($task in @($result.Data)) {
        $taskId = "$(Get-JsonProperty -Object $task -Name 'id')"
        if ($taskId -ieq $RemediationId) {
            $createdOn = Get-RemediationCreatedOn -Remediation $task
            if (-not $createdOn) { return $null }
            return @{ Id = $taskId; CreatedOn = $createdOn }
        }
    }
    return $null
}

function Assert-StorageTagAbsent {
    param([string]$StorageAccountName, [string]$ResourceGroupName, [string]$TagName, [string]$OwnerValue)
    $result = Invoke-AzJson @('storage', 'account', 'show', '--name', $StorageAccountName, '--resource-group', $ResourceGroupName)
    if ($result.ExitCode -ne 0 -or $null -eq $result.Data) {
        $script:testFailed = $true
        Write-RunLog 'storage tag absence read-back failed'
        return $false
    }
    $tags = Get-JsonProperty -Object $result.Data -Name 'tags'
    $tagValue = Get-JsonProperty -Object $tags -Name $TagName
    $owner = "$(Get-JsonProperty -Object $tags -Name 'Owner')"
    if (($null -ne $tagValue -and "$tagValue" -ne '') -or $owner -cne $OwnerValue) {
        $script:testFailed = $true
        Write-RunLog "storage tag re-enforcement baseline FAILED: '$TagName' must be absent and Owner must remain '$OwnerValue'"
        return $false
    }
    Write-RunLog "storage tag re-enforcement baseline verified: '$TagName' is absent and Owner='$OwnerValue' remains"
    return $true
}

function Remove-PolicyTagUnderExemption {
    param([hashtable]$Status, [string]$ResourceId, [string]$StorageAccountName,
        [string]$ResourceGroupName, [string]$OwnerValue, [hashtable]$Settings)
    $expectedId = "/subscriptions/$($Status['subscriptionId'])/resourceGroups/$($Status['targetResourceGroupName'])/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
    if ($ResourceId -ine $expectedId -or $ResourceGroupName -ine $Status['targetResourceGroupName'] -or $StorageAccountName -cne $Status['targetStorageAccountName']) {
        throw 'tag removal target differs from the captured run resource'
    }
    for ($attempt = 1; $attempt -le $Settings.RetryLimit; $attempt++) {
        Assert-RunInputsUnchanged -Status $Status | Out-Null
        Assert-ApprovedAzureContext
        $before = Invoke-AzJson @('storage', 'account', 'show', '--name', $StorageAccountName, '--resource-group', $ResourceGroupName)
        if ($before.ExitCode -ne 0 -or $null -eq $before.Data -or
            (Get-JsonProperty -Object $before.Data -Name 'id') -ine $ResourceId -or
            (Get-JsonProperty -Object (Get-JsonProperty -Object $before.Data -Name 'tags') -Name 'Owner') -cne $OwnerValue) {
            $script:testFailed = $true
            Write-RunLog 'tag removal refused: target read-back or protected Owner differs'
            return $false
        }
        $remove = Invoke-Az @('tag', 'update', '--resource-id', $ResourceId, '--operation', 'Delete', '--tags', 'CostCentre')
        if ($remove.ExitCode -ne 0) {
            $script:testFailed = $true
            Write-RunLog 'protected policy-tag delete failed'
            return $false
        }
        $after = Invoke-AzJson @('storage', 'account', 'show', '--name', $StorageAccountName, '--resource-group', $ResourceGroupName)
        $tags = Get-JsonProperty -Object $after.Data -Name 'tags'
        if ($after.ExitCode -ne 0 -or $null -eq $after.Data -or
            (Get-JsonProperty -Object $after.Data -Name 'id') -ine $ResourceId -or
            (Get-JsonProperty -Object $tags -Name 'Owner') -cne $OwnerValue) {
            $script:testFailed = $true
            Write-RunLog 'tag removal read-back failed or protected Owner changed'
            return $false
        }
        $tagPresent = if ($tags -is [System.Collections.IDictionary]) { $tags.Contains('CostCentre') } else { @($tags.PSObject.Properties.Name) -icontains 'CostCentre' }
        if (-not $tagPresent) {
            Write-RunLog "policy tag absence verified under exemption after $attempt attempt(s); Owner retained"
            return $true
        }
        Write-RunLog "policy tag remains after delete $attempt/$($Settings.RetryLimit); waiting for exemption enforcement"
        if ($attempt -lt $Settings.RetryLimit) { Start-Sleep -Seconds $Settings.IntervalSeconds }
    }
    $script:testFailed = $true
    Write-RunLog 'policy tag remained present within the bounded exemption enforcement window'
    return $false
}

function Assert-ExemptionAbsent {
    param([string]$ResourceGroupName, [string]$AssignmentId, [string]$ExemptionId)
    $result = Invoke-AzJson @('policy', 'exemption', 'list', '--resource-group', $ResourceGroupName, '--subscription', $script:subscriptionId)
    if ($result.ExitCode -ne 0 -or $null -eq $result.Data) {
        $script:testFailed = $true
        Write-RunLog 'exemption absence read-back failed or was inconclusive'
        return $false
    }
    foreach ($exemption in @($result.Data)) {
        $id = "$(Get-JsonProperty -Object $exemption -Name 'id')"
        $properties = Get-JsonProperty -Object $exemption -Name 'properties'
        $assignment = Get-JsonProperty -Object $exemption -Name 'policyAssignmentId'
        if ($null -eq $assignment) { $assignment = Get-JsonProperty -Object $properties -Name 'policyAssignmentId' }
        $assignment = "$assignment"
        if (($ExemptionId -and $id -ieq $ExemptionId) -or ($AssignmentId -and $assignment -ieq $AssignmentId)) {
            $script:testFailed = $true
            Write-RunLog 'exemption absence FAILED: the captured exemption remains or an exemption still references the run assignment'
            return $false
        }
    }
    Write-RunLog 'exemption absence verified: the captured exemption is absent and no exemption references the run assignment'
    return $true
}

function Wait-TargetNonCompliantPolicyState {
    param(
        [string]$ResourceGroupName,
        [string]$StorageAccountName,
        [string]$ResourceId,
        [string]$AssignmentId,
        [string]$MemberReferenceId,
        [ValidateSet('NonCompliant', 'Compliant', 'Exempt')][string]$ExpectedComplianceState = 'NonCompliant',
        [string]$NotBeforeUtc,
        [hashtable]$Settings
    )

    $expectedResourceId = "/subscriptions/$($script:subscriptionId)/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
    if ($ResourceId -ine $expectedResourceId -or
        $AssignmentId -notmatch "^/subscriptions/$([regex]::Escape($script:subscriptionId))/resourceGroups/$([regex]::Escape($ResourceGroupName))/providers/Microsoft\.Authorization/policyAssignments/[^/]+$" -or
        [string]::IsNullOrWhiteSpace($MemberReferenceId)) {
        $script:testFailed = $true
        Write-RunLog 'policy scan refused: resource, assignment or initiative member is outside the captured run target'
        return $false
    }

    $scan = Invoke-AzJson @('policy', 'state', 'trigger-scan', '--resource-group', $ResourceGroupName, '--no-wait', '--subscription', $script:subscriptionId)
    if ($scan.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog 'resource-group policy compliance scan failed; remediation was not started'
        return $false
    }

    $filter = "policyAssignmentId eq '$AssignmentId' and policyDefinitionReferenceId eq '$MemberReferenceId'"
    for ($attempt = 1; $attempt -le $Settings.RetryLimit; $attempt++) {
        $states = Invoke-AzJson @('policy', 'state', 'list', '--resource', $ResourceId, '--filter', $filter, '--subscription', $script:subscriptionId)
        if ($states.ExitCode -eq 0 -and $null -ne $states.Data) {
            foreach ($state in @($states.Data)) {
                $stateResourceId = "$(Get-JsonProperty -Object $state -Name 'resourceId')"
                $stateAssignmentId = "$(Get-JsonProperty -Object $state -Name 'policyAssignmentId')"
                $stateMemberReference = "$(Get-JsonProperty -Object $state -Name 'policyDefinitionReferenceId')"
                $complianceState = "$(Get-JsonProperty -Object $state -Name 'complianceState')"
                $timestampFresh = $true
                if ($NotBeforeUtc) {
                    $timestampFresh = $false
                    $stateTimestamp = Get-JsonProperty -Object $state -Name 'timestamp'
                    try {
                        $timestampFresh = [datetimeoffset]::Parse((ConvertTo-Rfc3339Argument $stateTimestamp)).UtcDateTime -ge [datetimeoffset]::Parse($NotBeforeUtc).UtcDateTime
                    }
                    catch { $timestampFresh = $false }
                }
                if ($stateResourceId -ieq $ResourceId -and
                    $stateAssignmentId -ieq $AssignmentId -and
                    $stateMemberReference -ceq $MemberReferenceId -and
                    $complianceState -ieq $ExpectedComplianceState -and $timestampFresh) {
                    Write-RunLog "scoped policy state confirms the captured target is $ExpectedComplianceState for initiative member '$MemberReferenceId' after $attempt read(s)"
                    return $true
                }
            }
            Write-RunLog "policy state read $attempt/$($Settings.RetryLimit): the exact target/assignment/member is not yet $ExpectedComplianceState"
        }
        else {
            Write-RunLog "policy state read $attempt/$($Settings.RetryLimit) failed or was inconclusive"
        }
        if ($attempt -lt $Settings.RetryLimit) { Start-Sleep -Seconds $Settings.IntervalSeconds }
    }

    $script:testFailed = $true
    Write-RunLog "policy state did not confirm target $ExpectedComplianceState within $($Settings.DeadlineSeconds) s"
    return $false
}

function Wait-StorageTagValue {
    # Exact string comparison: the policy-owned key must match while the
    # Terraform-owned Owner key remains intact.
    param([string]$StorageAccountName, [string]$ResourceGroupName, [hashtable]$Settings)
    for ($attempt = 1; $attempt -le $Settings.RetryLimit; $attempt++) {
        $result = Invoke-AzJson @('storage', 'account', 'show', '--name', $StorageAccountName, '--resource-group', $ResourceGroupName)
        if ($result.ExitCode -eq 0 -and $null -ne $result.Data) {
            $tags = Get-JsonProperty -Object $result.Data -Name 'tags'
            $actual = $null
            $owner = $null
            if ($tags) { $actual = Get-JsonProperty -Object $tags -Name $ExpectedTagName }
            if ($tags) { $owner = Get-JsonProperty -Object $tags -Name 'Owner' }
            if ("$actual" -ceq $ExpectedTagValue -and "$owner" -ceq $ExpectedOwnerTagValue) {
                Write-RunLog "tag read-back: $ExpectedTagName='$actual' and Owner='$owner' after $attempt poll(s)"
                return $true
            }
            Write-RunLog "tag poll $attempt/$($Settings.RetryLimit): $ExpectedTagName='$actual', Owner='$owner'"
        }
        else {
            Write-RunLog "tag poll $attempt/$($Settings.RetryLimit): storage account read-back failed"
        }
        if ($attempt -lt $Settings.RetryLimit) { Start-Sleep -Seconds $Settings.IntervalSeconds }
    }
    Write-RunLog "tag read-back: expected $ExpectedTagName='$ExpectedTagValue' and Owner='$ExpectedOwnerTagValue' within $($Settings.DeadlineSeconds) s"
    return $false
}

function Assert-StorageTagInitiallyAbsent {
    param([string]$StorageAccountName, [string]$ResourceGroupName, [string]$TagName, [string]$OwnerValue)
    $result = Invoke-AzJson @('storage', 'account', 'show', '--name', $StorageAccountName, '--resource-group', $ResourceGroupName)
    if ($result.ExitCode -ne 0 -or $null -eq $result.Data) {
        $script:testFailed = $true
        Write-RunLog 'pre-assignment target baseline read-back failed'
        return $false
    }
    $tags = Get-JsonProperty -Object $result.Data -Name 'tags'
    $value = Get-JsonProperty -Object $tags -Name $TagName
    if ($null -ne $value -and "$value" -ne '') {
        $script:testFailed = $true
        Write-RunLog "pre-assignment target baseline FAILED: policy-owned tag '$TagName' already has a value"
        return $false
    }
    $owner = Get-JsonProperty -Object $tags -Name 'Owner'
    if ("$owner" -cne $OwnerValue) {
        $script:testFailed = $true
        Write-RunLog "pre-assignment target baseline FAILED: Terraform-owned Owner tag did not equal '$OwnerValue'"
        return $false
    }
    Write-RunLog "pre-assignment target baseline verified: policy-owned tag '$TagName' is absent and Owner='$owner' is present"
    return $true
}

function Get-VarFileValue {
    param([string]$Path, [string]$Name)
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match ('^\s*' + [regex]::Escape($Name) + '\s*=\s*"(.*)"\s*$')) { return $Matches[1] }
    }
    return $null
}

function Get-VarFileSwitch {
    param([string]$Path, [string]$Name)
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match ('^\s*' + [regex]::Escape($Name) + '\s*=\s*(true|false)\s*$')) { return ($Matches[1] -eq 'true') }
    }
    return $false
}

# The harness passes the expiry with -var, which overrides the variable file, so
# the recorded status must carry the file's value. A file without the key takes
# the caller's default.
function Get-VarFileExpiry {
    param([string]$Path, [string]$Default)
    $fileExpiry = ConvertTo-Rfc3339Expiry "$(Get-VarFileValue -Path $Path -Name 'exemption_expiry')"
    if ($fileExpiry) { return $fileExpiry }
    return $Default
}

function Get-SourceFingerprint {
    param([string]$Root)
    $sourceFilesByPath = @{}
    foreach ($relativeRoot in @('modules', 'examples', 'governance', 'catalogue', 'tests/integration')) {
        $path = Join-Path $Root $relativeRoot
        if (Test-Path -LiteralPath $path) {
            Get-ChildItem -LiteralPath $path -File -Recurse |
                Where-Object { $_.Extension -in @('.tf', '.json', '.ps1') -and $_.FullName -notmatch '[\\/](\.terraform|artifacts)[\\/]' } |
                ForEach-Object { $sourceFilesByPath[$_.FullName] = $_ }
        }
    }
    Get-ChildItem -LiteralPath $Root -File -Filter '*.tf' |
        ForEach-Object { $sourceFilesByPath[$_.FullName] = $_ }
    $lines = foreach ($file in @($sourceFilesByPath.Values) | Sort-Object FullName) {
        $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\\', '/')
        "$relative|$($file.Extension.ToLowerInvariant())|$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $digest = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($digest)
}

function Test-EmptyTerraformStateDocument {
    param($StateDocument)
    if ($null -eq $StateDocument -or $null -eq $StateDocument.resources) { return $false }
    return @($StateDocument.resources).Count -eq 0
}

function Get-DefaultStateSnapshot {
    param([string]$ExampleRoot)
    $primaryPath = Join-Path $ExampleRoot 'terraform.tfstate'
    $backupPath = "$primaryPath.backup"
    $files = @()
    if (Test-Path -LiteralPath $primaryPath) {
        try { $document = Get-Content -LiteralPath $primaryPath -Raw | ConvertFrom-Json }
        catch { throw "default Terraform state '$primaryPath' is malformed; refusing to use this example directory" }
        if (-not (Test-EmptyTerraformStateDocument -StateDocument $document)) {
            throw "default Terraform state '$primaryPath' contains managed resources; refusing to adopt or alter it"
        }
        $files += [ordered]@{ path = (Resolve-Path -LiteralPath $primaryPath).Path; sha256 = (Get-FileHash -LiteralPath $primaryPath -Algorithm SHA256).Hash; role = 'primary'; lineage = "$($document.lineage)"; serial = [int]$document.serial; length = (Get-Item -LiteralPath $primaryPath).Length }
    }
    if (Test-Path -LiteralPath $backupPath) {
        $files += [ordered]@{ path = (Resolve-Path -LiteralPath $backupPath).Path; sha256 = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash; role = 'backup'; lineage = $null; serial = $null; length = (Get-Item -LiteralPath $backupPath).Length }
    }
    return $files
}

function Assert-DefaultStateUnchanged {
    param([hashtable]$Status)
    $expected = @($Status['defaultStateSnapshot'])
    try { $actual = @(Get-DefaultStateSnapshot -ExampleRoot $Status['exampleRoot']) }
    catch { throw $_.Exception.Message }
    if ($actual.Count -ne $expected.Count) { throw 'pre-existing default Terraform state/backup inventory changed; refusing to continue cleanup or mutation' }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        if ($actual[$index].path -ine $expected[$index].path -or $actual[$index].role -cne $expected[$index].role -or $actual[$index].sha256 -cne $expected[$index].sha256) {
            throw "pre-existing default Terraform state/backup '$($expected[$index].path)' changed; refusing to continue cleanup or mutation"
        }
    }
    return $true
}

function Assert-RunInputsUnchanged {
    param([hashtable]$Status)
    Assert-RecordedApprovedContext -Status $Status
    $sourceHash = Get-SourceFingerprint -Root $script:repoRoot
    $varHash = (Get-FileHash -LiteralPath $Status['varFile'] -Algorithm SHA256).Hash
    if ($sourceHash -ne $Status['sourceFingerprint'] -or $varHash -ne $Status['varFileSha256']) {
        throw 'Terraform source or the protected variable file changed during the live run; stop before the next Azure mutation and reconcile state.'
    }
    return $true
}

function Get-InventoryIds {
    param($Items)
    $ids = @()
    foreach ($item in @($Items)) {
        $id = Get-JsonProperty -Object $item -Name 'id'
        if ($id) { $ids += "$id".ToLowerInvariant() }
    }
    return @($ids | Sort-Object -Unique)
}

function Test-InventoryMatchesBaseline {
    param([string]$BaselinePath, [string[]]$Arguments, [string]$Label, [hashtable]$Status, [switch]$OwnedAbsenceVerified)
    $before = @()
    if (Test-Path -LiteralPath $BaselinePath) {
        $saved = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $BaselinePath -Raw) -NoEnumerate
        $before = Get-InventoryIds -Items $saved
    }
    $current = Invoke-AzJson $Arguments
    if ($current.ExitCode -ne 0 -or $null -eq $current.Data) {
        Write-RunLog "$Label inventory read-back inconclusive; absence and preservation are not established"
        return $false
    }
    $after = Get-InventoryIds -Items $current.Data
    $missing = @($before | Where-Object { $_ -notin $after })
    $unexpected = @($after | Where-Object { $_ -notin $before })
    if ($missing.Count -eq 0 -and $unexpected.Count -gt 0 -and $OwnedAbsenceVerified -and $Status -and
        $Label -ceq 'resource groups' -and ($Arguments -join ' ') -ceq 'group list') {
        # A subscription is shared. Only unrelated new groups may be recorded as
        # environmental drift, after every owned absence check has passed.
        $ownedIds = @($Status['createdResourceIds'].Values | ForEach-Object { $_ } | ForEach-Object { "$($_)".ToLowerInvariant() })
        if ($Status['targetResourceGroupName']) { $ownedIds += "/subscriptions/$($Status['subscriptionId'])/resourceGroups/$($Status['targetResourceGroupName'])".ToLowerInvariant() }
        $groupPattern = '^/subscriptions/' + [regex]::Escape($script:approvedSubscriptionId) + '/resourcegroups/[^/]+$'
        $runNamePattern = if ($Status['runId']) { '*' + [string]$Status['runId'] + '*' } else { $null }
        $unrelatedOnly = @($unexpected | Where-Object {
            $_ -notmatch $groupPattern -or $_ -in $ownedIds -or ($runNamePattern -and ($_ -split '/')[-1] -like $runNamePattern)
        }).Count -eq 0
        if ($unrelatedOnly) {
            if (-not $Status.ContainsKey('environmentalDrift')) { $Status['environmentalDrift'] = @() }
            $Status['environmentalDrift'] += @{
                observedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
                inventory = 'resource groups'
                additionalIds = @($unexpected)
                ownedAbsenceVerified = $true
            }
            Write-RunLog "resource group baseline preserved; unrelated additions recorded as environmental drift, not deleted: $($unexpected -join ',')"
            return $true
        }
    }
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        Write-RunLog "$Label inventory differs from baseline: missing=$($missing -join ','); additional=$($unexpected -join ',')"
        return $false
    }
    Write-RunLog "$Label inventory matches the confirmed pre-run baseline"
    return $true
}

function Assert-NoPreexistingResourceCollisions {
    param(
        [ValidateSet('complete', 'minimal')][string]$Profile,
        [string]$AssignmentScopeId,
        [string]$TargetResourceGroupName,
        [string]$TargetStorageAccountName,
        [AllowNull()][object[]]$AssignmentsBaseline,
        [AllowNull()][object[]]$DefinitionsBaseline,
        [AllowNull()][object[]]$InitiativesBaseline
    )
    if ($Profile -eq 'complete') {
        if (@($DefinitionsBaseline | Where-Object { $_.name -ieq 'add-costcentre-tag' }).Count -gt 0) {
            throw 'the custom policy definition name add-costcentre-tag already exists in the approved subscription'
        }
        if (@($InitiativesBaseline | Where-Object { $_.name -ieq 'tag-governance' }).Count -gt 0) {
            throw 'the custom policy set name tag-governance already exists in the approved subscription'
        }
        $groupRead = Invoke-AzJson @('group', 'show', '--name', $TargetResourceGroupName)
        if ($groupRead.ExitCode -eq 0 -or -not (Test-NotFoundText $groupRead.Text)) {
            throw "target resource group '$TargetResourceGroupName' exists or its absence is inconclusive"
        }
        $storageNameRead = Invoke-AzJson @('storage', 'account', 'check-name', '--name', $TargetStorageAccountName)
        if ($storageNameRead.ExitCode -ne 0 -or $null -eq $storageNameRead.Data -or (Get-JsonProperty -Object $storageNameRead.Data -Name 'nameAvailable') -ne $true) {
            throw "storage account name '$TargetStorageAccountName' is unavailable or could not be checked"
        }
        return
    }

    $assignmentNames = @('audit-sub-subscription-built-in-audit', 'audit-sub-replacement-subscription-built-in-audit')
    foreach ($assignmentName in $assignmentNames) {
        $existingAssignment = @($AssignmentsBaseline | Where-Object { $_.name -ieq $assignmentName -and $_.scope -ieq $AssignmentScopeId })
        if ($existingAssignment.Count -gt 0) {
            throw "subscription policy assignment '$assignmentName' already exists at the approved scope"
        }
    }
}

function Get-ExpectedAzureResourceIds {
    param([hashtable]$Status)
    $ids = @()
    foreach ($class in $Status['createdResourceIds'].Keys) {
        foreach ($value in @($Status['createdResourceIds'][$class])) {
            if ($value -is [string] -and $value -match '^/subscriptions/') { $ids += $value.ToLowerInvariant() }
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Add-StateModuleResources {
    param($Module, [System.Collections.Generic.List[object]]$Resources)
    $moduleResources = Get-JsonProperty -Object $Module -Name 'resources'
    $childModules = Get-JsonProperty -Object $Module -Name 'child_modules'
    if ($null -ne $moduleResources -and $moduleResources -isnot [array]) { throw 'Terraform state module resources property is malformed' }
    if ($null -ne $childModules -and $childModules -isnot [array]) { throw 'Terraform state child_modules property is malformed' }
    if ($null -ne $moduleResources) {
        foreach ($resource in @($moduleResources)) {
            if ($null -eq $resource) { throw 'Terraform state contains a null resource record' }
            if ($resource.mode -eq 'data') { continue }
            $Resources.Add($resource)
        }
    }
    if ($null -ne $childModules) {
        foreach ($child in @($childModules)) {
            if ($null -eq $child) { throw 'Terraform state contains a null child module record' }
            Add-StateModuleResources -Module $child -Resources $Resources
        }
    }
}

function Get-AllowedStateResourcePatterns {
    param([ValidateSet('complete', 'minimal')][string]$Profile)
    $sharedGuards = @(
        '^module\.framework\.module\.catalogue\.terraform_data\.(json_ingestion_contract|initiative_ingestion_contract)$',
        '^module\.framework\.module\.content\.terraform_data\.initiative_ingestion_contract$',
        '^module\.framework\.module\.behaviour_resolution\.terraform_data\.contract_guard$',
        '^module\.framework\.module\.operations\.terraform_data\.remediation_contract_guard$',
        '^module\.framework\.module\.operations\.terraform_data\.exemption_contract_guard$',
        '^module\.framework\.module\.governance\.terraform_data\.contract_guard$'
    )
    if ($Profile -eq 'minimal') {
        return @{
            terraform_data = $sharedGuards + @(
                '^module\.framework\.module\.assignments\.terraform_data\.contract_guard\["audit-sub"\]$',
                '^module\.framework\.module\.assignments\.terraform_data\.contract_guard\["audit-sub-replacement"\]$'
            )
            azurerm_subscription_policy_assignment = @(
                '^module\.framework\.module\.assignments\.azurerm_subscription_policy_assignment\.this\["audit-sub"\]$',
                '^module\.framework\.module\.assignments\.azurerm_subscription_policy_assignment\.this\["audit-sub-replacement"\]$'
            )
        }
    }
    return @{
        terraform_data = $sharedGuards + @('^module\.framework\.module\.assignments\.terraform_data\.contract_guard\["modify-tag-rg"\]$')
        azurerm_resource_group = @('^azurerm_resource_group\.target$')
        azurerm_storage_account = @('^azurerm_storage_account\.target$')
        azurerm_policy_definition = @('^module\.framework\.module\.content\.azurerm_policy_definition\.this\["add-costcentre-tag"\]$')
        azurerm_policy_set_definition = @('^module\.framework\.module\.content\.azurerm_policy_set_definition\.subscription\["tag-governance"\]$')
        azurerm_resource_group_policy_assignment = @('^module\.framework\.module\.assignments\.azurerm_resource_group_policy_assignment\.this\["modify-tag-rg"\]$')
        azurerm_user_assigned_identity = @('^module\.framework\.module\.identity_rbac\.azurerm_user_assigned_identity\.this\["modify-tag-rg"\]$')
        azurerm_role_assignment = @('^module\.framework\.module\.identity_rbac\.azurerm_role_assignment\.this\["modify-tag-rg\|[0-9a-f]{40}"\]$')
        azurerm_resource_group_policy_remediation = @('^module\.framework\.module\.operations\.azurerm_resource_group_policy_remediation\.this\["remediate-tag-rg"\]$')
        azurerm_resource_group_policy_exemption = @('^module\.framework\.module\.operations\.azurerm_resource_group_policy_exemption\.this\["exempt-tag-rg-uat"\]$')
    }
}

function Test-RunWorkspaceState {
    param([hashtable]$Status)
    $tfRoot = '-chdir=' + $Status['exampleRoot']
    $selected = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'show')
    if ($selected.ExitCode -ne 0 -or (($selected.Output -join '').Trim() -cne $Status['terraformWorkspace'])) {
        Write-RunLog 'state isolation FAILED: active Terraform workspace does not match the recorded per-run workspace'
        return $false
    }
    $state = Invoke-Terraform -TerraformArguments @($tfRoot, 'show', '-json')
    if ($state.ExitCode -ne 0) {
        Write-RunLog 'state isolation FAILED: Terraform could not read the recorded run workspace state'
        return $false
    }
    try { $stateJson = ($state.Output -join "`n") | ConvertFrom-Json }
    catch { Write-RunLog 'state isolation FAILED: Terraform state JSON could not be parsed'; return $false }
    if ($null -eq $stateJson.values -or $null -eq $stateJson.values.root_module) {
        Write-RunLog 'state isolation FAILED: Terraform state has no root module resource inventory'
        return $false
    }
    $resources = [System.Collections.Generic.List[object]]::new()
    Add-StateModuleResources -Module $stateJson.values.root_module -Resources $resources
    $expectedIds = Get-ExpectedAzureResourceIds -Status $Status
    $allowedPatterns = Get-AllowedStateResourcePatterns -Profile $Status['profile']
    $subPrefix = "/subscriptions/$($Status['subscriptionId'])/".ToLowerInvariant()
    $unexpected = @()
    foreach ($resource in $resources) {
        $type = "$($resource.type)"
        $address = "$($resource.address)"
        $id = "$(Get-JsonProperty -Object $resource.values -Name 'id')"
        if (-not $allowedPatterns.ContainsKey($type) -or @($allowedPatterns[$type] | Where-Object { $address -match $_ }).Count -eq 0) {
            $unexpected += "$address (unreviewed managed type/address $type)"
            continue
        }
        if ($type -eq 'terraform_data') {
            if ([string]::IsNullOrWhiteSpace($id) -or $id -match '^/subscriptions/') { $unexpected += "$address (terraform_data ID is missing or was misclassified as an Azure resource ID)" }
            continue
        }
        if ([string]::IsNullOrWhiteSpace($id) -or -not $id.ToLowerInvariant().StartsWith($subPrefix)) {
            $unexpected += "$address (Azure resource ID is outside the approved subscription or missing)"
            continue
        }
        if ($id.ToLowerInvariant() -notin $expectedIds) { $unexpected += "$address => unmanifested Azure ID $id" }
    }
    if ($resources.Count -eq 0 -or $unexpected.Count -gt 0) {
        Write-RunLog "state isolation FAILED: empty state or unmanifested resource(s): $($unexpected -join '; ')"
        return $false
    }
    Write-RunLog "state isolation verified: workspace '$($Status['terraformWorkspace'])' contains $($resources.Count) managed resource(s), and every Azure ID belongs to this run's captured manifest"
    return $true
}

function Test-MissingLocalStateDiagnostic {
    param([string]$StatePath, [hashtable]$StateListResult)
    if ([string]::IsNullOrWhiteSpace($StatePath)) { return $false }
    $lines = @($StateListResult.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    # A fresh local workspace, including default, may have no state file.
    # Accept only Terraform's exact no-state diagnostic while the canonical
    # path remains absent.
    if ($StateListResult.ExitCode -ne 1 -or (Test-Path -LiteralPath $StatePath)) { return $false }
    $missingFileMessageCount = @($lines | Where-Object { $_ -ceq 'No state file was found!' }).Count
    $knownDiagnosticLines = @(
        'No state file was found!',
        'System.Management.Automation.RemoteException',
        'State management commands require a state file. Run this command',
        'in a directory where Terraform has been run or use the -state flag',
        'to point the command to a specific state location.',
        'to point to a specific state location.'
    )
    $unknownLines = @($lines | Where-Object { $_ -cnotin $knownDiagnosticLines })
    return $missingFileMessageCount -eq 1 -and $unknownLines.Count -eq 0
}

function Test-NewWorkspaceEmpty {
    param([bool]$WorkspaceCreated, [string]$StatePath, [hashtable]$StateListResult)
    if (-not $WorkspaceCreated -or [string]::IsNullOrWhiteSpace($StatePath)) { return $false }
    $lines = @($StateListResult.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($StateListResult.ExitCode -eq 0) { return $lines.Count -eq 0 }
    return Test-MissingLocalStateDiagnostic -StatePath $StatePath -StateListResult $StateListResult
}

function Test-PostDestroyWorkspaceState {
    param([hashtable]$Status)
    $statePath = "$($Status['terraformStatePath'])"
    if (-not $statePath -or "$($Status['preDestroyStatePath'])" -ine $statePath -or
        @($Status['preDestroyStateAddresses'] | Where-Object { $_ }).Count -eq 0 -or -not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $false }
    $tfRoot = '-chdir=' + $Status['exampleRoot']
    $selected = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'show')
    $remaining = Invoke-Terraform -TerraformArguments @($tfRoot, 'state', 'list', '-no-color')
    if ($selected.ExitCode -ne 0 -or (($selected.Output -join '').Trim() -cne $Status['terraformWorkspace']) -or
        $remaining.ExitCode -ne 0 -or @($remaining.Output | Where-Object { ([string]$_).Trim() }).Count -gt 0) { return $false }
    try { $document = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
    catch { return $false }
    if (-not (Test-EmptyTerraformStateDocument -StateDocument $document)) { return $false }
    Assert-DefaultStateUnchanged -Status $Status | Out-Null
    Write-RunLog 'recorded pre-destroy inventory now has empty isolated state; resuming post-destroy Azure absence and baseline checks'
    return $true
}

function Get-PolicyDeleteArguments {
    param([string]$ResourceId, [hashtable]$Status)
    if ([string]::IsNullOrWhiteSpace($ResourceId) -or [string]::IsNullOrWhiteSpace($Status['subscriptionId']) -or $Status['profile'] -notin @('complete', 'minimal', 'supplemental')) {
        throw 'unsupported subscription-scoped delete contract: required resource ID or run scope is empty'
    }
    if ($Status['profile'] -in @('complete', 'supplemental') -and [string]::IsNullOrWhiteSpace($Status['targetResourceGroupName'])) {
        throw "unsupported subscription-scoped delete contract: $($Status['profile']) profile target resource group is empty"
    }
    $sub = [regex]::Escape($Status['subscriptionId'])
    $rg = ''
    if ($Status['profile'] -in @('complete', 'supplemental')) { $rg = [regex]::Escape($Status['targetResourceGroupName']) }
    if ($ResourceId -notmatch "^/subscriptions/$sub(?:/|$)") {
        throw 'out-of-scope policy resource ID: subscription does not match the recorded run subscription'
    }
    if ($Status['profile'] -eq 'minimal') { $rg = '(?!)' }
    if ($Status['profile'] -eq 'supplemental') {
        $targetResourceId = [string]$Status['targetResourceId']
        if ([string]::IsNullOrWhiteSpace($targetResourceId) -or $targetResourceId -notmatch "^/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft\.Storage/storageAccounts/[^/]+$") {
            throw 'unsupported supplemental delete contract: recorded target resource ID is outside the exact run storage resource'
        }
        $target = [regex]::Escape($targetResourceId)
        if ($ResourceId -match "^$target/providers/Microsoft\.PolicyInsights/remediations/([^/]+)$") {
            return ,@('policy', 'remediation', 'delete', '--name', $Matches[1], '--resource', $targetResourceId, '--subscription', $Status['subscriptionId'], '--output', 'none')
        }
        if ($ResourceId -match "^$target/providers/Microsoft\.Authorization/policyAssignments/([^/]+)$") {
            return ,@('policy', 'assignment', 'delete', '--name', $Matches[1], '--scope', $targetResourceId, '--subscription', $Status['subscriptionId'], '--output', 'none')
        }
    }
    if ($ResourceId -match "^/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft\.Authorization/policyExemptions/([^/]+)$") {
        return ,@('policy', 'exemption', 'delete', '--name', $Matches[1], '--resource-group', $Status['targetResourceGroupName'], '--subscription', $Status['subscriptionId'], '--output', 'none')
    }
    if ($ResourceId -match "^/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft\.PolicyInsights/remediations/([^/]+)$") {
        return ,@('policy', 'remediation', 'delete', '--name', $Matches[1], '--resource-group', $Status['targetResourceGroupName'], '--subscription', $Status['subscriptionId'], '--output', 'none')
    }
    if ($ResourceId -match "^/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft\.Authorization/policyAssignments/([^/]+)$") {
        $scope = "/subscriptions/$($Status['subscriptionId'])/resourceGroups/$($Status['targetResourceGroupName'])"
        return ,@('policy', 'assignment', 'delete', '--name', $Matches[1], '--scope', $scope, '--subscription', $Status['subscriptionId'], '--output', 'none')
    }
    if ($Status['profile'] -eq 'minimal' -and $ResourceId -match "^/subscriptions/$sub/providers/Microsoft\.Authorization/policyAssignments/([^/]+)$") {
        $scope = "/subscriptions/$($Status['subscriptionId'])"
        return ,@('policy', 'assignment', 'delete', '--name', $Matches[1], '--scope', $scope, '--subscription', $Status['subscriptionId'], '--output', 'none')
    }
    if ($ResourceId -match "^/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft\.Authorization/roleAssignments/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$") {
        return ,@('role', 'assignment', 'delete', '--ids', $ResourceId, '--subscription', $Status['subscriptionId'], '--output', 'none')
    }
    if ($ResourceId -match "^/subscriptions/$sub/providers/Microsoft\.Authorization/policySetDefinitions/([^/]+)$") {
        return ,@('policy', 'set-definition', 'delete', '--name', $Matches[1], '--subscription', $Status['subscriptionId'], '--output', 'none')
    }
    if ($ResourceId -match "^/subscriptions/$sub/providers/Microsoft\.Authorization/policyDefinitions/([^/]+)$") {
        return ,@('policy', 'definition', 'delete', '--name', $Matches[1], '--subscription', $Status['subscriptionId'], '--output', 'none')
    }
    throw 'unsupported subscription-scoped delete contract: resource ID type or scope does not match the approved run profile'
}

function Remove-ExactPolicyResources {
    param([hashtable]$Status)
    try { Assert-DefaultStateUnchanged -Status $Status | Out-Null }
    catch { $script:cleanupFailed = $true; Write-RunLog "exact Azure cleanup stopped: $($_.Exception.Message)"; return $false }
    try { Assert-RunInputsUnchanged -Status $Status | Out-Null }
    catch { $script:cleanupFailed = $true; Write-RunLog "exact Azure cleanup stopped: $($_.Exception.Message)"; return $false }
    $manifest = $Status['createdResourceIds']
    $classes = @('exemptions', 'remediations', 'assignments', 'role_assignments', 'set_definition_id', 'definition_ids')
    $requiredClasses = @()
    $stages = @($Status['appliedStages']) + @($Status['activeStage'])
    if ($Status['profile'] -eq 'minimal') {
        # The built-in assignment is the only policy resource created.
        if ($stages -contains 'minimal-apply') { $requiredClasses += 'assignments' }
    }
    else {
        if (@($stages | Where-Object { $_ -in @('stage-0b', 'stage-1a', 'stage-1b', 'stage-1c', 'stage-2', 'renewal') }).Count -gt 0) { $requiredClasses += @('set_definition_id', 'definition_ids') }
        if (@($stages | Where-Object { $_ -in @('stage-1b', 'stage-1c', 'stage-2', 'renewal') }).Count -gt 0) { $requiredClasses += @('assignments', 'role_assignments') }
        if (@($stages | Where-Object { $_ -in @('stage-1c', 'stage-2', 'renewal') }).Count -gt 0) { $requiredClasses += 'remediations' }
        if (@($stages | Where-Object { $_ -in @('stage-2', 'renewal') }).Count -gt 0) { $requiredClasses += 'exemptions' }
    }
    $required = @()
    foreach ($class in $classes) {
        if ($class -in $requiredClasses) { $required += @($manifest[$class]) }
    }
    $missing = @($required | Where-Object { -not $_ })
    if ($missing.Count -gt 0) {
        Write-RunLog 'exact Azure deletion refused: a stage may have created a policy resource whose exact ID was not captured'
        return $false
    }

    $subscriptionPrefix = "/subscriptions/$($Status['subscriptionId'])/"
    foreach ($id in $required) {
        $normalized = "$id".ToLowerInvariant()
        if (-not $normalized.StartsWith($subscriptionPrefix.ToLowerInvariant())) { Write-RunLog 'exact Azure deletion refused: a captured policy ID is outside the approved subscription'; return $false }
        try { $arguments = Get-PolicyDeleteArguments -ResourceId $id -Status $Status }
        catch { Write-RunLog "exact Azure deletion refused: $($_.Exception.Message)"; return $false }
        $Status['deletePendingId'] = $id
        $Status['manualDeletionStarted'] = $true
        Save-RunStatus -Status $Status
        $present = Test-ResourceAbsentNow -ResourceId $id
        if ($present -eq 'Present') {
            try { Assert-RunInputsUnchanged -Status $Status | Out-Null }
            catch { $script:cleanupFailed = $true; Write-RunLog "exact Azure deletion stopped: $($_.Exception.Message)"; return $false }
            try { Assert-ApprovedAzureContext }
            catch { Write-RunLog "exact Azure deletion stopped: $($_.Exception.Message)"; return $false }
            $delete = Invoke-Az $arguments
            if ($delete.ExitCode -ne 0) {
                $present = Test-ResourceAbsentNow -ResourceId $id
                if ($present -ne 'Absent') {
                    $script:cleanupFailed = $true
                    Write-RunLog "exact Azure deletion failed or was inconclusive for $($id.Split('/')[-1]); cleanup will resume from this recorded ID"
                    return $false
                }
            }
        }
        if (-not (Wait-Absence -Label "exact Azure policy resource $($id.Split('/')[-1])" -ProbeKind 'ResourceId' -Target $id -Settings $script:Polling.Absence)) {
            $script:cleanupFailed = $true
            return $false
        }
        $Status['deletedPolicyResourceIds'] = @($Status['deletedPolicyResourceIds']) + $id
        $Status['deletePendingId'] = $null
        Save-RunStatus -Status $Status
    }
    $Status['policyResourcesRemoved'] = $true
    Save-RunStatus -Status $Status
    return $true
}

function Get-OutputValue {
    param($Outputs, [string[]]$Candidates)
    foreach ($name in $Candidates) {
        $entry = Get-JsonProperty -Object $Outputs -Name $name
        if ($null -ne $entry) {
            $value = Get-JsonProperty -Object $entry -Name 'value'
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }
    return $null
}

function Get-OutputLeafValues {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return }
    if ($Value -is [string]) { return ,$Value }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($item in $Value.Values) { Get-OutputLeafValues -Value $item }
        return
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) { Get-OutputLeafValues -Value $property.Value }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) { Get-OutputLeafValues -Value $item }
    }
}

function Add-CapturedResourceId {
    param([hashtable]$Status, [string]$Class, [AllowNull()][object]$ResourceId)
    if ($null -eq $ResourceId) { return $true }
    if ($ResourceId -isnot [string] -or [string]::IsNullOrWhiteSpace($ResourceId)) {
        Write-RunLog "output ID capture FAILED: $Class contains a non-string or empty resource ID"
        $script:testFailed = $true
        return $false
    }

    $id = $ResourceId.Trim()
    if ($Class -in @('assignments', 'role_assignments', 'remediations', 'exemptions', 'definition_ids', 'set_definition_id')) {
        try { $null = Get-PolicyDeleteArguments -ResourceId $id -Status $Status }
        catch {
            Write-RunLog "output ID capture FAILED: $Class ID does not match the recorded run subscription, scope and resource type"
            $script:testFailed = $true
            return $false
        }
    }
    elseif ($Class -eq 'identities') {
        $subscription = [regex]::Escape([string]$Status['subscriptionId'])
        $resourceGroup = [regex]::Escape([string]$Status['targetResourceGroupName'])
        if ($id -notmatch "^/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft\.ManagedIdentity/userAssignedIdentities/[^/]+$") {
            Write-RunLog 'output ID capture FAILED: identity ID does not match the recorded run subscription and resource group'
            $script:testFailed = $true
            return $false
        }
    }
    elseif ($Class -eq 'principals') {
        if ($id -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            Write-RunLog 'output ID capture FAILED: principal ID is not a GUID'
            $script:testFailed = $true
            return $false
        }
    }
    else {
        Write-RunLog "output ID capture FAILED: unsupported resource class '$Class'"
        $script:testFailed = $true
        return $false
    }

    if (-not $Status['createdResourceIds'].ContainsKey($Class)) { $Status['createdResourceIds'][$Class] = @() }
    if (@($Status['createdResourceIds'][$Class] | Where-Object { "$_" -ieq $id }).Count -eq 0) {
        $Status['createdResourceIds'][$Class] += $id
    }
    return $true
}

function Add-CapturedOutputClassIds {
    param([hashtable]$Status, [string]$Class, [AllowNull()][object]$Value)
    $valid = $true
    foreach ($id in @(Get-OutputLeafValues -Value $Value)) {
        if (-not (Add-CapturedResourceId -Status $Status -Class $Class -ResourceId $id)) { $valid = $false }
    }
    return $valid
}

function Get-AssignmentReviewMap {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return @{} }
    return (ConvertTo-Hashtable -Object $Value)
}

function Update-CapturedStateIds {
    param([hashtable]$Status)
    $tfRoot = '-chdir=' + $Status['exampleRoot']
    $result = Invoke-Terraform -TerraformArguments @($tfRoot, 'show', '-json')
    if ($result.ExitCode -ne 0) {
        Write-RunLog 'Terraform state ID capture failed: show -json returned a non-zero exit code'
        $script:testFailed = $true
        return $false
    }
    try { $state = (($result.Output -join "`n") | ConvertFrom-Json) }
    catch {
        Write-RunLog 'Terraform state ID capture failed: show -json returned invalid JSON'
        $script:testFailed = $true
        return $false
    }
    $rootModule = Get-JsonProperty -Object (Get-JsonProperty -Object $state -Name 'values') -Name 'root_module'
    if ($null -eq $rootModule) {
        Write-RunLog 'Terraform state ID capture failed: root module resource inventory is missing'
        $script:testFailed = $true
        return $false
    }

    $classByType = @{
        azurerm_policy_definition = 'definition_ids'
        azurerm_policy_set_definition = 'set_definition_id'
        azurerm_subscription_policy_assignment = 'assignments'
        azurerm_resource_group_policy_assignment = 'assignments'
        azurerm_user_assigned_identity = 'identities'
        azurerm_role_assignment = 'role_assignments'
        azurerm_resource_group_policy_remediation = 'remediations'
        azurerm_resource_group_policy_exemption = 'exemptions'
    }
    $allowedPatterns = Get-AllowedStateResourcePatterns -Profile $Status['profile']
    $resources = [System.Collections.Generic.List[object]]::new()
    Add-StateModuleResources -Module $rootModule -Resources $resources
    $valid = $true
    foreach ($resource in $resources) {
        if ($resource.mode -eq 'data' -or $resource.type -eq 'terraform_data') { continue }
        $type = [string]$resource.type
        $address = [string]$resource.address
        if (-not $allowedPatterns.ContainsKey($type) -or @($allowedPatterns[$type] | Where-Object { $address -match $_ }).Count -eq 0) {
            Write-RunLog "Terraform state ID capture FAILED: managed resource '$address' is outside the profile allowlist"
            $script:testFailed = $true
            $valid = $false
            continue
        }
        if (-not $classByType.ContainsKey($type)) { continue }
        $class = $classByType[$type]
        $id = Get-JsonProperty -Object $resource.values -Name 'id'
        if ($null -ne $id -and -not (Add-CapturedResourceId -Status $Status -Class $class -ResourceId $id)) { $valid = $false }
        if ($type -eq 'azurerm_user_assigned_identity') {
            $principalId = Get-JsonProperty -Object $resource.values -Name 'principal_id'
            if ($null -ne $principalId -and -not (Add-CapturedResourceId -Status $Status -Class 'principals' -ResourceId $principalId)) { $valid = $false }
        }
    }
    return $valid
}

function ConvertTo-Hashtable {
    param($Object)
    $result = @{}
    if ($null -eq $Object) { return $result }
    foreach ($prop in $Object.PSObject.Properties) {
        $value = $prop.Value
        if ($value -is [System.Management.Automation.PSCustomObject]) {
            $value = ConvertTo-Hashtable -Object $value
        }
        elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            $value = @($value)
        }
        $result[$prop.Name] = $value
    }
    return $result
}

function ConvertTo-ExitCode {
    # R12 status mapping: either failure fails the run, and both are visible
    # in the exit code. StatusPathDemo asserts this mapping deterministically.
    param([bool]$TestFailed, [bool]$CleanupFailed)
    if ($TestFailed -and $CleanupFailed) { return 3 }
    if ($CleanupFailed) { return 2 }
    if ($TestFailed) { return 1 }
    return 0
}

function Write-StatusReport {
    $testText = 'PASSED'; if ($script:testFailed) { $testText = 'FAILED' }
    $cleanupText = 'PASSED'; if ($script:cleanupFailed) { $cleanupText = 'FAILED' }
    if ($script:cleanupPaused) { $cleanupText = 'PAUSED (intentional recovery probe; resume with CleanupOnly)' }
    $code = ConvertTo-ExitCode -TestFailed:$script:testFailed -CleanupFailed:$script:cleanupFailed
    Write-Host ''
    Write-Host 'run summary (test and cleanup statuses are reported separately)'
    Write-Host "  test status:    $testText"
    Write-Host "  cleanup status: $cleanupText"
    Write-Host "  exit code:      $code (0 pass, 1 test failure, 2 cleanup failure, 3 test and cleanup incomplete)"
    if ($script:logPath) {
        Add-Content -LiteralPath $script:logPath -Value "test status: $testText; cleanup status: $cleanupText; exit code: $code" -Encoding utf8
    }
}

function Save-RunStatus {
    # This private file is the recovery record, so it retains real Azure IDs.
    # Only console/log output is redacted. The directory is ignored and must
    # remain local because Terraform destroy needs the original identifiers.
    param([hashtable]$Status)
    if ($script:statusPath) {
        $json = ConvertTo-Json -InputObject $Status -Depth 8
        $tempPath = "$($script:statusPath).tmp"
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tempPath -Destination $script:statusPath -Force
    }
}

function Get-StageVarArguments {
    # Command-line -var values mirror the recorded final-stage configuration
    # exactly so plan and destroy match what was applied.
    param([hashtable]$Status)
    $values = $Status['terraformVars']
    $varArgs = @()
    if ($Status['profile'] -eq 'complete') { $varArgs += @('-var', ('evaluation_time=' + (ConvertTo-Rfc3339Argument $Status['evaluationTime']))) }
    if ($Status['profile'] -eq 'minimal') {
        $varArgs += @('-var', "assignment_scope_id=$($Status['assignmentScopeId'])")
        $varArgs += @('-var', "assignment_key=$($values['assignment_key'])")
        $varArgs += @('-var', "assignment_owner=$($values['assignment_owner'])")
    }
    if ("$($values['create_exemption'])" -eq 'true') {
        $varArgs += @('-var', 'create_exemption=true')
        if ("$($values['exemption_assignment_id'])") {
            $varArgs += @('-var', "exemption_assignment_id=$($values['exemption_assignment_id'])")
        }
    }
    if ($Status['profile'] -eq 'complete' -and "$($values['exemption_expiry'])") {
        $varArgs += @('-var', ('exemption_expiry=' + (ConvertTo-Rfc3339Argument $values['exemption_expiry'])))
    }
    return $varArgs
}

function Get-TerraformBaseArguments {
    param([hashtable]$Status)
    return ,(@('-input=false', '-no-color', ('-var-file=' + $Status['varFile'])) + (Get-StageVarArguments -Status $Status))
}

function Get-TerraformOutputArguments {
    param([hashtable]$Status)
    return ,@(( '-chdir=' + $Status['exampleRoot'] ), 'output', '-json')
}

function Get-TerraformReviewedPlanArguments {
    param([hashtable]$Status, [string]$PlanPath, [string[]]$AdditionalPlanArguments = @())
    $tfRoot = '-chdir=' + $Status['exampleRoot']
    return ,(@($tfRoot, 'plan', '-detailed-exitcode', '-no-color', ('-out=' + $PlanPath)) + $AdditionalPlanArguments + @(('-var-file=' + $Status['varFile'])) + (Get-StageVarArguments -Status $Status))
}

function Get-TerraformConvergenceArguments {
    param([hashtable]$Status, [string[]]$ExtraVars)
    $planVars = Get-StageVarArguments -Status $Status
    return ,(@(( '-chdir=' + $Status['exampleRoot'] ), 'plan', '-detailed-exitcode') + @('-input=false', '-no-color', ('-var-file=' + $Status['varFile'])) + $planVars + $ExtraVars)
}

function Get-TerraformDestroyArguments {
    param([hashtable]$Status, [string[]]$FinalVars)
    $tfRoot = '-chdir=' + $Status['exampleRoot']
    return ,(@($tfRoot, 'destroy', '-auto-approve') + @('-input=false', '-no-color', ('-var-file=' + $Status['varFile'])) + $FinalVars)
}

function Get-BackendDisabledInitArguments {
    param([string]$ExampleRoot)
    $arguments = @()
    $arguments += '-chdir=' + $ExampleRoot
    $arguments += 'init'
    $arguments += '-backend=false'
    $arguments += '-input=false'
    $arguments += '-no-color'
    return ,$arguments
}

function Update-CapturedOutputs {
    param([hashtable]$Status)
    $valid = $true
    $outputs = $null
    $r = Invoke-Terraform -TerraformArguments (Get-TerraformOutputArguments -Status $Status)
    if ($r.ExitCode -ne 0) {
        Write-RunLog 'terraform output -json failed; resource identifiers not captured'
        $valid = $false
    }
    elseif ($r.ExitCode -eq 0) {
        try { $outputs = (($r.Output -join "`n") | ConvertFrom-Json) }
        catch {
            Write-RunLog 'terraform output json parse failed; resource identifiers not captured'
            $valid = $false
        }
    }

    if ($null -ne $outputs) {
        $idsOutput = Get-OutputValue -Outputs $outputs -Candidates @($script:OutputCandidates.lifecycle_resource_ids)
        if ($null -ne $idsOutput) {
            $Status['lifecycleResourceIds'] = ConvertTo-Hashtable -Object $idsOutput
            foreach ($kind in @('assignments', 'identities', 'principals', 'role_assignments', 'remediations', 'exemptions')) {
                $kindOutput = Get-JsonProperty -Object $idsOutput -Name $kind
                if (-not (Add-CapturedOutputClassIds -Status $Status -Class $kind -Value $kindOutput)) { $valid = $false }
            }
        }

        # The minimal example publishes assignment_id inside its review map;
        # the complete example publishes the same resource through resolved_assignments
        # and resolved_assignment_id. Keep those public contracts usable directly.
        $reviewOutput = Get-OutputValue -Outputs $outputs -Candidates @($script:OutputCandidates.assignment_review)
        if ($null -ne $reviewOutput) {
            $review = Get-AssignmentReviewMap -Value $reviewOutput
            $Status['resolvedAssignmentReview'] = $review
            foreach ($key in $review.Keys) {
                $record = $review[$key]
                $assignment = Get-JsonProperty -Object $record -Name 'assignment'
                $id = Get-JsonProperty -Object $record -Name 'assignment_id'
                if ($null -eq $id) { $id = Get-JsonProperty -Object $assignment -Name 'id' }
                if ($null -ne $id -and -not (Add-CapturedResourceId -Status $Status -Class 'assignments' -ResourceId $id)) { $valid = $false }
            }
        }
        $directAssignmentId = Get-OutputValue -Outputs $outputs -Candidates @($script:OutputCandidates.assignment_id)
        if ($null -ne $directAssignmentId -and -not (Add-CapturedResourceId -Status $Status -Class 'assignments' -ResourceId $directAssignmentId)) { $valid = $false }

        foreach ($class in @('definition_ids', 'set_definition_id')) {
            $value = Get-OutputValue -Outputs $outputs -Candidates @($script:OutputCandidates[$class])
            if ($null -ne $value -and -not (Add-CapturedOutputClassIds -Status $Status -Class $class -Value $value)) { $valid = $false }
        }
    }

    # Current public examples expose assignment and content IDs, but do not
    # expose every Azure resource ID needed by the exact cleanup manifest.
    if (-not (Update-CapturedStateIds -Status $Status)) { $valid = $false }
    Save-RunStatus -Status $Status
    if (-not $valid) { $script:testFailed = $true }
    return $valid
}

function Capture-TargetResourceId {
    param([hashtable]$Status, [string]$Stage)
    if ($Status['profile'] -ne 'complete') { return }
    $class = $null
    $result = $null
    if ($Stage -eq 'stage-0a') {
        $class = 'resource_groups'
        $result = Invoke-AzJson @('group', 'show', '--name', $Status['targetResourceGroupName'])
    }
    elseif ($Stage -eq 'stage-1a') {
        $class = 'storage_accounts'
        $result = Invoke-AzJson @('storage', 'account', 'show', '--name', $Status['targetStorageAccountName'], '--resource-group', $Status['targetResourceGroupName'])
    }
    if ($class -and $result.ExitCode -eq 0 -and $result.Data) {
        $id = "$(Get-JsonProperty -Object $result.Data -Name 'id')"
        if ($id) {
            if (-not $Status['createdResourceIds'].ContainsKey($class)) { $Status['createdResourceIds'][$class] = @() }
            if ($id -notin $Status['createdResourceIds'][$class]) { $Status['createdResourceIds'][$class] += $id }
            Save-RunStatus -Status $Status
            Write-RunLog "$class run-owned resource ID captured after $Stage"
        }
    }
}

function Invoke-TrackedApply {
    param([hashtable]$Status, [string]$Stage, [string[]]$TerraformArguments)
    Assert-RunInputsUnchanged -Status $Status | Out-Null
    Assert-ApprovedAzureContext
    $script:mutationStarted = $true
    $Status['mutationStarted'] = $true
    $Status['activeStage'] = $Stage
    Save-RunStatus -Status $Status
    $result = Invoke-Terraform -TerraformArguments $TerraformArguments -FullLog
    # Capture partial state too: a failed apply can still create earlier
    # resources before Terraform reports an error.
    $outputsCaptured = Update-CapturedOutputs -Status $Status
    Capture-TargetResourceId -Status $Status -Stage $Stage
    if (-not $outputsCaptured -and $result.ExitCode -eq 0) { $result.ExitCode = 1 }
    if ($result.ExitCode -eq 0 -and -not (@($Status['appliedStages']) -contains $Stage)) {
        $Status['appliedStages'] = @($Status['appliedStages']) + $Stage
    }
    Save-RunStatus -Status $Status
    return $result
}

function Initialize-RunWorkspace {
    param([hashtable]$Status)
    Assert-DefaultStateUnchanged -Status $Status | Out-Null
    $tfRoot = '-chdir=' + $Status['exampleRoot']
    $current = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'show')
    if ($current.ExitCode -ne 0 -or (($current.Output -join '').Trim() -cne 'default')) { throw 'the example must be in the default workspace before a new live run can create its isolated workspace' }
    $defaultState = Invoke-Terraform -TerraformArguments @($tfRoot, 'state', 'list', '-no-color')
    $defaultStatePath = Join-Path $Status['exampleRoot'] 'terraform.tfstate'
    $defaultEmpty = ($defaultState.ExitCode -eq 0 -and @($defaultState.Output | Where-Object { ([string]$_).Trim() }).Count -eq 0) -or
        (Test-MissingLocalStateDiagnostic -StatePath $defaultStatePath -StateListResult $defaultState)
    if (-not $defaultEmpty) { throw 'the default example state is not empty or its absence is inconclusive; live execution refuses to adopt existing state' }
    $workspace = 'uat-' + $Status['runId']
    $listed = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'list', '-no-color')
    if ($listed.ExitCode -ne 0) { throw 'Terraform workspace inventory failed; live execution cannot prove workspace uniqueness' }
    $names = @($listed.Output | ForEach-Object { ([string]$_ -replace '^\s*\*?\s*', '').Trim() })
    if ($workspace -in $names) { throw "per-run Terraform workspace '$workspace' already exists; choose a new RunId or reconcile the previous run" }
    $created = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'new', $workspace)
    if ($created.ExitCode -ne 0) { throw "Terraform could not create isolated workspace '$workspace'" }
    $statePath = Join-Path $Status['exampleRoot'] ('terraform.tfstate.d/' + $workspace + '/terraform.tfstate')
    $Status['terraformWorkspace'] = $workspace
    $Status['terraformStatePath'] = $statePath
    $Status['workspaceInitiallyEmpty'] = $false
    Save-RunStatus -Status $Status
    $selected = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'show')
    $state = Invoke-Terraform -TerraformArguments @($tfRoot, 'state', 'list', '-no-color')
    if ($selected.ExitCode -ne 0 -or (($selected.Output -join '').Trim() -cne $workspace) -or -not (Test-NewWorkspaceEmpty -WorkspaceCreated $true -StatePath $statePath -StateListResult $state)) {
        throw "new Terraform workspace '$workspace' is not empty or not selected; live execution is blocked"
    }
    $Status['workspaceInitiallyEmpty'] = $true
    Assert-DefaultStateUnchanged -Status $Status | Out-Null
    Save-RunStatus -Status $Status
    Write-RunLog "isolated Terraform workspace '$workspace' created empty; module sources remain rooted at the published example path"
}

function Assert-AssignmentBinding {
    param([string]$Label, [string]$AssignmentId, [string]$ExpectedScope, [string]$ExpectedIdentityId, [string]$ExpectedPolicySetId, [hashtable]$ExpectedParameters)
    $assignmentName = ($AssignmentId -split '/')[-1]
    $result = Invoke-AzJson @('policy', 'assignment', 'show', '--name', $assignmentName, '--scope', $ExpectedScope, '--subscription', $script:approvedSubscriptionId)
    if ($result.ExitCode -ne 0 -or $null -eq $result.Data) {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: assignment read-back failed"
        return $false
    }
    $props = Get-JsonProperty -Object $result.Data -Name 'properties'
    $actualId = "$(Get-JsonProperty -Object $result.Data -Name 'id')"
    $scope = Get-JsonProperty -Object $result.Data -Name 'scope'
    if ($null -eq $scope) { $scope = Get-JsonProperty -Object $props -Name 'scope' }
    $policyDefinitionId = Get-JsonProperty -Object $result.Data -Name 'policyDefinitionId'
    if ($null -eq $policyDefinitionId) { $policyDefinitionId = Get-JsonProperty -Object $props -Name 'policyDefinitionId' }
    $scope = "$scope"
    $policyDefinitionId = "$policyDefinitionId"
    if ($actualId.ToLowerInvariant() -ne $AssignmentId.ToLowerInvariant() -or $scope.ToLowerInvariant() -ne $ExpectedScope.ToLowerInvariant() -or $policyDefinitionId.ToLowerInvariant() -ne $ExpectedPolicySetId.ToLowerInvariant()) {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: assignment ID, scope or policy set binding differs from the run outputs"
        return $false
    }
    $identity = Get-JsonProperty -Object $result.Data -Name 'identity'
    $identityType = "$(Get-JsonProperty -Object $identity -Name 'type')"
    if ($identityType -ne 'UserAssigned') {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: assignment identity type '$identityType' is not UserAssigned"
        return $false
    }
    $boundIds = @()
    $userAssigned = Get-JsonProperty -Object $identity -Name 'userAssignedIdentities'
    if ($userAssigned) { $boundIds = @($userAssigned.PSObject.Properties.Name) }
    if (@($boundIds | Where-Object { $_.ToLowerInvariant() -eq $ExpectedIdentityId.ToLowerInvariant() }).Count -eq 0) {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: assignment identity list does not contain the run's managed identity"
        return $false
    }
    $actualParameters = Get-JsonProperty -Object $result.Data -Name 'parameters'
    if ($null -eq $actualParameters) { $actualParameters = Get-JsonProperty -Object $props -Name 'parameters' }
    foreach ($key in $ExpectedParameters.Keys) {
        $parameter = Get-JsonProperty -Object $actualParameters -Name $key
        $parameterValue = Get-JsonProperty -Object $parameter -Name 'value'
        if ("$parameterValue" -cne "$($ExpectedParameters[$key])") {
            $script:testFailed = $true
            Write-RunLog "$Label FAILED: parameter '$key' did not read back as expected"
            return $false
        }
    }
    Write-RunLog "${Label}: assignment scope and user-assigned identity binding verified"
    return $true
}

function Assert-RoleGrantSet {
    param([string]$PrincipalId, [string]$Scope, [string[]]$ExpectedIds, [hashtable]$Settings)
    $expected = @($ExpectedIds | ForEach-Object { "$($_)".ToLowerInvariant() } | Sort-Object -Unique)
    if ($expected.Count -eq 0) {
        $script:testFailed = $true
        Write-RunLog 'role grant assertion failed: lifecycle_resource_ids exposed no required role-assignment IDs'
        return $false
    }
    for ($attempt = 1; $attempt -le $Settings.RetryLimit; $attempt++) {
        $result = Invoke-AzJson @('role', 'assignment', 'list', '--assignee', $PrincipalId, '--scope', $Scope)
        if ($result.ExitCode -eq 0 -and $null -ne $result.Data) {
            $observed = @()
            $unexpected = @()
            foreach ($grant in @($result.Data)) {
                $id = "$(Get-JsonProperty -Object $grant -Name 'id')".ToLowerInvariant()
                $roleId = "$(Get-JsonProperty -Object $grant -Name 'roleDefinitionId')"
                if ($id) { $observed += $id }
                if ($id -and $id -notin $expected) { $unexpected += $id }
                if ($roleId -and $roleId -notmatch '/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f$') { $unexpected += $roleId }
            }
            if ($unexpected.Count -gt 0) {
                $script:testFailed = $true
                Write-RunLog 'role grant assertion failed: an unrequested grant or a role outside Tag Contributor was read back'
                return $false
            }
            $observed = @($observed | Sort-Object -Unique)
            $missing = @($expected | Where-Object { $_ -notin $observed })
            if ($missing.Count -eq 0 -and $observed.Count -eq $expected.Count) {
                Write-RunLog 'role grant read-back matches the exact lifecycle_resource_ids set and Tag Contributor role'
                return $true
            }
            Write-RunLog "role grant poll $attempt/$($Settings.RetryLimit): waiting for $($missing.Count) expected grant(s)"
        }
        else { Write-RunLog "role grant poll $attempt/$($Settings.RetryLimit): CLI read-back failed" }
        if ($attempt -lt $Settings.RetryLimit) { Start-Sleep -Seconds $Settings.IntervalSeconds }
    }
    $script:testFailed = $true
    Write-RunLog "role grant set not fully visible within $($Settings.DeadlineSeconds) s"
    return $false
}

function Assert-MinimalAssignment {
    param([string]$AssignmentId, [string]$ExpectedScope, [string]$ExpectedName, [string]$ExpectedOwner, [string]$ExpectedDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d')
    $result = Invoke-AzJson @('policy', 'assignment', 'show', '--name', $ExpectedName, '--scope', $ExpectedScope, '--subscription', $script:approvedSubscriptionId)
    if ($result.ExitCode -ne 0 -or $null -eq $result.Data) {
        $script:testFailed = $true
        Write-RunLog 'minimal assignment read-back failed'
        return $false
    }
    if (-not (Test-MinimalAssignmentDocument -Document $result.Data -AssignmentId $AssignmentId -ExpectedScope $ExpectedScope -ExpectedName $ExpectedName -ExpectedOwner $ExpectedOwner -ExpectedDefinitionId $ExpectedDefinitionId)) {
        $script:testFailed = $true
        Write-RunLog 'minimal assignment read-back differs from expected name, owner metadata, scope, built-in Audit definition, captured ID or no-identity contract'
        return $false
    }
    Write-RunLog "minimal assignment read-back verified: '$ExpectedName' at approved subscription scope, owner '$ExpectedOwner', built-in Audit definition, no identity"
    return $true
}

function Test-MinimalAssignmentDocument {
    param($Document, [string]$AssignmentId, [string]$ExpectedScope, [string]$ExpectedName, [string]$ExpectedOwner, [string]$ExpectedDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d')
    $props = Get-JsonProperty -Object $Document -Name 'properties'
    $actualId = "$(Get-JsonProperty -Object $Document -Name 'id')"
    $scope = Get-JsonProperty -Object $Document -Name 'scope'
    if ($null -eq $scope) { $scope = Get-JsonProperty -Object $props -Name 'scope' }
    $definitionId = Get-JsonProperty -Object $Document -Name 'policyDefinitionId'
    if ($null -eq $definitionId) { $definitionId = Get-JsonProperty -Object $props -Name 'policyDefinitionId' }
    $scope = "$scope"
    $definitionId = "$definitionId"
    $actualName = "$(Get-JsonProperty -Object $Document -Name 'name')"
    if (-not $actualName) { $actualName = ($actualId -split '/')[-1] }
    $metadata = Get-JsonProperty -Object $Document -Name 'metadata'
    if ($null -eq $metadata) { $metadata = Get-JsonProperty -Object $props -Name 'metadata' }
    $actualOwner = "$(Get-JsonProperty -Object $metadata -Name 'owner')"
    $identity = Get-JsonProperty -Object $Document -Name 'identity'
    $parameters = Get-JsonProperty -Object $Document -Name 'parameters'
    if ($null -eq $parameters) { $parameters = Get-JsonProperty -Object $props -Name 'parameters' }
    $parameterCount = 0
    if ($parameters) { $parameterCount = @($parameters.PSObject.Properties).Count }
    $enforcementMode = Get-JsonProperty -Object $Document -Name 'enforcementMode'
    if ($null -eq $enforcementMode) { $enforcementMode = Get-JsonProperty -Object $props -Name 'enforcementMode' }
    $enforcementMode = "$enforcementMode"
    return $actualId -ieq $AssignmentId -and $actualName -ieq $ExpectedName -and $scope -ieq $ExpectedScope -and $definitionId -ieq $ExpectedDefinitionId -and $null -eq $identity -and $parameterCount -eq 0 -and $enforcementMode -eq 'Default' -and $actualOwner -ceq $ExpectedOwner
}

function Get-ResolvedMinimalAssignment {
    param([hashtable]$Status, [string]$AssignmentKey)
    $review = $Status['resolvedAssignmentReview']
    if ($review -isnot [System.Collections.IDictionary]) { return $null }
    if (-not $review.Contains($AssignmentKey)) { return $null }
    return $review[$AssignmentKey]
}

function Get-ChangedResourceActions {
    param($Plan)
    $actual = @{}
    foreach ($change in @($Plan.resource_changes)) {
        $actions = @($change.change.actions)
        if ($actions.Count -eq 1 -and $actions[0] -ceq 'no-op') { continue }
        $actual[$change.address] = ($actions -join ',')
    }
    return $actual
}

function Invoke-ReviewedTerraformPlan {
    param([hashtable]$Status, [string]$Stage, [hashtable]$ExpectedAddressActions, [string[]]$AdditionalPlanArguments = @())
    $planPath = Join-Path $Status['runDirectory'] "$Stage.tfplan"
    $tfRoot = '-chdir=' + $Status['exampleRoot']
    $plan = Invoke-Terraform -TerraformArguments (Get-TerraformReviewedPlanArguments -Status $Status -PlanPath $planPath -AdditionalPlanArguments $AdditionalPlanArguments)
    $expectedExitCode = if ($ExpectedAddressActions.Count -eq 0) { 0 } else { 2 }
    if ($plan.ExitCode -ne $expectedExitCode) {
        $script:testFailed = $true
        Write-RunLog "$Stage plan returned exit $($plan.ExitCode), expected $expectedExitCode"
        return $null
    }
    $shown = Invoke-Terraform -TerraformArguments @($tfRoot, 'show', '-json', $planPath)
    if ($shown.ExitCode -ne 0) {
        $script:testFailed = $true
        Write-RunLog "$Stage saved plan could not be read as JSON"
        return $null
    }
    try { $planJson = (($shown.Output -join "`n") | ConvertFrom-Json) }
    catch {
        $script:testFailed = $true
        Write-RunLog "$Stage saved plan JSON could not be parsed"
        return $null
    }
    $actual = Get-ChangedResourceActions -Plan $planJson
    if ($actual.Count -ne $ExpectedAddressActions.Count) {
        $script:testFailed = $true
        Write-RunLog "$Stage provider plan reported $($actual.Count) changing resource(s), expected $($ExpectedAddressActions.Count)"
        return $null
    }
    foreach ($address in $ExpectedAddressActions.Keys) {
        if (-not $actual.ContainsKey($address) -or $actual[$address] -cne (@($ExpectedAddressActions[$address]) -join ',')) {
            $script:testFailed = $true
            Write-RunLog "$Stage actual provider plan action for '$address' was '$($actual[$address])', expected '$(@($ExpectedAddressActions[$address]) -join ',')'"
            return $null
        }
    }
    $Status['providerPlanEvidence'] += @([ordered]@{ stage = $Stage; exitCode = $plan.ExitCode; planPath = $planPath; resourceActions = $actual })
    Save-RunStatus -Status $Status
    Write-RunLog "$Stage actual Terraform provider plan actions: $((ConvertTo-Json -InputObject $actual -Compress))"
    return @{ Path = $planPath; Actions = $actual; ExitCode = $plan.ExitCode; Plan = $planJson }
}

function Assert-ExemptionState {
    param([string]$Label, [string]$ResourceGroupName, [string]$AssignmentId, [string]$ExemptionId, [string]$ExpectedExpiryDate)
    $result = Invoke-AzJson @('policy', 'exemption', 'list', '--resource-group', $ResourceGroupName)
    if ($result.ExitCode -ne 0 -or $null -eq $result.Data) {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: exemption read-back failed"
        return $false
    }
    $matched = $null
    foreach ($exemption in @($result.Data)) {
        $props = Get-JsonProperty -Object $exemption -Name 'properties'
        $associationId = Get-JsonProperty -Object $exemption -Name 'policyAssignmentId'
        if ($null -eq $associationId) { $associationId = Get-JsonProperty -Object $props -Name 'policyAssignmentId' }
        $associationId = "$associationId"
        $actualId = "$(Get-JsonProperty -Object $exemption -Name 'id')"
        if ($associationId -ieq $AssignmentId -and $actualId -ieq $ExemptionId) {
            $matched = $exemption
        }
    }
    if (-not $matched) {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: captured exemption ID does not reference this run's assignment"
        return $false
    }
    $matchedProps = Get-JsonProperty -Object $matched -Name 'properties'
    $expiresOn = Get-JsonProperty -Object $matched -Name 'expiresOn'
    if ($null -eq $expiresOn) { $expiresOn = Get-JsonProperty -Object $matchedProps -Name 'expiresOn' }
    $expiresOn = ConvertTo-Rfc3339Argument $expiresOn
    try {
        $observedInstant = [datetimeoffset]::Parse($expiresOn).UtcDateTime
        $expectedInstant = [datetimeoffset]::Parse((ConvertTo-Rfc3339Expiry $ExpectedExpiryDate)).UtcDateTime
    }
    catch {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: exemption expiry could not be parsed as RFC3339"
        return $false
    }
    if ($observedInstant -ne $expectedInstant) {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: exemption expiry observed '$expiresOn', expected '$ExpectedExpiryDate'"
        return $false
    }
    $metadata = Get-JsonProperty -Object $matched -Name 'metadata'
    if ($null -eq $metadata) { $metadata = Get-JsonProperty -Object $matchedProps -Name 'metadata' }
    $metadataPopulated = $false
    if ($metadata) {
        foreach ($entry in @($metadata.PSObject.Properties)) {
            if ("$($entry.Value)" -ne '') { $metadataPopulated = $true }
        }
    }
    if (-not $metadataPopulated) {
        $script:testFailed = $true
        Write-RunLog "$Label FAILED: exemption governance metadata is absent or empty"
        return $false
    }
    Write-RunLog "${Label}: captured exemption, assignment association, exact expiry and governance metadata verified"
    return $true
}

function Assert-Convergence {
    # R9 ownership rule: a refreshed plan must converge on the applied
    # configuration, including the example's declared ownership of the
    # policy-added tag. Exit 2 (changes) or 1 (error) fails the run.
    param([string]$Label, [hashtable]$Status, [string[]]$ExtraVars)
    Assert-RunInputsUnchanged -Status $Status | Out-Null
    $r = Invoke-Terraform -TerraformArguments (Get-TerraformConvergenceArguments -Status $Status -ExtraVars $ExtraVars)
    if ($r.ExitCode -eq 0) {
        Write-RunLog "convergence after ${Label}: no unexpected changes (exit 0)"
        return $true
    }
    else {
        $script:testFailed = $true
        Write-RunLog "convergence after ${Label}: FAILED, terraform plan -detailed-exitcode returned $($r.ExitCode) (2 changes, 1 error)"
        return $false
    }
}

function Stop-BeforeDestroyForRecoveryProbe {
    param([hashtable]$Status)
    if (-not $Status['recoveryProbe'] -or -not $Status['recoveryPausePending'] -or $Status['cleanupOnlyResume']) { return $false }
    $Status['cleanupPausedForRecoveryProbe'] = $true
    $Status['cleanupCompleted'] = $false
    $Status['cleanupPhase'] = 'policy-resources-absent-state-inventoried-awaiting-cleanup-only'
    $Status['cleanupPausedAtUtc'] = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Save-RunStatus -Status $Status
    $script:cleanupFailed = $true
    $script:cleanupPaused = $true
    Write-RunLog 'recovery probe intentionally paused after exact policy-resource absence and state inventory, before final Terraform destroy; resume with CleanupOnly'
    return $true
}

function Invoke-Cleanup {
    param([hashtable]$Status)

    Write-RunLog 'cleanup handler started'
    $statePath = $Status['terraformStatePath']
    $finalVars = Get-StageVarArguments -Status $Status

    $Status['cleanupStarted'] = $true
    $Status['testFailed'] = [bool]$script:testFailed
    Save-RunStatus -Status $Status

    if ($Status['mutationStarted']) {
        $tfRoot = '-chdir=' + $Status['exampleRoot']
        $init = Invoke-Terraform -TerraformArguments (Get-BackendDisabledInitArguments -ExampleRoot $Status['exampleRoot'])
        if ($init.ExitCode -ne 0) {
            $script:cleanupFailed = $true
            Write-RunLog 'cleanup stopped: Terraform could not initialise the recorded per-run workspace'
        }
        else {
            $select = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'select', $Status['terraformWorkspace'])
            if ($select.ExitCode -ne 0) {
                $script:cleanupFailed = $true
                Write-RunLog 'cleanup stopped: recorded per-run workspace could not be selected'
            }
            elseif (Remove-ExactPolicyResources -Status $Status) {
                if (-not (Assert-RunInputsUnchanged -Status $Status)) {
                    $script:cleanupFailed = $true
                    Write-RunLog 'Terraform destroy stopped: source or variable snapshot changed after the run began'
                }
                elseif (Test-PostDestroyWorkspaceState -Status $Status) {
                    # The previous process completed destroy, then stopped
                    # before read-back or workspace removal.
                }
                elseif (Test-RunWorkspaceState -Status $Status) {
                    $addresses = Invoke-Terraform -TerraformArguments @($tfRoot, 'state', 'list', '-no-color')
                    if ($addresses.ExitCode -ne 0) {
                        $script:cleanupFailed = $true
                        Write-RunLog 'Terraform destroy stopped: the isolated workspace resource-address inventory failed'
                    }
                    else {
                        $Status['preDestroyStateAddresses'] = @($addresses.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
                        $Status['preDestroyStatePath'] = $statePath
                        Save-RunStatus -Status $Status
                        Write-RunLog "final Terraform destroy will use isolated state '$statePath' with addresses: $($Status['preDestroyStateAddresses'] -join ', ')"
                        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
                            $script:cleanupFailed = $true
                            Write-RunLog 'Terraform destroy stopped: the recorded isolated state path does not exist'
                        }
                        else {
                            try { Assert-ApprovedAzureContext }
                            catch {
                                $script:cleanupFailed = $true
                                Write-RunLog "Terraform destroy stopped: $($_.Exception.Message)"
                            }
                        }
                        if (-not $script:cleanupFailed) {
                            try { Assert-DefaultStateUnchanged -Status $Status | Out-Null }
                            catch { $script:cleanupFailed = $true; Write-RunLog "Terraform destroy stopped: $($_.Exception.Message)" }
                        }
                        if (-not $script:cleanupFailed) {
                            if (Stop-BeforeDestroyForRecoveryProbe -Status $Status) { return }
                            else {
                                $destroy = Invoke-Terraform -TerraformArguments (Get-TerraformDestroyArguments -Status $Status -FinalVars $finalVars) -FullLog
                                if ($destroy.ExitCode -ne 0) {
                                    $script:cleanupFailed = $true
                                    Write-RunLog "terraform destroy failed with exit code $($destroy.ExitCode); absence checks continue regardless"
                                }
                                $remaining = Invoke-Terraform -TerraformArguments @($tfRoot, 'state', 'list', '-no-color')
                                if ($remaining.ExitCode -ne 0 -or @($remaining.Output | Where-Object { ([string]$_).Trim() }).Count -gt 0) {
                                    $script:cleanupFailed = $true
                                    Write-RunLog 'Terraform destroy did not leave the isolated workspace state empty'
                                }
                                try { Assert-DefaultStateUnchanged -Status $Status | Out-Null }
                                catch { $script:cleanupFailed = $true; Write-RunLog "default Terraform state preservation check FAILED: $($_.Exception.Message)" }
                            }
                        }
                    }
                }
                else {
                    $script:cleanupFailed = $true
                    Write-RunLog 'Terraform destroy stopped: state does not prove an isolated, run-owned resource set'
                }
            }
            else {
                $script:cleanupFailed = $true
                Write-RunLog 'Terraform destroy stopped: exact Azure policy-resource deletion and absence checks did not complete'
            }
        }
    }
    else {
        Write-RunLog 'no Terraform/Azure mutation was started by this run; no destroy is authorised'
    }

    # Resource group absence is the primary evidence for everything scoped
    # inside it: storage account, identity, grant, remediation and the
    # RG-scoped exemption.
    if ($Status['profile'] -eq 'complete') {
        $rgAbsent = Wait-Absence -Label 'target resource group' -ProbeKind 'ResourceGroup' -Target "$($Status['targetResourceGroupName'])" -Settings $script:Polling.Absence
        if (-not $rgAbsent) { $script:cleanupFailed = $true }
    }

    $captured = $Status['createdResourceIds']
    if ($captured.Count -gt 0) {
        foreach ($class in @($captured.Keys)) {
            # Principal IDs are GUIDs, not Azure resource IDs. Identity and
            # role grant absence is checked through their captured resources.
            if ($class -eq 'principals') { continue }
            foreach ($id in @($captured[$class])) {
                if (-not (Wait-Absence -Label "$class" -ProbeKind 'ResourceId' -Target "$id" -Settings $script:Polling.Absence)) {
                    $script:cleanupFailed = $true
                }
            }
        }
    }
    else {
        Write-RunLog 'no captured resource identifiers; absence rests on the resource group check'
    }

    $expectedClasses = @()
    $stages = @($Status['appliedStages']) + @($Status['activeStage'])
    if ($Status['profile'] -eq 'minimal') {
        if ($stages -contains 'minimal-apply') { $expectedClasses += 'assignments' }
    }
    else {
        if (@($stages | Where-Object { $_ -in @('stage-0b', 'stage-1a', 'stage-1b', 'stage-1c', 'stage-2', 'renewal') }).Count -gt 0) { $expectedClasses += @('definition_ids', 'set_definition_id') }
        if (@($stages | Where-Object { $_ -in @('stage-1b', 'stage-1c', 'stage-2', 'renewal') }).Count -gt 0) { $expectedClasses += @('assignments', 'identities', 'role_assignments') }
        if (@($stages | Where-Object { $_ -in @('stage-1c', 'stage-2', 'renewal') }).Count -gt 0) { $expectedClasses += @('remediations') }
        if (@($stages | Where-Object { $_ -in @('stage-2', 'renewal') }).Count -gt 0) { $expectedClasses += @('exemptions') }
    }
    foreach ($class in $expectedClasses) {
        if (-not $captured.ContainsKey($class) -or @($captured[$class]).Count -eq 0) {
            $script:cleanupFailed = $true
            Write-RunLog "absence of $class cannot be established: lifecycle_resource_ids did not capture a real identifier; verify manually before considering cleanup complete"
        }
    }

    foreach ($inventory in @(
            @{ Name = 'inventory-before-groups.json'; Args = @('group', 'list'); Label = 'resource groups' },
            @{ Name = 'inventory-before-policy-assignments.json'; Args = @('policy', 'assignment', 'list'); Label = 'policy assignments' },
            @{ Name = 'inventory-before-definitions.json'; Args = @('policy', 'definition', 'list', '--query', "[?policyType=='Custom']"); Label = 'custom policy definitions' },
            @{ Name = 'inventory-before-initiatives.json'; Args = @('policy', 'set-definition', 'list', '--query', "[?policyType=='Custom']"); Label = 'custom policy sets' }
        )) {
        if (-not (Test-InventoryMatchesBaseline -BaselinePath (Join-Path $Status['runDirectory'] $inventory.Name) -Arguments $inventory.Args -Label $inventory.Label -Status $Status -OwnedAbsenceVerified:(-not $script:cleanupFailed))) {
            $script:cleanupFailed = $true
        }
    }

    if (-not $script:cleanupFailed -and $Status['terraformWorkspace']) {
        $tfRoot = '-chdir=' + $Status['exampleRoot']
        $toDefault = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'select', 'default')
        $deleteWorkspace = $null
        if ($toDefault.ExitCode -eq 0) { $deleteWorkspace = Invoke-Terraform -TerraformArguments @($tfRoot, 'workspace', 'delete', $Status['terraformWorkspace']) }
        if ($null -eq $deleteWorkspace -or $deleteWorkspace.ExitCode -ne 0) {
            $script:cleanupFailed = $true
            Write-RunLog 'per-run Terraform workspace could not be removed after verified Azure cleanup'
        }
        else {
            $Status['workspaceRemoved'] = $true
            Save-RunStatus -Status $Status
        }
    }

    if (-not $script:cleanupFailed -and $Status['recoveryProbe'] -and $Status['cleanupOnlyResume']) {
        $Status['recoveryPausePending'] = $false
        $Status['cleanupPausedForRecoveryProbe'] = $false
        $Status['cleanupPhase'] = 'recovery-probe-cleanup-complete'
        $Status['recoveryCleanupCompletedAtUtc'] = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    $Status['cleanupCompleted'] = -not $script:cleanupFailed
    Save-RunStatus -Status $Status

    if ($script:cleanupFailed) {
        Write-RunLog 'cleanup status: FAILED (see diagnostics above; state and status file are retained)'
    }
    else {
        Write-RunLog 'cleanup status: PASSED (all recorded resources verified absent)'
    }
}

function Invoke-RecordedCleanup {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "no run status file at '$Path'; cleanup cannot resume a run that was never recorded"
        return 2
    }
    $loaded = ConvertTo-Hashtable -Object (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    if ($loaded['subscriptionId'] -ine $script:subscriptionId -or $loaded['tenantId'] -ine $script:tenantId) {
        Write-Host 'cleanup resume rejected: recorded tenant/subscription differs from the active approved Azure context'
        return 2
    }
    try { Assert-RecordedCleanupContext -Status $loaded -StatusFilePath $Path }
    catch {
        Write-Host "cleanup resume rejected: $($_.Exception.Message)"
        return 2
    }
    $script:statusPath = $Path
    $script:logPath = Join-Path $loaded['runDirectory'] 'run.log'
    $script:mutationStarted = [bool]$loaded['mutationStarted']
    # Cleanup can resume after an external interruption before the test reaches
    # its terminal assertion. Absence of a recorded failure is not a pass.
    $script:testFailed = [bool]$loaded['testFailed'] -or [bool]$loaded['intentionalFailure'] -or -not [bool]$loaded['testCompleted']
    $loaded['cleanupOnlyResume'] = $true
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:mutationLockPath) | Out-Null
    $script:mutationLockStream = $null
    if (Test-Path -LiteralPath $script:mutationLockPath) {
        # An exclusive open fails while a live run still holds the lock. Only
        # take over an orphan belonging to this exact recorded run and context.
        # Retain the verified handle so ownership cannot change before cleanup.
        try {
            $script:mutationLockStream = [System.IO.File]::Open($script:mutationLockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $buffer = [byte[]]::new($script:mutationLockStream.Length)
            [void]$script:mutationLockStream.Read($buffer, 0, $buffer.Length)
            $recordedLock = [System.Text.Encoding]::UTF8.GetString($buffer).Trim()
            $expectedOriginalLock = "$($loaded['runId'])`n$($script:tenantId)`n$($script:subscriptionId)"
            if ($recordedLock -cne $expectedOriginalLock -and $recordedLock -cne "cleanup:$($loaded['runId'])") {
                $script:mutationLockStream.Dispose()
                $script:mutationLockStream = $null
                Write-Host 'cleanup resume refused: mutation lock belongs to another run or context'
                return 2
            }
            Write-RunLog "verified orphaned mutation lock for run '$($loaded['runId'])' acquired for cleanup resume"
        }
        catch {
            if ($script:mutationLockStream) { $script:mutationLockStream.Dispose(); $script:mutationLockStream = $null }
            Write-Host 'cleanup resume refused: another live run holds the UAT mutation lock or its ownership could not be verified'
            return 2
        }
    }
    try {
        if (-not $script:mutationLockStream) {
            $script:mutationLockStream = [System.IO.File]::Open($script:mutationLockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        }
        $lockText = [System.Text.Encoding]::UTF8.GetBytes("cleanup:" + $loaded['runId'])
        $script:mutationLockStream.SetLength(0)
        $script:mutationLockStream.Position = 0
        $script:mutationLockStream.Write($lockText, 0, $lockText.Length)
        $script:mutationLockStream.Flush()
    }
    catch {
        if ($script:mutationLockStream) { $script:mutationLockStream.Dispose(); $script:mutationLockStream = $null }
        Write-Host 'cleanup resume refused: another live run holds the UAT mutation lock'
        return 2
    }
    try {
        Save-RunStatus -Status $loaded
        Write-RunLog "cleanup-only resume for run '$($loaded['runId'])'"
        Invoke-Cleanup -Status $loaded
    }
    catch {
        $script:cleanupFailed = $true
        Write-RunLog ("cleanup-only run failed with an unexpected error: {0}" -f $_)
    }
    finally {
        if ($script:mutationLockStream) { $script:mutationLockStream.Dispose(); Remove-Item -LiteralPath $script:mutationLockPath -Force -ErrorAction SilentlyContinue }
    }
    Write-StatusReport
    return (ConvertTo-ExitCode -TestFailed:$script:testFailed -CleanupFailed:$script:cleanupFailed)
}

function Assert-RecordedCleanupContext {
    # The recovery JSON is local input, not authority to select an arbitrary
    # example, state file, or variable file for an automatic destroy.
    param([hashtable]$Status, [string]$StatusFilePath)
    Assert-RecordedApprovedContext -Status $Status
    $runId = "$($Status['runId'])"
    if ($runId -notmatch '^[a-z0-9]{1,14}$') { throw 'recorded run ID is invalid' }
    $expectedExampleName = switch ($Status['profile']) {
        'complete' { 'complete-policy-lifecycle' }
        'minimal' { 'minimal-audit-assignment' }
        default { throw 'recorded example profile is unsupported' }
    }
    $expectedExampleRoot = [System.IO.Path]::GetFullPath((Join-Path $script:repoRoot ('examples/' + $expectedExampleName)))
    $recordedExampleRoot = [System.IO.Path]::GetFullPath([string]$Status['exampleRoot'])
    if (-not [string]::Equals($recordedExampleRoot, $expectedExampleRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'recorded example root does not match the reviewed live profile'
    }
    $expectedRunDirectory = [System.IO.Path]::GetFullPath((Split-Path -Parent $StatusFilePath))
    $recordedRunDirectory = [System.IO.Path]::GetFullPath([string]$Status['runDirectory'])
    if (-not [string]::Equals($recordedRunDirectory, $expectedRunDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'recorded run directory does not match the status file location'
    }
    $expectedVarFile = [System.IO.Path]::GetFullPath((Join-Path $expectedRunDirectory 'run-input.tfvars'))
    $recordedVarFile = [System.IO.Path]::GetFullPath([string]$Status['varFile'])
    if (-not [string]::Equals($recordedVarFile, $expectedVarFile, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $expectedVarFile -PathType Leaf)) {
        throw 'protected variable file is missing or outside the recorded run directory'
    }
    if ("$($Status['sourceFingerprint'])" -notmatch '^[0-9A-Fa-f]{64}$' -or "$($Status['varFileSha256'])" -notmatch '^[0-9A-Fa-f]{64}$') {
        throw 'recorded source or variable fingerprint is missing or malformed'
    }
    if (-not $Status.ContainsKey('defaultStateSnapshot')) { throw 'recorded default-state preservation snapshot is missing' }
    Assert-DefaultStateUnchanged -Status $Status | Out-Null
    if ($Status['mutationStarted']) {
        $expectedWorkspace = 'uat-' + $runId
        if ($Status['terraformWorkspace'] -cne $expectedWorkspace) { throw 'recorded Terraform workspace does not match the run ID' }
        $expectedStatePath = [System.IO.Path]::GetFullPath((Join-Path $expectedExampleRoot ('terraform.tfstate.d/' + $expectedWorkspace + '/terraform.tfstate')))
        $recordedStatePath = [System.IO.Path]::GetFullPath([string]$Status['terraformStatePath'])
        if (-not [string]::Equals($recordedStatePath, $expectedStatePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'recorded Terraform state path does not match the isolated per-run workspace'
        }
    }
}
