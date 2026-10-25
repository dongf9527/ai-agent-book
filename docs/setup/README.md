# 本地 LLM 后端工具包：vLLM（WSL）+ Ollama（Windows 宿主机）

> 目标：让 `chapter1/context` 等实验在两套本地推理后端之间**自动探测/手工切换**，全程零 API 花费。
> 原理基础见《2026-10-25-本地vLLM-Qwen接入指南.md》：实验的 ollama provider 免 key、OpenAI 兼容，
> 任何后端只需一个 `OLLAMA_BASE_URL` 指向即可接入（`agentbook/providers/models.py:64-72` 的
> `base_url_var` 覆盖机制，全仓所有章节实验通用）。

## 一、目录清单

| 文件 | 运行位置 | 作用 |
|---|---|---|
| `select_backend.sh` | WSL（仓库内） | **核心**：探测三个候选端点 → 列出各后端模型 → 自动选第一个存活者或手工指定 → 幂等写入 `chapter1/context/.env` 受管块 |
| `serve_vllm_wsl.sh` | WSL | 启动 vLLM（自动发现 HF 缓存模型、内置 `--tool-call-parser hermes` 等实验必需参数、幂等防重复启动） |
| `setup_ollama_windows.ps1` | Windows（管理员 PowerShell） | 安装/重启 Ollama、改绑 `0.0.0.0`、防火墙放行 WSL 子网、拉取 qwen3:8b、自检并打印 WSL 侧地址 |
| `verify_all.sh` | WSL（仓库内） | **分层验证**：三端点探测（附服务版本号）→ 问答级 → 工具调用级 → `.env` 受管块与 provider 解析校验；`--quick` 只查端口与模型列表 |
| `gpu_server.sh` | GPU 服务器（仓库内） | **一键脚本**：Kimi 云端路径（自动探测国际站/国内站 + 账号模型校验）与 vLLM 本地路径（serve/probe/keycheck/five）全覆盖，对应练习计划阶段 0→2；详见第九节 |

## 二、拓扑

```
┌──────────────── Windows 宿主机 ────────────────┐
│  Ollama  0.0.0.0:11434   (qwen3:8b 等)         │
│      ▲ 防火墙放行 WSL 子网                      │
│ ┌──────────── WSL2 (Linux) ─────────────────┐  │
│ │  vLLM  0.0.0.0:8000   (--served-model-name)│  │
│ │  chapter1/context 实验进程                  │  │
│ │    └─ .env: LLM_PROVIDER=ollama            │  │
│ │        OLLAMA_BASE_URL = 三选一 ↓           │  │
│ └────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
三个候选端点（select_backend.sh 逐一探测）:
  [1] vLLM        http://localhost:8000/v1       (WSL 内,直连)
  [2] Ollama-WSL  http://localhost:11434/v1      (若 WSL 内也装了 Ollama)
  [3] Ollama-Win  http://<宿主机IP>:11434/v1      (NAT=网关IP / 镜像=localhost)
```

## 三、快速开始（三步）

```bash
# ① Windows 管理员 PowerShell —— 配好宿主机 Ollama 并打印连接地址
Set-ExecutionPolicy -Scope Process Bypass -Force
.\docs\setup\setup_ollama_windows.ps1

# ② WSL —— 启动 vLLM(不装 vLLM 可跳过,直接用 Ollama)
./docs/setup/serve_vllm_wsl.sh            # 自动发现 HF 缓存中的 Qwen 模型

# ③ WSL —— 探测并写入实验配置(自动/手工)
./docs/setup/select_backend.sh            # 自动: vLLM > Ollama-WSL > Ollama-Win
./docs/setup/select_backend.sh list       # 只看各后端有什么模型
./docs/setup/select_backend.sh ollama-win # 手工: 强制用 Windows 宿主机的 Ollama
./docs/setup/select_backend.sh vllm Qwen/Qwen2.5-7B-Instruct   # 手工: 指定模型

cd chapter1/context && python run_experiment_1_1.py   # 消融实验跑起来
```

## 四、自动/手工选择语义

