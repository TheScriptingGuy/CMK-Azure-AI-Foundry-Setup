<#
.SYNOPSIS
  Direct local Terraform deploy of the Azure AI Foundry + CMK stack, using
  the signed-in `az` user (no service principal, no Docker, no act).

.DESCRIPTION
  Sibling of `deploy-local.ps1` (which runs the GH workflows via `act` with an
  SP). This script bypasses both — Terraform uses your Azure CLI session for
  auth and your own user object ID is auto-set as the Key Vault admin.

  Steps:
    1. `az login` if not already signed in
    2. Resolve subscription + signed-in user object ID
    3. Run bootstrap (local state) to create the remote-state storage account,
       unless `-SkipBootstrap` and a previous backend_config.env exists
    4. Grant the signed-in user Storage Blob Data Contributor on the tfstate
       storage account (the backend uses use_azuread_auth = true)
    5. `terraform init` against the remote backend + run plan / apply / destroy

  Prereqs: `az` and `terraform` on PATH. You need permissions to create the
  resources (Owner or Contributor + User Access Administrator at the
  subscription scope, since Terraform creates role assignments).

.PARAMETER Action
  Terraform action: plan | apply | destroy. Default: plan.

.PARAMETER SkipBootstrap
  Skip the bootstrap step. `terraform/bootstrap/backend_config.env` must
  already exist.

.PARAMETER SubscriptionId
  Override the subscription ID. Default: from `az account show`.

.PARAMETER Location
  Azure region. Default: swedencentral.

.PARAMETER NamePrefix
  Resource name prefix. Default: cmkfoundry.

.EXAMPLE
  .\scripts\deploy.ps1 -Action plan

.EXAMPLE
  .\scripts\deploy.ps1 -Action apply
#>

[CmdletBinding()]
param(
  [ValidateSet('plan', 'apply', 'destroy')]
  [string]$Action = 'plan',
  [switch]$SkipBootstrap,
  [string]$SubscriptionId,
  [string]$Location = 'swedencentral',
  [string]$NamePrefix = 'cmkfoundry',
  # Object ID of the AAD user/SP to wire as KV admin + Cognitive Services User.
  # Provide this to skip the Microsoft Graph lookup (useful when Conditional
  # Access blocks Graph token issuance). Find yours at:
  #   https://entra.microsoft.com  →  Users  →  your account  →  Object ID
  [string]$UserObjectId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $PSScriptRoot) {
  throw "This script must be invoked as a file (e.g. .\scripts\deploy.ps1), not pasted into the shell. \$PSScriptRoot is empty."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$tfDir = Join-Path $repoRoot 'terraform'
$bootstrapDir = Join-Path $tfDir 'bootstrap'

function Assert-Command {
  param([string]$Name, [string]$Hint)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "'$Name' not found on PATH. $Hint"
  }
}

function Write-Step { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }

Assert-Command 'az'        'Install Azure CLI: https://aka.ms/installazurecliwindows'
Assert-Command 'terraform' 'Install Terraform: winget install Hashicorp.Terraform'

# --- 1. Login + subscription ---------------------------------------------
Write-Step 'Checking Azure login'
$account = $null
try { $account = az account show --only-show-errors 2>$null | ConvertFrom-Json } catch { }
if (-not $account) {
  Write-Host 'Not logged in — running `az login`.' -ForegroundColor Yellow
  az login --only-show-errors | Out-Null
  $account = az account show --only-show-errors | ConvertFrom-Json
}
if (-not $SubscriptionId) { $SubscriptionId = $account.id }
if ($account.id -ne $SubscriptionId) {
  az account set --subscription $SubscriptionId --only-show-errors | Out-Null
  $account = az account show --only-show-errors | ConvertFrom-Json
}
Write-Host "Subscription : $($account.name) ($($account.id))"
Write-Host "Tenant       : $($account.tenantId)"

# --- 2. Resolve signed-in user object ID ---------------------------------
# Needs Microsoft Graph. Conditional Access in some tenants blocks Graph
# token issuance entirely (AADSTS53003) — pass -UserObjectId to bypass.
if ($UserObjectId) {
  Write-Host 'Using -UserObjectId override; skipping Microsoft Graph lookup.'
}
else {
  $UserObjectId = az ad signed-in-user show --query id -o tsv --only-show-errors
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($UserObjectId)) {
    Write-Host 'Microsoft Graph access denied (likely Conditional Access).' -ForegroundColor Yellow
    Write-Host "Trying interactive Graph login on tenant $($account.tenantId)..." -ForegroundColor Yellow
    # Drop --only-show-errors so the underlying CA failure surfaces.
    az login --tenant $account.tenantId --scope 'https://graph.microsoft.com//.default' | Out-Null
    $loginExit = $LASTEXITCODE
    # `az login --scope` can reset the subscription context.
    az account set --subscription $SubscriptionId --only-show-errors | Out-Null

    if ($loginExit -eq 0) {
      $UserObjectId = az ad signed-in-user show --query id -o tsv --only-show-errors
    }

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($UserObjectId)) {
      throw @"
Could not resolve your AAD object ID via Microsoft Graph.

Your tenant's Conditional Access policy is blocking Graph token issuance.
Find your object ID manually and re-run with -UserObjectId:

  1. Open https://entra.microsoft.com  →  Users  →  click your account
  2. Copy the 'Object ID' (a GUID)
  3. .\scripts\deploy.ps1 -Action $Action -UserObjectId <that-guid>
"@
    }
  }
}
Write-Host "User object  : $UserObjectId"

