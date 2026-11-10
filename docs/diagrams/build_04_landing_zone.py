"""Generates docs/diagrams/04-landing-zone.svg (hand-laid-out architecture diagram).

Usage: python3 docs/diagrams/build_04_landing_zone.py docs/diagrams/04-landing-zone.svg
       rsvg-convert -w 1800 docs/diagrams/04-landing-zone.svg -o docs/diagrams/04-landing-zone.png
Same visual language as build_01/02/03.
"""
import sys
from xml.sax.saxutils import escape

W, H = 1200, 1090
FONT = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

INK = "#16191f"
MUTED = "#5f6b7a"
ORG = "#7d8998"
OU = "#8c4fff"
SEC = "#dd344c"
LOGS = "#2e5fa8"
ID = "#1d8102"
WORK = "#ed7100"
OK = "#1d8102"
PENDING = "#b26200"

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
for c in {INK, MUTED, LOGS, SEC, ID}:
    cid = c.strip("#")
    add(f'<marker id="ah-{cid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
add("</defs>")
add(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')

# ------------------------------------------------------------------ title
text(40, 44, "Project 04 · Secure multi-account landing zone", size=22, weight="700")
text(1160, 44, "github.com/Bernard-Baah/aws-architect-portfolio", size=12, fill=MUTED, anchor="end")
text(40, 68, "One organization, guardrails at the root, and every account logged, recorded and scored from two security accounts.",
     size=13.5, fill=MUTED)

# ------------------------------------------------------------------ people
node(40, 92, 200, 56, "You · bernard.baah", ("password + MFA, no IAM keys",), color=ID)

# ------------------------------------------------------------------ organization
rect(40, 172, 1120, 598, ORG, dash="6 5", rx=10)
text(56, 194, "AWS Organization · all features · adopted with terraform import", size=14, weight="700")

# management account
rect(56, 206, 1088, 118, "#c6ccd5", "#fafbfc", rx=8)
text(72, 226, "Management account", size=13, weight="700")
text(1128, 226, "no workloads · SCPs never apply here, so nothing runs here", size=11.5, fill=MUTED, anchor="end")
MY = 238
node(72, MY, 250, 72, "Organizations", ("3 OUs · 4 member accounts", "root access centralized (no root", "passwords in members)"), color=OU)
node(338, MY, 250, 72, "IAM Identity Center", ("group lz-platform-team", "LZ-Admin (1 h) · LZ-PowerUser", "LZ-ReadOnly"), color=ID)
node(604, MY, 250, 72, "Organization CloudTrail", ("every account · every region", "log file validation", "SSE-KMS (Log Archive key)"), color=LOGS)
node(870, MY, 258, 72, "CloudWatch Logs", ("/aws/cloudtrail/org-trail", "Logs Insights across 5 accounts", "90-day retention"), color=LOGS)
arrow([(854, 274), (868, 274)], LOGS)

# SCP banner
rect(56, 336, 1088, 40, SEC, "#fdf3f4", rx=6, sw=1.5)
text(72, 361, "Root SCPs", size=13, weight="700", fill=SEC)
text(160, 361, "guardrails: can't leave the org, can't disable CloudTrail · Config · GuardDuty · Security Hub, no root user  |  "
     "region allow-list: us-east-1 + us-west-2", size=12, fill=INK)

# OUs
OY, OH = 390, 236
rect(56, OY, 560, OH, OU, rx=8, sw=2)
text(72, OY + 22, "Security OU", size=13, weight="700", fill=OU)
node(72, OY + 36, 260, 186, "Log Archive", (
    "org-cloudtrail bucket", "· Object Lock (governance)", "· SSE-KMS, own CMK", "· TLS only, writes from this trail only",
    "org-config bucket", "· Config snapshots from all accounts", "· org-only, own prefix per account"), color=LOGS)
node(344, OY + 36, 256, 186, "Audit (delegated admin)", (
    "GuardDuty: all members, 2 regions", "Security Hub CSPM", "· central configuration", "· FSBP policy on the org root",
    "· us-west-2 findings aggregated", "· into us-east-1", "Org CloudTrail logs: decrypt only"), color=SEC)

rect(632, OY, 336, OH, OU, rx=8, sw=2)
text(648, OY + 22, "Workloads OU", size=13, weight="700", fill=OU)
node(648, OY + 36, 304, 86, "dev", ("Identity Center: LZ-Admin, LZ-PowerUser", "adopted from an earlier org", "(name and email kept)"), color=WORK)
node(648, OY + 136, 304, 86, "prod", ("Identity Center: LZ-Admin, LZ-ReadOnly", "adopted from an earlier org", "(name and email kept)"), color=WORK)

rect(984, OY, 160, OH, OU, rx=8, sw=2)
text(1000, OY + 22, "Sandbox OU", size=13, weight="700", fill=OU)
text(1064, OY + 120, "(empty, for", size=12, fill=MUTED, anchor="middle")
text(1064, OY + 138, "experiments)", size=12, fill=MUTED, anchor="middle")

# baseline strip
BY = 654
rect(56, BY, 1088, 100, "#c6ccd5", "#fafbfc", rx=8)
text(72, BY + 22, "Baseline in every account × us-east-1 + us-west-2 (Terraform modules)", size=13, weight="700")
text(72, BY + 44, "AWS Config (service-linked role, daily) · GuardDuty member · Security Hub FSBP · security contact on file",
     size=12, fill=MUTED)
text(72, BY + 64, "S3 + EBS snapshot public access blocked · EBS encrypted by default · SSM documents can't be shared publicly",
     size=12, fill=MUTED)
text(72, BY + 84, "IAM password policy (NIST 800-63B) · unused default VPCs deleted (script skips any VPC in use)",
     size=12, fill=MUTED)

# ------------------------------------------------------------------ flows
# person -> Identity Center
arrow([(240, 120), (560, 120), (560, 236)], ID)
text(400, 112, "access portal", size=11, weight="600", fill=ID, anchor="middle", halo=True)
# Identity Center -> workloads: crosses the SCP banner on purpose (roles stay bound by SCPs)
arrow([(500, 310), (500, 330), (940, 330), (940, 424)], ID, dash="5 4")
text(932, 386, "LZ-* roles, still bound by SCPs", size=11, weight="600", fill=ID, anchor="end", halo=True)
# org trail -> log archive bucket
arrow([(729, 310), (729, 384), (300, 384), (300, 424)], LOGS)
text(470, 380, "logs from all 5 accounts", size=11, weight="600", fill=LOGS, anchor="middle", halo=True)
# config snapshots + findings from baseline
arrow([(140, 652), (140, 614)], LOGS)
text(148, 644, "Config snapshots", size=11, weight="600", fill=LOGS, halo=True)
arrow([(420, 652), (420, 614)], SEC)
text(428, 644, "findings", size=11, weight="600", fill=SEC, halo=True)

# ------------------------------------------------------------------ cards
CY = 794
rect(40, CY, 540, 236, "#d5dbe3", "#fafbfc", rx=8)
text(56, CY + 24, "Tested, 2026-11-07 → 11-10", size=13, weight="700")
rows = [
    ("eu-west-1 call from dev, as an account admin", "denied · SCP", OK),
    ("Stop Config in dev as Identity Center LZ-Admin", "denied · SCP", OK),
    ("Stop the org trail from dev", "denied · owned by mgmt", OK),
    ("Delete a trail log as Log Archive admin", "denied · Object Lock", OK),
    ("Accounts in one Logs Insights query", "5 / 5", OK),
    ("GuardDuty members managed from Audit", "4 / 4", OK),
    ("Config recorders delivering centrally", "10 / 10", OK),
    ("Security Hub policy associations", "9 / 9 SUCCESS", OK),
]
y = CY + 50
for label, value, color in rows:
    text(56, y, label, size=12, fill=MUTED)
    text(566, y, value, size=12, weight="700", fill=color, anchor="end")
    y += 23

rect(620, CY, 540, 236, "#d5dbe3", "#fafbfc", rx=8)
text(636, CY + 24, "Security Hub FSBP, failed checks org-wide", size=13, weight="700")
rows = [
    ("Failed checks, whole org", "236 → 152 (day 3)", OK),
    ("Critical (whole org)", "26 → 12 (day 3)", OK),
    ("SSM.7 (critical) · S3.1 · EC2.7 · SSM.6", "10 → 0 each", OK),
    
    ("Default-VPC controls (EC2.10, .55–.58, .60)", "10 → 1 each", OK),
    ("Config.1 · Account.1 · CloudTrail.5", "fixed day 2–3", OK),
    ("Inspector · Macie · extra GuardDuty plans", "deferred (paid)", PENDING),
]
y = CY + 50
for label, value, color in rows:
    text(636, y, label, size=12, fill=MUTED)
    text(1146, y, value, size=12, weight="700", fill=color, anchor="end")
    y += 23
text(636, CY + 200, "Score 92% → 87% → 88%: the first reading ran before Config's", size=11.5, fill=MUTED, italic=True)
text(636, CY + 218, "first full snapshot. Per-control and per-check counts show the real change.", size=11.5, fill=MUTED, italic=True)

# ------------------------------------------------------------------ legend
ly = 1062
arrow([(40, ly), (84, ly)], ID)
text(92, ly + 4, "sign-in / access", size=12, fill=MUTED)
arrow([(230, ly), (274, ly)], LOGS)
text(282, ly + 4, "logs + snapshots", size=12, fill=MUTED)
arrow([(420, ly), (464, ly)], SEC)
text(472, ly + 4, "findings", size=12, fill=MUTED)
for i, (color, lab) in enumerate(((OU, "organization"), (ID, "identity"), (LOGS, "logging"), (SEC, "security"), (WORK, "workloads"))):
    lx = 620 + i * 110
    add(f'<rect x="{lx}" y="{ly - 9}" width="5" height="16" rx="2" fill="{color}"/>')
    text(lx + 12, ly + 4, lab, size=12, fill=MUTED)

add("</svg>")
open(sys.argv[1], "w").write("\n".join(out))