- **自动模式**（无参数）：按 `PRIORITY` 环境变量指定的顺序（默认 `vllm,ollama-wsl,ollama-win`）取第一个 `GET /v1/models` 有响应的后端；模型取其列表第一个。想改变优先级：`PRIORITY=ollama-win,vllm ./select_backend.sh`。
- **手工模式**：第一个参数为后端键，第二个可选参数直接指定 `MODEL_NAME`。后端不在线会告警但仍写入（便于先配好再启动服务）。
- **选择建议**：跑消融实验（`run_experiment_1_1.py`，大量工具调用、要求结构化 tool_calls）优先 vLLM——吞吐高、工具解析最可靠；日常问答式实验或显存被占用时用 Ollama。`qwen3:8b` 是 provider 的 `default_model`，若 vLLM 端用 `SERVED_NAME=qwen3:8b` 启动，实验 `.env` 甚至可以不写 `MODEL_NAME`。
- **受管块**：脚本只改写 `.env` 中 `# >>> local-llm-backend >>>` 标记包裹的块，你手工配置的云厂商 Key（DASHSCOPE/DEEPSEEK 等）不受影响；重复执行幂等覆盖。注意 `load_dotenv()` 不覆盖**已导出的环境变量**——若之前 `export` 过同名变量，以导出值为准。

## 五、WSL → Windows 的两种网络模式

| 模式 | 判断 | 实验侧地址 |
|---|---|---|
| NAT（默认） | `wslinfo --networking-mode` = nat，或不输出 | `http://<默认网关IP>:11434/v1`（`ip route show default` 的第三列；脚本自动探测） |
| 镜像 mirrored（Win11 22H2+，`.wslconfig` 开启） | `wslinfo --networking-mode` = mirrored | `http://localhost:11434/v1`（与宿主机共享回环） |

- **NAT 模式**下宿主机侧需要 `OLLAMA_HOST=0.0.0.0:11434` + 防火墙放行（PowerShell 脚本的步骤②③已处理）；**镜像模式不需要**——Ollama 默认回环绑定即可被 WSL 访问。
- **镜像模式下两个 ollama 端点是同一台服务**：Windows 与 WSL 共享回环命名空间，`localhost:11434` 与 `127.0.0.1:11434` 必然同生同死，两个"存活"不代表两份算力。脚本用 `pgrep` 判定服务实际由哪侧提供——WSL 内有 `ollama` 进程 → 判为 WSL 实例；无进程但端口有响应 → 判为 Windows 宿主机实例经镜像映射——并在输出中以 `⚑ 镜像网络` 注记标明。NAT 模式下两端点是两台独立服务器，标注天然准确。

## 六、故障排查

| 症状 | 原因与解法 |
|---|---|
| `env: 'bash\r': No such file or directory`（执行 .sh 报错） | Windows 侧克隆被 `core.autocrlf` 转成 CRLF，shebang 变 `bash\r` → `sed -i 's/\r$//' docs/setup/*.sh` 后重跑；根治见根目录 `.gitattributes`（2026-10-25 起新克隆自动 LF），完整分析见 `docs/ops/2026-10-25-CRLF行尾问题分析与修复.md` |
| `[ollama-win] 不可达` 但本机 `curl localhost:11434` 正常 | Ollama 仍绑 127.0.0.1 → 重跑 ps1 步骤②；或防火墙拦截 → 重跑步骤③ |
| 实验报 404 / connection refused | `OLLAMA_BASE_URL` 漏了 `/v1` 后缀 |
| 工具调用返回纯文本、实验结果失真 | vLLM 启动漏了 `--enable-auto-tool-choice --tool-call-parser hermes`（Qwen 系列必需） |
| `MODEL_NAME` 不匹配报错 | 必须等于 vLLM 的 `--served-model-name` / Ollama 的 tag（`select_backend.sh` 自动取 `/v1/models` 列表，一般不会错） |
| Moonshot 报 401 Invalid Authentication | key 与端点平台不匹配：国内站 key 走 `api.moonshot.cn`、国际站走 `api.moonshot.ai`，**两站账号不互通**（裸配默认 .cn，国际站 key 必 401）。`gpu_server.sh kimi` 自动探测平台并写入 `KIMI_BASE_URL`；手工配置则 `export KIMI_BASE_URL=https://api.moonshot.ai/v1` |
| Moonshot 报 429 账户暂停（insufficient balance） | key 有效但账户余额不足 → 去对应平台（.cn/.ai）充值后重跑；harness 会 fail-closed 并落盘证据，不会污染 canonical |
| 账号模型列表里没有 kimi-k3 | 可用模型由平台/账号决定（国际站部分账号仅 kimi-k2.6 / kimi-k2.7-code）。`gpu_server.sh kimi` 按账号列表自动选模型并拦截不存在的模型名（FORCE=1 可强制但实验会 400） |
| vLLM 启动 OOM | 7B bf16 需 16–18GB 显存；用 AWQ/GPTQ 量化版，或 `GPU_UTIL=0.7 MAXLEN=4096 ./serve_vllm_wsl.sh` |
| 想临时走云端 API | 删除 `.env` 受管块，恢复 env.example 里的厂商配置即可（两套配置互不干扰） |

## 七、分层验证

