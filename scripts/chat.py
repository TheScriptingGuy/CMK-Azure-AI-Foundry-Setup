"""Simple chat against an Azure AI Foundry Anthropic MaaS deployment.

Authenticates with Azure AD via azure-identity (DefaultAzureCredential) and
POSTs to the Anthropic-compatible /v1/messages route exposed by the Foundry
account.

Required environment variables (the same names emitted by `terraform output
-raw opencode_env`):
    ANTHROPIC_BASE_URL   e.g. https://<account>.services.ai.azure.com/anthropic
    ANTHROPIC_MODEL      e.g. claude-opus-4-7

Optional:
    ANTHROPIC_VERSION    Anthropic API version header (default: 2023-06-01)

The signed-in principal needs a data-plane role on the AIServices account,
e.g. "Cognitive Services User". Run `az login` first (or set the
AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_CLIENT_SECRET env vars for SP auth).

Usage:
    python chat.py "Write me a haiku about Terraform."
"""

from __future__ import annotations

import argparse
import os
import sys

import requests
from azure.identity import DefaultAzureCredential

COGNITIVE_SERVICES_SCOPE = "https://cognitiveservices.azure.com/.default"
DEFAULT_ANTHROPIC_VERSION = "2023-06-01"


def get_token() -> str:
    credential = DefaultAzureCredential()
    return credential.get_token(COGNITIVE_SERVICES_SCOPE).token


def chat(prompt: str, max_tokens: int = 1024) -> str:
    base_url = os.environ["ANTHROPIC_BASE_URL"].rstrip("/")
    model = os.environ["ANTHROPIC_MODEL"]
    anthropic_version = os.environ.get("ANTHROPIC_VERSION", DEFAULT_ANTHROPIC_VERSION)

    token = get_token()

    url = f"{base_url}/v1/messages"
    headers = {
        "Authorization": f"Bearer {token}",
        "anthropic-version": anthropic_version,
        "content-type": "application/json",
    }
    body = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }

    resp = requests.post(url, headers=headers, json=body, timeout=60)
    resp.raise_for_status()
    data = resp.json()

    return "".join(
        block.get("text", "")
        for block in data.get("content", [])
        if block.get("type") == "text"
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Simple chat against Azure AI Foundry Anthropic MaaS."
    )
    parser.add_argument(
        "prompt",
        nargs="?",
        default="Say hello in one short sentence.",
        help="Prompt to send to the model.",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=1024,
        help="Max tokens in the response (default: 1024).",
    )
    args = parser.parse_args()

    print(chat(args.prompt, max_tokens=args.max_tokens))
    return 0


if __name__ == "__main__":
    sys.exit(main())
