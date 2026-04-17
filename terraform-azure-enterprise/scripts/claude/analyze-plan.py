#!/usr/bin/env python3
"""
analyze-plan.py
---------------
Sends terraform plan output to Claude API and returns a plain-English
summary of what will change, highlighting risky operations (destroy,
replace, security group changes).

Usage:
    python3 analyze-plan.py --plan-file tfplan-dev.txt --environment dev

Output:
    Prints Claude's analysis to stdout (captured by Jenkins and shown in logs)
    Exits 1 if Claude detects HIGH-RISK changes (destroys in prod)
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error

def call_claude(prompt: str, api_key: str) -> str:
    payload = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 1024,
        "messages": [
            {"role": "user", "content": prompt}
        ]
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

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())["content"][0]["text"]
    except urllib.error.HTTPError as e:
        print(f"Claude API error {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-file", required=True, help="Path to terraform show -no-color output")
    parser.add_argument("--environment", required=True, help="Target environment (dev/staging/prod)")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ERROR: ANTHROPIC_API_KEY environment variable not set", file=sys.stderr)
        sys.exit(1)

    with open(args.plan_file) as f:
        plan_text = f.read()

    # Truncate very large plans to stay within token limits
    if len(plan_text) > 12000:
        plan_text = plan_text[:12000] + "\n\n[... plan truncated for analysis ...]"

    prompt = f"""You are a senior Azure infrastructure engineer reviewing a Terraform plan for the **{args.environment}** environment.

Analyze this plan and provide:

1. **SUMMARY** — 2-3 sentences: what is being created, changed, or destroyed
2. **CHANGES TABLE** — bullet list of key resources: action (add/change/destroy), resource type, resource name
3. **RISK ASSESSMENT** — rate overall risk: LOW / MEDIUM / HIGH
4. **WARNINGS** — call out any:
   - Resources being DESTROYED (especially in prod)
   - Resources being REPLACED (destroy + create)
   - Security group or firewall rule changes
   - Database or storage changes
   - IAM/RBAC changes
5. **RECOMMENDATION** — one line: APPROVE / APPROVE WITH CAUTION / REJECT

Be concise. Use plain English. Flag anything that needs human review.

---

TERRAFORM PLAN:
{plan_text}
"""

    print("=" * 60)
    print(f"CLAUDE PLAN ANALYSIS — {args.environment.upper()}")
    print("=" * 60)

    analysis = call_claude(prompt, api_key)
    print(analysis)
    print("=" * 60)

    # Exit 1 if Claude recommends REJECT (blocks the pipeline)
    if "REJECT" in analysis.upper() and args.environment == "prod":
        print("\n⚠  Claude flagged this plan as REJECT for prod — blocking pipeline.")
        print("   Review the analysis above and re-run with FORCE_PLAN=true to override.")
        sys.exit(1)


if __name__ == "__main__":
    main()
