<#
.SYNOPSIS
  End-to-end local `act` deploy of the Azure AI Foundry + CMK stack on Windows.

.DESCRIPTION
  Orchestrates:
    1. `az login` (skipped if already signed in)
    2. Subscription selection (defaults to `az account show`)
    3. `.secrets` generation — creates an SP via `az ad sp create-for-rbac`,
       grants it User Access Administrator on the subscription, and writes
       ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID. Reused if it exists.
    4. `act` bootstrap run → parses backend config from the artifact
    5. `act` deploy run (plan | apply | destroy)

  Prereqs: az + act on PATH. By default uses container mode (needs Docker
  Desktop); pass -HostMode to run on the host without Docker (then you also
  need bash + terraform on PATH).

.PARAMETER Action
  Terraform action: plan | apply | destroy. Default: plan.

.PARAMETER HostMode
  Use `act` host mode (`-P ubuntu-latest=-self-hosted`) instead of containers.

.PARAMETER SkipBootstrap
  Skip the bootstrap step. Reads backend config from
  `terraform/bootstrap/backend_config.env` (which must already exist).

.PARAMETER SubscriptionId
  Override the subscription ID. Default: from `az account show`.

.PARAMETER Location
  Azure region. Default: swedencentral.

.PARAMETER NamePrefix
  Resource name prefix. Default: cmkfoundry.

.PARAMETER SpName
  Display name of the SP to create (only if `.secrets` does not yet exist).
  Default: cmk-foundry-tf-deploy.

.EXAMPLE
  .\scripts\deploy-local.ps1 -Action plan

.EXAMPLE
  .\scripts\deploy-local.ps1 -Action apply -HostMode
#>

[CmdletBinding()]
param(
  [ValidateSet('plan', 'apply', 'destroy')]
  [string]$Action = 'plan',
  [switch]$HostMode,
  [switch]$SkipBootstrap,
  [string]$SubscriptionId,
  [string]$Location = 'swedencentral',
  [string]$NamePrefix = 'cmkfoundry',
  [string]$SpName = 'cmk-foundry-tf-deploy'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Assert-Command {
  param([string]$Name, [string]$Hint)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "'$Name' not found on PATH. $Hint"
  }
}

function Write-Step { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }

Assert-Command 'az'  'Install Azure CLI: https://aka.ms/installazurecliwindows'
Assert-Command 'act' 'Install act: `winget install nektos.act` (or `choco install act-cli`).'

# --- 1. Login -------------------------------------------------------------
Write-Step 'Checking Azure login'
$account = $null
try { $account = az account show --only-show-errors 2>$null | ConvertFrom-Json } catch { }
if (-not $account) {
  Write-Host 'Not logged in — running `az login`.' -ForegroundColor Yellow
  az login --only-show-errors | Out-Null
  $account = az account show --only-show-errors | ConvertFrom-Json
}

# --- 2. Subscription -----------------------------------------------------
if (-not $SubscriptionId) { $SubscriptionId = $account.id }
if ($account.id -ne $SubscriptionId) {
  Write-Step "Setting active subscription to $SubscriptionId"
  az account set --subscription $SubscriptionId --only-show-errors | Out-Null
  $account = az account show --only-show-errors | ConvertFrom-Json
}
Write-Host "Subscription : $($account.name) ($($account.id))"
Write-Host "Tenant       : $($account.tenantId)"

