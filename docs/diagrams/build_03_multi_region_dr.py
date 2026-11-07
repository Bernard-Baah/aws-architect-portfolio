"""Generates docs/diagrams/03-multi-region-dr.svg (hand-laid-out architecture diagram).

Usage: python3 docs/diagrams/build_03_multi_region_dr.py docs/diagrams/03-multi-region-dr.svg
       rsvg-convert -w 1800 docs/diagrams/03-multi-region-dr.svg -o docs/diagrams/03-multi-region-dr.png
Same visual language as build_01/02.
"""
import sys
from xml.sax.saxutils import escape

W, H = 1200, 975
FONT = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

INK = "#16191f"
MUTED = "#5f6b7a"
REGION = "#7d8998"
VPC = "#8c4fff"
EDGE = "#8c4fff"
WAF = "#dd344c"
COMPUTE = "#ed7100"
DB = "#2e5fa8"
SEC = "#dd344c"
NET = "#8c4fff"
OK = "#1d8102"
STANDBY = "#b26200"

out = []
add = out.append


def text(x, y, s, size=13, weight="normal", fill=INK, anchor="start", halo=False, italic=False):
    extra = ' stroke="#ffffff" stroke-width="4" paint-order="stroke" stroke-linejoin="round"' if halo else ""
    style = ' font-style="italic"' if italic else ""
    add(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{fill}" '
        f'text-anchor="{anchor}"{style}{extra}>{escape(s)}</text>')


def rect(x, y, w, h, stroke, fill="none", rx=6, dash=None, sw=1.5):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')


def node(x, y, w, h, title, lines=(), color=COMPUTE, title_size=13):
    rect(x, y, w, h, "#c6ccd5", "#ffffff", rx=6, sw=1.2)
    add(f'<rect x="{x}" y="{y}" width="5" height="{h}" rx="2" fill="{color}"/>')
    cy = y + 20
    text(x + 14, cy, title, size=title_size, weight="600")
    for ln in lines:
        cy += 16
        text(x + 14, cy, ln, size=11.5, fill=MUTED)


