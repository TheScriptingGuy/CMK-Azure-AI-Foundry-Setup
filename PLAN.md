# Plan: Fix Multi-Model Support Gaps + Deploy GPT-5.5

Generated: 2026-05-16

## Phase 0.5: Remove DeepSeek Deployment + Deploy GPT-5.5 (run now)

### Context

The last successful `terraform apply` (May 15) left a **DeepSeek-R1-0528** deployment live in Azure AI Foundry.
`var.deployments` default was subsequently changed to `gpt-5.5` (OpenAI format).
Running `terraform apply` now will automatically destroy the DeepSeek deployment and create the GPT-5.5 one — no manual deletion needed.

### What to run

```powershell
.\deploy\scripts\deploy-with-docker.ps1 -Action apply -SkipBootstrap
```

`-SkipBootstrap` is safe because:
- `terraform/bootstrap/backend_config.env` exists (rg=`rg-cmkfoundry-tfstate-e2aa4c84`, sa=`stcmkfoundrytfe2aa4c84`)
- `.secrets` exists (SP credentials from prior run)

### What Terraform will do

> **Note:** GPT-5.5 has 0 quota on VS Enterprise (`InsufficientQuota`). Switched default to `gpt-4o` GlobalStandard (450 TPM available). Same OpenAI format/SDK.

1. DeepSeek-R1-0528 already destroyed (first attempt succeeded on destroy, failed on create)
2. Create `gpt-4o` (version `2024-11-20`, GlobalStandard, capacity=1)
3. Emit `opencode_env` with `AZURE_OPENAI_ENDPOINT` / `AZURE_OPENAI_DEPLOYMENT=gpt-4o` / `OPENAI_API_VERSION`

### Verification checklist

- [ ] `act` deploy job exits 0
- [ ] Azure Portal → AI Foundry account → Model deployments: `gpt-5-5` present, no `deepseek-r1-0528`
- [ ] `terraform -chdir=terraform output -raw opencode_env` emits `AZURE_OPENAI_ENDPOINT` (not `ANTHROPIC_*`)
- [ ] `python scripts/chat.py "Write me a haiku about Terraform."` returns a response

---

## Phase 0: Documentation Discovery (Complete)

### Allowed APIs

**OpenAI SDK (for OpenAI-format models):**
- `AzureOpenAI(azure_endpoint=..., azure_ad_token_provider=..., api_version=...)`
- `client.chat.completions.create(model=..., messages=[...], max_tokens=...)`
- Token provider: `get_bearer_token_provider(DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default")`
- Source: `scripts/chat.py:33-41` (current implementation, working)

**Anthropic SDK (for Anthropic/DeepSeek-format models):**
- `anthropic.Anthropic(api_key=..., base_url=...)`
- `client.messages.create(model=..., max_tokens=..., messages=[...])`
- Auth: primary key (from `ANTHROPIC_API_KEY` env var), not Azure AD token
- Source: Anthropic Python SDK docs; env vars defined in `terraform/outputs.tf:50-56`

**PowerShell path resolution:**
- `$PSScriptRoot` = directory containing the script being run
- `Split-Path -Parent $PSScriptRoot` = one level up
- Source: PowerShell docs; observed bug in `deploy/scripts/deploy.ps1:69`

### Key Files

| File | Role |
|------|------|
| `deploy/scripts/deploy.ps1` | Local deploy script — 2 bugs identified |
| `scripts/chat.py` | Reference client — OpenAI only, missing Anthropic branch |
| `scripts/requirements.txt` | Python deps — missing `anthropic` |
| `terraform/outputs.tf` | `opencode_env` output — correct multi-format branching |
| `terraform/modules/model-deployment/outputs.tf` | `primary_key` description wrong |
| `README.md` | Wrong default model; Anthropic-only examples |

### Anti-Patterns to Avoid

- Do NOT use `Split-Path -Parent $PSScriptRoot` alone when the script is 2+ levels deep in the repo
- Do NOT hardcode model names or env var names in deploy script output — use `terraform output` instead
- Do NOT add `--anthropic-version` header to `anthropic.Anthropic()` constructor; AI Foundry doesn't require it
- Do NOT use `azure_ad_token_provider` with the Anthropic SDK; it uses key-based auth via `ANTHROPIC_API_KEY`

---

## Phase 1: Fix `deploy.ps1` — Two Bugs

### What to implement

**Bug 1 — Wrong `$repoRoot` (line 69):**

File: `deploy/scripts/deploy.ps1`

Old (line 69):
```powershell
$repoRoot = Split-Path -Parent $PSScriptRoot
```

New:
```powershell
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
```

