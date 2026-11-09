---
name: liyu-scan
description: 從 Claude Code 的 session transcript 盡量拉出有疑慮、不順利、討論較多的對話，每段寫成一封 inbox 交給 liyu-vet。使用者打 /liyu-scan 時使用。
argument-hint: "[--focus \"重點\"] [--since 60d] [--dry-run] [--help]"
---

參數：$ARGUMENTS

scan 只把討論拉出來：不分類成規則、不判斷能否通用、不讀 `decisions.jsonl` 或標準。不問使用者問題。`~/.claude/projects` 只讀。

路徑：`RUBRIC=~/talenttb/rubric`，腳本在 `$RUBRIC/skills/liyu-scan/scan/`，用 `/bin/bash` 執行。

## --help

有 `--help` 就只印這段，然後結束：

```
/liyu-scan                            處理還沒判過的回合
/liyu-scan --focus "命名"              這次多看某個重點
/liyu-scan --since 60d --focus "命名"  判近 60 天還沒判過或判過沒拉的回合
/liyu-scan --dry-run                   只產生預覽，不寫 inbox 和紀錄
/liyu-scan --help                      顯示這段
```

## 第 1 步：找新回合

執行 `/bin/bash $RUBRIC/skills/liyu-scan/scan/find-turns.sh`，有 `--since` 就把它帶上。它回傳 JSON（files、sessions、new_turns、batches、warning）。`new_turns` 是 0 就回報「沒有新對話」，結束。

## 第 2 步：判斷

每個 `$RUBRIC/.scan-tmp/batch-N.json` 派一個 general-purpose subagent，同時最多 5 個，prompt 用下面的模板，代入 N 和 focus。派完等全部結束。

```
判斷一批對話，寫結果到 ~/talenttb/rubric/.scan-tmp/result-N.json。回傳只要回合數與信數，不要貼對話原文。

讀 ~/talenttb/rubric/scan-criteria.md，照它判；原則是盡量拉，拿不定一律拉。這次多看：<focus，沒有就寫「無」>。

~/talenttb/rubric/.scan-tmp/batch-N.json 的 sessions[] 有 sid、file、first、context、new。回合欄位：uuid、last、ts、u（使用者文字）、suggest（接受系統建議）、a（agent 最後文字的頭尾）、marks（REJECT、INT、RETRY）、fails、edits、tools、prior。context、first 只當背景，不判。

第一階段：只看摘要，對每個 new 回合判 inbox 或 skip。

第二階段：對 inbox 的回合讀原文：
jq -nRr --arg from <uuid> --arg to <last> -f ~/talenttb/rubric/skills/liyu-scan/scan/expand.jq <file>
背景在別的 session 時，用 rg 搜 ~/talenttb/rubric/.scan-tmp/all.jsonl，可以唯讀 transcript 提到的 ledger 檔。一封信只談 agent 的一個問題，同一問題的連續回合合成一封。prior 是 inbox 的回合已有舊信，只看它長大的部分；沒有新內容就回 inbox 但不列進任何一封。

寫出 JSON：
{"turns":[{"uuid":"…","outcome":"inbox","reason":""},{"uuid":"…","outcome":"skip","reason":"一句原因"}],
 "letters":[{"turns":["…"],"title":"一句話","stage":"plan|PoC|實作|研究","background":"當時在做什麼","background_missing":"拉不回來的背景，沒有就空字串","result":"最後怎麼結束","why":"為什麼拉出來；使用者說法和紀錄不符也寫在這"}]}
每個 new 回合都要出現在 turns。原文由腳本寫入，letters 不要重打原文。不得掃 home 根層或 ~/Library；只用 jq、rg。
```

## 第 3 步：寫出

- 一般：`/bin/bash $RUBRIC/skills/liyu-scan/scan/write-results.sh`
- `--dry-run`：`/bin/bash $RUBRIC/skills/liyu-scan/scan/write-results.sh --preview`，再讀每批 result 的 skip 原因，一起列出。

腳本只寫完整的 session；缺回合的 session 不寫信也不寫紀錄，下次重來。

## 回報

一句摘要：幾個回合、幾封信、哪些 session 下次重來、warning（有的話）。不要 commit。
