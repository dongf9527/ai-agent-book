#!/usr/bin/env bash
# select_backend.sh —— 探测本地 LLM 后端并写入实验 .env（自动/手工双模式）
#
# 用法:
#   ./select_backend.sh list               # 只探测并列出各后端可用模型，不写 .env
#   ./select_backend.sh                    # 自动: 按 PRIORITY 顺序选第一个存活后端
#   ./select_backend.sh vllm [MODEL]       # 手工: 指定 vLLM (WSL, :8000)
#   ./select_backend.sh ollama-wsl [MODEL] # 手工: WSL 内 Ollama (:11434)
#   ./select_backend.sh ollama-win [MODEL] # 手工: Windows 宿主机 Ollama
#
# 写入位置: chapter1/context/.env 的受管块(可重复执行,幂等覆盖)
# 原理: 实验的 ollama provider 免 key、OpenAI 兼容,只需 OLLAMA_BASE_URL 指向任一后端
#       (证据链见 docs/2026-10-25-本地vLLM-Qwen接入指南.md 第二节)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$REPO_ROOT/chapter1/context/.env"
MARK_BEGIN="# >>> local-llm-backend (managed by select_backend.sh) >>>"
MARK_END="# <<< local-llm-backend <<<"
PRIORITY="${PRIORITY:-vllm,ollama-wsl,ollama-win}"

# ---------- 工具函数 ----------

json_models() {  # $1=base_url(含/v1) → 每行一个模型 id
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

server_version() {  # $1=base_url(含/v1) → 后端服务版本号(空=未知)
  local body
  body="$(curl -fsS --max-time 2 "${1%/v1}/api/version" 2>/dev/null || true)"          # Ollama
  [[ -z "$body" ]] && body="$(curl -fsS --max-time 2 "${1%/v1}/version" 2>/dev/null || true)"  # vLLM
  [[ -z "$body" ]] && return 0
  printf '%s' "$body" | python3 -c '
import sys, json
try: print(json.load(sys.stdin).get("version", ""))
except Exception: pass'
}

win_host_ip() {  # WSL → Windows 宿主机可达 IP(空串=不可达)
  # 镜像网络模式(Win11 22H2+): localhost 即宿主机
  if command -v wslinfo >/dev/null 2>&1 \
     && [[ "$(wslinfo --networking-mode 2>/dev/null)" == "mirrored" ]]; then
    echo "127.0.0.1"; return
  fi
  # NAT 模式: 默认网关即 Windows 宿主 vEthernet 适配器
  local gw ns
  gw="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
  if [[ -n "$gw" ]] && curl -fsS --max-time 2 "http://$gw:11434/v1/models" >/dev/null 2>&1; then
    echo "$gw"; return
  fi
  # 兜底: resolv.conf 的 nameserver
  ns="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
  if [[ -n "$ns" ]] && curl -fsS --max-time 2 "http://$ns:11434/v1/models" >/dev/null 2>&1; then
    echo "$ns"; return
  fi
  echo ""
}

# ---------- 探测 ----------

declare -A URLS MODELS VERSIONS
URLS[vllm]="http://localhost:8000/v1"
URLS[ollama-wsl]="http://localhost:11434/v1"
WIN_IP="$(win_host_ip)"
URLS[ollama-win]="http://${WIN_IP:-unreachable}:11434/v1"

probe_all() {
  local k
  for k in vllm ollama-wsl ollama-win; do
    MODELS[$k]="$(json_models "${URLS[$k]}")"
    VERSIONS[$k]=""
    if [[ -n "${MODELS[$k]}" ]]; then    # if 形式: 不可达端点不能让 set -e 中断
      VERSIONS[$k]="$(server_version "${URLS[$k]}")"
    fi
  done
}

show_table() {
  local k v
  echo "=============== 本地 LLM 后端探测结果 ==============="
  for k in vllm ollama-wsl ollama-win; do
    v="${VERSIONS[$k]:-}"
    if [[ "${MODELS[$k]}" != "" ]]; then
      echo "[$k] 存活    ${URLS[$k]}${v:+  server v$v}"
      echo "${MODELS[$k]}" | sed 's/^/    - /'
    else
      echo "[$k] 不可达  ${URLS[$k]}"
    fi
  done
  echo "======================================================"
}

# ---------- 写入 .env ----------

write_env() {  # $1=backend key  $2=model id
  local backend="$1" model="$2" url="${URLS[$1]}"
  if [[ -z "$model" ]]; then
    model="qwen3:8b"   # agentbook ollama provider 的 default_model,兜底
    echo "警告: 未能从后端获取模型列表,MODEL_NAME 暂用 $model(请核对 --served-model-name)" >&2
  fi
  mkdir -p "$(dirname "$ENV_FILE")"
  [[ -f "$ENV_FILE" ]] || cp "$(dirname "$ENV_FILE")/env.example" "$ENV_FILE" 2>/dev/null || touch "$ENV_FILE"
  # 删除旧受管块(若有),再追加新块 —— 幂等
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" \
      'index($0,b)>0 {inblk=1} !inblk {print} inblk && index($0,e)>0 {inblk=0}' \
      "$ENV_FILE" > "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  cat >> "$ENV_FILE" <<EOF
$MARK_BEGIN
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=$url
OLLAMA_API_KEY=local-ignored
MODEL_NAME=$model
$MARK_END
EOF
  echo
  echo "已写入 $ENV_FILE :"
  grep -A5 "$MARK_BEGIN" "$ENV_FILE" | head -6
  echo
  echo "验证: cd chapter1/context && python main.py   (或 run_experiment_1_1.py)"
}

# ---------- 主流程 ----------

MODE="${1:-auto}"
probe_all

case "$MODE" in
  list)
    show_table; exit 0 ;;
  vllm|ollama-wsl|ollama-win)
    MODEL="${2:-${MODELS[$MODE]}}"
    [[ -z "${MODELS[$MODE]}" ]] && echo "警告: [$MODE] 探测不到服务" >&2
    show_table; write_env "$MODE" "$MODEL" ;;
  auto)
    show_table
    SELECTED=""
    IFS=',' read -ra ORDER <<< "$PRIORITY"
    for k in "${ORDER[@]}"; do
      if [[ "${MODELS[$k]:-}" != "" ]]; then SELECTED="$k"; break; fi
    done
    if [[ -z "$SELECTED" ]]; then
      echo "没有任何后端存活。请先执行其一:" >&2
      echo "  WSL:      docs/local-setup/serve_vllm_wsl.sh" >&2
      echo "  Windows:  docs/local-setup/setup_ollama_windows.ps1" >&2
      exit 1
    fi
    echo ">>> 自动选择: $SELECTED (优先级 $PRIORITY)"
    write_env "$SELECTED" "$(echo "${MODELS[$SELECTED]}" | head -1)" ;;
  *)
    echo "未知参数: $MODE (可用: list | vllm | ollama-wsl | ollama-win)" >&2
    exit 1 ;;
esac
