# 第 5 章 　Coding Agent 与通用 Agent 🟣 高级 ｜ 16 个实验（实验最多的一章）

> 拆分自 [项目结构与十章详解](../guide/2026-10-24-项目结构与十章详解.md) ｜ [返回章节索引](README.md)

**核心问题**：为什么 Coding 能力是通用 Agent 的基础，代码为什么是"能创造新工具的工具"。本章实验数量冠绝全书，因为它是官方推荐终极项目（自研 coding agent）的主参考。

**内容脉络**：Coding 是 Agent 的基础能力 → 案例研究：从 Manus 到 OpenClaw——通用 Agent 的 Coding 内核 → Coding Agent 整体流程 → Harness 工程实践（故障与错误恢复）→ 实现技巧 → 搜索工具与文件编辑工具 → 安全 → **代码作为通用 Agent 的元能力**六个方向：代码作为思考工具（用执行结果验证逻辑，而非让模型"读数据猜结论"）、代码约束业务规则、代码驱动多媒体生成、代码作为系统适配器、代码生成式 UI、代码创造代码（Agent 自举）。

**实验亮点**：`coding-agent` 是生产级 Coding Agent 骨架（文件系统 + 终端 + 编辑）；`cad-vs-diffusion`、`code-for-logic`、`code-for-math` 验证"代码即思考"；`agent-creator`、`paper-to-ppt` 展示代码元能力的应用面。

**工程启示**：面向开放任务的 Agent 无法预置所有工具，运行时自造工具（写脚本、存文件）是灵活性来源，但必须由权限控制、执行隔离与结果验证兜底。
