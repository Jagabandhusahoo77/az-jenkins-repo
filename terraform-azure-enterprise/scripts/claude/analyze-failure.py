#!/usr/bin/env python3
"""
analyze-failure.py
------------------
Called in Jenkins post { failure } block.
Sends the failed stage logs to Claude and returns a root-cause analysis
with suggested fix — printed directly into the Jenkins build log.

Usage:
    python3 analyze-failure.py --log-file build.log --stage "Terraform Plan" --environment dev
"""

import argparse
import json
import os
import sys
import urllib.request


def call_claude(prompt: str, api_key: str) -> str:
    payload = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}]
    }

    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps(payload).encode(),
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        method="POST"
    )

    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())["content"][0]["text"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--stage", required=True, help="Name of the failed Jenkins stage")
    parser.add_argument("--environment", default="unknown")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        # Fail silently — don't break pipeline just because Claude isn't available
        print("ANTHROPIC_API_KEY not set — skipping failure analysis")
        sys.exit(0)

    try:
        with open(args.log_file) as f:
            log = f.read()[-8000:]  # last 8000 chars (most relevant)
    except FileNotFoundError:
        print(f"Log file not found: {args.log_file}")
        sys.exit(0)

    prompt = f"""A Jenkins CI/CD pipeline failed at stage: **{args.stage}** (environment: {args.environment})

Analyze the error log and provide:
1. **ROOT CAUSE** — what exactly went wrong (1-2 sentences)
2. **FIX** — the exact command or code change needed to resolve it
3. **PREVENTION** — how to prevent this in future

Be specific. Reference exact error messages and line numbers where possible.

---

BUILD LOG (last portion):
{log}
"""

    print("\n" + "=" * 60)
    print(f"CLAUDE FAILURE ANALYSIS — Stage: {args.stage}")
    print("=" * 60)
    analysis = call_claude(prompt, api_key)
    print(analysis)
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()
