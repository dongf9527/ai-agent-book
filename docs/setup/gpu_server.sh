#!/usr/bin/env bash
# gpu_server.sh —— GPU 服务器一键脚本：vLLM 部署探针 / Kimi 云端路径 / 消融实验驱动
#
# 对应练习计划: docs/experiments/2026-10-25-实验1-1-GPU服务器练习计划.md
#   阶段0 serve+probe → 阶段1 keycheck → 阶段2 five；Kimi 云端对照走 kimi+keycheck
#   消融变体(阶段3)与模型阶梯(阶段4)见计划文档,直接改 keycheck/five 的参数即可
#
# 用法:
#   ./gpu_server.sh check                        # 环境预检: 依赖/GPU/vLLM/git/Kimi 配置(报告性,不阻断)
#   ./gpu_server.sh kimi [KEY]                   # Kimi 云端: 自动探测国内站/国际站 → 写 .env → 模型核对
#   ./gpu_server.sh serve [MODEL] [vLLM参数…]     # 起 vLLM(幂等; 内置工具+思考解析必需参数)
#   ./gpu_server.sh probe [BASE_URL] [MODEL]     # 三探针: ①模型在位 ②思考上线 ③结构化工具调用
#   ./gpu_server.sh keycheck [PROVIDER] [MODEL]  # 单臂快测(full 臂, 阶段1, 最小成本验证链路)
#   ./gpu_server.sh five [PROVIDER] [MODEL]      # canonical 五臂(阶段2, exit 0 ⇔ accepted 且晋升)
#
# 环境变量:
#   DRY_RUN=1        只打印将执行的命令与配置,不实际执行/不写文件
#   PORT=8000  PARSER=hermes  REASONING_PARSER=qwen3(置空禁用)  GPU_UTIL=0.85  MAXLEN=8192  SERVED_NAME=
#   KIMI_MODEL=      kimi 路径指定模型(默认按 kimi-k3 → kimi-k2.6 → 列表首个 选第一个在账号内存在的)
#   FORCE=1          kimi/keycheck 的模型名不在账号可用列表时仍继续
#
# 受管块说明: 沿用 select_backend.sh 的标记格式(verify_all.sh ② 段依赖该标记)。
#   本脚本与 select_backend.sh 谁后写谁生效,互相幂等覆盖;.env 中受管块之外
#   手工配置的其它厂商 key 不受影响。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
CTX_DIR="$REPO_ROOT/chapter1/context"
ENV_FILE="$CTX_DIR/.env"
MARK_BEGIN="# >>> local-llm-backend (managed by select_backend.sh) >>>"
MARK_END="# <<< local-llm-backend <<<"
DRY_RUN="${DRY_RUN:-0}"
PORT="${PORT:-8000}"
PARSER="${PARSER:-hermes}"
REASONING_PARSER="${REASONING_PARSER-qwen3}"   # 置空(=)禁用,未设置时默认 qwen3
GPU_UTIL="${GPU_UTIL:-0.85}"
MAXLEN="${MAXLEN:-8192}"
SERVED_NAME="${SERVED_NAME:-}"

say()  { echo "$*"; }
warn() { echo "⚠️  $*" >&2; }
die()  { echo "❌ $*" >&2; exit 1; }

# ---------- 通用工具 ----------

ts() { date -u +%Y%m%dT%H%M%SZ; }

json_models() {  # $1=base_url(含/v1) → 每行一个模型 id(空=不可达)
  local body
  body="$(curl -fsS --max-time 3 "$1/models" 2>/dev/null || true)"
  [[ -z "$body" ]] && return 0
  printf '%s' "$body" | python3 -c '
import sys, json
try:
    for m in json.load(sys.stdin).get("data", []):
        mid = m.get("id", "")
        if mid: print(mid)
except Exception:
    pass'
}

is_placeholder() {  # env.example 的占位值不算真 key
  local v="$1"
  [[ -z "$v" ]] && return 0
  case "$v" in your_*|your-*|"") return 0 ;; esac
  return 1
}

