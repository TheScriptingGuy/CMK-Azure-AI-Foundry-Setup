# Azure AI Foundry — Tools Reference

All tools available to agents in the Azure AI Foundry Agent Service.  
Research date: 2026-05-16 | Sources: Microsoft Learn, Azure Blogs (official only)

---

## 1. MCP Servers (Model Context Protocol)

Remote servers agents can call via the MCP protocol. Each requires a **project connection** (auth config) and an **agent tool definition**.

### Microsoft-Hosted (Catalog)

| Name | Endpoint | Purpose | Auth | Status |
|------|----------|---------|------|--------|
| **Azure DevOps** | `mcp.dev.azure.com` | Work items, PRs, pipelines, repos, wikis, test plans | Entra ID OBO (per-user) | Public Preview |
| **Foundry MCP Server** | `mcp.ai.azure.com` | Manage Foundry resources: models, deployments, evaluations, agents | Entra ID | Preview |
| **Azure MCP Server** | `mcp.azure.com` | Natural-language access to Azure resources (Foundry, Cosmos DB, etc.) | Entra ID | Preview |

### Database & Storage

| Name | Purpose | Auth | Prerequisites |
|------|---------|------|---------------|
| **Azure Cosmos DB** | List accounts/DBs/containers, run SQL queries, inspect metadata | Managed Identity or connection string | Existing Cosmos DB account |
| **SQL / Data API Builder** | Query Azure SQL or SQL Server via MCP | Managed Identity or connection string | Existing SQL server |

### Custom / Third-Party

| Name | Endpoint | Purpose | Auth |
|------|----------|---------|------|
| **GitHub** | `api.githubcopilot.com/mcp` | Issues, PRs, code search, repos, commits | GitHub PAT (API key) |
| **Anthropic (MCP)** | Custom (Anthropic-hosted) | Anthropic tool use via MCP | Anthropic API key |
| **Your own server** | Any HTTPS URL | Custom business logic | API key, Entra ID, or custom headers |

### Approval & access controls (all MCP servers)

```
require_approval: "always" | "never" | { never: ["tool1"] } | { always: ["tool2"] }
allowed_tools:    ["tool_name_1", "tool_name_2"]   # whitelist; omit = all tools allowed
```

---

## 2. Connectors (Logic Apps — 1,400+)

Exposed as MCP tools via the **Logic Apps Connectors** registry in the Foundry catalog (Public Preview, April 2026).  
Source: https://techcommunity.microsoft.com/blog/integrationsonazureblog/public-preview-azure-logic-apps-connectors-as-mcp-tools-in-microsoft-foundry/4473062

Auth varies per connector (OAuth, API key, or managed identity). Listed below are the most useful connectors by category.

### Data & Storage

| Connector ID | Service | Key actions |
|-------------|---------|------------|
| `azureblob` | Azure Blob Storage | Read/write blobs, list containers |
| `azuretables` | Azure Table Storage | Query and write table rows |
| `azurequeues` | Azure Queue Storage | Send and receive messages |
| `azurecosmosdb` | Azure Cosmos DB | CRUD on documents |
| `sql` | Azure SQL / SQL Server | Run queries, insert/update rows |
| `azuredataexplorer` | Azure Data Explorer | Run KQL queries |
| `azuredatalake` | Azure Data Lake | Read/write files |
| `onedriveforbusiness` | OneDrive for Business | Read/write files |
| `sharepointonline` | SharePoint Online | Read/write files, list items |

### Communication & Productivity

| Connector ID | Service | Key actions |
|-------------|---------|------------|
| `office365` | Outlook (Exchange Online) | Send email, read inbox, manage calendar |
| `teams` | Microsoft Teams | Post messages, create meetings, list channels |
| `office365users` | Azure AD Users | Look up user profiles |
| `office365groups` | Microsoft 365 Groups | List/manage groups |
| `planner` | Microsoft Planner | Create/update tasks and plans |
| `onenote` | OneNote | Read/write notebook pages |
| `yammer` | Viva Engage (Yammer) | Post and read community messages |

### Enterprise Systems

| Connector ID | Service | Key actions |
|-------------|---------|------------|
| `sap` | SAP ERP / S/4HANA | Call BAPIs, read tables |
| `servicenow` | ServiceNow | Create/update incidents and tickets |
| `salesforce` | Salesforce CRM | CRUD on objects (leads, opportunities) |
| `dynamics365` | Dynamics 365 | Read/write CRM/ERP data |
| `dynamics365fo` | Dynamics 365 Finance & Ops | Read/write financial records |
| `d365financeoperations` | Dynamics 365 Supply Chain | Supply chain operations |

### Developer & DevOps

| Connector ID | Service | Key actions |
|-------------|---------|------------|
| `github` | GitHub | Issues, PRs, repos (connector version) |
| `visualstudioteamservices` | Azure DevOps (connector) | Work items, builds |
| `jira` | Jira (Atlassian) | Issues, sprints, projects |
| `jenkins` | Jenkins | Trigger builds, get build status |
| `azurefunctions` | Azure Functions | Call HTTP-triggered functions |
| `azureloganalytics` | Log Analytics | Run KQL queries against logs |
| `azuremonitor` | Azure Monitor | Read metrics and alerts |

### AI & Cognitive

