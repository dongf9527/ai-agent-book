# 实验 1-1 canonical run 命令卡（ollama / qwen3.5:9b）

> 用途：在你的机器（WSL，`/mnt/e/sourcecode/ai-agent-book`）上一次性产出**可晋升**的
> 全五臂 canonical 证据，并按协作规则推送到 fork。
> 前置状态：判读文档第七节的 **A 档修复已落地**——`agent.py` 的 ollama 分支现在默认
> 发送 `reasoning_effort=high`（与 deepseek 分支的 thinking 开关对齐），`OLLAMA_THINK=0`
> 可显式关闭。变更只增 12 行，`tests/` 25 项回归全过。
> 关联：[全五臂真跑判读](2026-10-25-实验1-1全五臂真跑判读.md)（根因与分档依据）、
> [实验状态总账](EXPERIMENT_STATUS.md)。

## 一、为什么直接跑就行，但仍要 30 秒预检

上一跑（`real_20261025T054152Z`）被验收门拦下的唯一原因是服务端没在 wire 上回传推理
内容，而不是 harness 或合同有任何问题。A 档修复把"请求思考"这一步补上了，但这依赖
Ollama 的 `/v1` 端点真的接受并透传 `reasoning_effort` 字段——这一点只有你的服务器版本
（v0.40.11）能回答。预检用 30 秒把两可变成确定，避免 1.5 分钟的五臂跑出一份同型失败
的复制品。预检通过后，canonical 命令本身就是无参数缺省口径，没有任何额外开关。

## 二、命令序列（逐段复制执行）

```bash
# ⓪ 同步沙箱已推送的修复（含 agent.py A 档 + 本命令卡）
cd /mnt/e/sourcecode/ai-agent-book
git pull --ff-only

# ① 模型能力：capabilities 数组里是否含 "thinking"
curl -s http://localhost:11434/api/show -d '{"model":"qwen3.5:9b"}' \
  | python3 -c "import json,sys; print('capabilities =', json.load(sys.stdin).get('capabilities'))"

# ② /v1 端点实测：agent.py 现在发的就是这个字段，探针必须看到推理才算数
curl -s http://localhost:11434/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.5:9b","messages":[{"role":"user","content":"9.11 与 9.8 谁大"}],"reasoning_effort":"high"}' \
  | python3 -c "
import json,sys
raw=sys.stdin.read()
try:
    m=json.loads(raw)['choices'][0]['message']
    print('reasoning_on_wire =', bool(m.get('reasoning') or m.get('reasoning_content')))
except Exception:
    print('unexpected response:', raw[:300])
"

# ③ canonical 全五臂（--modes 缺省即五臂齐全；guarded + empty 为 canonical 口径；
#    无 --seed 机制，temperature 0.3 固定在代码里）
cd chapter1/context
python run_experiment_1_1.py --provider ollama --model qwen3.5:9b

# ④ 自检：最后一行应为 "Promoted to validation/latest.json"，exit code 为 0
echo "exit=$?"
```

## 三、预检判读表（② 的三种结果怎么走）

| 预检结果 | 含义 | 行动 |
|---|---|---|
| ① 含 `thinking` 且 ② `reasoning_on_wire = True` | A 档生效条件齐备 | 直接跑第②段 canonical 命令 |
| ② HTTP 200 但 `False` | `/v1` 忽略了该字段 | 跑判读文档第六节③的 native `/api/chat think:true` 探针：native 为 True → 端点透传问题，升级 Ollama 后复探；native 也 False → 走 B/C 档 |
| ② HTTP 400（`unexpected response`） | 后端拒绝该字段 | 后端不兼容此提示时用 `OLLAMA_THINK=0` 降级跑（仅当模型默认吐推理，如经 provider=ollama 路由的 vLLM+reasoning parser）；否则走 C 档 |

## 四、canonical 判定与晋升机制（脚本自动完成，无需手工干预）

晋升条件在 `run_experiment_1_1.py` L617-621：`--task guarded` + `--hidden-result empty` +
五臂齐全（缺省 `--modes`），三者缺一不可。满足时若 `experiment_execution_accepted=true`，
脚本自动把证据复制为 `validation/latest.json` 并打印 `Promoted to validation/latest.json`；
任何探针式的子集跑（如单臂）永远不会触碰 `latest.json`。因此自检只需看两处：最后
一行是否为 Promoted，以及 `echo $?` 是否为 0（exit code 0 当且仅当 accepted）。

## 五、推送清单（跑完后执行）

```bash
cd /mnt/e/sourcecode/ai-agent-book
# 新证据目录 + 上次会话遗留的两个本地证据目录 + （若晋升）latest.json
git add chapter1/context/validation/real_20261025T*
git add chapter1/context/validation/latest.json
git commit -m "chore: add local ollama evidence for experiment 1-1 (canonical five-arm run)"
git push
```

- `git add` 通配会同时带上 `real_20261025T052851Z`（单臂快测）、`real_20261025T054152Z`
  （五臂未晋升）与新目录——未晋升证据入库是仓库既有惯例（`probes_*` 目录即先例），
  它们记录本地复现史，不影响 `latest.json` 的权威性。
- 若本次未被晋升，`latest.json` 不会有变更，`git add` 对它是无害空操作；此时把判定
  JSON 贴回对话判读即可，不需要重复推送。
- 推送遵循[协作规则](../ops/GitHub协作规则.md)：小步提交、conventional commits、禁止 force push。

## 六、本次 A 档修复的变更说明

`chapter1/context/agent.py` 请求构造处（deepseek 分支旁）新增 ollama 分支：请求体附加
`reasoning_effort=high`，并同步写入 `request_data`，保证证据文件里的请求记录与实际
发出的 payload 一致——这是证据完整性的硬要求，不许有"代码发了但证据没记"的差位。
逃生门 `OLLAMA_THINK=0` 覆盖两类场景：后端对该字段返回 400，或经 provider=ollama
路由到自带推理输出的后端（如 vLLM）不需要提示。读取端无需改动：`_reasoning_content()`
本就兼容 `reasoning_content` 与 Ollama 原生的 `reasoning` 字段，服务端只要回传就必然
进入 `trajectory.reasoning_steps` 并成为合同检查依据。
