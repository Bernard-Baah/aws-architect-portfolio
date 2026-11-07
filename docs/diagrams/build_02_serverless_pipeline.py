"""Generates docs/diagrams/02-serverless-pipeline.svg (hand-laid-out architecture diagram).

Usage: python3 docs/diagrams/build_02_serverless_pipeline.py docs/diagrams/02-serverless-pipeline.svg
       rsvg-convert -w 1800 docs/diagrams/02-serverless-pipeline.svg -o docs/diagrams/02-serverless-pipeline.png
Same visual language as build_01_ha_web_app.py.
"""
import sys

W, H = 1200, 930
FONT = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

INK = "#16191f"
MUTED = "#5f6b7a"
REGION = "#7d8998"
SFN = "#e7157b"
COMPUTE = "#ed7100"
DB = "#2e5fa8"
STORAGE = "#3f8624"
INTEG = "#e7157b"
NET = "#8c4fff"
PASS = "#7d8998"
OK = "#1d8102"
FAIL = "#d13212"

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
    rect(x, y, w, h, "#c6ccd5", "#ffffff", rx=6, sw=1.2)
    add(f'<rect x="{x}" y="{y}" width="5" height="{h}" rx="2" fill="{color}"/>')
    cy = y + 20
    text(x + 14, cy, title, size=title_size, weight="600")
    for ln in lines:
        cy += 16
        text(x + 14, cy, ln, size=11.5, fill=MUTED)


def state(x, y, name, kind, color, w=160, h=40, fill="#ffffff", line="#c6ccd5"):
    """Step Functions state: name + service type, colored by type."""
    rect(x, y, w, h, line, fill, rx=6, sw=1.2)
    add(f'<rect x="{x}" y="{y}" width="5" height="{h}" rx="2" fill="{color}"/>')
    text(x + 13, y + 17, name, size=12.5, weight="600")
    text(x + 13, y + 32, kind, size=10.5, fill=MUTED)


