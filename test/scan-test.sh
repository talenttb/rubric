#!/bin/bash
# scan 流程測試：用合成 transcript 與假判斷跑腳本，不碰真實資料。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"; S="$ROOT/skills/liyu-scan/scan"
T="$(mktemp -d)"; export RUBRIC_HOME="$T/home" RUBRIC_PROJECTS="$T/projects"; mkdir -p "$RUBRIC_HOME/inbox" "$RUBRIC_PROJECTS/p"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
u(){ printf '{"type":"user","origin":{"kind":"human"},"uuid":"%s","sessionId":"%s","timestamp":"%s","cwd":"/work/app/.claude/worktrees/x","message":{"content":"%s"}}\n' "$1" "$2" "$3" "$4"; }
a(){ printf '{"type":"assistant","uuid":"%s","sessionId":"%s","timestamp":"%s","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" "$2" "$3" "$4"; }
idle(){ export RUBRIC_IDLE_SECONDS="$1"; }
scan(){ /bin/bash "$S/find-turns.sh" "$@" >/dev/null; jq -c '[.[].uuid]' "$RUBRIC_HOME/.scan-tmp/new.json"; }
judge(){ jq '{turns:[.[]|{uuid,outcome:(if (.u|test("不對")) then "inbox" else "skip" end),reason:""}],letters:[.[]|select(.u|test("不對"))|{turns:[.uuid],title:"t",stage:"實作",background:"b",background_missing:"",result:"r",why:"w"}]}' "$RUBRIC_HOME/.scan-tmp/new.json" > "$RUBRIC_HOME/.scan-tmp/result-0.json"; }
write(){ /bin/bash "$S/write-results.sh" "$@" >/dev/null; }
inbox(){ find "$RUBRIC_HOME/inbox" -name '*.md' | wc -l | tr -d ' '; }
F="$RUBRIC_PROJECTS/p/s1.jsonl"
{ u t1 s1 2026-10-01T00:00:00.000Z 新需求; a a1 s1 2026-10-01T00:01:00.000Z ok; u t2 s1 2026-10-01T00:02:00.000Z 不對，改掉; a a2 s1 2026-10-01T00:03:00.000Z 好; u t3 s1 2026-10-01T00:04:00.000Z 進行中; } > "$F"
idle 99999
chk "進行中：最後一回合不處理" "$(scan)" '["t1","t2"]'
judge; write
chk "寫一封 inbox" "$(inbox)" 1
chk "紀錄兩行" "$(wc -l < "$RUBRIC_HOME/scan-seen.jsonl" | tr -d ' ')" 2
L="$(find "$RUBRIC_HOME/inbox" -name '*.md' | head -1)"
chk "信含使用者原文" "$(grep -c '^U: 不對，改掉' "$L")" 1
chk "信含 agent 原文" "$(grep -c '^A: 好' "$L")" 1
chk "project 去掉 worktree" "$(grep -c '^project: /work/app$' "$L")" 1
chk "再跑沒有新回合" "$(scan)" '[]'
idle 0
chk "閒置：處理最後一回合" "$(scan)" '["t3"]'
judge; write
idle 99999
{ a a3 s1 2026-10-11T00:00:00.000Z 十天後; u t4 s1 2026-10-11T00:01:00.000Z 不對，第二段; a a4 s1 2026-10-11T00:02:00.000Z 好; u t5 s1 2026-10-11T00:03:00.000Z 還在跑; } >> "$F"
chk "十天後：t3 長大、t4 新、t5 進行中" "$(scan)" '["t3","t4"]'
judge; write
chk "第二封" "$(inbox)" 2
{ cat "$F"; a a2b s1 2026-10-01T00:03:30.000Z 長大; } > "$F.new"; mv "$F.new" "$F"
chk "已有信的回合長大" "$(scan)" '["t2"]'
judge; write
chk "長大的信是新檔，舊信不動" "$(inbox)" 3
chk "長大後紀錄仍是 inbox" "$(jq -Rr 'fromjson?|select(.uuid=="t2")|.outcome' "$RUBRIC_HOME/scan-seen.jsonl" | tail -1)" inbox
{ u t1 s2 2026-10-01T00:00:00.000Z 新需求; u x1 s2 2026-10-20T00:00:00.000Z fork後; u x2 s2 2026-10-20T00:01:00.000Z 下一則; } > "$RUBRIC_PROJECTS/p/s2.jsonl"
chk "fork：複製的回合不重判" "$(scan)" '["x1"]'
judge; write
{ u c1 s3 2026-10-21T00:00:00.000Z 不對，當掉; u c2 s3 2026-10-21T00:01:00.000Z 下一則; } > "$RUBRIC_PROJECTS/p/s3.jsonl"
scan >/dev/null; judge; write; B="$(inbox)"
head -n -1 "$RUBRIC_HOME/scan-seen.jsonl" 2>/dev/null > "$T/x" || sed '$d' "$RUBRIC_HOME/scan-seen.jsonl" > "$T/x"; cp "$T/x" "$RUBRIC_HOME/scan-seen.jsonl"
chk "寫完信就當掉：回合重來" "$(scan)" '["c1"]'
judge; write
chk "重跑同一封不多檔" "$(inbox)" "$B"
{ u f1 s4 2026-10-22T00:00:00.000Z 不對，批次失敗; u f2 s4 2026-10-22T00:00:30.000Z 不對，也是; u f3 s4 2026-10-22T00:01:00.000Z 下一則; } > "$RUBRIC_PROJECTS/p/s4.jsonl"
scan >/dev/null; judge; B="$(inbox)"
jq 'del(.turns[0])' "$RUBRIC_HOME/.scan-tmp/result-0.json" > "$T/r"; cp "$T/r" "$RUBRIC_HOME/.scan-tmp/result-0.json"; write
chk "少一個回合：整個 session 不寫信" "$(inbox)" "$B"
chk "少一個回合：下次重來" "$(scan)" '["f1","f2"]'
judge; write
printf '{"uuid":"trunc' >> "$RUBRIC_HOME/scan-seen.jsonl"
chk "紀錄截斷不當掉" "$(scan)" '[]'
printf '\n' >> "$RUBRIC_HOME/scan-seen.jsonl"
{ u z1 s5 2026-10-23T00:00:00.000Z 不對，預覽; u z2 s5 2026-10-23T00:01:00.000Z 下一則; } > "$RUBRIC_PROJECTS/p/s5.jsonl"
scan >/dev/null; judge; B="$(inbox)"; Lines="$(wc -l < "$RUBRIC_HOME/scan-seen.jsonl")"; write --preview
chk "預覽：inbox 不變" "$(inbox)" "$B"
chk "預覽：紀錄不變" "$(wc -l < "$RUBRIC_HOME/scan-seen.jsonl")" "$Lines"
chk "預覽：有預覽檔" "$(find "$RUBRIC_HOME/.scan-tmp/preview" -name '*.md' | wc -l | tr -d ' ')" 1
judge; write
{ u k1 s6 2026-10-24T00:00:00.000Z 'api_key=abcd1234secret sk-abcdefghijklmnopqrstuvwxyz 不對'; u k2 s6 2026-10-24T00:01:00.000Z 下一則; } > "$RUBRIC_PROJECTS/p/s6.jsonl"
scan >/dev/null; judge; write
K="$(grep -l 'k1' "$RUBRIC_HOME"/inbox/*.md | head -1)"
chk "遮蔽 key" "$(grep -cE 'abcd1234secret|abcdefghijklmnop' "$K")" 0
/bin/bash "$S/find-turns.sh" --since 60d >/dev/null
chk "--since：inbox 的不重判，skip 的重判" "$(jq -c '[.[].uuid]|contains(["t1"]) and (contains(["t2"])|not)' "$RUBRIC_HOME/.scan-tmp/new.json")" true
{ u q1 s7 2026-10-25T00:00:00.000Z 不對，一; printf '{"type":"attachment","attachment":{"type":"queued_command","origin":{"kind":"human"},"prompt":"不對，插話"},"uuid":"q2","sessionId":"s7","timestamp":"2026-10-25T00:01:00.000Z"}\n'; u q3 s7 2026-10-25T00:02:00.000Z 下一則; } > "$RUBRIC_PROJECTS/p/s7.jsonl"
scan >/dev/null; jq '{turns:[.[]|{uuid,outcome:"inbox",reason:""}],letters:[{turns:["q2"],title:"甲",stage:"",background:"",background_missing:"",result:"",why:""},{turns:["q2"],title:"乙",stage:"",background:"",background_missing:"",result:"",why:""}]}' "$RUBRIC_HOME/.scan-tmp/new.json" > "$RUBRIC_HOME/.scan-tmp/result-0.json"; write
chk "同回合兩封都留" "$(grep -l q2 "$RUBRIC_HOME"/inbox/*.md | wc -l | tr -d " ")" 2
chk "插話回合展開原文" "$(grep -l q2 "$RUBRIC_HOME"/inbox/*.md | head -1 | xargs grep -c "^U: 不對，插話")" 1
L2K="$(printf 'x%.0s' $(seq 1 2500))"; L40K="$(printf 'y%.0s' $(seq 1 40000))"
{ u m1 s8 2026-10-26T00:00:00.000Z "不對 ${L2K}尾巴 task-notification-abcdefghijkl risk-assessment-framework A123456789 身分"; a m2 s8 2026-10-26T00:00:30.000Z "${L40K}回覆尾巴"; u m3 s8 2026-10-26T00:01:00.000Z 下一則; } > "$RUBRIC_PROJECTS/p/s8.jsonl"
scan >/dev/null; judge; write
M="$(grep -l 'm1' "$RUBRIC_HOME"/inbox/*.md | head -1)"
chk "長訊息完整留在信裡" "$(grep -c '尾巴 task-notification' "$M")" 1
chk "超長回覆不截斷" "$(grep -c '回覆尾巴$' "$M")" 1
chk "信沒有截斷標記" "$(grep -c '^\[TRUNCATED' "$M")" 0
chk "task- 不被遮蔽" "$(grep -c 'task-notification-abcdefghijkl' "$M")" 1
chk "risk- 不被遮蔽" "$(grep -c 'risk-assessment-framework' "$M")" 1
chk "身分證遮蔽" "$(grep -c 'A123456789' "$M")" 0
chk "判斷用的展開仍有上限" "$(jq -nRr --arg from m1 --arg to m2 -f "$S/expand.jq" "$RUBRIC_PROJECTS/p/s8.jsonl" | grep -c '回覆尾巴')" 0
{ u n1 s9 2026-10-27T00:00:00.000Z 不對，通知; printf '{"type":"attachment","attachment":{"type":"queued_command","origin":{"kind":"task-notification"},"prompt":"<task-notification>系統通知</task-notification>"},"uuid":"n2","sessionId":"s9","timestamp":"2026-10-27T00:00:30.000Z"}\n'; a n3 s9 2026-10-27T00:00:40.000Z 好; u n4 s9 2026-10-27T00:01:00.000Z 下一則; } > "$RUBRIC_PROJECTS/p/s9.jsonl"
scan >/dev/null; judge; write
N="$(grep -l 'n1' "$RUBRIC_HOME"/inbox/*.md | head -1)"
chk "系統通知不當成使用者原文" "$(grep -c '^U: <task-notification' "$N")" 0
chk "通知所在回合的使用者原文還在" "$(grep -c '^U: 不對，通知' "$N")" 1
sec(){ awk -v h="$2" 'index($0,"## ")==1{p=($0==h)} p' "$1"; }
PRE='## 前文（只當背景）'; POST='## 後文（只當背景）'; IN="$RUBRIC_HOME/inbox"
chk "前文貼前一回合" "$(sec "$L" "$PRE" | grep -c '^U: 新需求')" 1
chk "後一回合還在進行：不貼" "$(sec "$L" "$POST" | grep -c '^還在進行')" 1
chk "信在 session 開頭：前文寫無" "$(sec "$(grep -l '^turns: \[c1\]' "$IN"/*.md | head -1)" "$PRE" | grep -c '^無，session 開頭')" 1
G="$RUBRIC_PROJECTS/p/s10.jsonl"
{ u g1 s10 2026-10-28T00:00:00.000Z 新需求甲
  printf '{"type":"assistant","uuid":"gt","sessionId":"s10","timestamp":"2026-10-28T00:00:30.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}\n'
  a ga1 s10 2026-10-28T00:01:00.000Z ok; u g2 s10 2026-10-28T00:02:00.000Z 不對，一; a ga2 s10 2026-10-28T00:03:00.000Z 好
  u g3 s10 2026-10-28T00:04:00.000Z 中間確認; a ga3 s10 2026-10-28T00:05:00.000Z ok; u g4 s10 2026-10-28T00:06:00.000Z 不對，二; a ga4 s10 2026-10-28T00:07:00.000Z 好
  u g5 s10 2026-10-28T00:08:00.000Z 收尾; a ga5 s10 2026-10-28T00:09:00.000Z 完成; u g6 s10 2026-10-28T00:10:00.000Z 不對，進行中; } > "$G"
scan >/dev/null
jq '{turns:[.[]|{uuid,outcome:(if (.u|test("不對|收尾")) then "inbox" else "skip" end),reason:""}],letters:[{turns:["g2","g4"],title:"跳號信",stage:"",background:"",background_missing:"",result:"",why:""},{turns:["g5"],title:"收尾信",stage:"",background:"",background_missing:"",result:"",why:""}]}' "$RUBRIC_HOME/.scan-tmp/new.json" > "$RUBRIC_HOME/.scan-tmp/result-0.json"; write
GA="$(grep -l '^# 跳號信' "$IN"/*.md | head -1)"; GB="$(grep -l '^# 收尾信' "$IN"/*.md | head -1)"
chk "前文：被 skip 的前一回合也貼" "$(sec "$GA" "$PRE" | grep -c '^U: 新需求甲')" 1
chk "前文不貼工具呼叫" "$(sec "$GA" "$PRE" | grep -c '^T: ')" 0
chk "略過標記" "$(grep -c '^\[略過 1 回合：g3\]$' "$GA")" 1
chk "略過的回合不貼原文" "$(grep -c '中間確認' "$GA")" 0
chk "後文貼後一回合" "$(sec "$GA" "$POST" | grep -c '^U: 收尾')" 1
chk "next 指向這次寫的下一封" "$(grep -c "^next: $(basename "$GB" .md)$" "$GA")" 1
chk "prev 指向這次寫的上一封" "$(grep -c "^prev: $(basename "$GA" .md)$" "$GB")" 1
chk "還在進行的後一回合內容不進信" "$(grep -c '不對，進行中' "$GB")" 0
u g7 s10 2026-10-28T00:11:00.000Z 下一則 >> "$G"
scan >/dev/null; judge; write
chk "prev 指向 inbox 已有的信" "$(grep -c "^prev: $(basename "$GB" .md)$" "$(grep -l '^turns: \[g6\]' "$IN"/*.md | head -1)")" 1
chk "舊信不改" "$(grep -c '^next: $' "$GB")" 1
{ u h1 s11 2026-10-29T00:00:00.000Z 不對，唯一; a h2 s11 2026-10-29T00:01:00.000Z 好; } > "$RUBRIC_PROJECTS/p/s11.jsonl"
idle 0; scan >/dev/null; judge; write; idle 99999
H="$(grep -l '^turns: \[h1\]' "$IN"/*.md | head -1)"
chk "單回合 session：前文寫無" "$(sec "$H" "$PRE" | grep -c '^無，session 開頭')" 1
chk "信在 session 結尾：後文寫無" "$(sec "$H" "$POST" | grep -c '^無，session 結尾')" 1
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
