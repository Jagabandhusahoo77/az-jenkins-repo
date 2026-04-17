#!/usr/bin/env python3
"""
analyze-security.py
-------------------
Sends checkov/tfsec scan results to Claude API.
Claude prioritizes findings, explains each in plain English,
and suggests the exact Terraform fix.

Usage:
    python3 analyze-security.py --checkov-file results_junitxml.xml
    python3 analyze-security.py --tfsec-file tfsec-results.json
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET


def call_claude(prompt: str, api_key: str) -> str:
    payload = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 2048,
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


def parse_checkov_junit(filepath: str) -> list[dict]:
    """Extract failed checks from checkov JUnit XML output."""
    tree = ET.parse(filepath)
    root = tree.getroot()
    failures = []
    for tc in root.iter("testcase"):
        failure = tc.find("failure")
        if failure is not None:
            failures.append({
                "check": tc.get("name", ""),
                "resource": tc.get("classname", "").split(".")[-1],
                "file": tc.get("file", ""),
                "message": failure.get("message", ""),
            })
    return failures


def parse_tfsec_json(filepath: str) -> list[dict]:
    """Extract findings from tfsec JSON output."""
    with open(filepath) as f:
        data = json.load(f)
    findings = []
    for r in data.get("results", []):
        findings.append({
            "rule": r.get("rule_id", ""),
            "severity": r.get("severity", ""),
            "description": r.get("description", ""),
            "resource": r.get("resource", ""),
            "location": f"{r.get('location', {}).get('filename','')}:{r.get('location', {}).get('start_line','')}",
        })
    return findings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkov-file", help="Path to checkov JUnit XML")
    parser.add_argument("--tfsec-file", help="Path to tfsec JSON output")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ERROR: ANTHROPIC_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    findings_text = ""

    if args.checkov_file and os.path.exists(args.checkov_file):
        failures = parse_checkov_junit(args.checkov_file)
        if failures:
            findings_text += "CHECKOV FINDINGS:\n"
            for f in failures:
                findings_text += f"  - {f['check']}\n    Resource: {f['resource']}\n    File: {f['file']}\n\n"

    if args.tfsec_file and os.path.exists(args.tfsec_file):
        findings = parse_tfsec_json(args.tfsec_file)
        if findings:
            findings_text += "TFSEC FINDINGS:\n"
            for f in findings:
                findings_text += f"  - [{f['severity']}] {f['rule']}: {f['description']}\n    Resource: {f['resource']} @ {f['location']}\n\n"

    if not findings_text:
        print("No security findings to analyze.")
        sys.exit(0)

    prompt = f"""You are a cloud security engineer reviewing Terraform security scan results.

For each finding below:
1. **Explain** what the risk is in plain English (1 sentence)
2. **Show the exact Terraform fix** (code snippet)
3. **Rate severity**: CRITICAL / HIGH / MEDIUM / LOW

Then give an overall **ACTION REQUIRED** summary.

---

{findings_text}
"""

    print("=" * 60)
    print("CLAUDE SECURITY ANALYSIS")
    print("=" * 60)
    analysis = call_claude(prompt, api_key)
    print(analysis)
    print("=" * 60)


if __name__ == "__main__":
    main()