env_key() {  # 从 .env 取 Moonshot key(占位值视为无); 无则空串
  local v=""
  if [[ -f "$ENV_FILE" ]]; then
    v="$(grep -E '^(MOONSHOT_API_KEY|KIMI_API_KEY)=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
  fi
  if is_placeholder "$v"; then
    v="${MOONSHOT_API_KEY:-}"
    if is_placeholder "$v"; then v="${KIMI_API_KEY:-}"; fi
  fi
  if is_placeholder "$v"; then echo ""; else echo "$v"; fi
}

# ---------- 受管块 ----------

strip_managed_block() {  # 幂等删除旧受管块(与 select_backend.sh 同一标记)
  [[ -f "$ENV_FILE" ]] || { touch "$ENV_FILE"; return; }
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" \
      'index($0,b)>0 {inblk=1} !inblk {print} inblk && index($0,e)>0 {inblk=0}' \
      "$ENV_FILE" > "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
}

show_env_block() {  # 展示受管块(key 打码)
  sed -n '/local-llm-backend (managed/,/local-llm-backend <<</p' "$ENV_FILE" \
    | grep '=' \
    | sed -E 's/^(MOONSHOT_API_KEY|KIMI_API_KEY)=.{6}.*/\1=******(已打码)/'
}

# ---------- Kimi 平台探测(国际站/国内站 key 不互通,这是 401 的头号根因) ----------

KIMI_BASE=""
KIMI_MODELS=""

kimi_detect() {  # $1=key → 设置 KIMI_BASE 与 KIMI_MODELS; 返回 0/1
  local key="$1" body base
  KIMI_BASE=""; KIMI_MODELS=""
  for base in https://api.moonshot.cn/v1 https://api.moonshot.ai/v1; do
    body="$(curl -fsS --max-time 10 "$base/models" -H "Authorization: Bearer $key" 2>/dev/null || true)"
    if [[ -n "$body" ]]; then
      KIMI_BASE="$base"
      KIMI_MODELS="$(printf '%s' "$body" | python3 -c '
import sys, json
try:
    for m in json.load(sys.stdin).get("data", []):
        mid = m.get("id", "")
        if mid: print(mid)
except Exception:
    pass' || true)"
      return 0
    fi
  done
  return 1
}

kimi_pick_model() {  # 默认模型偏好: kimi-k3 → kimi-k2.6 → 账号列表首个; KIMI_MODEL 显式指定优先
  local want="${KIMI_MODEL:-}"
  if [[ -z "$want" ]]; then
    local cand
    for cand in kimi-k3 kimi-k2.6; do
      if printf '%s\n' "$KIMI_MODELS" | grep -qx "$cand"; then want="$cand"; break; fi
    done
    if [[ -z "$want" ]]; then want="$(printf '%s\n' "$KIMI_MODELS" | head -1)"; fi
  fi
  echo "$want"
}

# ---------- 探针辅助(同 verify_all.sh 的分层验证语义) ----------

chat_reason_field() {  # $1=base $2=model → reasoning_content | reasoning | 空(思考未上线)
  local body
  body="{\"model\":\"$2\",\"messages\":[{\"role\":\"user\",\"content\":\"1+1=? 只回答数字\"}],\"max_tokens\":64,\"temperature\":0}"
  curl -fsS --max-time 60 "$1/chat/completions" \
       -H 'Content-Type: application/json' -d "$body" 2>/dev/null | python3 -c '
import sys, json
try:
    msg = json.load(sys.stdin)["choices"][0]["message"]
    for f in ("reasoning_content", "reasoning"):
        if (msg.get(f) or "").strip():
            print(f); break
except Exception:
    pass' 2>/dev/null || true
}