def arrow(points, color=INK, dash=None, sw=1.8, head=True):
    pts = " ".join(f"{px},{py}" for px, py in points)
    d = f' stroke-dasharray="{dash}"' if dash else ""
    m = ' marker-end="url(#ah-%s)"' % color.strip("#") if head else ""
    add(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="{sw}"{d}{m} stroke-linejoin="round"/>')


add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}">')
add("<defs>")
for c in {INK, MUTED, DB, FAIL, INTEG}:
    cid = c.strip("#")
    add(f'<marker id="ah-{cid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
add("</defs>")
add(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')

# ------------------------------------------------------------------ title
text(40, 44, "Project 02 · Serverless event-driven pipeline", size=22, weight="700")
text(1160, 44, "github.com/Bernard-Baah/aws-architect-portfolio", size=12, fill=MUTED, anchor="end")
text(40, 68, "Every rack-inventory CSV is checked automatically. Nothing runs while idle; nothing is lost when it fails.",
     size=13.5, fill=MUTED)

# ------------------------------------------------------------------ region
rect(200, 92, 975, 750, REGION, dash="6 5", rx=10)
text(1163, 112, "AWS Region · us-east-1 · serverless", size=12.5, weight="600", fill=REGION, anchor="end")

# ------------------------------------------------------------------ ingest (left)
node(40, 138, 130, 52, "Uploader", ("aws s3 cp",), color=INK)
node(230, 130, 186, 70, "S3 bucket", ("incoming/*.csv", "TLS-only · 30-day expiry"), color=STORAGE)
arrow([(170, 164), (228, 164)], INK)
text(199, 156, "PUT", size=10.5, anchor="middle", halo=True)

node(230, 250, 186, 70, "EventBridge rule", ("Object Created, incoming/", "retry 10× · DLQ on failure"), color=NET)
arrow([(323, 200), (323, 248)], INK)
text(330, 228, "event", size=10.5, halo=True)

# ------------------------------------------------------------------ Step Functions container
rect(450, 120, 425, 600, SFN, rx=10, sw=2)
text(465, 142, "Step Functions · Standard workflow", size=12.5, weight="600", fill=SFN)

MX = 550  # main column
states_main = [
    ("Prepare", "Pass · doc_id = key#etag", PASS),
    ("Validate", "Lambda · type, size", COMPUTE),
    ("RecordReceived", "DynamoDB · conditional put", DB),
    ("Analyze", "Lambda · CSV data quality", COMPUTE),
    ("StoreResult", "DynamoDB · update", DB),
    ("Notify", "SNS · publish", INTEG),
]
ys = [160, 215, 270, 325, 380, 435]
for (name, kind, color), y in zip(states_main, ys):
    state(MX, y, name, kind, color)
state(MX, 490, "Done", "Succeed", OK, fill="#f2f8ee", line="#9bc58a")
for y in ys:
    arrow([(MX + 80, y + 40), (MX + 80, y + 53)], INK)

# start
arrow([(416, 285), (470, 285), (470, 180), (MX - 2, 180)], INK)
text(475, 300, "start", size=10.5, halo=True)

# duplicate branch
state(740, 270, "Duplicate", "Succeed · already done", OK, w=125, fill="#f2f8ee", line="#9bc58a")
arrow([(MX + 160, 290), (738, 290)], INK)

# retry note
text(MX + 168, 341, "retries: throttling 10×,", size=10.5, fill=MUTED)
text(MX + 168, 355, "each wait ≤ 30 s, jitter", size=10.5, fill=MUTED)

# catch bus on the left
for y in (235, 290, 345, 400):
    arrow([(MX, y), (535, y)], FAIL, head=False, sw=1.5)
arrow([(535, 235), (535, 565), (738, 565)], FAIL, sw=1.5)
text(527, 470, "Catch: any error", size=10.5, fill=FAIL, anchor="end", halo=True)

# failure column
state(740, 545, "MarkFailed", "DynamoDB · update", DB, w=125)
state(740, 605, "SendToDLQ", "SQS · full context", INTEG, w=125)
state(740, 665, "ProcessingFailed", "Fail", FAIL, w=125, fill="#fbeeee", line="#e2a3a3")
arrow([(802, 585), (802, 603)], FAIL)
arrow([(802, 645), (802, 663)], FAIL)

# ------------------------------------------------------------------ data + integrations
node(560, 765, 300, 58, "DynamoDB · documents", ("on-demand · GSIs by-status, by-key · PITR",), color=DB)
arrow([(650, 720), (650, 763)], DB)
text(656, 746, "put / update", size=10.5, fill=DB, halo=True)

node(900, 420, 262, 70, "SNS topic", ("completion + alarm notices", "email subscription (optional)"), color=INTEG)
arrow([(MX + 160, 455), (898, 455)], INTEG)

node(900, 595, 262, 70, "SQS dead-letter queue", ("14-day retention · encrypted", "redrive-dlq.sh replays fixed files"), color=INTEG)
arrow([(865, 625), (898, 625)], INTEG)

node(900, 705, 262, 56, "CloudWatch alarm", ("DLQ depth > 0",), color=SFN)
arrow([(1031, 665), (1031, 703)], INTEG)
arrow([(1162, 733), (1168, 733), (1168, 470), (1164, 470)], INTEG)
text(1160, 545, "alarm → notify", size=10.5, fill=INTEG, anchor="end", halo=True)

# ------------------------------------------------------------------ query API (bottom-left)
node(40, 678, 130, 52, "Ops engineer", ("curl --aws-sigv4",), color=INK)
node(230, 670, 186, 68, "API Gateway HTTP API", ("IAM auth · 10 rps throttle", "JSON access logs"), color=NET)
arrow([(170, 704), (228, 704)], INK)
text(199, 696, "SigV4", size=10.5, anchor="middle", halo=True)
node(230, 765, 186, 58, "Lambda · query API", ("read-only, public fields only",), color=COMPUTE)
arrow([(323, 738), (323, 763)], INK)
arrow([(416, 794), (558, 794)], DB)
text(487, 786, "Query (GSIs)", size=10.5, fill=DB, anchor="middle", halo=True)

# ------------------------------------------------------------------ measured results card
rect(222, 355, 212, 290, "#d5dbe3", "#fafbfc", rx=8)
text(236, 378, "Measured · 2026-11-07", size=12.5, weight="700")
results = [
    ("500-file burst", "0 lost"),
    ("Status", "500 complete"),
    ("Planted issues found", "89 / 89"),
    ("Lambda concurrency", "10 (account)"),
    ("Throttles absorbed", "13"),
    ("Latency p50 / p95", "0.33 / 0.50 s"),
    ("Cost per 1,000 files", "≈ $0.19"),
    ("Duplicate upload", "skipped"),
    ("Incident drill", "DLQ → redrive ✓"),
    ("Query API unsigned", "403"),
]
y = 403
for label, value in results:
    text(236, y, label, size=11.2, fill=MUTED)
    text(424, y, value, size=11.2, weight="700", fill=OK, anchor="end")
    y += 23.5

# ------------------------------------------------------------------ legend
ly = 880
arrow([(40, ly), (84, ly)], INK)
text(92, ly + 4, "event / request flow", size=12, fill=MUTED)
arrow([(250, ly), (294, ly)], FAIL, sw=1.5)
text(302, ly + 4, "failure path", size=12, fill=MUTED)
for i, (color, lab) in enumerate(((COMPUTE, "Lambda"), (DB, "DynamoDB"), (INTEG, "SNS / SQS"), (PASS, "Pass state"), (OK, "Succeed"))):
    lx = 430 + i * 120
    add(f'<rect x="{lx}" y="{ly - 9}" width="5" height="16" rx="2" fill="{color}"/>')
    text(lx + 12, ly + 4, lab, size=12, fill=MUTED)

add("</svg>")
open(sys.argv[1], "w").write("\n".join(out))
