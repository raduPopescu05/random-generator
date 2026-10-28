#!/usr/bin/env bash
# Run from the repository root: bash k8s-local/load-test.sh [workers] [seconds] [api|mixed|history] [url]
# Compatible with macOS Bash 3.2 and WSL Bash. No Kubernetes changes are made.
set -u

usage() {
  cat <<'EOF'
Usage: bash k8s-local/load-test.sh [workers] [seconds] [api|mixed|history] [url]
Defaults: 50 workers, 120 seconds, api, http://app.localhost
Examples:
  bash k8s-local/load-test.sh 50 120
  bash k8s-local/load-test.sh 100 300
  bash k8s-local/load-test.sh 50 120 mixed
Each worker sends one request at a time without pauses. Ctrl+C stops all workers.
api: /api only, no database writes (best starting point for API CPU/HPA tests).
mixed: /number, /letter, /rock-paper-scissors, /history?limit=10 (writes history).
history: /history?limit=100 only (database read load).
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
if [ "$#" -gt 4 ]; then usage >&2; exit 2; fi
workers=${1:-50}
duration=${2:-120}
mode=${3:-api}
base_url=${4:-http://app.localhost}
base_url=${base_url%/}
for value in "$workers" "$duration"; do
  case "$value" in ''|*[!0-9]*|0*) printf 'Workers and seconds must be positive integers without leading zeros.\n' >&2; exit 2 ;; esac
  if [ "${#value}" -gt 4 ]; then printf 'Value exceeds supported limits.\n' >&2; exit 2; fi
done
if [ "$workers" -gt 200 ] || [ "$duration" -gt 1800 ]; then
  printf 'Limits: 200 workers and 1800 seconds per run.\n' >&2
  exit 2
fi
case "$mode" in api|mixed|history) ;; *) usage >&2; exit 2 ;; esac
case "$base_url" in http://*|https://*) ;; *) printf 'URL must start with http:// or https://.\n' >&2; exit 2 ;; esac
for tool in curl awk mktemp; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'Missing prerequisite: %s\n' "$tool" >&2; exit 2; }
done

printf 'Checking %s/api ...\n' "$base_url"
curl --silent --show-error --fail --connect-timeout 3 --max-time 10 --output /dev/null "$base_url/api" || exit 1
if [ "$mode" != api ]; then
  curl --silent --show-error --fail --connect-timeout 3 --max-time 10 --output /dev/null "$base_url/history?limit=1" || exit 1
fi

results=$(mktemp -d "${TMPDIR:-/tmp}/random-generator-load.XXXXXX") || exit 1
pids=()
started=$SECONDS
deadline=$((SECONDS + duration))

report() {
  local elapsed=$((SECONDS - started))
  [ "$elapsed" -gt 0 ] || elapsed=1
  awk -v elapsed="$elapsed" '
    NF == 3 {
      n++; total += $2; if ($2 > max) max=$2;
      if ($3 != 0) transport++;
      else if ($1 >= 200 && $1 < 300) ok++;
      else http++;
    }
    END {
      printf "Elapsed %ds | completed %d | %.1f req/s | 2xx %d | HTTP errors %d | network/timeouts %d | mean %.1f ms | max %.1f ms\n",
        elapsed,n,n/elapsed,ok,http,transport,n ? total*1000/n : 0,max*1000;
    }
  ' "$results"/*.log
}

worker() {
  # Each worker owns its curl child; never signal unrelated processes.
  local id=$1 request_pid='' code=0 count=0 route='' remaining=0 timeout=0
  trap 'if [ -n "$request_pid" ]; then kill "$request_pid" 2>/dev/null || :; wait "$request_pid" 2>/dev/null || :; fi; exit 0' TERM INT
  while [ "$SECONDS" -lt "$deadline" ]; do
    case "$mode" in
      api) route=api ;;
      history) route='history?limit=100' ;;
      mixed)
        case $((count % 4)) in
          0) route=number ;; 1) route=letter ;; 2) route=rock-paper-scissors ;; 3) route='history?limit=10' ;;
        esac ;;
    esac
    remaining=$((deadline - SECONDS))
    [ "$remaining" -gt 0 ] || break
    timeout=10
    [ "$remaining" -ge 10 ] || timeout=$remaining
    curl --silent --connect-timeout 3 --max-time "$timeout" \
      --output /dev/null --write-out '%{http_code} %{time_total}' \
      "$base_url/$route" > "$results/$id.current" 2>/dev/null &
    request_pid=$!
    code=0
    wait "$request_pid" || code=$?
    request_pid=''
    # One line per completed attempt: HTTP status, seconds, curl exit status.
    printf '%s %s\n' "$(cat "$results/$id.current")" "$code" >> "$results/$id.log"
    count=$((count + 1))
  done
}

cleanup() {
  trap - EXIT INT TERM
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || :; done
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || :; done
  printf '\nFinal summary (completed requests; interrupted requests excluded):\n'
  report
  rm -rf -- "$results"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Target: %s | workers: %s | duration: %ss | mode: %s\n' "$base_url" "$workers" "$duration" "$mode"
[ "$mode" != mixed ] || printf 'Mixed mode inserts database history on every successful generation request.\n'
printf 'Statistics are cumulative. Ctrl+C stops the load.\n'
for ((i=1; i<=workers; i++)); do
  : > "$results/$i.log"
  worker "$i" &
  pids+=("$!")
done
next_report=$((SECONDS + 5))
while [ "$SECONDS" -lt "$deadline" ]; do
  sleep 1
  if [ "$SECONDS" -ge "$next_report" ]; then
    report
    next_report=$((SECONDS + 5))
  fi
done
for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || :; done
# EXIT handles the final summary and temporary-file cleanup.
