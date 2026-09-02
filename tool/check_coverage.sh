#!/usr/bin/env sh
set -eu

minimum=${1:-60}
report=${2:-coverage/lcov.info}

test -s "$report"

set -- $(awk -F: '
  /^LF:/ { found += $2 }
  /^LH:/ { hit += $2 }
  END { print hit + 0, found + 0 }
' "$report")

hit=$1
found=$2
if [ "$found" -eq 0 ]; then
  echo 'Coverage report contains no executable lines.' >&2
  exit 1
fi

percent=$(awk -v hit="$hit" -v found="$found" 'BEGIN { printf "%.1f", 100 * hit / found }')
echo "Line coverage: $hit/$found ($percent%; required: $minimum%)"

awk -v hit="$hit" -v found="$found" -v minimum="$minimum" \
  'BEGIN { exit !(100 * hit / found >= minimum) }'
