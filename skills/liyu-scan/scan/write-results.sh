#!/bin/bash
# 用法：write-results.sh [--preview]
# 讀 .scan-tmp/result-*.json，寫 inbox 與 scan-seen.jsonl。
# --preview：只把信寫到 .scan-tmp/preview/，不寫 inbox 和紀錄。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOME_DIR="${RUBRIC_HOME:-$HOME/talenttb/rubric}"
TMP="$HOME_DIR/.scan-tmp"
SEEN="$HOME_DIR/scan-seen.jsonl"
PREVIEW=false; [ "${1:-}" = "--preview" ] && PREVIEW=true
OUT="$HOME_DIR/inbox"; $PREVIEW && OUT="$TMP/preview"
mkdir -p "$OUT"
shopt -s nullglob
files=("$TMP"/result-*.json)
[ ${#files[@]} -gt 0 ] || { echo '{"error":"沒有 result 檔"}'; exit 1; }
jq -s '[.[].turns[]]' "${files[@]}" > "$TMP/turn-results.json"
jq -s '[.[].letters[]?]' "${files[@]}" > "$TMP/letters.json"
jq --slurpfile r "$TMP/turn-results.json" '$r[0] as $results|'"$(cat "$HERE/seen-rows.jq")" -c "$TMP/new.json" > "$TMP/rows.jsonl"
jq -s 'map(.uuid)' "$TMP/rows.jsonl" > "$TMP/ok-uuids.json"

mask() { sed -E \
  -e 's/(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{12,}/\1[已遮蔽]/g' \
  -e 's/(gh[pousr]_[A-Za-z0-9]{10})[A-Za-z0-9]*/[已遮蔽]/g' \
  -e 's/AKIA[0-9A-Z]{12,}/[已遮蔽]/g' \
  -e 's/([Bb]earer )[A-Za-z0-9._-]{12,}/\1[已遮蔽]/g' \
  -e 's/((api[_-]?key|token|secret|password|passwd|密碼)["'"'"' ]*[:=：]["'"'"' ]*)[^ ",'"'"']{4,}/\1[已遮蔽]/gI' \
  -e 's/(^|[^A-Za-z0-9])[A-Z][12][0-9]{8}($|[^A-Za-z0-9])/\1[已遮蔽]\2/g'; }

written=0; held=0
n=$(jq length "$TMP/letters.json")
for i in $(seq 0 $((n-1))); do
  [ "$n" -gt 0 ] || break
  letter="$(jq -c ".[$i]" "$TMP/letters.json")"
  ok=$(jq -n --argjson l "$letter" --slurpfile o "$TMP/ok-uuids.json" '$l.turns|all(. as $u|$o[0]|index($u)!=null)')
  if [ "$ok" != "true" ]; then held=$((held+1)); continue; fi
  jq -c --argjson l "$letter" '[.[]|select(.uuid as $u|$l.turns|index($u))]|sort_by(.ts)' "$TMP/new.json" > "$TMP/letter-turns.json"
  first_ts=$(jq -r '.[0].ts' "$TMP/letter-turns.json")
  day=$(jq -nr --arg t "$first_ts" '$t|sub("\\.[0-9]+Z$";"Z")|fromdate|strflocaltime("%Y%m%d")')
  a=$(jq -r '.[0].uuid[0:8]' "$TMP/letter-turns.json"); z=$(jq -r '.[-1].last[0:8]' "$TMP/letter-turns.json")
  h=$(jq -nr --argjson l "$letter" '$l.title//""' | md5 | cut -c1-4)
  dest="$OUT/F-$day-$a-$z-$h.md"
  project=$(jq -r '.[0]|(.cwd//"") as $c|if ($c|test("/\\.claude(/|$)")) and (($c|test("/\\.claude/worktrees/"))|not) and ($c|test("^/Users/[^/]+/\\.claude")) then (.file|split("/")|.[-2]) else ($c|sub("/\\.claude(/.*)?$";"")) end' "$TMP/letter-turns.json")
  {
    echo '---'
    echo "id: F-$day-$a-$z-$h"
    jq -r '"turns: [" + (map(.uuid)|join(", ")) + "]"' "$TMP/letter-turns.json"
    jq -r '"session: " + .[0].sid' "$TMP/letter-turns.json"
    echo "project: $project"
    jq -nr --argjson l "$letter" '"stage: " + ($l.stage//"")'
    echo "time: $first_ts"
    echo '---'
    jq -nr --argjson l "$letter" '"# \($l.title//"")\n\n## 背景\n\($l.background//"")\n\n## 背景缺\n\($l.background_missing//"無")\n\n## 最後結果\n\($l.result//"")\n\n## 為什麼拉出來\n\($l.why//"")\n\n## 原文"'
    jq -r '.[]|[.file,.uuid,.last]|@tsv' "$TMP/letter-turns.json" | while IFS=$'\t' read -r file from to; do
      echo; EXPAND_FULL=1 jq -nRr --arg from "$from" --arg to "$to" -f "$HERE/expand.jq" "$file" | grep -E '^(U|A|T|FAIL|ERROR|\[TRUNCATED)' || true
    done
  } | mask > "$dest.tmp"
  mv "$dest.tmp" "$dest"
  written=$((written+1))
done
if ! $PREVIEW; then cat "$TMP/rows.jsonl" >> "$SEEN"; fi
jq -n --argjson total "$(jq length "$TMP/new.json")" --argjson done "$(jq length "$TMP/ok-uuids.json")" \
  --argjson letters "$written" --argjson held "$held" --arg out "$OUT" --argjson preview "$PREVIEW" \
  --argjson failed "$(jq --slurpfile o "$TMP/ok-uuids.json" '[.[]|select(.uuid as $u|$o[0]|index($u)|not)|.sid]|unique' "$TMP/new.json")" \
  '{new_turns:$total,recorded:$done,letters:$letters,letters_held:$held,failed_sessions:$failed,out:$out,preview:$preview}'