| Connector ID | Service | Key actions |
|-------------|---------|------------|
| `cognitiveservicestextanalytics` | Azure AI Language | Sentiment, entity extraction, key phrases |
| `cognitiveservicescomputervision` | Azure AI Vision | Describe/analyze images |
| `cognitiveservicesspeech` | Azure AI Speech | Text-to-speech, speech-to-text |
| `formrecognizer` | Azure Document Intelligence | Extract data from forms/PDFs |
| `contentmoderator` | Azure Content Moderator | Text and image moderation |

### Integration & Messaging

| Connector ID | Service | Key actions |
|-------------|---------|------------|
| `servicebus` | Azure Service Bus | Send/receive messages and sessions |
| `eventhubs` | Azure Event Hubs | Send events, read from consumer group |
| `eventgrid` | Azure Event Grid | Publish events |
| `slack` | Slack | Post messages, list channels |
| `twilio` | Twilio | Send SMS |
| `sendgrid` | SendGrid | Send transactional email |

### Finance & ERP

| Connector ID | Service | Key actions |
|-------------|---------|------------|
| `xero` | Xero Accounting | Invoices, contacts, accounts |
| `quickbooks` | QuickBooks Online | Invoices, expenses |
| `stripe` | Stripe | Payments, customers, subscriptions |

> Full catalog of 1,400+ connectors: browse **Foundry portal → Build → Tools → Logic Apps Connectors registry**

---

## 3. Built-in Skills (Native Agent Tools)

First-class tools built into the Foundry Agent Service — no MCP connection required.

| Skill | Purpose | Status | Notes |
|-------|---------|--------|-------|
| **Web Search** | Real-time public web search with inline URL citations | GA | Already enabled in this repo via `azapi_resource_action.enable_web_search` |
| **Code Interpreter** | Run Python in a sandboxed container; produce files/charts | GA | Uploads/downloads files via thread attachments |
| **File Search** | Vector search over uploaded files (PDF, DOCX, TXT, etc.) | GA | Requires a vector store; supports up to 10,000 files |
| **Azure AI Search** | Full-text + vector search against an Azure AI Search index | GA | Requires an existing AI Search resource |
| **Azure Functions** | Call any HTTP-triggered Azure Function | GA | Pass function URL + API key as connection |
| **Image Generation** | Generate images from text (DALL·E 3 / GPT-image-1) | Preview | Requires an image-generation model deployment |
| **Browser Automation** | Control a headless browser; scrape and interact with web pages | Preview | Higher latency; use for dynamic pages |
| **Computer Use** | Control a virtual desktop (mouse/keyboard) | Preview | Requires dedicated VM; very high latency |
| **Microsoft Fabric** | Query Fabric data agents (semantic models, lakehouses) | Preview | Requires Fabric workspace connection |
| **SharePoint** | Search and read SharePoint document libraries | Preview | Uses Entra ID; read-only |
| **Function Calling** | Define arbitrary JSON-schema functions the model calls | GA | Serverless; you implement the function handler |

### Foundry Toolboxes (Preview)

Bundle any combination of built-in skills + MCP servers + OpenAPI specs into a **single MCP endpoint**. Agents connect to the Toolbox instead of individual tools.

- Create in: **Foundry portal → Build → Toolboxes**
- Supported members: Web Search, Code Interpreter, File Search, Azure AI Search, Azure Functions, any MCP server, OpenAPI tool specs, Agent-to-Agent (A2A) connections
- The Toolbox itself acts as an MCP server — expose it to Claude Code or other clients via a single URL

---

## 4. Agent-to-Agent (A2A) Connections

Connect one Foundry agent as a tool of another (orchestrator pattern).

- The sub-agent exposes a typed interface; the orchestrator calls it like a function
- Configured as a skill in the Toolbox or directly in the agent definition
- Auth: Entra ID (same tenant) or API key

---

## 5. OpenAPI Tools

Point an agent at any OpenAPI 3.0 spec and it auto-generates callable tools from the paths.

- Upload the spec file or provide a URL
- Supports API key and OAuth auth schemes
- Good for: internal REST APIs, third-party services without a native connector

---

## 6. Implementation Notes

### What requires which Terraform provider?

| Item | Provider |
|------|---------|
| AI Foundry account, Key Vault, Storage | `azurerm` |
| Model deployments | `azapi` (preview resource type) |
| Project connections (MCP auth) | `azapi` (preview resource type) |
| Agent definitions | `azapi` (preview) — or **Python SDK** (recommended for stability) |
| Subscription feature flags (web search, Logic Apps) | `azapi_resource_action` |

### Connection resource type (verify before use)
```
Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview
```
Verify: `az provider show --namespace Microsoft.CognitiveServices --query "resourceTypes[?contains(resourceType,'connections')]"`

### Checking available Logic Apps feature flag
```powershell
az feature list --namespace Microsoft.Logic --query "[?contains(name,'MCP')]" --output table
```

### Testing an MCP connection from Python
```python
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MCPTool
from azure.identity import DefaultAzureCredential

project = AIProjectClient(
    endpoint=os.environ["AZURE_FOUNDRY_PROJECT_ENDPOINT"],
    credential=DefaultAzureCredential(),
)
tool = MCPTool(
    server_label="azure-devops",
    server_url="https://mcp.dev.azure.com",
    require_approval="never",
    allowed_tools=["list_work_items"],
)
```