chat_tool_test() {  # $1=base $2=model → "tool:<name> <args>" | 空(无结构化工具调用)
  local body
  body="{\"model\":\"$2\",\"messages\":[{\"role\":\"user\",\"content\":\"计算 3+4,必须调用工具\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"calculator\",\"description\":\"计算算术表达式\",\"parameters\":{\"type\":\"object\",\"properties\":{\"expr\":{\"type\":\"string\",\"description\":\"如 3+4\"}},\"required\":[\"expr\"]}}}],\"tool_choice\":\"auto\",\"max_tokens\":400,\"temperature\":0}"
  curl -fsS --max-time 90 "$1/chat/completions" \
       -H 'Content-Type: application/json' -d "$body" 2>/dev/null | python3 -c '
import sys, json
try:
    tc = json.load(sys.stdin)["choices"][0]["message"].get("tool_calls")
    if tc:
        print("tool:" + tc[0]["function"]["name"] + " " + tc[0]["function"]["arguments"])
except Exception:
    pass' 2>/dev/null || true
}

# ---------- 子命令: check ----------

cmd_check() {
  say "======== GPU 服务器环境预检(报告性,不阻断) ========"

  local miss="" m
  for m in openai requests dotenv pypdf; do
    if ! python3 -c "import $m" 2>/dev/null; then miss="$miss $m"; fi
  done
  if [[ -z "$miss" ]]; then
    say "✅ Python 依赖齐: openai/requests/dotenv/pypdf"
  else
    warn "缺 Python 依赖:$miss → pip install openai requests python-dotenv pypdf"
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    say "✅ GPU: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1 || echo '?')"
  else
    warn "未检测到 nvidia-smi —— vLLM 路径不可用(Kimi 云端路径不受影响)"
  fi

  if python3 -c "import vllm" 2>/dev/null; then
    say "✅ vLLM: $(python3 -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo '?')"
  else
    warn "vLLM 未安装(仅 GPU 路径需要): pip install vllm"
  fi

  local head_rev
  head_rev="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"
  say "ℹ️  仓库 HEAD: $head_rev"
  if git -C "$REPO_ROOT" remote get-url fork >/dev/null 2>&1; then
    git -C "$REPO_ROOT" fetch fork -q 2>/dev/null || true
    local lf rf
    lf="$(git -C "$REPO_ROOT" rev-parse main 2>/dev/null || true)"
    rf="$(git -C "$REPO_ROOT" rev-parse fork/main 2>/dev/null || true)"
    if [[ -n "$lf" && "$lf" == "$rf" ]]; then
      say "✅ git: main == fork/main == $head_rev"
    else
      warn "git: main($lf) 与 fork/main($rf) 不一致 → git pull 同步后再跑实验"
    fi
  else
    say "ℹ️  无 fork 远端,跳过对齐检查"
  fi

  local dirty
  dirty="$(git -C "$REPO_ROOT" status --short 2>/dev/null | grep -v '^??' | head -3 || true)"
  if [[ -n "$dirty" ]]; then
    warn "有未提交改动(不影响实验,但结果不可追溯):"
    printf '%s\n' "$dirty" | sed 's/^/      /'
  fi

  local key; key="$(env_key)"
  if [[ -n "$key" ]]; then
    if kimi_detect "$key"; then
      say "✅ Kimi key 有效: 平台 $KIMI_BASE, 账号模型: $(echo "$KIMI_MODELS" | tr '\n' ' ')"
      local mname
      mname="$(grep -E '^MODEL_NAME=' "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
      if [[ -n "$mname" ]] && ! printf '%s\n' "$KIMI_MODELS" | grep -qx "$mname"; then
        warn ".env MODEL_NAME=$mname 不在该账号可用列表(keycheck 会拦截)"
        warn "  → 换模型重配: KIMI_MODEL=<列表内模型> $0 kimi"
      fi
    else
      warn "Kimi key 被两平台拒绝(401): 核对 key 完整性;注意 moonshot.cn 与 .ai 账号不互通"
    fi
  else
    say "⚪ 未配置 Kimi key(Kimi 云端路径跳过) → $0 kimi <key>"
  fi

  if command -v df >/dev/null 2>&1; then
    local avail
    avail="$(df -PG ~/.cache/huggingface 2>/dev/null | tail -1 | awk '{print $4}' || true)"
    if [[ -n "$avail" ]]; then
      if (( avail < 20 * 1024 * 1024 )); then
        warn "HF 缓存分区仅剩 $(( avail / 1024 / 1024 ))GB(<20GB),下载模型可能失败"
      else
        say "✅ 磁盘: HF 缓存分区可用 $(( avail / 1024 / 1024 ))GB"
      fi
    fi
  fi

  say ""
  say "建议路径: $0 kimi <key>   (云端对照)"
  say "     或:  $0 serve → $0 probe → $0 keycheck → $0 five   (GPU 路径,计划阶段 0→1→2)"
}

