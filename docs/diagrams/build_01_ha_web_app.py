"""Generates docs/diagrams/01-ha-web-app.svg (hand-laid-out architecture diagram).

Usage: python3 docs/diagrams/build_01_ha_web_app.py docs/diagrams/01-ha-web-app.svg
       rsvg-convert -w 1800 docs/diagrams/01-ha-web-app.svg -o docs/diagrams/01-ha-web-app.png
"""
import sys

W, H = 1200, 880
FONT = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

# palette
INK = "#16191f"
MUTED = "#5f6b7a"
REGION = "#7d8998"
VPC = "#8c4fff"
AZ = "#3f7fd8"
PUB_FILL, PUB_LINE = "#eef6e3", "#7aa116"
PRIV_FILL, PRIV_LINE = "#e8f1fb", "#3f7fd8"
DATA_FILL, DATA_LINE = "#eaf0fa", "#2e5fa8"
EDGE = "#8c4fff"
WAF = "#dd344c"
COMPUTE = "#ed7100"
DB = "#2e5fa8"
NET = "#8c4fff"
SEC = "#dd344c"
MGMT = "#e7157b"
OK = "#1d8102"

out = []
add = out.append


def text(x, y, s, size=13, weight="normal", fill=INK, anchor="start", halo=False, italic=False):
    extra = ' stroke="#ffffff" stroke-width="4" paint-order="stroke" stroke-linejoin="round"' if halo else ""
    style = ' font-style="italic"' if italic else ""
    add(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{fill}" '
        f'text-anchor="{anchor}"{style}{extra}>{s}</text>')


def rect(x, y, w, h, stroke, fill="none", rx=6, dash=None, sw=1.5):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')


def node(x, y, w, h, title, lines=(), color=COMPUTE, title_size=13):
    """Service box with a colored accent bar."""
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


