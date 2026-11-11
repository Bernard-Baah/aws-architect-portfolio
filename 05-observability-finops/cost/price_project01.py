#!/usr/bin/env python3
"""Cost case study for Project 01 (HA web app), priced live from the AWS Price List API.

Prices every fixed-cost component of Project 01's design in us-east-1 and walks
from the "production pattern left running in dev" to a dev-sized configuration,
one change at a time, with the trade-off of each. Usage-based charges (data
processed, requests, logs) are listed separately: an idle lab has almost none.

    AWS_PROFILE=tf python3 05-observability-finops/cost/price_project01.py

Needs only the AWS CLI (pricing:GetProducts, read-only; ReadOnlyAccess covers it).
"""
import json
import re
import subprocess
import sys

LOCATION = "US East (N. Virginia)"
HOURS_PER_MONTH = 730
# Office hours: 12 h on weekdays = 60 of 168 hours a week.
OFFICE_FRACTION = 60 / 168


def get_products(service, filters):
    cmd = ["aws", "pricing", "get-products", "--region", "us-east-1", "--no-cli-pager",
           "--service-code", service, "--output", "json", "--filters"]
    cmd += [f"Type=TERM_MATCH,Field={k},Value={v}" for k, v in filters.items()]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"pricing call failed for {service} {filters}:\n{out.stderr}")
    return [json.loads(p) for p in json.loads(out.stdout).get("PriceList", [])]


def price(label, service, filters, usage=None, unit=None):
    """First on-demand USD price > 0 whose usagetype matches `usage` (regex)."""
    for p in get_products(service, filters):
        attrs = p["product"]["attributes"]
        if usage and not re.search(usage, attrs.get("usagetype", "")):
            continue
        for term in p.get("terms", {}).get("OnDemand", {}).values():
            for dim in term["priceDimensions"].values():
                usd = float(dim["pricePerUnit"].get("USD", 0))
                if usd > 0 and (unit is None or dim["unit"] == unit):
                    return {"label": label, "usd": usd, "unit": dim["unit"],
                            "usagetype": attrs.get("usagetype", "")}
    sys.exit(f"no price found for {label} ({service} {filters} usage~{usage})")


def main():
    loc = {"location": LOCATION}
    p = {
        "nat": price("NAT gateway", "AmazonEC2", {**loc, "productFamily": "NAT Gateway"}, r"NatGateway-Hours$"),
        "nat_gb": price("NAT data processed", "AmazonEC2", {**loc, "productFamily": "NAT Gateway"}, r"NatGateway-Bytes$"),
        "ipv4": price("Public IPv4 (in use)", "AmazonVPC", loc, r"PublicIPv4:InUseAddress$"),
        "alb": price("Application Load Balancer", "AmazonEC2", {**loc, "productFamily": "Load Balancer-Application"}, r"LoadBalancerUsage$"),
        "t4g": price("EC2 t4g.micro", "AmazonEC2", {**loc, "instanceType": "t4g.micro", "operatingSystem": "Linux",
                     "tenancy": "Shared", "preInstalledSw": "NA", "capacitystatus": "Used"}),
        "t3": price("EC2 t3.micro", "AmazonEC2", {**loc, "instanceType": "t3.micro", "operatingSystem": "Linux",
                    "tenancy": "Shared", "preInstalledSw": "NA", "capacitystatus": "Used"}),
        "ebs": price("EBS gp3 (GB-month)", "AmazonEC2", {**loc, "productFamily": "Storage", "volumeApiName": "gp3"}),
        "rds_maz": price("RDS db.t4g.micro Multi-AZ", "AmazonRDS", {**loc, "instanceType": "db.t4g.micro",
                         "databaseEngine": "PostgreSQL", "deploymentOption": "Multi-AZ"}),
        "rds_saz": price("RDS db.t4g.micro Single-AZ", "AmazonRDS", {**loc, "instanceType": "db.t4g.micro",
                         "databaseEngine": "PostgreSQL", "deploymentOption": "Single-AZ"}),
        "rds_gp3_maz": price("RDS gp3 storage Multi-AZ (GB-month)", "AmazonRDS", loc, r"Multi-AZ-GP3-Storage$"),
        "rds_gp3_saz": price("RDS gp3 storage Single-AZ (GB-month)", "AmazonRDS", loc, r"(?<!Multi-AZ-)GP3-Storage$"),
    }

    H = HOURS_PER_MONTH
    office = H * OFFICE_FRACTION

    def monthly(c):
        nat = c["nats"] * (p["nat"]["usd"] + p["ipv4"]["usd"]) * H
        alb = p["alb"]["usd"] * H
        ec2_rate = p[c["ec2"]]["usd"]
        ec2 = 2 * ec2_rate * (office if c["schedule"] else H)
        ebs = 2 * 10 * p["ebs"]["usd"]
        rds_rate = p["rds_maz" if c["multi_az"] else "rds_saz"]["usd"]
        rds = rds_rate * (office if c["schedule"] else H)
        storage = 20 * p["rds_gp3_maz" if c["multi_az"] else "rds_gp3_saz"]["usd"]
        return {"NAT + IPv4": nat, "ALB": alb, "EC2": ec2, "EBS": ebs, "RDS": rds, "RDS storage": storage}

    steps = [
        ("Production pattern left on in dev", "", {"nats": 2, "ec2": "t3", "multi_az": True, "schedule": False}),
        ("Graviton (t3 → t4g)", "Arm64 build; same performance class, lower price",
         {"nats": 2, "ec2": "t4g", "multi_az": True, "schedule": False}),
        ("One shared NAT instead of one per AZ", "An AZ outage cuts egress for the other AZ (fine for dev, not prod)",
         {"nats": 1, "ec2": "t4g", "multi_az": True, "schedule": False}),
        ("RDS Single-AZ in dev", "No automatic failover (Project 01 measured 40 s with Multi-AZ); keep Multi-AZ in prod",
         {"nats": 1, "ec2": "t4g", "multi_az": False, "schedule": False}),
        ("Office-hours schedule (EC2 + RDS, 12 h × weekdays)", "App is down nights/weekends; RDS restarts itself after 7 days stopped",
         {"nats": 1, "ec2": "t4g", "multi_az": False, "schedule": True}),
    ]

    print("## Unit prices (AWS Price List API, us-east-1, on-demand)\n")
    print("| Component | Price | Unit | Usage type |\n|---|---:|---|---|")
    for v in p.values():
        print(f"| {v['label']} | ${v['usd']:.4f} | {v['unit']} | `{v['usagetype']}` |")

    print("\n## Walk from production pattern to dev-sized (fixed costs, $/month)\n")
    print("| Change | Monthly | Saved | Trade-off |\n|---|---:|---:|---|")
    first = prev = None
    for name, tradeoff, cfg in steps:
        total = sum(monthly(cfg).values())
        if first is None:
            first = prev = total
            print(f"| **{name}** | **${total:,.2f}** | | |")
            continue
        print(f"| {name} | ${total:,.2f} | ${prev - total:,.2f} | {tradeoff} |")
        prev = total
    print(f"| **Total** | **${prev:,.2f}** | **${first - prev:,.2f} ({100 * (first - prev) / first:.0f}%)** | |")

    print("\n## Not in the totals (usage-based, near zero for an idle lab)\n")
    print(f"- NAT data processed: ${p['nat_gb']['usd']:.3f}/GB (an S3 **gateway endpoint** is free and takes S3 traffic off the NAT)")
    print("- ALB LCUs, CloudFront requests and data transfer, WAF ($5/month per web ACL + $1 per rule + requests), VPC flow log ingestion")


if __name__ == "__main__":
    main()
