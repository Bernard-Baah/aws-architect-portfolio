#!/usr/bin/env python3
"""Checks the price model against the real bill.

For the usage types Project 01/03 actually ran (NAT, ALB, EC2, RDS), Cost
Explorer gives hours used and dollars charged over the period. Dollars / hours
is the effective rate you were billed; it should equal the list price that
price_project01.py uses. Run from the management account (consolidated bill).

    AWS_PROFILE=tf python3 05-observability-finops/cost/check_against_bill.py 2026-11-01 2026-11-12
"""
import json
import subprocess
import sys

WATCH = ("NatGateway-Hours", "LoadBalancerUsage", "BoxUsage:t4g.micro",
         "Multi-AZUsage:db.t4g.micro", "InstanceUsage:db.t4g.micro", "PublicIPv4:InUseAddress")


def main(start, end):
    cmd = ["aws", "ce", "get-cost-and-usage", "--no-cli-pager", "--output", "json",
           "--time-period", f"Start={start},End={end}", "--granularity", "MONTHLY",
           "--metrics", "UnblendedCost", "UsageQuantity",
           "--group-by", "Type=DIMENSION,Key=USAGE_TYPE"]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stderr)

    totals = {}
    for period in json.loads(out.stdout)["ResultsByTime"]:
        for g in period["Groups"]:
            ut = g["Keys"][0]
            base = ut.split("-", 1)[1] if ut.startswith(("USE1-", "USW2-")) else ut
            if not any(base == w or base.endswith(w) for w in WATCH):
                continue
            cost = float(g["Metrics"]["UnblendedCost"]["Amount"])
            qty = float(g["Metrics"]["UsageQuantity"]["Amount"])
            c, q = totals.get(ut, (0.0, 0.0))
            totals[ut] = (c + cost, q + qty)

    print(f"## Billed {start} → {end} (management account, consolidated)\n")
    print("| Usage type | Hours | Billed | Effective $/hour |\n|---|---:|---:|---:|")
    for ut, (cost, qty) in sorted(totals.items(), key=lambda kv: -kv[1][0]):
        rate = cost / qty if qty else 0
        print(f"| `{ut}` | {qty:,.1f} | ${cost:,.2f} | ${rate:.4f} |")
    if not totals:
        print("| (no matching usage in this period) | | | |")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: check_against_bill.py START END   (YYYY-MM-DD, END exclusive)")
    main(*sys.argv[1:])