# azurerm provider picks up Azure CLI auth automatically when ARM_CLIENT_* are unset.
$env:ARM_SUBSCRIPTION_ID = $SubscriptionId
$env:ARM_TENANT_ID = $account.tenantId
$env:ARM_USE_AZUREAD = 'true'
$env:TF_IN_AUTOMATION = '1'
$env:TF_INPUT = '0'

# --- 3. Bootstrap (local state) ------------------------------------------
$backendEnv = Join-Path $bootstrapDir 'backend_config.env'

if (-not $SkipBootstrap) {
  Write-Step 'Bootstrap (remote state storage account)'
  Push-Location $bootstrapDir
  try {
    terraform init -no-color
    if ($LASTEXITCODE -ne 0) { throw 'terraform init (bootstrap) failed' }

    terraform apply -no-color -auto-approve `
      -var "subscription_id=$SubscriptionId" `
      -var "location=$Location" `
      -var "name_prefix=$NamePrefix"
    if ($LASTEXITCODE -ne 0) { throw 'terraform apply (bootstrap) failed' }

    $rg = terraform output -raw resource_group_name
    $sa = terraform output -raw storage_account_name
    $ctn = terraform output -raw container_name
    $body = @(
      "resource_group_name=$rg",
      "storage_account_name=$sa",
      "container_name=$ctn"
    ) -join "`n"
    [System.IO.File]::WriteAllText($backendEnv, $body + "`n")
  }
  finally { Pop-Location }
}

if (-not (Test-Path $backendEnv)) {
  throw "Backend config not found at $backendEnv. Re-run without -SkipBootstrap."
}

$backend = @{}
Get-Content $backendEnv | ForEach-Object {
  if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*?)\s*$') { $backend[$matches[1]] = $matches[2] }
}
foreach ($k in 'resource_group_name', 'storage_account_name', 'container_name') {
  if (-not $backend.ContainsKey($k)) { throw "Missing '$k' in $backendEnv" }
}

# --- 4. Grant blob data access on tfstate SA -----------------------------
# backend.tf sets `use_azuread_auth = true`, so the user needs a data-plane
# role on the storage account, not just Contributor on the management plane.
Write-Step 'Granting Storage Blob Data Contributor on tfstate SA (idempotent)'
$saId = az storage account show `
  --name $backend['storage_account_name'] `
  --resource-group $backend['resource_group_name'] `
  --query id -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($saId)) {
  throw 'Failed to resolve tfstate storage account ID.'
}
# `az role assignment create` returns non-zero if the assignment already exists — that's fine.
az role assignment create `
  --role 'Storage Blob Data Contributor' `
  --assignee-object-id $UserObjectId `
  --assignee-principal-type User `
  --scope $saId `
  --only-show-errors 1>$null 2>$null
$global:LASTEXITCODE = 0

# --- 5. Main config: init + action ---------------------------------------
Write-Step "Main config: terraform init + $Action"

$env:TF_VAR_subscription_id = $SubscriptionId
$env:TF_VAR_tenant_id = $account.tenantId
$env:TF_VAR_location = $Location
$env:TF_VAR_name_prefix = $NamePrefix
# Make the signed-in user a KV admin (needed to create the CMK key)
# AND grant them the data-plane role to call inference via AAD.
$env:TF_VAR_key_vault_admin_object_ids = ConvertTo-Json -Compress @($UserObjectId)
$env:TF_VAR_ai_foundry_role_assignments = ConvertTo-Json -Compress @(
  @{ principal_id = $UserObjectId; role = 'Cognitive Services User'; principal_type = 'User' }
)

Push-Location $tfDir
try {
  terraform init -no-color -reconfigure `
    -backend-config="resource_group_name=$($backend['resource_group_name'])" `
    -backend-config="storage_account_name=$($backend['storage_account_name'])" `
    -backend-config="container_name=$($backend['container_name'])"
  if ($LASTEXITCODE -ne 0) { throw 'terraform init failed' }

  terraform validate -no-color
  if ($LASTEXITCODE -ne 0) { throw 'terraform validate failed' }

  switch ($Action) {
    'plan' { terraform plan -no-color }
    'apply' { terraform apply -no-color -auto-approve }
    'destroy' { terraform destroy -no-color -auto-approve }
  }
  if ($LASTEXITCODE -ne 0) { throw "terraform $Action failed" }
}
finally { Pop-Location }

if ($Action -eq 'apply') {
  Write-Host ''
  Write-Host 'Apply succeeded. Try the chat script:' -ForegroundColor Green
  Write-Host '  $env:ANTHROPIC_BASE_URL = (terraform -chdir=terraform output -raw account_endpoint).TrimEnd(''/'') + "/anthropic"'
  Write-Host '  $env:ANTHROPIC_MODEL    = "claude-opus-4-7"'
  Write-Host '  python scripts/chat.py "Write me a haiku about Terraform."'
}

Write-Host '==> Done.' -ForegroundColor Green