一键（WSL，自动完成②～④全部检查，两级验收：问答级 + 工具调用级）：

```bash
./docs/setup/verify_all.sh          # 完整验证；exit 0 = 有后端达到实验级就绪
./docs/setup/verify_all.sh --quick  # 只查端口与模型列表，不做推理
```

其中「② .env 受管块与 provider 解析」一行复刻实验的真实模型解析链：`.env` 的 `MODEL_NAME` 经 `Config.get_default_model()` 作为 `model` 参数传给 `resolve_backend()`（`resolve_backend` 本身不读 `MODEL_NAME`，不传参时返回工具包内置默认 `qwen3:8b`）。因此该行显示 `model=<你的模型> (来自 .env MODEL_NAME)` 即配置生效；若显示「工具包默认」，说明受管块缺 `MODEL_NAME` 行，用 `select_backend.sh <后端> <模型>` 重写即可。

手工逐层验证（第 ① 层在 Windows 侧，脚本覆盖不了）：

```powershell
# ① Windows 宿主机（管理员 PowerShell）—— 服务本身是否健康
ollama -v                                        # 版本
netstat -ano | findstr :11434                    # 必须看到 0.0.0.0:11434 LISTENING（127.0.0.1 则 WSL 连不进）
ollama list                                      # 已拉取的模型
Get-NetFirewallRule -DisplayName "Ollama for WSL" | Format-List DisplayName,Enabled,Action
```

```bash
# ② WSL → Windows 连通（NAT/镜像两种模式）
wslinfo --networking-mode                        # nat 或 mirrored
ip route show default                            # NAT 模式：第三列即宿主机 IP
curl http://<宿主机IP>:11434/v1/models           # 镜像模式用 http://localhost:11434/v1/models

# ③ 后端推理能力（问答 → 工具调用，后者是消融实验硬前提）
curl -s http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"<served-name>","messages":[{"role":"user","content":"1+1=?只回答数字"}],"max_tokens":16}'
curl -s http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"<served-name>","messages":[{"role":"user","content":"计算3+4，调用工具"}], \
       "tools":[{"type":"function","function":{"name":"calculator","description":"计算", \
        "parameters":{"type":"object","properties":{"expr":{"type":"string"}},"required":["expr"]}}}], \
       "tool_choice":"auto","max_tokens":200}'
# 期望响应含 "tool_calls"；只有 content 文本 = 工具解析未生效（vLLM 缺 --tool-call-parser hermes）

# ④ 实验配置链最终验收（.env 受管块 → provider 解析 → 最小实验）
./docs/setup/select_backend.sh             # 写入受管块
cd chapter1/context && python main.py --mode single --provider ollama \
  --task "用计算器算 12*8 然后告诉我结果"          # 最小实验冒烟（约 1 分钟）
```

> 冒烟通过后进入消融实验：先单臂快测（如 `--modes no_tool_results`），再全五臂 canonical
> run。单臂输出中的 `ERROR - Error executing code`、`no_terminal_response`、
> `accepted=False` 均可能是预期行为，逐项判读见
> [实验 1-1 单臂快测判读](../experiments/2026-10-25-实验1-1单臂快测判读.md)。

> 全五臂跑完若五臂齐全却仍未晋升（`accepted=False` 且 `exact_five_arms_present=true`），
> 通常是本地模型未回传推理内容、`full` 与 `no_reasoning` 两臂上下文合同 fail-closed
> 所致——消融空转比行为不符更常见。挂点定位、三步探针与修复路径分档见
> [实验 1-1 全五臂真跑判读](../experiments/2026-10-25-实验1-1全五臂真跑判读.md)。

> 探测与验证输出会附带各端点的 `server vX.Y.Z`（Ollama 走 `/api/version`，vLLM 走 `/version`），
> Windows 与 WSL 两侧版本错位（CLI 新、常驻服务旧）一眼可比。

## 八、WSL 内 Ollama 的检测与升级

WSL 内也可以装一份 Ollama（候选端点② `ollama-wsl`）。它与 Windows 宿主机那份是**两个独立实例**：
模型需单独 `ollama pull`，版本可能不同；装上后 auto 模式将优先于 `ollama-win`（PRIORITY 顺序），
跑实验前先确认它拉好了模型。