def arrow(points, color=INK, dash=None, sw=1.8, head=True):
    pts = " ".join(f"{px},{py}" for px, py in points)
    d = f' stroke-dasharray="{dash}"' if dash else ""
    m = ' marker-end="url(#ah-%s)"' % color.strip("#") if head else ""
    add(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="{sw}"{d}{m} stroke-linejoin="round"/>')


add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}">')
add("<defs>")
for c in {INK, MUTED, DB, STANDBY, SEC}:
    cid = c.strip("#")
    add(f'<marker id="ah-{cid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
add("</defs>")
add(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')

# ------------------------------------------------------------------ title
text(40, 44, "Project 03 · Multi-region disaster recovery (warm standby)", size=22, weight="700")
text(1160, 44, "github.com/Bernard-Baah/aws-architect-portfolio", size=12, fill=MUTED, anchor="end")
text(40, 68, "One URL, two regions. Reads fail over per request with no errors; writes move with a one-command promotion.",
     size=13.5, fill=MUTED)

# ------------------------------------------------------------------ edge
node(40, 108, 120, 52, "Users", ("browser",), color=INK)
node(370, 92, 460, 86, "Amazon CloudFront + AWS WAF",
     ("one HTTPS URL · origin group (GET/HEAD/OPTIONS)",
      "primary first; standby on 500/502/503/504",
      "or primary connect timeout (1 attempt, 2 s)"), color=EDGE)
arrow([(160, 134), (368, 134)], INK)
text(264, 126, "HTTPS", size=10.5, anchor="middle", halo=True)

# ------------------------------------------------------------------ regions
REG = [
    dict(x=40, label="us-east-1 · primary", label_color=INK, cidr="VPC 10.0.0.0/16", az="us-east-1a + us-east-1b"),
    dict(x=640, label="us-west-2 · warm standby", label_color=STANDBY, cidr="VPC 10.1.0.0/16", az="us-west-2a + us-west-2b"),
]
RW = 520
for r in REG:
    x = r["x"]
    rect(x, 232, RW, 470, REGION, dash="6 5", rx=10)
    text(x + 14, 254, r["label"], size=14, weight="700", fill=r["label_color"])
    rect(x + 16, 268, RW - 32, 300, VPC, rx=8, sw=2)
    text(x + RW - 28, 288, r["cidr"], size=12, weight="600", fill=VPC, anchor="end")

# primary contents
L = 40
node(L + 36, 300, 440, 52, "Internal ALB", ("no public IP · ingress only from CloudFront's prefix list",), color=NET)
node(L + 36, 380, 440, 68, "Auto Scaling group · 2 × t4g.micro",
     ("us-east-1a + us-east-1b · ELB health checks", "reads DB credentials from Secrets Manager at boot"), color=COMPUTE)
node(L + 36, 476, 440, 68, "RDS PostgreSQL 17 · primary",
     ("encrypted · backups on (required for a replica)", "password set via write-only attribute"), color=DB)
node(L + 36, 600, 440, 68, "Secrets Manager · db-credentials",
     ("value written with secret_string_wo", "never in Terraform state"), color=SEC)

# standby contents
R = 640
node(R + 36, 300, 440, 52, "Internal ALB", ("same module, same security group chain",), color=NET)
node(R + 36, 380, 440, 68, "Auto Scaling group · 1 × t4g.micro (warm)",
     ("scaled to 2 by promote-standby.sh", "serves reads immediately on failover"), color=COMPUTE)
node(R + 36, 476, 440, 68, "RDS read replica → promoted on failover",
     ("own-region KMS key · ignore_changes on its source", "writable 290 s after promotion started"), color=DB)
node(R + 36, 600, 440, 68, "Secrets Manager · replica secret",
     ("readable while us-east-1 is down",), color=SEC)

# in-region arrows
for cx in (L + 256, R + 256):
    arrow([(cx, 352), (cx, 378)], INK)
    arrow([(cx, 448), (cx, 474)], DB)
text(L + 262, 368, ":8080", size=10.5, halo=True)
text(R + 262, 368, ":8080", size=10.5, halo=True)
text(L + 262, 465, ":5432 TLS", size=10.5, fill=DB, halo=True)
text(R + 262, 465, ":5432 TLS (local replica)", size=10.5, fill=DB, halo=True)

# CloudFront -> ALBs
arrow([(520, 178), (520, 206), (L + 256, 206), (L + 256, 298)], INK)
text(L + 340, 199, "preferred", size=11, weight="600", halo=True)
arrow([(680, 178), (680, 206), (R + 256, 206), (R + 256, 298)], STANDBY, dash="6 4")
text(R + 160, 199, "on failover, per request", size=11, weight="600", fill=STANDBY, halo=True)

# cross-region replication
arrow([(L + 476, 510), (R + 34, 510)], DB, dash="5 4")
text(600, 502, "async replication", size=11, weight="600", fill=DB, anchor="middle", halo=True)
arrow([(L + 476, 634), (R + 34, 634)], SEC, dash="5 4")
text(600, 626, "replicated", size=11, weight="600", fill=SEC, anchor="middle", halo=True)

# ------------------------------------------------------------------ cards
rect(40, 728, 520, 196, "#d5dbe3", "#fafbfc", rx=8)
text(56, 752, "Game day · 2026-11-07", size=13, weight="700")
rows = [
    ("Availability during the outage (808 requests)", "100.00%", OK),
    ("RTO for reads", "0 s", OK),
    ("RTO for writes (incident → writable DB)", "9 min 15 s", OK),
    ("   of which promotion", "290 s", OK),
    ("Target", "< 15 min ✓", OK),
    ("RPO under write load", "next game day", STANDBY),
]
y = 778
for label, value, color in rows:
    text(56, y, label, size=12, fill=MUTED)
    text(546, y, value, size=12, weight="700", fill=color, anchor="end")
    y += 24

rect(640, 728, 520, 196, "#d5dbe3", "#fafbfc", rx=8)
text(656, 752, "Timeline (UTC)", size=13, weight="700")
tl = [
    ("17:14:31", "us-east-1 app tier scaled to 0 (the incident)"),
    ("17:14:31", "CloudFront serves us-west-2, no failed requests"),
    ("17:19:00", "disaster declared: promote-standby.sh"),
    ("17:23:46", "replica promoted, database writable"),
    ("17:23:54", "2 healthy instances in us-west-2"),
]
y = 778
for t, ev in tl:
    text(656, y, t, size=12, weight="700", fill=INK)
    text(730, y, ev, size=12, fill=MUTED)
    y += 26

# ------------------------------------------------------------------ legend
ly = 952
arrow([(40, ly), (84, ly)], INK)
text(92, ly + 4, "normal path", size=12, fill=MUTED)
arrow([(200, ly), (244, ly)], STANDBY, dash="6 4")
text(252, ly + 4, "failover path", size=12, fill=MUTED)
arrow([(370, ly), (414, ly)], DB, dash="5 4")
text(422, ly + 4, "cross-region replication", size=12, fill=MUTED)
for i, (color, lab) in enumerate(((NET, "network"), (COMPUTE, "compute"), (DB, "database"), (SEC, "secrets"))):
    lx = 640 + i * 130
    add(f'<rect x="{lx}" y="{ly - 9}" width="5" height="16" rx="2" fill="{color}"/>')
    text(lx + 12, ly + 4, lab, size=12, fill=MUTED)

add("</svg>")
open(sys.argv[1], "w").write("\n".join(out))
