# rubric

從 Claude Code 的對話裡找出 agent 做錯的地方，整理成審核規則，之後拿來審 diff 和計畫。

## 流程

```
/liyu-scan  →  inbox/  →  /liyu-vet  →  criteria/  →  /liyu-audit
```

1. `/liyu-scan`：讀 `~/.claude/projects` 的 session transcript，把有疑慮、不順利、討論較多的對話各寫成一封信，放進 `inbox/`。
2. `/liyu-vet`：分批看 inbox。沒有要判斷的信直接刪；有的攤開討論，更新審核規則或 scan 判準後刪信。
3. `/liyu-audit`：拿還沒 commit 的 diff 或一份計畫，對照 ledger 定案和 `criteria/`，回報 fix／ask。

## 目錄

| 路徑 | 內容 |
|---|---|
| `scan-criteria.md` | scan 判準：哪些對話要拉、哪些不拉 |
| `criteria/INDEX.md` | 審核規則索引，一條一行 |
| `criteria/<短 uuid>.md` | 審核規則，一條一檔 |
| `skills/liyu-scan/` | scan 的 skill 和腳本 |
| `skills/liyu-vet/` | vet 的 skill |
| `skills/liyu-audit/` | audit 的 skill |
| `test/scan-test.sh` | scan 腳本的流程測試，用合成資料，不碰真實 transcript |
| `inbox/` | 待處理的信，不進版控 |

## 安裝

在 repo 裡執行，三個 skill 各建一個 symlink：

```
ROOT="$(git rev-parse --show-toplevel)"
ln -s "$ROOT/skills/liyu-scan"  ~/.claude/skills/liyu-scan
ln -s "$ROOT/skills/liyu-vet"   ~/.claude/skills/liyu-vet
ln -s "$ROOT/skills/liyu-audit" ~/.claude/skills/liyu-audit
```

需要 macOS，另外安裝 `jq`、`rg`。

目前 skill 預設 repo 在 `~/talenttb/rubric`，放別處要改三個 `SKILL.md` 裡的路徑；scan 的腳本可以用環境變數 `RUBRIC_HOME` 指定。

## 測試

```
/bin/bash test/scan-test.sh
```
