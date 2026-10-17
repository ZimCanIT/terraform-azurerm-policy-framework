# Public-package smoke check (goal requirement R11).
#
# Builds a controlled snapshot containing only the intended distributable
# files, including intended new untracked files, and excluding local working
# material, caches, state and unrelated local files. Then runs the public
# checks inside that snapshot: formatting, backend-disabled init and validate
# for every root in the shared inventory, and the repository documentation
# gate. This verifies public self-containment without publication or a Git
# commit.
#
# Usage: pwsh tests/integration/smoke-public-package.ps1 [-SourceRoot <path>] [-SnapshotRoot <path>]
# Exit codes: 0 smoke passed; 1 check failure; 2 snapshot build failure.

param(
    [string]$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$SnapshotRoot = (Join-Path ([System.IO.Path]::GetTempPath()) "tf-policy-smoke-$(Get-Random)")
)

# Native commands emit benign stderr noise (git line-ending warnings, terraform
# notices) that must not terminate the run; every result is judged by exit code.
$ErrorActionPreference = 'Continue'

Write-Host "smoke: source $SourceRoot"
Write-Host "smoke: snapshot $SnapshotRoot"

$sourcePath = (Resolve-Path -LiteralPath $SourceRoot).Path
$snapshotPath = [System.IO.Path]::GetFullPath($SnapshotRoot)
if ($snapshotPath.Equals($sourcePath, [System.StringComparison]::OrdinalIgnoreCase) -or
    $snapshotPath.StartsWith($sourcePath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $snapshotPath)) {
    Write-Host 'smoke: snapshot destination must be a new directory outside the source tree'
    exit 2
}
$candidatePaths = @(git -C $sourcePath ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { Write-Host 'smoke: candidate inventory failed'; exit 2 }
$deletedPaths = @(git -C $sourcePath ls-files --deleted)
if ($LASTEXITCODE -ne 0) { Write-Host 'smoke: deleted-path inventory failed'; exit 2 }
if (@($deletedPaths | Where-Object { [System.IO.Path]::GetFileName($_) -ne '.gitkeep' }).Count -gt 0) {
    Write-Host 'smoke: unexpected tracked deletion in public candidate inventory'
    exit 2
}
$deleted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($path in $deletedPaths) { [void]$deleted.Add($path) }
New-Item -ItemType Directory -Path $snapshotPath | Out-Null
$SnapshotRoot = $snapshotPath
$copiedPaths = @()
# The same Git candidate set used by repository_gate.py is the copy source.
# Ignored local locks, state, variable files and test artifacts never enter it.
foreach ($path in $candidatePaths) {
    if ($deleted.Contains($path)) { continue }
    $sourceFile = Join-Path $sourcePath $path
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        Write-Host "smoke: candidate file missing: $path"
        exit 2
    }
    $destinationFile = Join-Path $snapshotPath $path
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationFile) | Out-Null
    Copy-Item -LiteralPath $sourceFile -Destination $destinationFile
    $copiedPaths += $path
}
$manifestPath = $snapshotPath + '.manifest.json'
ConvertTo-Json -InputObject @($copiedPaths) | Set-Content -LiteralPath $manifestPath -Encoding utf8
$global:LASTEXITCODE = 0

$inventory = Get-Content (Join-Path $SnapshotRoot 'scripts/tf-inventory.json') -Raw | ConvertFrom-Json
$checkVersion = $inventory.versions.terraform_normal
Write-Host "smoke: inventory declares Terraform normal version $checkVersion with AzureRM $($inventory.versions.azurerm_constraint)"

$failed = @()

# Formatting must pass repository wide in the snapshot.
$rootChdir = "-chdir=$SnapshotRoot"
terraform $rootChdir fmt -check -recursive . 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { $failed += 'terraform fmt -check -recursive .' }

foreach ($root in $inventory.groups.validate_roots) {
    $path = Join-Path $SnapshotRoot $root
    if (-not (Test-Path $path)) {
        $failed += "inventory root missing from snapshot: $root"
        continue
    }
    $chdir = "-chdir=$path"
    terraform $chdir init -backend=false -input=false -no-color 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $failed += "terraform init: $root"; continue }
    terraform $chdir validate -no-color 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $failed += "terraform validate: $root" }
}

# The manifest remains outside the snapshot and records exactly what was
# copied, before init created local caches and locks. No Git index is needed.
if (Test-Path (Join-Path $SnapshotRoot 'scripts/repository_gate.py')) {
    Push-Location $SnapshotRoot
    try {
        python scripts/repository_gate.py --manifest $manifestPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { $failed += 'repository gate' }
    }
    finally {
        Pop-Location
    }
}
else {
    $failed += 'scripts/repository_gate.py missing from snapshot'
}

if ($failed.Count -gt 0) {
    Write-Host 'smoke: FAILED checks:'
    $failed | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host 'smoke: PASSED (public package is self-contained from the clean snapshot)'
exit 0