```bash
# ── 检测（WSL 内逐项执行）──
command -v ollama                            # 装没装（有输出=已装，路径通常 /usr/local/bin/ollama）
ollama --version                             # 客户端版本；服务未运行会带 Warning
curl -s http://localhost:11434/api/version   # 服务端版本 JSON（最权威，不管 CLI 什么版本）
pgrep -af ollama                             # 服务进程；systemd 环境可用 systemctl is-active ollama
ollama list && ollama ps                     # 已拉取的模型 / 已加载进显存的模型

# ── 升级（官方安装器，重复执行即原地升级，模型与配置保留）──
curl -fsSL https://ollama.com/install.sh | sh

# 重启服务（WSL 已启用 systemd 时，2026 年新装的 WSL2 默认启用）
sudo systemctl restart ollama

# 未启用 systemd 的 WSL：手动重启进程
pkill -x ollama; nohup ollama serve >/dev/null 2>&1 &

# ── ollama.com / GitHub 网络慢时的手动升级（amd64）──
curl -LO https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tgz
sudo tar -xzf ollama-linux-amd64.tgz -C /usr/local
# 覆盖后同样需要重启服务（systemctl restart 或 pkill + nohup）
```

版本错位自检（Windows 侧已踩过的坑，WSL 同样适用）：`ollama --version` 若出现
`Warning: client version is ...`，说明 CLI 与常驻服务版本不一致——安装器升级后**务必重启服务**，
新版本二进制才会真正生效；以 `/api/version` 的返回为准判定服务版本。

## 九、GPU 服务器一键脚本（gpu_server.sh）

远程 GPU 服务器上直跑练习计划各阶段，Kimi 云端对照与 vLLM 本地路径全覆盖（无 GPU 也能跑云端对照）：

| 子命令 | 对应计划阶段 | 作用 |
|---|---|---|
| `check` | — | 预检：Python 依赖 / GPU / vLLM / git 对齐 / Kimi key（报告性，不阻断） |
| `kimi [KEY]` | 云端对照 | 自动探测 key 属国内站(.cn)还是国际站(.ai) → 写 `KIMI_BASE_URL` 覆盖 → 账号模型列表核对并自动选模型（kimi-k3 不在账号时拦截） |
| `serve [MODEL]` | 阶段 0 | 起 vLLM：内置 `--enable-auto-tool-choice --tool-call-parser hermes --reasoning-parser qwen3`（缺一消融即失真），幂等防重启，透传附加参数给 vLLM |
| `probe [URL] [MODEL]` | 阶段 0 | 三探针：①模型在位 ②思考上线（reasoning_content / reasoning 双字段）③结构化 tool_calls，失败即输出对应修复旗标 |
| `keycheck [PROVIDER] [MODEL]` | 阶段 1 | full 单臂快测（`--task guarded --hidden-result empty --max-iterations 5`），证据落 `validation/probes_gpu_*`；harness 的 exit 0 只对五臂有意义（单臂 probe 恒 exit 1），本脚本按 evidence 归一为 exit 0/1（full 臂 correct + 合同绿 + 无编造） |
| `five [PROVIDER] [MODEL]` | 阶段 2 | canonical 五臂，exit 0 ⇔ accepted 且自动晋升 `latest.json` |

快速开始：

```bash
# ── Kimi 云端对照(两站 key 不互通,脚本自动识别;模型名按账号列表自动校验) ──
./docs/setup/gpu_server.sh check               # 预检
./docs/setup/gpu_server.sh kimi sk-xxx         # key 自动入 .env 受管块(打码/600 权限)
./docs/setup/gpu_server.sh keycheck            # 读受管块解析 provider/model
./docs/setup/gpu_server.sh five

# ── vLLM 本地路径(阶段 0→1→2) ──
./docs/setup/gpu_server.sh serve Qwen/Qwen3.5-9B   # 缺省自动发现 HF 缓存(识别 HF_HOME/HF_HUB_CACHE)
./docs/setup/gpu_server.sh probe                   # 或 probe <served-name>;非 http 参数按模型名理解
docs/setup/select_backend.sh vllm <served-name>    # 切 .env 到本地后端
./docs/setup/gpu_server.sh keycheck ollama <served-name>
./docs/setup/gpu_server.sh five ollama <served-name>
```

要点：

- **DRY_RUN=1** 全子命令支持：只打印将执行的命令与配置，不实际执行/不写文件——上服务器前先过一遍。
- **受管块**与 `select_backend.sh` 同一标记，互写幂等覆盖（谁后写谁生效）；受管块之外手工配置的其它厂商 key 不受影响。
- **key 安全**：只写入 `chapter1/context/.env`（gitignore 覆盖，600 权限），输出一律打码；轮换 key 直接 `kimi <新key>` 重跑即可（旧 key 散行会被清掉）；stdin 非交互且无 key 时拒绝而非挂起。
- **模型守卫**：kimi 路径会拉取账号 `/v1/models` 实际列表，模型名不存在即拦截并给出列表（避免 registry 默认 kimi-k3 在部分账号不存在导致的 400）。
