"""Web search agent using Azure AI Foundry Agent Service.

Creates a transient agent with WebSearchTool, sends a query, prints the
grounded response with URL citations, then deletes the agent.

Required environment variables (emitted by `terraform output -raw opencode_env`):
    AZURE_FOUNDRY_PROJECT_ENDPOINT   https://<account>.services.ai.azure.com/api/projects/<project>
    AZURE_OPENAI_DEPLOYMENT          model deployment name, e.g. gpt-4o

Optional:
    WEB_SEARCH_COUNTRY   ISO 3166-1 alpha-2 country code for localised results (default: NL)
    WEB_SEARCH_CITY      city name for localised results (default: Amsterdam)

The signed-in principal needs "Cognitive Services User" on the AIServices account.
Run `az login` first.

Usage:
    python web_search.py "What are the latest AI developments this week?"
"""

from __future__ import annotations

import argparse
import os
import sys

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    PromptAgentDefinition,
    WebSearchTool,
    WebSearchApproximateLocation,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Web search via Foundry Agent Service.")
    parser.add_argument(
        "prompt",
        nargs="?",
        default="What are the latest developments in AI this week?",
    )
    parser.add_argument("--max-tokens", type=int, default=1024)
    args = parser.parse_args()

    endpoint = os.environ["AZURE_FOUNDRY_PROJECT_ENDPOINT"]
    model = os.environ["AZURE_OPENAI_DEPLOYMENT"]

    client = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())
    openai = client.get_openai_client()

    location = WebSearchApproximateLocation(
        country=os.environ.get("WEB_SEARCH_COUNTRY", "NL"),
        city=os.environ.get("WEB_SEARCH_CITY", "Amsterdam"),
    )

    agent = client.agents.create_version(
        agent_name="_web_search_tmp",
        definition=PromptAgentDefinition(
            model=model,
            instructions="You are a helpful assistant. Always cite your sources inline.",
            tools=[WebSearchTool(user_location=location)],
        ),
    )

    try:
        response = openai.responses.create(
            model=model,
            input=args.prompt,
            tool_choice="required",
            extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
        )
        print(response.output_text)

        for item in getattr(response, "output", []):
            for part in getattr(item, "content", []):
                for ann in getattr(part, "annotations", []):
                    if getattr(ann, "type", "") == "url_citation":
                        print(f"\n[{ann.title}]({ann.url})")
    finally:
        client.agents.delete_version(agent_name=agent.name, agent_version=agent.version)

    return 0


if __name__ == "__main__":
    sys.exit(main())
