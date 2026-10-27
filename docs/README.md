# docs/ 目录索引

> 本目录按**用途**分区。新增文档请按下方「归档路由」落位，不要平铺在 `docs/` 根下。
> 结构重组于 2026-10-25（commit 见 `git log --oneline -- docs/`），此后新文档直接入区。

## 一、分区总览

| 分区 | 用途（一句话） | 内容 |
|---|---|---|
| [`guide/`](guide/) | **怎么学**：学习路线、精读计划、项目评估 | 全书评估与学习路径（十章详解/章间逻辑/三条路径+最短路径/实验串联导图/GPU 需求评估/消融速查）、实验明细总表（109 项逐实验一行+技术栈/依赖+台账状态+blocked 替代路径速查）、全书主线与学习实践计划、项目结构与十章详解、阶段一精读执行步骤、评估与实践指南 |
| [`chapters/`](chapters/) | **按章打卡**：十章讲义的按章拆分版 | `ch01`–`ch10` + 章节索引 `README.md` |
| [`experiments/`](experiments/) | **怎么跑实验、怎么读结果**：证据规范与判读 | `EXPERIMENT_STATUS.md`（各章实验状态总账，第一章四实验已全部入账）、`EXPERIMENT_CONVENTIONS.md`（目录与证据约定）、实验 1-1 判读四篇（单臂快测 / 全五臂 / 第二次 canonical / 晋升判定）、实验 1-1 canonical-run 命令卡、实验 1-1 GPU 服务器练习计划（vLLM 五阶段演练）、第一章实验验证指南（三层验证方法 + `verify_chapter1_experiments.py` 一键 28 项机器复核） |
| [`setup/`](setup/) | **怎么跑起来**：本地后端搭建与接入 | `gpu_server.sh`（GPU 服务器/Kimi 云端一键）、`select_backend.sh` / `verify_all.sh` / `serve_vllm_wsl.sh` / `setup_ollama_windows.ps1`、分层验证 README、本地 vLLM-Qwen 接入指南 |
| [`ops/`](ops/) | **怎么协作、出了事怎么查**：仓库治理与运维记录 | GitHub 协作规则、CRLF 行尾事故分析、仓库体积调查报告、轻量克隆与沙箱恢复手册、STATIC_SITE_I18N、`session-handover.md`（会话交接快照） |
| [`presentations/`](presentations/) | **演示资产**：PPT 成品与方案 | 两套 pptx、`slides/`（13 页 HTML）、`onepage/`（单页版）、展示方案文档 |
| [`i18n/`](i18n/) | **多语言索引与学习建议**（上游翻译区） | 13 个语言目录 `<locale>/README.md + LEARNING.md`，及根级 `LEARNING.*.md` 重定向存根 |

## 二、归档路由（新文档放哪）

写完一篇文档后，按下表选择分区；判断标准是**用途**而非时间：

| 文档性质 | 去处 |
|---|---|
| 学习计划 / 精读笔记方法 / 阶段复盘 | `guide/` |
| 某个实验的输出判读、证据解读、复现记录 | `experiments/` |
| 环境搭建、后端接入、脚本使用说明 | `setup/`（脚本本体同目录） |
| 协作规范、事故分析、仓库运维、构建工程文档 | `ops/` |
| 幻灯片、演示 HTML、展示方案 | `presentations/`（资产同目录） |
| 某章内容的按章拆分讲义 | `chapters/` |
| 语言翻译 | `i18n/<locale>/` |

命名建议：操作类/判读类文档保留日期前缀（`YYYY-MM-DD-标题.md`），长期维护的
规范类文档用稳定名称（如 `EXPERIMENT_STATUS.md`），避免日期过期误导。

## 三、与其他区域的边界

- **`book/`**（书稿正文）与 **`chapterN/`**（各章配套实验代码）不在本目录，也不受
  本索引管理；实验证据 JSON 属于各章实验目录内的 `validation/`。
- **站点构建不消费本目录**：MkDocs 站点源是 `_web/`（由 `scripts/build_site.sh`
  从 `book/` 组装）。`docs/` 的改动不会触发站点内容变化（但 `.github/workflows/`
  的路径过滤器已覆盖 `docs/**`）。
- **上游对照**：本仓库（fork）历史与上游 `bojieli/ai-agent-book` 无共同祖先，
  `i18n/`、`chapters/` 等上游来源文件在本 fork 内的位置以本索引为准；与上游
  逐目录比对时注意存在这一层目录差异。

## 四、维护规则

1. 移动/重命名本目录文件时，必须同步修正全部相对链接并跑
   `python scripts/check_docs_links.py`（索引级存在性判定，稀疏检出不误报），
   确认零新增断链后再提交。
2. `EXPERIMENT_STATUS.md` 与 13 个语言 README 属于跨区强引用文件（被根 README、
   章节页、`check_i18n_consistency.py`、`build_site.sh` 引用），改动前先
   `git grep` 全库引用面。
3. 新增文档提交遵循 [协作规则](ops/GitHub协作规则.md)：conventional commits、
   小步提交、`docs:` 前缀。