# ------------------------------------------------------------------ canvas
add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}">')
add("<defs>")
for c in {INK, MUTED, DB, OK}:
    cid = c.strip("#")
    add(f'<marker id="ah-{cid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
add("</defs>")
add(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')

# title
text(40, 44, "Project 01 · Highly available multi-tier web app", size=22, weight="700")
text(1160, 44, "github.com/Bernard-Baah/aws-architect-portfolio", size=12, fill=MUTED, anchor="end")
text(40, 68, "No public endpoint inside the VPC. Built with Terraform in us-east-1; every layer measured.", size=13.5, fill=MUTED)

# ------------------------------------------------------------------ region / VPC / AZs
rect(430, 92, 745, 708, REGION, dash="6 5", rx=10)
text(1163, 112, "AWS Region · us-east-1", size=12.5, weight="600", fill=REGION, anchor="end")

rect(450, 126, 525, 654, VPC, rx=8, sw=2)
text(700, 150, "VPC 10.0.0.0/16 · Flow Logs on", size=12.5, weight="600", fill=VPC)

for ax, label in ((468, "us-east-1a"), (722, "us-east-1b")):
    rect(ax, 162, 236, 604, AZ, dash="5 4", rx=8)
    text(ax + 10, 180, label, size=12, weight="600", fill=AZ)

# subnets: (row_y, row_h, fill, line, labels for a/b)
rows = [
    (192, 116, PUB_FILL, PUB_LINE, ("Public 10.0.0.0/24", "Public 10.0.1.0/24")),
    (322, 246, PRIV_FILL, PRIV_LINE, ("App 10.0.10.0/24", "App 10.0.11.0/24")),
    (582, 170, DATA_FILL, DATA_LINE, ("Data 10.0.20.0/24 (isolated)", "Data 10.0.21.0/24 (isolated)")),
]
for i, (ry, rh, fill, line, labels) in enumerate(rows):
    for sx, lab in zip((478, 732), labels):
        rect(sx, ry, 216, rh, line, fill, rx=6, sw=1.2)
        # data-tier labels sit at the bottom so the DB arrows can enter from above
        ly_ = ry + rh - 9 if i == 2 else ry + 17
        text(sx + 10, ly_, lab, size=11, weight="600", fill=line)

# internet gateway straddling the VPC edge
node(548, 112, 132, 30, "Internet gateway", color=NET, title_size=12)

# NAT
node(492, 222, 188, 62, "NAT Gateway", ("app tier outbound only", "1 shared (lab)"), color=NET)
text(840, 258, "NAT per AZ in production", size=11, fill=MUTED, anchor="middle", italic=True)

# internal ALB spanning both app subnets
node(490, 348, 446, 56, "Internal Application Load Balancer",
     ("no public IP · HTTP :80 from CloudFront prefix list only · /health every 10 s",), color=NET)

# ASG + instances
rect(486, 430, 454, 82, COMPUTE, dash="6 4", rx=8, sw=1.5)
node(498, 444, 192, 58, "EC2 t4g.micro", ("AL2023 · app :8080 · IMDSv2",), color=COMPUTE)
node(744, 444, 184, 58, "EC2 t4g.micro", ("AL2023 · app :8080 · IMDSv2",), color=COMPUTE)
text(715, 434, "Auto Scaling group · 2–4", size=11.5, weight="600", fill=COMPUTE, anchor="middle", halo=True)

# RDS
node(492, 610, 188, 62, "RDS primary", ("PostgreSQL 17 · encrypted",), color=DB)
node(746, 610, 182, 62, "RDS standby", ("synchronous replica",), color=DB)
text(713, 704, "RDS Multi-AZ · automatic failover", size=11.5, weight="600", fill=DB, anchor="middle", halo=True)
text(713, 722, "no internet route · no egress · password in Secrets Manager", size=11, fill=MUTED, anchor="middle", halo=True)

# regional services
text(1078, 384, "Regional services", size=12, weight="600", fill=MUTED, anchor="middle")
node(992, 396, 172, 50, "Secrets Manager", ("DB credentials, rotated",), color=SEC)
node(992, 458, 172, 50, "Systems Manager", ("Session Manager shell",), color=MGMT)
node(992, 520, 172, 50, "CloudWatch Logs", ("VPC Flow Logs, 7 days",), color=MGMT)

# ------------------------------------------------------------------ edge (left)
text(40, 266, "Internet", size=12, weight="600", fill=MUTED)
node(40, 280, 120, 52, "Users", ("browser",), color=INK)

text(196, 186, "Edge · global", size=12, weight="600", fill=MUTED)
node(196, 198, 210, 112, "Amazon CloudFront",
     ("HTTPS (*.cloudfront.net cert)", "HTTP → HTTPS redirect", "HSTS + security headers", "caching off (dynamic app)"), color=EDGE)
node(196, 322, 210, 86, "AWS WAF",
     ("per-IP rate limit (500 / 5 min)", "Amazon IP reputation list", "Core rule set · known bad inputs"), color=WAF)

# ------------------------------------------------------------------ request path
arrow([(160, 306), (194, 306)], INK)
text(177, 298, "HTTPS", size=10.5, fill=INK, anchor="middle", halo=True)
arrow([(301, 310), (301, 320)], INK, head=False)  # CloudFront <-> WAF attachment
arrow([(406, 262), (448, 262), (448, 376), (488, 376)], INK)
text(412, 252, "VPC origin", size=11, weight="600", fill=INK, halo=True)
text(412, 396, "AWS network", size=10.5, fill=MUTED, halo=True)

arrow([(594, 404), (594, 442)], INK)
arrow([(836, 404), (836, 442)], INK)
text(600, 424, ":8080", size=10.5, fill=INK, halo=True)
text(842, 424, ":8080", size=10.5, fill=INK, halo=True)

arrow([(594, 502), (594, 608)], DB)
arrow([(836, 502), (836, 548), (712, 548), (712, 626), (682, 626)], DB)
text(600, 540, ":5432 TLS", size=10.5, fill=DB, halo=True)
arrow([(680, 656), (744, 656)], DB, dash="4 3")
text(712, 670, "sync", size=10, fill=DB, anchor="middle", halo=True)

# ------------------------------------------------------------------ outbound (dashed)
arrow([(614, 222), (614, 144)], MUTED, dash="5 4")
text(620, 176, "outbound", size=10, fill=MUTED, halo=True)
arrow([(928, 472), (966, 472), (966, 421), (990, 421)], MUTED, dash="5 4")
arrow([(966, 472), (966, 483), (990, 483)], MUTED, dash="5 4")

# ------------------------------------------------------------------ results + security cards (left)
rect(40, 452, 366, 196, "#d5dbe3", "#fafbfc", rx=8)
text(56, 476, "Measured on AWS · 2026-11-06", size=13, weight="700")
results = [
    ("Graceful instance replacement", "100.00%"),
    ("Instance crash, no warning", "96.5% · ~18 s"),
    ("RDS Multi-AZ failover", "40 s"),
    ("XSS probe at the edge", "403 (WAF)"),
    ("ALB from the internet", "unreachable"),
    ("DB check from both AZs", "ok · TLS"),
]
y = 502
for label, value in results:
    text(56, y, label, size=12, fill=MUTED)
    text(392, y, value, size=12, weight="700", fill=OK, anchor="end")
    y += 24

rect(40, 662, 366, 138, "#d5dbe3", "#fafbfc", rx=8)
text(56, 686, "Security group chain", size=13, weight="700")
chain = [
    "CloudFront prefix list → ALB :80",
    "ALB security group → app :8080",
    "app security group → RDS :5432",
    "RDS: no outbound rules",
    "app outbound: HTTPS only (SSM, Secrets Manager)",
]
y = 710
for ln in chain:
    text(56, y, ln, size=12, fill=INK)
    y += 19

# ------------------------------------------------------------------ legend
ly = 836
arrow([(40, ly), (84, ly)], INK)
text(92, ly + 4, "request path", size=12, fill=MUTED)
arrow([(200, ly), (244, ly)], MUTED, dash="5 4")
text(252, ly + 4, "outbound only", size=12, fill=MUTED)
arrow([(370, ly), (414, ly)], DB, dash="4 3")
text(422, ly + 4, "replication", size=12, fill=MUTED)
for i, (fill, line, lab) in enumerate(((PUB_FILL, PUB_LINE, "public subnet"), (PRIV_FILL, PRIV_LINE, "private app subnet"), (DATA_FILL, DATA_LINE, "private data subnet"))):
    lx = 540 + i * 170
    rect(lx, ly - 9, 22, 16, line, fill, rx=3, sw=1.2)
    text(lx + 30, ly + 4, lab, size=12, fill=MUTED)


add("</svg>")
open(sys.argv[1], "w").write("\n".join(out))
