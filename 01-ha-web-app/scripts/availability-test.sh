#!/usr/bin/env bash
# Hit the app twice a second and report availability while you break things.
#
#   ./scripts/availability-test.sh [URL] [SECONDS]
#
# URL defaults to `terraform output -raw app_url`; SECONDS defaults to 180.
# Run it in one terminal, then terminate an instance (or fail over the DB) in
# another. Works with macOS's bash 3.2.

set -u

URL="${1:-$(terraform output -raw app_url 2>/dev/null)}"
DURATION="${2:-180}"
INTERVAL=0.5

if [ -z "$URL" ]; then
  echo "usage: $0 URL [SECONDS]   (or run from the stack folder so terraform output works)" >&2
  exit 2
fi

LOG=$(mktemp -t availability.XXXXXX)
END=$(($(date +%s) + DURATION))
echo "Probing $URL/health for ${DURATION}s. Ctrl-C to stop early. Raw log: $LOG"

trap 'END=0' INT
last=200

while [ "$(date +%s)" -lt "$END" ]; do
  now=$(date +%s)
  out=$(curl -s -m 2 -w ' %{http_code}' "$URL/health" 2>/dev/null)
  code=${out##* }
  [ -z "$code" ] && code=000
  instance=$(printf '%s' "$out" | sed -n 's/.*"instance": *"\([^"]*\)".*/\1/p')
  az=$(printf '%s' "$out" | sed -n 's/.*"az": *"\([^"]*\)".*/\1/p')
  echo "$now $code ${instance:--} ${az:--}" >> "$LOG"

  if [ "$code" = "200" ]; then
    [ "$last" != "200" ] && printf '\n'
    printf '.'
  else
    [ "$last" = "200" ] && printf '\n'
    printf '%s  %s\n' "$(date '+%H:%M:%S')" "$code"
  fi
  last=$code
  sleep "$INTERVAL"
done

echo
awk '
  { total++; codes[$2]++
    if ($2 == "200") { ok++; seen[$3 " (" $4 ")"]++; if (run) { if (run_len > worst) { worst = run_len; worst_start = run_start }; run = 0 } }
    else { if (!run) { run = 1; run_start = $1; run_len = 0 }; run_len = $1 - run_start + 1 }
  }
  END {
    if (run && run_len > worst) { worst = run_len; worst_start = run_start }
    printf "\nRequests: %d   OK: %d   Availability: %.2f%%\n", total, ok, (total ? 100 * ok / total : 0)
    printf "Status codes:"; for (c in codes) printf "  %s x%d", c, codes[c]; printf "\n"
    printf "Longest failure window: %ds\n", worst
    printf "Instances that served traffic:\n"; for (i in seen) printf "  %-32s %d\n", i, seen[i]
  }' "$LOG"
