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

# 設定 letter、id；寫 $TMP/letter-turns.json。信裡有沒寫進紀錄的回合就回傳 1。
prep() {
  letter="$(jq -c ".[$1]" "$TMP/letters.json")"
  ok=$(jq -n --argjson l "$letter" --slurpfile o "$TMP/ok-uuids.json" '$l.turns|all(. as $u|$o[0]|index($u)!=null)')
  [ "$ok" = "true" ] || return 1
  jq -c --argjson l "$letter" '[.[]|select(.uuid as $u|$l.turns|index($u))]|sort_by(.ts)' "$TMP/new.json" > "$TMP/letter-turns.json"
  first_ts=$(jq -r '.[0].ts' "$TMP/letter-turns.json")
  day=$(jq -nr --arg t "$first_ts" '$t|sub("\\.[0-9]+Z$";"Z")|fromdate|strflocaltime("%Y%m%d")')
  a=$(jq -r '.[0].uuid[0:8]' "$TMP/letter-turns.json"); z=$(jq -r '.[-1].last[0:8]' "$TMP/letter-turns.json")
  h=$(jq -nr --argjson l "$letter" '$l.title//""' | md5 | cut -c1-4)
  id="F-$day-$a-$z-$h"
}
# 回合所在的信（這次要寫的＋inbox 已有的），不含自己：$1=回合 uuid $2=自己的 id
letters_of() { awk -F'\t' -v u="$1" -v me="$2" '$1==u && $2!=me{print $2}' "$TMP/ids.tsv" | sort -u | paste -sd, - | sed 's/,/, /g'; }
# 前文／後文：$1=prev|next。只貼使用者的話和 agent 的文字回覆。
context() {
  case "$(jq -r ".$1.state" "$TMP/letter-plan.json")" in
    ok) jq -r ".$1|[.file,.uuid,.last]|@tsv" "$TMP/letter-plan.json" | while IFS=$'\t' read -r file from to; do
          echo "回合：${from:0:8}"
          EXPAND_FULL=1 jq -nRr --arg from "$from" --arg to "$to" -f "$HERE/expand.jq" "$file" | grep -E '^(U|A|ERROR)' || true
        done ;;
    running) echo "還在進行，這次沒有貼" ;;
    edge) if [ "$1" = prev ]; then echo "無，session 開頭"; else echo "無，session 結尾"; fi ;;
    *) echo "找不到" ;;
  esac
}