# ---------- 子命令: kimi ----------

cmd_kimi() {
  local key="" source="arg"
  if [[ -n "${1:-}" ]]; then
    key="$1"
  else
    key="$(env_key)"
    if [[ -n "$key" ]]; then
      source="env/.env"
    elif [[ -t 0 ]]; then
      read -rsp "粘贴 MOONSHOT_API_KEY(输入不回显): " key || true; echo
      source="input"
    else
      die "未提供 key 且 stdin 非交互。用法: $0 kimi <key>(或先 export MOONSHOT_API_KEY)"
    fi
  fi
  [[ -n "$key" ]] || die "未提供 key。用法: $0 kimi <key>"

  say "探测 Kimi 平台(国内站 .cn → 国际站 .ai)…"
  if ! kimi_detect "$key"; then
    die "两平台 /v1/models 均被拒。排查: ① key 是否复制完整 ② 是否 Moonshot key ③ 手动看原始响应: curl -s https://api.moonshot.ai/v1/models -H 'Authorization: Bearer <key>'"
  fi
  case "$KIMI_BASE" in
    *moonshot.cn*) say "✅ 平台: 国内站 api.moonshot.cn(仓库默认端点,无需覆盖)" ;;
    *moonshot.ai*) say "✅ 平台: 国际站 api.moonshot.ai → 将写入 KIMI_BASE_URL 覆盖默认 .cn 端点(两站账号不互通,这就是裸配 401 的根因)" ;;
  esac
  [[ -n "$KIMI_MODELS" ]] || die "平台连通但未取得模型列表(异常响应),中止"
  say "   账号可用模型: $(echo "$KIMI_MODELS" | tr '\n' ' ')"

  local model; model="$(kimi_pick_model)"
  if ! printf '%s\n' "$KIMI_MODELS" | grep -qx "$model"; then
    warn "模型 $model 不在该账号可用列表"
    if [[ "${FORCE:-0}" != "1" ]]; then
      die "改用: KIMI_MODEL=<列表内模型> $0 kimi  (或 FORCE=1 强制,实验可能 400)"
    fi
  fi
  say "   采用模型: $model"

  if [[ "$DRY_RUN" == "1" ]]; then
    say "[dry-run] 将重写 $ENV_FILE 受管块(并清除块外 Moonshot 散行):"
    {
      echo "$MARK_BEGIN"
      echo "LLM_PROVIDER=kimi"
      echo "MOONSHOT_API_KEY=<已打码>"
      echo "KIMI_BASE_URL=$KIMI_BASE"
      echo "MODEL_NAME=$model"
      echo "$MARK_END"
    } | sed -E 's/^(MOONSHOT_API_KEY)=.*/\1=<已打码>/'
    return 0
  fi

  # 本脚本全面接管 Moonshot 配置: 清旧块 → 清块外 Moonshot 散行(key/URL,含轮换前的旧值) → 写新块
  strip_managed_block
  grep -vE '^(MOONSHOT_API_KEY|KIMI_API_KEY|KIMI_BASE_URL)=' "$ENV_FILE" > "$ENV_FILE.tmp" || true
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  {
    echo "$MARK_BEGIN"
    echo "LLM_PROVIDER=kimi"
    echo "MOONSHOT_API_KEY=$key"
    echo "KIMI_BASE_URL=$KIMI_BASE"
    echo "MODEL_NAME=$model"
    echo "$MARK_END"
  } >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  say ""
  say "已写入 $ENV_FILE (受管块,key 打码;来源: $source):"
  show_env_block
  say ""
  say "下一步: $0 keycheck        # 单臂快测(阶段1)"
  say "        $0 five            # canonical 五臂(阶段2)"
}

