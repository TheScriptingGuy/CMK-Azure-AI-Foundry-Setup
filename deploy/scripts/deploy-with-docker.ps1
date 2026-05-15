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
  [string]$SpName = 'cmk-foundry-tf-deploy',
  [string]$UserObjectId = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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

# Resolve personal user object ID for KV Admin + AI Foundry role assignment.
if (-not $UserObjectId) {
  Write-Step 'Resolving signed-in user object ID'
  $UserObjectId = az ad signed-in-user show --query id -o tsv --only-show-errors 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($UserObjectId)) {
    Write-Host 'Could not resolve user object ID — Key Vault and AI Foundry user roles will not be granted. Pass -UserObjectId to suppress this warning.' -ForegroundColor Yellow
    $UserObjectId = ''
  } else {
    Write-Host "User object ID : $UserObjectId"
  }
}

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

  $actArgs = @(
    'workflow_dispatch',
    '-W', '.github/workflows/bootstrap.yml',
    '--secret-file', '.secrets',
    '--input', "subscription_id=$SubscriptionId",
    '--input', "location=$Location",
    '--input', "name_prefix=$NamePrefix"
  )
  if ($HostMode) { $actArgs += @('-P', 'ubuntu-latest=-self-hosted') }

  # Display output in real-time and capture it for parsing.
  $actLines = [System.Collections.Generic.List[string]]::new()
  & act @actArgs | ForEach-Object { Write-Host $_; $actLines.Add($_) }
  if ($LASTEXITCODE -ne 0) { throw "act bootstrap failed with exit code $LASTEXITCODE" }

  # Extract the three values from terraform output lines, which look like:
  #   | resource_group_name = "rg-cmkfoundry-tfstate-abc123"
  $parsed = @{}
  foreach ($line in $actLines) {
    foreach ($key in 'resource_group_name', 'storage_account_name', 'container_name') {
      if ($line -match "\|\s+${key}\s*=\s*`"([^`"]+)`"") { $parsed[$key] = $matches[1] }
    }
  }
  foreach ($k in 'resource_group_name', 'storage_account_name', 'container_name') {
    if (-not $parsed.ContainsKey($k)) {
      throw "Could not parse '$k' from bootstrap output. Check act logs above."
    }
  }

  $body = "resource_group_name=$($parsed['resource_group_name'])`nstorage_account_name=$($parsed['storage_account_name'])`ncontainer_name=$($parsed['container_name'])`n"
  [System.IO.File]::WriteAllText($backendEnvPath, $body)
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

# Grant Storage Blob Data Contributor on the tfstate SA so the SP can access
# the backend with use_azuread_auth = true. Idempotent — no-op if already assigned.
Write-Step 'Granting Storage Blob Data Contributor on tfstate SA (idempotent)'
$saId = $null
try {
  $saId = az storage account show `
    --name $backend['storage_account_name'] `
    --resource-group $backend['resource_group_name'] `
    --query id -o tsv --only-show-errors 2>$null
} catch { }
$global:LASTEXITCODE = 0
if (-not [string]::IsNullOrWhiteSpace($saId)) {
  $spClientId = (Get-Content $secretsPath | Where-Object { $_ -match '^ARM_CLIENT_ID=' }) -replace '^ARM_CLIENT_ID=', ''
  $spOid = az ad sp show --id $spClientId --query id -o tsv --only-show-errors 2>$null
  if (-not [string]::IsNullOrWhiteSpace($spOid)) {
    az role assignment create `
      --role 'Storage Blob Data Contributor' `
      --assignee-object-id $spOid `
      --assignee-principal-type ServicePrincipal `
      --scope $saId `
      --only-show-errors 1>$null 2>$null
    $global:LASTEXITCODE = 0
  }
}

# --- 5. Deploy -----------------------------------------------------------
Write-Step "Running deploy ($Action) via act"

# Resolve SP object ID here (host has az) so the container doesn't need az.
$secrets = @{}
Get-Content $secretsPath | ForEach-Object {
  if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*?)\s*$') { $secrets[$matches[1]] = $matches[2] }
}
$spObjectId = az ad sp show --id $secrets['ARM_CLIENT_ID'] --query id -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($spObjectId)) {
  throw "Failed to resolve service principal object ID from ARM_CLIENT_ID in .secrets."
}

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
  '--input', "sp_object_id=$spObjectId",
  '--input', "user_object_id=$UserObjectId",
  '--input', "location=$Location",
  '--input', "name_prefix=$NamePrefix"
)
if ($HostMode) { $actArgs += @('-P', 'ubuntu-latest=-self-hosted') }

& act @actArgs
if ($LASTEXITCODE -ne 0) { throw "act deploy failed with exit code $LASTEXITCODE" }

Write-Host '==> Done.' -ForegroundColor Green
