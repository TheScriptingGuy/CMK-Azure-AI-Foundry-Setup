"""Simple chat against an Azure AI Foundry OpenAI-compatible deployment.

Authenticates with Azure AD via azure-identity (DefaultAzureCredential) and
calls the chat completions endpoint exposed by the Foundry account.

Required environment variables (emitted by `terraform output -raw opencode_env`):
    AZURE_OPENAI_ENDPOINT     e.g. https://<account>.services.ai.azure.com/openai
    AZURE_OPENAI_DEPLOYMENT   deployment name, e.g. gpt-5-5

Optional:
    OPENAI_API_VERSION        API version header (default: 2024-10-21)

The signed-in principal needs "Cognitive Services User" on the AIServices account.
Run `az login` first (or set AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_CLIENT_SECRET).

Usage:
    python chat.py "Write me a haiku about Terraform."
"""

from __future__ import annotations

import argparse
import os
import sys

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

COGNITIVE_SERVICES_SCOPE = "https://cognitiveservices.azure.com/.default"
DEFAULT_API_VERSION = "2024-10-21"


def make_client() -> AzureOpenAI:
    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(), COGNITIVE_SERVICES_SCOPE
    )
    return AzureOpenAI(
        azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        azure_ad_token_provider=token_provider,
        api_version=os.environ.get("OPENAI_API_VERSION", DEFAULT_API_VERSION),
    )


def chat(prompt: str, max_tokens: int = 1024) -> str:
    client = make_client()
    deployment = os.environ["AZURE_OPENAI_DEPLOYMENT"]
    response = client.chat.completions.create(
        model=deployment,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens,
    )
    return response.choices[0].message.content or ""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Simple chat against an Azure AI Foundry OpenAI-compatible deployment."
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