# ---------- 子命令: serve ----------

cmd_serve() {
  if curl -fsS --max-time 2 "http://localhost:$PORT/v1/models" >/dev/null 2>&1; then
    say "vLLM 已在端口 $PORT 运行:"
    json_models "http://localhost:$PORT/v1" | sed 's/^/  - /'
    say "如需重启: 先 pkill -f 'vllm serve' 再运行本脚本"
    return 0
  fi

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    die "未检测到 nvidia-smi —— 无 GPU 时走云端路径: $0 kimi <key>"
  fi
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true
  if ! python3 -c "import vllm" 2>/dev/null; then
    die "vLLM 未安装: pip install vllm (建议 Python 3.10+ 虚拟环境)"
  fi

  local model="${1:-}"
  if [[ $# -gt 0 ]]; then shift; fi
  if [[ -z "$model" ]]; then
    say "未指定模型,从 HuggingFace 缓存发现候选:"
    local HF_HUB="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"
    local -a CANDS=()
    mapfile -t CANDS < <(ls -1 "$HF_HUB" 2>/dev/null | grep '^models--' \
      | sed 's#^models--##; s#--#/#' | sort || true)
    if [[ ${#CANDS[@]} -eq 0 ]]; then
      say "  (缓存为空)请指定模型,例如:"
      say "    $0 serve Qwen/Qwen3.5-9B     # 首次运行会自动下载"
      say "    $0 serve /path/to/local-model-dir"
      exit 1
    fi
    printf '  %s\n' "${CANDS[@]}"
    model="$(printf '%s\n' "${CANDS[@]}" | grep -i qwen | head -1 || true)"
    if [[ -z "$model" ]]; then model="${CANDS[0]}"; fi
    say ">>> 自动选择: $model (可 Ctrl+C 中止后手动指定)"
    sleep 3
  fi

  if [[ -z "$SERVED_NAME" ]]; then
    SERVED_NAME="$(basename "$model")"
    SERVED_NAME="${SERVED_NAME%%.*}"
  fi

  local -a rp=()
  if [[ -n "$REASONING_PARSER" ]]; then
    rp=(--reasoning-parser "$REASONING_PARSER")
  fi

  say ""
  say "启动 vLLM: model=$model  port=$PORT  tool_parser=$PARSER  reasoning_parser=${REASONING_PARSER:-<无>}  gpu_util=$GPU_UTIL  maxlen=$MAXLEN  served_name=$SERVED_NAME"
  say "两个必开项: --enable-auto-tool-choice(消融不失真) + --reasoning-parser(思考不混入 content)"
  say ""
  say "启动完成后另开终端执行:"
  say "  $0 probe $SERVED_NAME                            # 三探针(工具/思考解析验证)"
  say "  docs/setup/select_backend.sh vllm $SERVED_NAME   # 写 .env 切到本地后端"
  say "  $0 keycheck ollama $SERVED_NAME                  # 单臂快测(阶段1)"
  say ""
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] vllm serve $model --host 0.0.0.0 --port $PORT --served-model-name $SERVED_NAME --enable-auto-tool-choice --tool-call-parser $PARSER ${rp[*]:-} --gpu-memory-utilization $GPU_UTIL --max-model-len $MAXLEN ${*:-(无附加参数)}"
    return 0
  fi
  exec vllm serve "$model" \
    --host 0.0.0.0 --port "$PORT" \
    --served-model-name "$SERVED_NAME" \
    --enable-auto-tool-choice --tool-call-parser "$PARSER" \
    ${rp[@]+"${rp[@]}"} \
    --gpu-memory-utilization "$GPU_UTIL" --max-model-len "$MAXLEN" \
    "$@"
}

# ---------- 子命令: probe ----------

cmd_probe() {
  local base="http://localhost:$PORT/v1"
  local model="${2:-}"
  if [[ -n "${1:-}" && "${1:-}" != http* ]]; then
    model="$1"          # 第一参数非 URL → 按模型名理解(probe <model>)
  elif [[ -n "${1:-}" ]]; then
    base="$1"
  fi
  if [[ -z "$model" ]]; then
    model="$(grep -E '^MODEL_NAME=' "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  fi
  say "======== 三探针: $base ========"

  local models; models="$(json_models "$base")"
  if [[ -z "$models" ]]; then
    die "探针① 失败: /v1/models 不可达 → 确认服务已起、地址含 /v1 后缀、防火墙放行"
  fi
  say "✅ 探针① 模型在位: $(echo "$models" | tr '\n' ' ')"
  if [[ -n "$model" ]] && ! printf '%s\n' "$models" | grep -qx "$model"; then
    warn "期望模型 '$model' 不在列表 → 实验的 MODEL_NAME 必须与 --served-model-name 完全一致"
  fi
  if [[ -z "$model" ]]; then model="$(echo "$models" | head -1)"; fi

  local reason; reason="$(chat_reason_field "$base" "$model")"
  case "$reason" in
    reasoning_content) say "✅ 探针② 思考上线: vLLM 风格 reasoning_content(harness 双字段都认)" ;;
    reasoning)         say "✅ 探针② 思考上线: Ollama 风格 reasoning" ;;
    *)                 warn "探针② 未看到思考字段 → vLLM 补 --reasoning-parser qwen3 重启,否则 no_reasoning 臂合同检查失败"
  esac

  local tool; tool="$(chat_tool_test "$base" "$model")"
  if [[ "$tool" == tool:* ]]; then
    say "✅ 探针③ 结构化 tool_calls: $tool"
  else
    warn "探针③ 无结构化 tool_calls → vLLM 补 --enable-auto-tool-choice --tool-call-parser hermes 重启,否则所有臂的工具调用静默失效、消融全部失真"
  fi

  say ""
  local hint_provider
  hint_provider="$(sed -n '/local-llm-backend (managed/,/local-llm-backend <<</p' "$ENV_FILE" 2>/dev/null | grep -E '^LLM_PROVIDER=' | tail -1 | cut -d= -f2- || true)"
  if [[ -z "$hint_provider" ]]; then hint_provider="ollama"; fi
  say "探针通过后: $0 keycheck $hint_provider $model   # 单臂快测(阶段1)"
}

# ---------- 子命令: keycheck / five ----------

resolve_target() {  # $1=provider(可空) $2=model(可空) → 设置 PROVIDER/MODEL
  PROVIDER="${1:-}"
  MODEL="${2:-}"
  if [[ -z "$PROVIDER" || -z "$MODEL" ]]; then
    local bp bm
    bp="$(sed -n '/local-llm-backend (managed/,/local-llm-backend <<</p' "$ENV_FILE" 2>/dev/null | grep -E '^LLM_PROVIDER=' | tail -1 | cut -d= -f2- || true)"
    bm="$(sed -n '/local-llm-backend (managed/,/local-llm-backend <<</p' "$ENV_FILE" 2>/dev/null | grep -E '^MODEL_NAME=' | tail -1 | cut -d= -f2- || true)"
    if [[ -z "$PROVIDER" ]]; then
      if [[ -n "$bp" ]]; then PROVIDER="$bp"
      else die "未确定 provider → 先执行 $0 kimi <key> 或 docs/setup/select_backend.sh,或显式传参: $0 <子命令> <provider> <model>"
      fi
    fi
    if [[ -z "$MODEL" ]]; then
      if [[ -n "$bm" ]]; then MODEL="$bm"
      elif [[ "$PROVIDER" == "kimi" ]]; then
        die "kimi 必须显式模型(registry 默认 kimi-k3 常不在账号列表) → KIMI_MODEL=<模型> $0 kimi,或 $0 <子命令> kimi <model>"
      fi
    fi
  fi
  if [[ "$PROVIDER" == "kimi" && -n "$MODEL" && "${FORCE:-0}" != "1" && "$DRY_RUN" != "1" ]]; then
    local key; key="$(env_key)"
    if [[ -n "$key" ]] && kimi_detect "$key"; then
      if ! printf '%s\n' "$KIMI_MODELS" | grep -qx "$MODEL"; then
        die "模型 $MODEL 不在该账号可用列表(仅: $(echo "$KIMI_MODELS" | tr '\n' ' ')) → 改用列表内模型,或 FORCE=1 强制"
      fi
    fi
  fi
}

run_experiment() {  # $1=kind: keycheck|five
  local kind="$1"
  local outdir
  if [[ "$kind" == "keycheck" ]]; then outdir="validation/probes_gpu_$(ts)"; else outdir="validation/real_$(ts)"; fi

  local -a cmd=(python3 run_experiment_1_1.py --provider "$PROVIDER" --task guarded --hidden-result empty --max-iterations 5 --output-dir "$outdir")
  if [[ "$kind" == "keycheck" ]]; then cmd+=(--modes full); fi
  if [[ -n "$MODEL" ]]; then cmd+=(--model "$MODEL"); fi

  say ">>> cd chapter1/context && ${cmd[*]}"
  if [[ "$DRY_RUN" == "1" ]]; then return 0; fi

  local rc=0
  ( cd "$CTX_DIR" && "${cmd[@]}" ) || rc=$?
  say ""
  if [[ "$kind" == "keycheck" ]]; then
    if [[ "$rc" == "0" ]]; then
      say "✅ 单臂完成(exit 0)。判读 evidence.json 三件事: ①每轮 tools 在位 ②reasoning* 非空 ③tool_calls 与观测配对"
      say "   下一步: $0 five"
    else
      say "❌ 单臂未通过(exit $rc)。常见: 401=key/平台不互通(见 kimi 子命令) | 429=余额不足 | 404/连接=端点或 --served-model-name 不对 | 400 invalid temperature=仓库过旧(kimi-k2.x 仅允许 temperature=1),git pull 后重跑"
      say "   证据已落盘 $outdir/evidence.json,api_turns[].error 有原始报错"
    fi
  else
    if [[ "$rc" == "0" ]]; then
      say "✅ 五臂完成且已晋升 latest.json(exit 0)"
      say "   复核: python3 docs/experiments/verify_chapter1_experiments.py"
      say "   对照: 与 Ollama canonical(real_20261025T070721Z) 填计划文档阶段 2 的对照表"
    else
      say "❌ 五臂未晋升(exit $rc)。exact_five_arms_present=true 但 accepted=False 多为合同 fail-closed,判读见 docs/experiments/2026-10-25-实验1-1全五臂真跑判读.md"
    fi
  fi
  return "$rc"
}

cmd_keycheck() {
  resolve_target "${1:-}" "${2:-}"
  say "单臂快测: provider=$PROVIDER model=${MODEL:-<registry默认>} task=guarded hidden=empty"
  run_experiment keycheck
}

cmd_five() {
  resolve_target "${1:-}" "${2:-}"
  say "canonical 五臂: provider=$PROVIDER model=${MODEL:-<registry默认>} task=guarded hidden=empty"
  run_experiment five
}

# ---------- 帮助与分发 ----------

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | grep -E '^#( |$)' | sed 's/^# \{0,1\}//'
}

cd "$REPO_ROOT"
case "${1:-}" in
  check)    cmd_check ;;
  kimi)     shift || true; cmd_kimi "${1:-}" ;;
  serve)    shift || true; cmd_serve "$@" ;;
  probe)    shift || true; cmd_probe "${1:-}" "${2:-}" ;;
  keycheck) shift || true; cmd_keycheck "${1:-}" "${2:-}" ;;
  five)     shift || true; cmd_five "${1:-}" "${2:-}" ;;
  ""|-h|--help|help) usage ;;
  *) die "未知子命令: $1 (可用: check | kimi | serve | probe | keycheck | five)" ;;
esac