n=$(jq length "$TMP/letters.json")
: > "$TMP/ids.tsv"
existing=("$HOME_DIR/inbox"/F-*.md)
if [ ${#existing[@]} -gt 0 ]; then
  awk 'FNR<=5 && /^turns: \[/{id=FILENAME; sub(/.*\//,"",id); sub(/\.md$/,"",id); s=$0; sub(/^turns: \[/,"",s); sub(/\].*$/,"",s); k=split(s,t,/, */); for(i=1;i<=k;i++) print t[i] "\t" id}' "${existing[@]}" >> "$TMP/ids.tsv"
fi
for i in $(seq 0 $((n-1))); do
  [ "$n" -gt 0 ] || break
  prep "$i" || continue
  jq -r --arg id "$id" '.[]|[.uuid,$id]|@tsv' "$TMP/letter-turns.json" >> "$TMP/ids.tsv"
done

written=0; held=0
for i in $(seq 0 $((n-1))); do
  [ "$n" -gt 0 ] || break
  if ! prep "$i"; then held=$((held+1)); continue; fi
  dest="$OUT/$id.md"
  project=$(jq -r '.[0]|(.cwd//"") as $c|if ($c|test("/\\.claude(/|$)")) and (($c|test("/\\.claude/worktrees/"))|not) and ($c|test("^/Users/[^/]+/\\.claude")) then (.file|split("/")|.[-2]) else ($c|sub("/\\.claude(/.*)?$";"")) end' "$TMP/letter-turns.json")
  # 這封信在 session 裡的位置：前一回合、後一回合、信裡回合之間略過的回合
  jq --slurpfile all "$TMP/all.jsonl" '
    .[0].file as $f
    | ($all|map(select(.file==$f))|unique_by(.uuid)|sort_by(.ts)) as $o
    | ($o|map(.uuid)) as $ids
    | map(.uuid as $u|$ids|index($u)) as $pos
    | {prev:(if $pos[0]==null then {state:"none"} elif $pos[0]==0 then {state:"edge"}
             else ($o[$pos[0]-1]|{state:"ok",uuid,last,file}) end),
       next:(if $pos[-1]==null then {state:"none"} elif $pos[-1]==(($o|length)-1) then {state:"edge"}
             else ($o[$pos[-1]+1]|if (.is_last and (.idle|not)) then {state:"running",uuid} else {state:"ok",uuid,last,file} end) end),
       segs:[range(0;length) as $i|.[$i] as $t
             |(if $i>0 and $pos[$i]!=null and $pos[$i-1]!=null and ($pos[$i]-$pos[$i-1])>1 then $ids[($pos[$i-1]+1):$pos[$i]] else [] end) as $gap
             |{file:$t.file,uuid:$t.uuid,last:$t.last,
               note:(if ($gap|length)>0 then "[略過 \($gap|length) 回合：\($gap|map(.[0:8])|join("、"))]" else "" end)}]}' \
    "$TMP/letter-turns.json" > "$TMP/letter-plan.json"
  prev_ids=$(letters_of "$(jq -r '.prev.uuid//""' "$TMP/letter-plan.json")" "$id")
  next_ids=$(letters_of "$(jq -r '.next.uuid//""' "$TMP/letter-plan.json")" "$id")
  {
    echo '---'
    echo "id: $id"
    jq -r '"turns: [" + (map(.uuid)|join(", ")) + "]"' "$TMP/letter-turns.json"
    jq -r '"session: " + .[0].sid' "$TMP/letter-turns.json"
    echo "project: $project"
    jq -nr --argjson l "$letter" '"stage: " + ($l.stage//"")'
    echo "time: $first_ts"
    echo "prev: $prev_ids"
    echo "next: $next_ids"
    echo '---'
    jq -nr --argjson l "$letter" '"# \($l.title//"")\n\n## 背景\n\($l.background//"")\n\n## 背景缺\n\($l.background_missing//"無")\n\n## 最後結果\n\($l.result//"")\n\n## 為什麼拉出來\n\($l.why//"")\n\n## 前文（只當背景）"'
    context prev
    echo; echo '## 原文'
    jq -r '.segs[]|[.file,.uuid,.last,.note]|@tsv' "$TMP/letter-plan.json" | while IFS=$'\t' read -r file from to note; do
      echo; if [ -n "$note" ]; then echo "$note"; echo; fi
      EXPAND_FULL=1 jq -nRr --arg from "$from" --arg to "$to" -f "$HERE/expand.jq" "$file" | grep -E '^(U|A|T|FAIL|ERROR|\[TRUNCATED)' || true
    done
    echo; echo '## 後文（只當背景）'
    context next
  } | mask > "$dest.tmp"
  mv "$dest.tmp" "$dest"
  written=$((written+1))
done
if ! $PREVIEW; then cat "$TMP/rows.jsonl" >> "$SEEN"; fi
jq -n --argjson total "$(jq length "$TMP/new.json")" --argjson done "$(jq length "$TMP/ok-uuids.json")" \
  --argjson letters "$written" --argjson held "$held" --arg out "$OUT" --argjson preview "$PREVIEW" \
  --argjson failed "$(jq --slurpfile o "$TMP/ok-uuids.json" '[.[]|select(.uuid as $u|$o[0]|index($u)|not)|.sid]|unique' "$TMP/new.json")" \
  '{new_turns:$total,recorded:$done,letters:$letters,letters_held:$held,failed_sessions:$failed,out:$out,preview:$preview}'