# --- 3. .secrets ---------------------------------------------------------
$secretsPath = Join-Path $repoRoot '.secrets'
if (Test-Path $secretsPath) {
  Write-Step '.secrets already exists — reusing it'
}
else {
  Write-Step "Creating service principal '$SpName' and writing .secrets"

  # Probe Microsoft Graph access first. Conditional Access often blocks the
  # cached ARM token from being reused against Graph (AADSTS53003), and
  # `az ad sp create-for-rbac` will fail with no usable error JSON.
  az ad signed-in-user show --query id -o tsv --only-show-errors 1>$null 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'Microsoft Graph access denied (likely Conditional Access).' -ForegroundColor Yellow
    Write-Host "Re-running az login with the Graph scope on tenant $($account.tenantId)..." -ForegroundColor Yellow
    az login --tenant $account.tenantId --scope 'https://graph.microsoft.com//.default' --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Interactive Graph login failed. Cannot create service principal.' }
    # Restore the subscription context — `az login --scope` can reset it.
    az account set --subscription $SubscriptionId --only-show-errors | Out-Null
  }

  $spJson = az ad sp create-for-rbac `
    --name $SpName `
    --role Contributor `
    --scopes "/subscriptions/$SubscriptionId" `
    --only-show-errors
  $exit = $LASTEXITCODE
  if ($exit -ne 0 -or [string]::IsNullOrWhiteSpace($spJson)) {
    throw @"
Failed to create service principal (az exit code $exit).
If you saw a Conditional Access (AADSTS53003) message above, run these manually then re-run this script:
  az logout
  az login --tenant '$($account.tenantId)' --scope 'https://graph.microsoft.com//.default'
  az account set --subscription '$SubscriptionId'
"@
  }
  $sp = $spJson | ConvertFrom-Json
  if (-not $sp.appId) { throw "Service principal creation returned unexpected output:`n$spJson" }

  # Terraform creates role assignments → SP needs User Access Administrator.
  $principalId = az ad sp show --id $sp.appId --query id -o tsv --only-show-errors
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
    throw "Failed to resolve principal id for SP $($sp.appId)."
  }
  az role assignment create `
    --role 'User Access Administrator' `
    --assignee-object-id $principalId `
    --assignee-principal-type ServicePrincipal `
    --scope "/subscriptions/$SubscriptionId" `
    --only-show-errors | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Failed to grant User Access Administrator on the subscription.' }

  $body = @(
    "ARM_CLIENT_ID=$($sp.appId)",
    "ARM_CLIENT_SECRET=$($sp.password)",
    "ARM_TENANT_ID=$($sp.tenant)"
  ) -join "`n"
  # Write UTF-8 without BOM — act parses .secrets as plain ASCII key=value.
  [System.IO.File]::WriteAllText($secretsPath, $body + "`n")
  Write-Host "Wrote .secrets (client_id=$($sp.appId))"
}

# --- 4. Bootstrap (acquire backend config) -------------------------------
$backendEnvPath = Join-Path $repoRoot 'terraform\bootstrap\backend_config.env'

if (-not $SkipBootstrap) {
  Write-Step 'Running bootstrap via act'
  $artifactsDir = Join-Path $repoRoot 'artifacts'
  if (Test-Path $artifactsDir) { Remove-Item -Recurse -Force $artifactsDir }

  $actArgs = @(
    'workflow_dispatch',
    '-W', '.github/workflows/bootstrap.yml',
    '--secret-file', '.secrets',
    '--artifact-server-path', './artifacts',
    '--input', "subscription_id=$SubscriptionId",
    '--input', "location=$Location",
    '--input', "name_prefix=$NamePrefix"
  )
  if ($HostMode) { $actArgs += @('-P', 'ubuntu-latest=-self-hosted') }

  & act @actArgs
  if ($LASTEXITCODE -ne 0) { throw "act bootstrap failed with exit code $LASTEXITCODE" }

  $candidate = Get-ChildItem -Path $artifactsDir -Recurse -Filter 'backend_config.env' -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if (-not $candidate) {
    throw "Could not find backend_config.env under $artifactsDir after bootstrap."
  }
  Copy-Item $candidate.FullName $backendEnvPath -Force
  Write-Host "Backend config saved to $backendEnvPath"
}

if (-not (Test-Path $backendEnvPath)) {
  throw "Backend config not found at $backendEnvPath. Re-run without -SkipBootstrap."
}

# Parse key=value file into a hashtable.
$backend = @{}
Get-Content $backendEnvPath | ForEach-Object {
  if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*?)\s*$') {
    $backend[$matches[1]] = $matches[2]
  }
}
foreach ($k in 'resource_group_name', 'storage_account_name', 'container_name') {
  if (-not $backend.ContainsKey($k)) { throw "Missing '$k' in $backendEnvPath" }
}

# --- 5. Deploy -----------------------------------------------------------
Write-Step "Running deploy ($Action) via act"
$actArgs = @(
  'workflow_dispatch',
  '-W', '.github/workflows/deploy.yml',
  '--secret-file', '.secrets',
  '--artifact-server-path', './artifacts',
  '--input', "subscription_id=$SubscriptionId",
  '--input', "action=$Action",
  '--input', "backend_resource_group=$($backend['resource_group_name'])",
  '--input', "backend_storage_account=$($backend['storage_account_name'])",
  '--input', "backend_container=$($backend['container_name'])",
  '--input', "location=$Location",
  '--input', "name_prefix=$NamePrefix"
)
if ($HostMode) { $actArgs += @('-P', 'ubuntu-latest=-self-hosted') }

& act @actArgs
if ($LASTEXITCODE -ne 0) { throw "act deploy failed with exit code $LASTEXITCODE" }

Write-Host '==> Done.' -ForegroundColor Green
