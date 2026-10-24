# PPT：《深入理解 AI Agent》全书总览与实践路线

> 重建日期：2026-10-24 ｜ 13 页 ｜ 深空科技蓝（#0B1220 / #F5F1E8 / #22D3EE）｜ Noto Serif SC + JetBrains Mono ｜ 每页含完整中文讲稿备注
> 方案依据：[核心内容PPT展示方案](../2026-10-24-核心内容PPT展示方案.md)

## 目录内容

| 文件 | 说明 |
| --- | --- |
| `深入理解AI-Agent-全书总览与实践路线.pptx` | 成品演示文稿（13 页，含逐页讲稿备注，可直接用 PowerPoint/WPS 打开） |
| `slides/slide_01.html ~ slide_13.html` | 逐页源稿（1280×720 独立 HTML，TailwindCSS + global.css） |
| `slides/global.css` | 全套设计系统（调色板、字号 token、卡片/胶囊/幽灵数字等组件） |
| `slides/slides_brief.json` | 结构清单（13 页的标题/版式/内容简报，单一事实源） |

## 十三页结构

1. 封面 ｜ 2. 公式主线：Agent = LLM + 上下文 + 工具 ｜ 3. 生产形态：Model + Harness ｜ 4. 三层学习资产 ｜ 5. 十章地图
6. 结构主线 ｜ 7. 方法论主线 ｜ 8. 设计模式主线（五模式）｜ 9. 演化主线 ｜ 10. 三条更新路径
11. 六阶段计划·构建期 W1–4 ｜ 12. 提升与创造期 W5–10 + 主线自查清单 ｜ 13. 结语行动页

## 再生成与迭代

- **改样式**：编辑 `slides/global.css` 后重新导出即可全局生效。
- **改内容**：先改 `slides/slides_brief.json` 对应页的 `task_brief`，再改对应 `slide_NN.html`。
- **导出 pptx**：`NODE_PATH=/usr/local/lib/node_modules node skills/pptx/batch_html2pptx.js docs/ppt/slides docs/ppt/<名称>.pptx`（在本仓库根目录执行；转换器来自沙箱 pptx 技能目录）。
- 历史注记：初版 PPT 于 2026-10-24 生成后因沙箱重置丢失；本版为按原设计规范重建，源稿自本提交起纳入版本管理。
