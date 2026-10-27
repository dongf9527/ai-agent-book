# 会话交接文档（Session Handover）

> 交接时间：2026-10-26（Asia/Shanghai）
> 交接目的：当日会话收尾。明日（2026-10-27）审核 `docs/guide/` 两份评估文档；本文供审核者与后续会话（含新开的 AI 会话）快速恢复完整上下文。
> 阅读顺序建议：先本文 → 再两份评估文档 → 需要会话级细节时查沙箱侧 worklog（见 §七）。
> 安全约定：本文不含任何凭据明文；PAT 相关只写位置与生命周期。

## 一、当前状态快照

| 项 | 状态 |
|---|---|
| 仓库同步 | `main == fork/main == 5a3295f`（完全同步，无滞留提交、无未提交改动） |
| 今日提交 | `4aba4f7`（评估文档 v1）→ `5a3295f`（六项增强 + 明细总表附录） |
| 待审核对象 | `docs/guide/` 两份评估文档（见 §三） |
| GPU 实验 1-1 | 阶段 0/1 已通，阶段 2 待收尾：五臂重跑（一条命令，见 §四） |
| 推送链路 | 正常：`git push fork main`（credential.helper=store 已恢复） |
| 风险与提醒 | PAT 有效期约至 2026-11-25，到期提醒已设（见 §六.4） |

## 二、近期会话完成了什么（2026-10-25 ~ 10-26）

### 2.1 Harness 修复链（六笔提交，全部已推送）

| 提交 | 内容 | 解决的问题 |
|---|---|---|
| `1ba5fbb` | kimi-kN.M 温度守卫：正则 `kimi-k\d+\.\d+` 匹配新代际 id，强制 temperature=1 | GPU keycheck 报 400 invalid temperature |
| `18d9faa` | `probe_verdict()` 证据判读（full 臂 correct + 真实 API 证据 + 合同绿） | 单臂 probe 恒 exit 1 的语义错配（probe 本就不晋升） |
| `299fa44` | 429 被动退避：等 25s 再试 ×5（env 可调） | Moonshot 免费档 RPM=3 打断五臂 |
| `a8fad8c8` | 主动节流 `_RpmLimiter`：moonshot 域自动 ≤3 req/min（实际约 2.8/min），SDK `max_retries=0` 收拢重试 | 「每分钟最多 3 个请求」要求达成，429 退避降级为兜底 |
| `4aba4f7` | 全书评估文档 v1（六章结构） | 全书评估任务 |
| `5a3295f` | 评估文档六项增强 + 新增《实验明细总表》附录 | 六项文档增强需求 |

### 2.2 六项文档增强的落地情况（全部完成，待审核）

1. **沙箱与 GitHub 同步** ✅ 推送后 `ls-remote` 校验一致。
2. **十章逐章详解 + 排版分层** ✅ 「十章速查表」（主题/一句话核心/实验数/难度图例）+ 每章三层展开：核心问题 → 内容主线（缩进对齐原书节级结构，可当精读目录）→ 实验与启示。
3. **4.2 三条路径详解** ✅ 每条路径含：适合人群 / 目标 / 为什么是这条线 / 周级拆解 / 验收标准；尾部汇入官方终极主线（自研 Coding Agent）。
4. **分实验明细** ✅ 拆为附录《实验明细总表》：109 个编号实验逐项一行（名称 / 技术栈与依赖 / 说明 / 台账状态，7 种状态图例，状态全部溯源各章台账）。
5. **技术人员最短路径** ✅ 新增 4.3：5–7 天速通表（每天读什么/跑什么/自检标准，锚点实验仅 1-1、2-3、2-5、7-1）+ 极简三日读版 + 选做原则。
6. **实验串联导图** ✅ 新增 5.3：一条主线（拆/测/扩/评/改五动作）+ mermaid 五阶段流程图 + 三个环（方法学环/证据环/内化环）。

### 2.3 运维与安全

- PAT 三处冗余保管（均在 git 跟踪范围外），详见 §六.4；有效期约至 2026-11-25。
- 外层工作区仓库的历史泄密风险已清除（filter-branch 全历史移除 + reflog expire + gc）。
- 沙箱侧 worklog 已记录至 Task 42；本文对应 Task 43。

## 三、明日审核对象（两份文档）

