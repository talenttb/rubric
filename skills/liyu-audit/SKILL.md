---
name: liyu-audit
description: 拿還沒 commit 的 diff 或一份計畫，對照 ledger 定案與 rubric 的審核規則，回報 fix／ask。使用者打 /liyu-audit，或 agent 被指示用 liyu-audit 審查時使用。
argument-hint: "[--help]"
---

參數：$ARGUMENTS

審核規則：`~/talenttb/rubric/criteria/INDEX.md`（索引）＋ `~/talenttb/rubric/criteria/<短 uuid>.md`（一條一檔）。

只讀三樣：要審的東西、ledger、上面的 `criteria/`。不改任何檔、不改規則、不讀 transcript、不得掃 home 根層或 ~/Library。

## --help
有 `--help` 就只印這段，然後結束：
```
/liyu-audit         審目前專案還沒 commit 的 diff
/liyu-audit --help  顯示這段

結果分兩種：
  fix  在範圍內、確定違反規則，直接修
  ask  超出 ledger 範圍，或判斷不了，先問使用者
```

## 你是誰
- 使用者直接打 `/liyu-audit`：你是主 session，不自己審。派一個 subagent，prompt 寫清楚：
  - 用 Skill 工具呼叫 liyu-audit，照「審」那段做。
  - 要審的是目前專案還沒 commit 的改動（`git diff HEAD`，加上 `git status --short` 列出的新檔）。
  - 這個對話有在用的 ledger 就附絕對路徑，沒有就寫「沒有 ledger」。
  - 不得掃 home 根層或 ~/Library。
  subagent 回來後把結果原樣轉給使用者，不自己修。
- 你是被派來審的 agent：派工 prompt 會給要審的東西、有沒有 ledger、模式。直接做「審」。

## 審
輸入：要審的東西（計畫或 diff）、ledger 路徑（可能沒有）、模式（`scope` 只做 A；沒指定就 A、B 都做）。

### A 範圍檢查
1. 沒有 ledger：不做，在回傳註明，直接到 B。
2. 讀 ledger 的「定案」段。「待定案」段的內容不算使用者的決定。
3. 把要審的東西拆成一項一項改動。
4. 每一項找對應的定案編號。對不到的列進 ask：哪一項、為什麼對不到、建議怎麼處理。

### B 規則檢查
1. 讀 INDEX。哪一行的適用情境對得上這次要審的東西，就打開那個規則檔；拿不定就打開。
2. 照規則檔的「怎麼抓」判。
3. 違反的列進 fix。規則寫明判斷不了、或手上的資料不夠判，列進 ask。
4. 同一處已經在 A 列過 ask 的，不重複列，在那一項補上規則 id。

### 回傳
派工方有給 schema 就照 schema。沒有就印：
```
範圍檢查：有做／沒有 ledger，沒做
開了哪幾條規則：<規則 id，…>
fix：
- <規則 id>｜<檔案:行 或 計畫的哪一項>｜<理由>｜<建議>
ask：
- <scope 或 規則 id>｜<位置>｜<理由>｜<建議>
```
每一項要指到具體位置。沒有發現就回空的，不湊數。
