#!/bin/bash
# 用法：find-turns.sh [--since 60d]
# 產出 .scan-tmp/{all.jsonl,new.json,batches.json}，只讀 transcript，不改紀錄。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOME_DIR="${RUBRIC_HOME:-$HOME/talenttb/rubric}"
PROJECTS="${RUBRIC_PROJECTS:-$HOME/.claude/projects}"
TMP="$HOME_DIR/.scan-tmp"
SEEN="$HOME_DIR/scan-seen.jsonl"
SINCE=""
if [ "${1:-}" = "--since" ]; then
  DAYS="${2%d}"
  SINCE="$(date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ)"
fi
rm -rf "$TMP"; mkdir -p "$TMP"; touch "$TMP/all.jsonl" "$SEEN"
NOW=$(date +%s); OLDEST=$NOW; COUNT=0
while IFS= read -r f; do
  m=$(stat -f %m "$f"); [ "$m" -lt "$OLDEST" ] && OLDEST=$m
  COUNT=$((COUNT+1))
  idle=false; [ $((NOW-m)) -ge "${RUBRIC_IDLE_SECONDS:-1800}" ] && idle=true
  jq -nRc --arg file "$f" --argjson idle "$idle" -f "$HERE/turns.jq" "$f" >> "$TMP/all.jsonl"
done < <(find "$PROJECTS" -maxdepth 2 -name '*.jsonl' -not -name '*.orphaned-*')
jq -R 'fromjson?' "$SEEN" > "$TMP/seen.ok"
jq -s --slurpfile seen "$TMP/seen.ok" --arg since "$SINCE" -f "$HERE/new-turns.jq" "$TMP/all.jsonl" > "$TMP/new.json"
jq --slurpfile all "$TMP/all.jsonl" -f "$HERE/batches.jq" "$TMP/new.json" > "$TMP/batches.json"
BATCHES=$(jq length "$TMP/batches.json")
for i in $(seq 0 $((BATCHES-1))); do jq ".[$i]" "$TMP/batches.json" > "$TMP/batch-$i.json"; done
WARN=""
if [ -s "$SEEN" ] && [ "$(stat -f %m "$SEEN")" -lt "$OLDEST" ]; then WARN="上次掃描早於現存最舊的 transcript，中間可能有對話已被清除"; fi
jq -n --argjson files "$COUNT" --argjson turns "$(jq length "$TMP/new.json")" --argjson batches "$BATCHES" \
  --argjson sessions "$(jq '[.[].sid]|unique|length' "$TMP/new.json")" --arg warn "$WARN" --arg since "$SINCE" \
  --arg tmp "$TMP" '{files:$files,sessions:$sessions,new_turns:$turns,batches:$batches,since:$since,warning:$warn,tmp:$tmp}'
