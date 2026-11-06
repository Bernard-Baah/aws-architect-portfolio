#!/usr/bin/env python3
"""Generate realistic rack-inventory CSVs for the burst test (stdlib only).

    python3 scripts/generate_inventory.py OUT_DIR COUNT [--seed N]

About 1 in 5 files gets planted problems (missing serial, duplicate U,
bad rack unit, unknown status, duplicate tag). Every file is a valid CSV, so
all of them should end COMPLETE; none belong in the DLQ.
Prints a JSON manifest summary on stdout.
"""

import argparse
import csv
import json
import pathlib
import random

MODELS = ["Graviton Server G2", "Graviton Server G3", "Storage Node S4", "GPU Node P5", "Top-of-Rack Switch 100G"]
STATUSES = ["in_service"] * 8 + ["spare", "staged", "rma"]


def make_file(rng, idx):
    racks = [f"R{n:02d}" for n in rng.sample(range(1, 81), rng.randint(1, 3))]  # distinct racks
    rows, n = [], 0
    for rack in racks:
        units = rng.sample(range(1, 43), rng.randint(8, 20))
        for u in sorted(units):
            n += 1
            rows.append({
                "asset_tag": f"DC1-{idx:04d}{n:03d}",
                "serial_number": f"SN{rng.randrange(16**8):08X}",
                "rack": rack,
                "rack_unit": str(u),
                "model": rng.choice(MODELS),
                "status": rng.choice(STATUSES),
            })
        rows.append({"asset_tag": f"DC1-{idx:04d}T{rack}", "serial_number": f"SN{rng.randrange(16**8):08X}",
                     "rack": rack, "rack_unit": "43", "model": MODELS[-1], "status": "in_service"})

    planted = 0
    if rng.random() < 0.2:
        victim = rng.choice(rows)
        problem = rng.choice(["serial", "unit", "status", "dup_tag", "dup_u"])
        if problem == "serial":
            victim["serial_number"] = ""
        elif problem == "unit":
            victim["rack_unit"] = str(rng.randint(49, 60))
        elif problem == "status":
            victim["status"] = "broken"
        elif problem == "dup_tag":
            rows.append(dict(victim, rack_unit="44", serial_number=f"SN{rng.randrange(16**8):08X}"))
        else:
            other = dict(victim, asset_tag=victim["asset_tag"] + "B", status="in_service")
            victim["status"] = "in_service"
            rows.append(other)
        planted = 1
    return rows, planted


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("count", type=int)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    total_rows = files_with_issues = 0
    for i in range(args.count):
        rows, planted = make_file(rng, i)
        total_rows += len(rows)
        files_with_issues += planted
        with open(out / f"inventory-{i:04d}.csv", "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
    print(json.dumps({"files": args.count, "rows": total_rows, "files_with_planted_issues": files_with_issues}))


if __name__ == "__main__":
    main()