Reason: script lives at `deploy\scripts\deploy.ps1`, so `$PSScriptRoot = deploy\scripts\`, one `Split-Path -Parent` gives `deploy\`, and `$tfDir = deploy\terraform` (does not exist). Two levels up gives the repo root.

**Bug 2 — Stale post-apply message (lines 241-247):**

Old:
```powershell
if ($Action -eq 'apply') {
  Write-Host ''
  Write-Host 'Apply succeeded. Try the chat script:' -ForegroundColor Green
  Write-Host '  $env:ANTHROPIC_BASE_URL = (terraform -chdir=terraform output -raw account_endpoint).TrimEnd(''/'') + "/anthropic"'
  Write-Host '  $env:ANTHROPIC_MODEL    = "claude-opus-4-7"'
  Write-Host '  python scripts/chat.py "Write me a haiku about Terraform."'
}
```

New:
```powershell
if ($Action -eq 'apply') {
  Write-Host ''
  Write-Host 'Apply succeeded. Load env vars and try the chat script:' -ForegroundColor Green
  Write-Host "  Invoke-Expression (terraform -chdir=`"$tfDir`" output -raw opencode_env)" -ForegroundColor White
  Write-Host "  python `"$repoRoot\scripts\chat.py`" `"Write me a haiku about Terraform.`"" -ForegroundColor White
}
```

This uses the already-computed `$tfDir` (now correct after Bug 1 fix) and lets `opencode_env`'s own format-branching decide which env vars to export.

### Verification checklist

- [ ] `$repoRoot` resolves to the repository root: run `& "$repoRoot\deploy\scripts\deploy.ps1" -Action plan` and confirm it finds `$repoRoot\terraform\` without "path not found" errors
- [ ] `$tfDir` = `<repo-root>\terraform` (grep for `Join-Path $repoRoot 'terraform'` — should still be there, just with corrected `$repoRoot`)
- [ ] Post-apply message references `opencode_env` output, not hardcoded model names
- [ ] Grep check: `Select-String -Path deploy\scripts\deploy.ps1 -Pattern "claude-opus|ANTHROPIC_BASE_URL|ANTHROPIC_MODEL"` — should return no matches after fix

### Anti-pattern guards

- Do NOT change `$tfDir` or `$bootstrapDir` variable names — they are used later in the script
- Do NOT use `-chdir` on `terraform init` in the bootstrap step — the script uses `Push-Location $bootstrapDir` for that

---

## Phase 2: Add Anthropic-format support to `chat.py`

### What to implement

**File: `scripts/chat.py`** — add a second client factory and branch on env vars.

Pattern to copy: current OpenAI branch is at `chat.py:33-41` (working). Add Anthropic branch alongside it.

Detection logic: check `AZURE_OPENAI_ENDPOINT` vs `ANTHROPIC_BASE_URL` to decide which client to build. If `AZURE_OPENAI_ENDPOINT` is set → OpenAI branch. If `ANTHROPIC_BASE_URL` is set → Anthropic branch. If neither → clear error message.

New structure:
```python
"""Simple chat against an Azure AI Foundry deployment.

Supports both OpenAI-format and Anthropic-format deployments.
The required environment variables differ by model format — run:
    Invoke-Expression (terraform output -raw opencode_env)  # PowerShell
to load the correct variables for your deployed model.

OpenAI format (e.g. gpt-5.5):
    AZURE_OPENAI_ENDPOINT     e.g. https://<account>.services.ai.azure.com/openai
    AZURE_OPENAI_DEPLOYMENT   deployment name, e.g. gpt-5-5
    OPENAI_API_VERSION        (optional, default: 2024-10-21)

Anthropic/DeepSeek format (e.g. claude-opus-4-7, deepseek-r1-0528):
    ANTHROPIC_BASE_URL        e.g. https://<account>.services.ai.azure.com/anthropic
    ANTHROPIC_MODEL           model name, e.g. claude-opus-4-7
    ANTHROPIC_API_KEY         primary key from the AI Services account

The signed-in principal needs "Cognitive Services User" on the AIServices account.
Run `az login` first (OpenAI format uses Azure AD; Anthropic format uses the primary key).
"""
```

Add `make_anthropic_client()` returning `anthropic.Anthropic`:
```python
def make_anthropic_client():
    import anthropic
    return anthropic.Anthropic(
        api_key=os.environ["ANTHROPIC_API_KEY"],
        base_url=os.environ["ANTHROPIC_BASE_URL"],
    )
