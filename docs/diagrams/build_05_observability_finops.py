"""Generates docs/diagrams/05-observability-finops.svg (hand-laid-out architecture diagram).

Usage: python3 docs/diagrams/build_05_observability_finops.py docs/diagrams/05-observability-finops.svg
       rsvg-convert -w 1800 docs/diagrams/05-observability-finops.svg -o docs/diagrams/05-observability-finops.png
Same visual language as build_01..04.
"""
import sys
from xml.sax.saxutils import escape

W, H = 1200, 1060
FONT = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

INK = "#16191f"
MUTED = "#5f6b7a"
ORG = "#7d8998"
WORK = "#ed7100"
OBS = "#e7157b"
SEC = "#dd344c"
COST = "#1d8102"
LOGS = "#2e5fa8"
OK = "#1d8102"
WARN = "#b26200"

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


def node(x, y, w, h, title, lines=(), color=WORK, title_size=13):
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
for c in {INK, MUTED, LOGS, SEC, OBS, COST, WORK}:
    cid = c.strip("#")
    add(f'<marker id="ah-{cid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
add("</defs>")
add(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')

# ------------------------------------------------------------------ title
text(40, 44, "Project 05 · Observability & FinOps", size=22, weight="700")
text(1160, 44, "github.com/Bernard-Baah/aws-architect-portfolio", size=12, fill=MUTED, anchor="end")
text(40, 68, "Project 02 runs in the landing zone's dev account, watched by SLOs that page once, seen from Audit, and costed from live prices.",
     size=13.5, fill=MUTED)

# ------------------------------------------------------------------ dev account
DX, DY, DW, DH = 40, 90, 780, 470
rect(DX, DY, DW, DH, WORK, dash="6 5", rx=10)
text(DX + 16, DY + 22, "dev account (Workloads OU) · same Terraform as Project 02, own workspace", size=14, weight="700")

# pipeline row
PY = DY + 40
node(DX + 16, PY, 120, 56, "S3 uploads", ("incoming/*.csv",), color=WORK)
node(DX + 156, PY, 120, 56, "EventBridge", ("Object Created",), color=WORK)
node(DX + 296, PY, 170, 56, "Step Functions", ("validate → analyze → store",), color=WORK)
node(DX + 486, PY, 130, 56, "DynamoDB", ("results + status",), color=WORK)
node(DX + 636, PY, 128, 56, "SQS DLQ", ("every failure", "lands here"), color=WORK)
for x1, x2 in ((DX + 136, DX + 156), (DX + 276, DX + 296), (DX + 466, DX + 486), (DX + 616, DX + 636)):
    arrow([(x1, PY + 28), (x2 - 2, PY + 28)], INK)
node(DX + 296, PY + 72, 170, 44, "Lambda ×3 (arm64)", ("validate · analyze · api · X-Ray",), color=WORK)
node(DX + 486, PY + 72, 130, 44, "API Gateway", ("SigV4, /documents",), color=WORK)

# observability row
OY = PY + 140
rect(DX + 16, OY, DW - 32, 280, OBS, "#fdf5f9", rx=8)
text(DX + 32, OY + 22, "Observability (05-observability-finops/workload)", size=13, weight="700", fill=OBS)
node(DX + 32, OY + 36, 230, 116, "SLOs → child alarms", (
    "API ≥ 99.9% non-5xx", "API p95 < 1 s", "upload → result p95 < 60 s",
    "system Lambda errors · timeouts", "(no actions on children)"), color=OBS)
node(DX + 278, OY + 36, 230, 116, "Composite alarm", (
    "inventory-pipeline-unhealthy", "= OR of the 5 children", "the only thing that pages",
    "one incident → one email", "links runbook section"), color=SEC)
node(DX + 524, OY + 36, 224, 116, "SNS → email", (
    "ALARM and OK", "runbook in docs/runbooks/", "pipeline-unhealthy.md"), color=SEC)
arrow([(DX + 262, OY + 94), (DX + 276, OY + 94)], OBS)
arrow([(DX + 508, OY + 94), (DX + 522, OY + 94)], SEC)

node(DX + 32, OY + 166, 230, 98, "Bad input ≠ incident", (
    "rejected files → FAILED + DLQ", "metric filter counts only", "validate errors that are NOT", "ValidationError"), color=WARN)
node(DX + 278, OY + 166, 230, 98, "Dashboard", (
    "inventory-pipeline-slo", "SLO numbers, p50/p95/p99", "succeeded / rejected / stuck", "DLQ depth = information"), color=OBS)
node(DX + 524, OY + 166, 224, 98, "Logs Insights (saved)", (
    "lambda-errors · slowest", "cold-starts · api-non-2xx", "failed-executions"), color=LOGS)

# ------------------------------------------------------------------ audit account
AX, AY, AW, AH = 850, 90, 310, 210
rect(AX, AY, AW, AH, SEC, dash="6 5", rx=10)
text(AX + 16, AY + 22, "Audit account (monitoring)", size=14, weight="700")
node(AX + 16, AY + 36, 278, 70, "CloudWatch OAM sink", (
    "accepts links from this org only", "metrics · log groups · X-Ray traces"), color=LOGS)
node(AX + 16, AY + 120, 278, 74, "Read-only investigation", (
    "dev's 20 Step Functions metrics", "listed from Audit, next to its own;", "nobody signs into dev"), color=SEC)
arrow([(DX + DW - 70, DY + 150), (AX - 2, DY + 150)], LOGS, dash="5 4")
text(DX + DW - 8, DY + 172, "OAM link →", size=11, weight="600", fill=LOGS, anchor="end", halo=True)

# ------------------------------------------------------------------ management account (FinOps)
MX, MY, MW, MH = 850, 320, 310, 240
rect(MX, MY, MW, MH, COST, dash="6 5", rx=10)
text(MX + 16, MY + 22, "Management account (billing)", size=14, weight="700")
node(MX + 16, MY + 36, 278, 58, "Cost allocation tags", ("Project · Owner · ManagedBy", "active org-wide"), color=COST)
node(MX + 16, MY + 104, 278, 58, "Budgets", ("org $25/mo: forecast 50/80/100%", "dev + prod $10/mo"), color=COST)
node(MX + 16, MY + 172, 278, 54, "Cost Anomaly Detection", ("all 5 accounts · daily email ≥ $5",), color=COST)

# ------------------------------------------------------------------ cards
CY = 590
rect(40, CY, 540, 400, "#d5dbe3", "#fafbfc", rx=8)
text(56, CY + 24, "Game day: bad IAM change (2026-11-11)", size=13, weight="700")
rows = [
    ("12:57:58", "analyze loses s3:GetObject; valid file uploaded", INK),
    ("12:59:55", "composite pages: ~2 min to detect", OK),
    ("~13:10", "saved query shows AccessDenied", INK),
    ("13:14:55", "OK email, while still broken (!)", WARN),
    ("~13:20", "terraform plan finds drift, apply fixes", INK),
    ("~13:23", "DLQ redrive replays the failed upload", INK),
    ("13:29", "file COMPLETE: no data lost", OK),
]
y = CY + 52
for t, label, color in rows:
    text(56, y, t, size=12, weight="700", fill=color)
    text(140, y, label, size=12, fill=MUTED)
    y += 24
text(56, CY + 238, "Lessons", size=12.5, weight="700")
lessons = [
    "• \"Alarm OK\" ≠ recovered on a quiet pipeline: the error window",
    "   went quiet 8 min before the fix. Prove recovery with a run.",
    "• Day one: the DLQ alarm paged on a rejected sample file, so it",
    "   became information and a metric filter took its place.",
    "• DLQ dry run over-counted (visibility 0 repeats messages):",
    "   now de-duplicated by MessageId.",
]
y = CY + 260
for ln in lessons:
    text(56, y, ln, size=11.5, fill=MUTED)
    y += 19

rect(620, CY, 540, 400, "#d5dbe3", "#fafbfc", rx=8)
text(636, CY + 24, "Cost case study: Project 01, live Price List API", size=13, weight="700")
rows = [
    ("Production pattern left on in dev", "$134.17/mo", INK),
    ("Graviton (t3 → t4g)", "−$2.92", OK),
    ("One shared NAT (not per AZ)", "−$36.50", OK),
    ("RDS Single-AZ in dev", "−$13.98", OK),
    ("Office hours (12 h × weekdays)", "−$15.39", OK),
    ("Dev-sized total", "$65.38/mo (−51%)", OK),
]
y = CY + 52
for label, value, color in rows:
    text(636, y, label, size=12, fill=MUTED)
    text(1146, y, value, size=12, weight="700", fill=color, anchor="end")
    y += 24
text(636, CY + 210, "Checked against the real bill (Cost Explorer)", size=12.5, weight="700")
rows = [
    ("NAT gateway hour", "$0.0450 = list", OK),
    ("ALB hour", "$0.0225 = list", OK),
    ("t4g.micro hour", "$0.0084 = list", OK),
    ("db.t4g.micro Multi-AZ / Single-AZ", "$0.0320 / $0.0160 = list", OK),
    ("Public IPv4 hour", "$0.0050 = list", OK),
]
y = CY + 236
for label, value, color in rows:
    text(636, y, label, size=12, fill=MUTED)
    text(1146, y, value, size=12, weight="700", fill=color, anchor="end")
    y += 22
text(636, CY + 362, "NAT ($36) and ALB ($16) can't be scheduled: for an idle dev", size=11.5, fill=MUTED, italic=True)
text(636, CY + 380, "account, destroy between sessions. Projects 01–03 cost ~$1.36.", size=11.5, fill=MUTED, italic=True)

# ------------------------------------------------------------------ legend
ly = 1032
arrow([(40, ly), (84, ly)], INK)
text(92, ly + 4, "pipeline flow", size=12, fill=MUTED)
arrow([(220, ly), (264, ly)], LOGS, dash="5 4")
text(272, ly + 4, "telemetry shared", size=12, fill=MUTED)
for i, (color, lab) in enumerate(((WORK, "workload"), (OBS, "observability"), (SEC, "paging / security"), (LOGS, "logs + telemetry"), (COST, "cost"))):
    lx = 450 + i * 145
    add(f'<rect x="{lx}" y="{ly - 9}" width="5" height="16" rx="2" fill="{color}"/>')
    text(lx + 12, ly + 4, lab, size=12, fill=MUTED)

add("</svg>")
open(sys.argv[1], "w").write("\n".join(out))