| 文档 | 体量 | 内容 | 审核关注点建议 |
|---|---|---|---|
| `docs/guide/AI-Agent-Book-全书评估与学习路径.md` | 约 1.55 万字 | 概览 / 十章详解 / 章间逻辑与暗线 / 学习路径（含最短路径）/ 实验体系与串联导图 / 文档地图 | ① 逐章详解的深度与层次是否符合预期；② 4.3 最短路径的天数安排是否合理；③ mermaid 图能否正常渲染；④ 实验计数口径（109 = ch1-8 台账 94 + ch9 为 9 + ch10 为 6） |
| `docs/guide/AI-Agent-Book-实验明细总表.md` | 约 1.05 万字 | 109 实验逐项一行 + 状态图例 + 台账红线 | ① 技术栈/依赖列的粒度；② 状态溯源是否准确（抽查几行对台账）；③ 重复编号检查已通过，可复核 |

两份文档的副本也已放在沙箱 `download/` 目录，可直接阅读无需克隆。

## 四、GPU 实验 1-1：进度与待办

**已完成**：阶段 0 预检全绿；阶段 1 keycheck 通过——full 臂 correct、3 轮收敛、reasoning_tokens=378、无编造、真实 API 证据落盘；主动节流已生效。

**待办（用户侧，一条命令）**：

```bash
git pull && ./docs/setup/gpu_server.sh five
```

- 预计 8–15 分钟；日志出现 `rate pacing` 等待属预期（节流器在工作）。
- `exit 0` ⇔ accepted 且晋升 `validation/latest.json`。
- 若再遇 429：脚本已区分「余额型」（exceeded_current_quota，需充值）与「限流型」（rate_limit，脚本会自动等待）；保守可 `LLM_RPM=2 ./docs/setup/gpu_server.sh five`。

**五臂成功后的收尾（接续会话配合）**：
1. `python docs/experiments/verify_chapter1_experiments.py`（28 项机器复核）。
2. 填阶段 2 对照表：kimi 路径 temperature=1（平台硬约束）与 Ollama canonical 0.3 的差异按「部署层差异」口径记录，不做逐字节 diff。
3. 判读短文入 `docs/experiments/`（参照既有四篇判读文档格式）。

## 五、明日待办清单

**用户侧**：
1. 审核两份文档（关注点见 §三表格）。
2. GPU 服务器重跑五臂（§四）。
3. 审核意见反馈给 agent 修订。

**Agent 侧（接续会话）**：
1. 按审核意见修订两份文档 → 提交推送 → 同步校验（老三样流程）。
2. 五臂输出判读（用户贴回结果后）；成功则走 §四收尾三步。
3. 下一个实验：1-2（web-search-agent），随后进 ch2——2-3（KV Cache 反模式）与 2-10（六种压缩）是 1-1 的直接延伸。
4. 若用户要求「同步沙箱和 github」：先 `git ls-remote fork refs/heads/main` 比对哈希，再决定 fetch/push（blobless 克隆下轻量比对优先）。

## 六、关键操作知识（新会话必读）

### 6.1 推送

```bash
cd /home/z/my-project/repo-ai-agent-book && git push fork main
```

凭据在 credential.helper=store。若沙箱重置导致推送 401/无凭据：凭据有三处备份（`.env` / `.secrets/` / `~/.git-credentials`），沙箱重置只会清掉它们所在工作区文件，按 ops 手册重建即可；仍失败则需用户重新提供 PAT。

### 6.2 沙箱特性

- sparse checkout（约 28MB blobless）：`docs/ book/ chapter1/ agentbook/` 四目录；其余章节约 2.1GB 资产不在本地。
- **跨浅边界 `git show`/`diff` 会按 OID 惰性补取 blob**（绕过 filter，曾一次拉入 254MB）——上游/远端比对只看哈希（`git ls-remote`），不 show 跨界对象。
- 沙箱重置清凭据但不动仓库文件与 worklog；`core.fileMode false` 已设（消音模式位噪音）。

### 6.3 实验命令速查