```

Update `chat()` to branch:
```python
def chat(prompt: str, max_tokens: int = 1024) -> str:
    if os.environ.get("AZURE_OPENAI_ENDPOINT"):
        client = make_openai_client()
        deployment = os.environ["AZURE_OPENAI_DEPLOYMENT"]
        response = client.chat.completions.create(
            model=deployment,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
        )
        return response.choices[0].message.content or ""
    elif os.environ.get("ANTHROPIC_BASE_URL"):
        import anthropic
        client = make_anthropic_client()
        model = os.environ["ANTHROPIC_MODEL"]
        message = client.messages.create(
            model=model,
            max_tokens=max_tokens,
            messages=[{"role": "user", "content": prompt}],
        )
        return message.content[0].text
    else:
        raise EnvironmentError(
            "No model endpoint configured. Run: Invoke-Expression (terraform output -raw opencode_env)"
        )
```

Rename `make_client()` → `make_openai_client()` for clarity.

**File: `scripts/requirements.txt`** — add anthropic:
```
azure-identity>=1.17.0
openai>=1.50.0
anthropic>=0.40.0
```

### Verification checklist

- [ ] `python -m py_compile scripts/chat.py` — no syntax errors
- [ ] `python -c "import scripts.chat"` or `python scripts/chat.py --help` succeeds (imports resolve)
- [ ] Grep: `Select-String -Path scripts\chat.py -Pattern "ANTHROPIC_BASE_URL"` — match found
- [ ] Grep: `Select-String -Path scripts\chat.py -Pattern "make_openai_client|make_anthropic_client"` — both found
- [ ] Grep: `Select-String -Path scripts\requirements.txt -Pattern "anthropic"` — match found

### Anti-pattern guards

- Do NOT use `azure_ad_token_provider` in the Anthropic branch — AI Foundry Anthropic endpoint uses key-based auth
- Do NOT call `anthropic.Anthropic()` without `base_url` — the default base_url is `api.anthropic.com`, not Azure
- Do NOT import `anthropic` at module level — keep it inside the branch so the script doesn't fail when `anthropic` is not installed and only OpenAI models are used (lazy import pattern already used above)

---

## Phase 3: Fix minor Terraform output issue

### What to implement

**File: `terraform/modules/model-deployment/outputs.tf`**

Find the `primary_key` output description. Change from:
```hcl
description = "Use as ANTHROPIC_API_KEY"
```
to:
```hcl
description = "Primary key for the AI Services account. Use as AZURE_OPENAI_API_KEY (OpenAI format) or ANTHROPIC_API_KEY (Anthropic/DeepSeek format)."
```

Also add a comment to the `endpoint_url` output explaining why DeepSeek routes to `/anthropic`:
```hcl
# DeepSeek MaaS on Azure AI Foundry exposes an Anthropic-compatible inference API,
# so non-OpenAI models (including DeepSeek) use the /anthropic path.
```

### Verification checklist

- [ ] `terraform validate` in `terraform/` succeeds (no HCL syntax errors)
- [ ] Grep: `Select-String -Path terraform\modules\model-deployment\outputs.tf -Pattern "ANTHROPIC_API_KEY"` — old description gone, new generic one present

---

## Phase 4: Update README.md

### What to implement

**File: `README.md`**

1. Line 3 (or wherever "Claude Opus 4.7" is mentioned as default): change to `gpt-5.5 (OpenAI format)`
2. `opencode_env` example section: show both branches (OpenAI and Anthropic), matching what `terraform output -raw opencode_env` actually emits
3. Architecture diagram description: replace "One Anthropic MaaS deployment" with "One model deployment per entry in `var.deployments` (OpenAI or Anthropic/DeepSeek format)"
4. "Choosing a different model" section: add a `gpt-5.5` example alongside the Anthropic example

### Verification checklist

- [ ] Grep: `Select-String -Path README.md -Pattern "Claude Opus 4.7"` — no mention as default model (may remain in catalog documentation)
- [ ] Grep: `Select-String -Path README.md -Pattern "AZURE_OPENAI_ENDPOINT"` — appears in the opencode_env section
- [ ] `README.md` compiles as valid Markdown (no broken fences)

---

## Final Phase: Integration Verification

### Checklist

- [ ] `terraform validate` passes in both `terraform/` and `terraform/bootstrap/`
- [ ] `python -m py_compile scripts/chat.py` — no errors
- [ ] `deploy/scripts/deploy.ps1` path check: parse the file and verify `$repoRoot` uses double `Split-Path -Parent`
- [ ] Grep sweep — none of these should appear:
  - `Select-String -Path deploy\scripts\deploy.ps1 -Pattern "claude-opus|ANTHROPIC_BASE_URL = |ANTHROPIC_MODEL = "` → 0 matches
  - `Select-String -Path terraform\modules\model-deployment\outputs.tf -Pattern "Use as ANTHROPIC_API_KEY"` → 0 matches
- [ ] `git diff --stat` lists only the 5 expected files: `deploy/scripts/deploy.ps1`, `scripts/chat.py`, `scripts/requirements.txt`, `terraform/modules/model-deployment/outputs.tf`, `README.md`
