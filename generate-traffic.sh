#!/bin/sh
# Usage: ./generate-traffic.sh [base-url] [rounds]
set -eu

base_url=${1:-http://localhost:3000}
base_url=${base_url%/}
rounds=${2:-30}
case "$rounds" in
  ''|*[!0-9]*|0) printf 'Rounds must be a positive integer.\n' >&2; exit 1 ;;
esac
command -v curl >/dev/null 2>&1 || { printf 'curl is required.\n' >&2; exit 1; }

request() {
  route=$1
  if ! code=$(curl --silent --show-error --fail --connect-timeout 5 --max-time 15 \
    --output /dev/null --write-out '%{http_code}' "$base_url/$route"); then
    printf '\nRequest failed: %s/%s (HTTP %s). Check the app port and API/database logs.\n' \
      "$base_url" "$route" "$code" >&2
    exit 1
  fi
  printf '  HTTP %s  /%s\n' "$code" "$route"
}

printf 'Checking %s/history ...\n' "$base_url"
request 'history?limit=1'
printf 'Generating traffic: %s rounds, 4 requests per round. Ctrl+C stops.\n' "$rounds"
i=1
while [ "$i" -le "$rounds" ]; do
  printf 'Round %s/%s\n' "$i" "$rounds"
  for route in number letter rock-paper-scissors 'history?limit=10'; do
    request "$route"
  done
  i=$((i + 1))
  if [ "$i" -le "$rounds" ]; then sleep 2; fi
done
printf 'Done. Refresh Grafana after 30–60 seconds to see the new samples.\n'