| 命令 | 用途 |
|---|---|
| `./docs/setup/gpu_server.sh check` | GPU 服务器预检 |
| `./docs/setup/gpu_server.sh kimi` | 平台探测（.cn/.ai 自动）+ 受管块写入 + 模型校验（建议无参运行，key 从 .env 读，不进 history） |
| `./docs/setup/gpu_server.sh keycheck` | 单臂快测（按证据判读 exit code） |
| `./docs/setup/gpu_server.sh five` | 五臂对照（exit 0 ⇔ accepted 且晋升 latest.json） |
| `DRY_RUN=1` 前缀 | 全子命令支持演练模式 |
| `LLM_RPM=<n>` env | 调整/关闭（0）节流 |
| `python docs/experiments/verify_chapter1_experiments.py` | 第一章 28 项机器复核 |

### 6.4 PAT 生命周期

- 位置：沙箱 `.env`（GITHUB_TOKEN 键）、`.secrets/github-pat-*.txt`（含元数据）、`~/.git-credentials`；三处均在 git 跟踪范围外。
- 有效期约至 **2026-11-25**；2026-11-20 10:00 已设一次性提醒（验证健康 + 提醒换新）。
- 换新流程 = 更新上述三处。纪律：不入书仓、不入 worklog、不进对话明文。

## 七、踩坑速查表（症状 → 根因 → 修复）

| 症状 | 根因 | 修复 | 提交 |
|---|---|---|---|
| 400 invalid temperature | kimi-k2.6 等新代际固定 temperature=1，旧守卫名单没认 | 正则守卫 `kimi-k\d+\.\d+`，四处模块同步 | `1ba5fbb` |
| keycheck ❌ 但 full 臂 correct | 单臂 probe 语义上不晋升，恒 exit 1，harness 语义错配 | `probe_verdict()` 按证据归一 exit code | `18d9faa` |
| 五臂第 1 轮全灭（429） | 免费档 RPM=3，SDK 内置重试仅等 1s | 被动退避 + 主动节流双保险 | `299fa44`/`a8fad8c8` |
| 推送 401 / 无凭据 | 沙箱重置清空凭据文件 | 三处备份恢复；不行则请用户换新 PAT | — |
| `.sh` 报 `env: 'bash\r'` | Windows 检出 CRLF（autocrlf） | `.gitattributes` 已根治；存量 `sed -i 's/\r$//'` | `ab4d180` |
| argparse 报 `invalid choice: 'kimi\r'`，check 里 MODEL_NAME 误报不在账号列表 | **.env**（gitignored，不受 .gitattributes 管辖）被 Windows 编辑器存成 CRLF，bash 提取值带尾 `\r` | gpu_server.sh 启动自动归一（DRY_RUN 只提示不落盘）；kimi 子命令对粘贴 key 剥 `\r`；手动 `sed -i 's/\r$//' chapter1/context/.env` | （worklog Task 45） |
| Ollama 连不上（WSL） | OLLAMA_HOST 未生效 / NAT 模式防火墙 | `docs/setup/README.md` 排障表（mirrored 模式无需 0.0.0.0） | — |
| 验证显示 qwen3:8b 而非 .env 模型 | `resolve_backend` 不读 MODEL_NAME，纯显示缺陷 | verify_all ② 段已改为端到端解析校验 | `08825a3` |
| 改 git 历史误删工作树文件 | filter-branch 收尾 `read-tree -u` 同步删除已移除文件 | 改历史前先备份工作树；从 refs/original 抢回 | （worklog Task 41） |

## 八、文档地图（本文之外去哪找）

| 需要什么 | 去处 |
|---|---|
| 明日审核对象 | `docs/guide/` 两份评估文档（§三） |
| 学习路径与最短路径 | 评估文档 §四（4.2/4.3） |
| 实验怎么跑、脚本用法 | `docs/setup/`（gpu_server.sh + README 第九节） |
| 实验判读规范与验证 | `docs/experiments/`（CONVENTIONS / 验证指南 / 判读四篇） |
| 协作规则（提交规范等） | `docs/ops/GitHub协作规则.md` |
| 环境搭建排障 | `docs/setup/README.md` 排障表 |
| 会话级完整细节 | 沙箱侧 `/home/z/my-project/worklog.md`（Task 11–43，含每次判读与测试记录；仓库外文件，仅沙箱可见） |

维护约定：本文是一次性快照。下次会话收尾时可直接覆盖更新本文（保留文件名），并在 worklog 留痕；历史版本经 `git log -- docs/ops/session-handover.md` 追溯。
