# GitHub 协作规则

> 版本：v1.1（含 2026-10-24 注记；2026-10-24 补充仓库地址） ｜ 适用范围：本仓库所有协作者及 AI Agent 助手
> 仓库位置：**`https://github.com/dongf9527/ai-agent-book.git`**

---

## 一、核心规则总览

| # | 规则 | 说明 |
| :--: | --- | --- |
| 1 | **唯一同步方式** | 所有代码/文档改动通过 `git commit` + `git push` 推送到 GitHub，不在对话中凭空产生代码 |
| 2 | **仓库位置** | `https://github.com/dongf9527/ai-agent-book.git`，不在其他目录创建 `.git` |
| 3 | **提交规范** | 小步提交，commit message 使用 conventional commits 风格（`feat:` / `fix:` / `docs:` / `refactor:` / `chore:` / `test:`） |
| 4 | **会话记录** | 分析/评估/测试记录写入 `docs/` 目录，以 Markdown 形式提交推送 |
| 5 | **禁止 force push** | 绝不使用 `git push --force`；同理禁止对已推送 commit 执行 `--amend` 后再推送（等效 force，同样触犯本条，2026-10-24 注记）；未推送 commit 的 amend 属修正笔误常规手段，不受限 |
| 6 | **Rebase 前置** | rebase 前先评估替代方案（revert/merge），必要时提前告知确认 |
| 7 | **bug 修复不重命名变量** | 修复 bug 时保持原变量名，仅在 refactor 时重命名 |

---

## 二、规则详解

### 规则 1：唯一同步方式

- 任何代码或文档改动，最终状态以 GitHub 仓库为准。
- 对话中讨论、草稿、临时代码均不算交付，必须落到 commit 并 push。
- 目的：保证工作成果可追溯、可回滚，避免"对话里有一版、仓库里是另一版"的状态分叉。

### 规则 2：仓库位置

- 唯一工作仓库：**`https://github.com/dongf9527/ai-agent-book.git`**（2026-10-24 确认，当前为空仓库，首次推送将创建 `main` 分支）。
- 除该目录外，禁止在任何其他目录执行 `git init` 或创建 `.git`，防止出现多个"真相源"。

### 规则 3：提交规范

- 采用**小步提交**：一次 commit 只做一件事，便于 review 与回滚定位。
- commit message 使用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 风格：

| 前缀 | 用途 | 示例 |
| --- | --- | --- |
| `feat:` | 新功能 | `feat: add user-memory evaluation script` |
| `fix:` | 缺陷修复 | `fix: correct token counting in context compressor` |
| `docs:` | 仅文档变更 | `docs: add GitHub collaboration rules` |
| `refactor:` | 重构（不改行为） | `refactor: extract memory manager into separate module` |
| `chore:` | 构建/工具/杂项 | `chore: update uv.lock` |
| `test:` | 测试相关 | `test: add regression test for message bus ack` |

### 规则 4：会话记录归档

- 分析结论、评估报告、测试记录等过程性产出，统一写入 `docs/` 目录。
- 一律使用 Markdown 格式，并随代码一起 commit + push（前缀用 `docs:`）。
- 目的：让每次会话的结论沉淀为仓库资产，而非散落在聊天记录中。

### 规则 5：禁止 force push（含 2026-10-24 注记）

三层含义，逐条遵守：

1. **绝对禁止** `git push --force`（含 `--force-with-lease` 之外的任何强推变体）。
2. **等效禁止**：对**已推送**的 commit 执行 `git commit --amend` 后再推送——这同样会改写远端历史，视同 force push，同样触犯本条（2026-10-24 注记）。
3. **允许**：对**尚未推送**的本地 commit 使用 `--amend`，这属于修正笔误的常规手段，不受限制。

### 规则 6：Rebase 前置评估

- 执行 rebase 前，先评估替代方案：能用 `revert` 撤销的用 revert，能 `merge` 的用 merge。
- 若确需 rebase（尤其是涉及共享分支时），必须提前告知协作者并确认后再操作。
- 目的：rebase 会改写历史，与规则 5 的精神一致——避免对共享历史造成不可预期的影响。

### 规则 7：bug 修复不重命名变量

- 修复 bug 时，**保持原变量名不变**，最小化 diff，让 review 聚焦在逻辑修正本身。
- 变量重命名只允许出现在 `refactor:` 类型的提交中，与 bug 修复严格分离。
- 目的：修复提交里混杂重命名会淹没真正的改动，显著增加排查与回滚成本。

---

## 三、快速自查清单（每次提交前）

- [ ] 改动是否已 `git commit` 并 `git push` 到唯一仓库（规则 1、2）？
- [ ] commit message 是否使用 conventional commits 前缀（规则 3）？
- [ ] 分析/测试记录是否已写入 `docs/` 并提交（规则 4）？
- [ ] 本次操作是否涉及 force push 或对已推送 commit 的 amend？（必须为否，规则 5）
- [ ] 如涉及 rebase，是否已评估 revert/merge 并获得确认（规则 6）？
- [ ] bug 修复 diff 中是否混入了变量重命名？（必须为否，规则 7）
