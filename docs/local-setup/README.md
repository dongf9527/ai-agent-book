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
.\docs\local-setup\setup_ollama_windows.ps1

# ② WSL —— 启动 vLLM(不装 vLLM 可跳过,直接用 Ollama)
./docs/local-setup/serve_vllm_wsl.sh            # 自动发现 HF 缓存中的 Qwen 模型

# ③ WSL —— 探测并写入实验配置(自动/手工)
./docs/local-setup/select_backend.sh            # 自动: vLLM > Ollama-WSL > Ollama-Win
./docs/local-setup/select_backend.sh list       # 只看各后端有什么模型
./docs/local-setup/select_backend.sh ollama-win # 手工: 强制用 Windows 宿主机的 Ollama
./docs/local-setup/select_backend.sh vllm Qwen/Qwen2.5-7B-Instruct   # 手工: 指定模型

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

宿主机侧无论如何都需要 `OLLAMA_HOST=0.0.0.0:11434` + 防火墙放行（PowerShell 脚本的步骤②③已处理）。

## 六、故障排查

| 症状 | 原因与解法 |
|---|---|
| `[ollama-win] 不可达` 但本机 `curl localhost:11434` 正常 | Ollama 仍绑 127.0.0.1 → 重跑 ps1 步骤②；或防火墙拦截 → 重跑步骤③ |
| 实验报 404 / connection refused | `OLLAMA_BASE_URL` 漏了 `/v1` 后缀 |
| 工具调用返回纯文本、实验结果失真 | vLLM 启动漏了 `--enable-auto-tool-choice --tool-call-parser hermes`（Qwen 系列必需） |
| `MODEL_NAME` 不匹配报错 | 必须等于 vLLM 的 `--served-model-name` / Ollama 的 tag（`select_backend.sh` 自动取 `/v1/models` 列表，一般不会错） |
| vLLM 启动 OOM | 7B bf16 需 16–18GB 显存；用 AWQ/GPTQ 量化版，或 `GPU_UTIL=0.7 MAXLEN=4096 ./serve_vllm_wsl.sh` |
| 想临时走云端 API | 删除 `.env` 受管块，恢复 env.example 里的厂商配置即可（两套配置互不干扰） |

## 七、分层验证

一键（WSL，自动完成②～④全部检查，两级验收：问答级 + 工具调用级）：

```bash
./docs/local-setup/verify_all.sh          # 完整验证；exit 0 = 有后端达到实验级就绪
./docs/local-setup/verify_all.sh --quick  # 只查端口与模型列表，不做推理
```

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
./docs/local-setup/select_backend.sh             # 写入受管块
cd chapter1/context && python main.py --mode single --provider ollama \
  --task "用计算器算 12*8 然后告诉我结果"          # 最小实验冒烟（约 1 分钟）
```
