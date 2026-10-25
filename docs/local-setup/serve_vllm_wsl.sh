#!/usr/bin/env bash
# serve_vllm_wsl.sh —— 在 WSL 中启动 vLLM OpenAI 兼容服务
#
# 内置 Agent 实验必需参数: --enable-auto-tool-choice --tool-call-parser hermes
# (消融实验依赖工具调用;Qwen2.5/Qwen3 系列在 vLLM 中必须显式开启工具解析)
#
# 用法:
#   ./serve_vllm_wsl.sh                                  # 自动发现 HF 缓存中的 Qwen 模型
#   ./serve_vllm_wsl.sh Qwen/Qwen2.5-7B-Instruct         # 指定 HF 模型 id
#   ./serve_vllm_wsl.sh /mnt/d/models/qwen2.5-7b         # 指定本地模型目录
#
# 可调环境变量:
#   PORT=8000  PARSER=hermes  GPU_UTIL=0.85  MAXLEN=8192  SERVED_NAME=<别名>
set -euo pipefail

PORT="${PORT:-8000}"
PARSER="${PARSER:-hermes}"
GPU_UTIL="${GPU_UTIL:-0.85}"
MAXLEN="${MAXLEN:-8192}"
MODEL="${1:-}"

# 0) 已在运行则直接退出(幂等)
if curl -fsS --max-time 2 "http://localhost:$PORT/v1/models" >/dev/null 2>&1; then
  echo "vLLM 已在端口 $PORT 运行:"
  curl -fsS "http://localhost:$PORT/v1/models" | python3 -c '
import sys, json
for m in json.load(sys.stdin).get("data", []): print("  -", m.get("id"))'
  echo "如需重启: 先 pkill -f 'vllm serve' 再运行本脚本"
  exit 0
fi

# 1) 预检: GPU / vLLM
command -v nvidia-smi >/dev/null 2>&1 || {
  echo "错误: 未检测到 nvidia-smi。确认 WSL 已装 NVIDIA 驱动(Windows 侧安装,WSL 内直接可用)。"; exit 1; }
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true
python3 -c "import vllm" 2>/dev/null || {
  echo "vLLM 未安装。执行: pip install vllm  (建议 Python 3.10+ 虚拟环境)"; exit 1; }

# 2) 模型发现/校验
if [[ -z "$MODEL" ]]; then
  echo "未指定模型,从 HuggingFace 缓存发现候选:"
  HF_HUB=~/.cache/huggingface/hub
  mapfile -t CANDS < <(ls -1 "$HF_HUB" 2>/dev/null | grep '^models--' \
    | sed 's#^models--##; s#--#/#' | sort)
  if [[ ${#CANDS[@]} -eq 0 ]]; then
    echo "  (缓存为空)请指定模型,例如:"
    echo "    $0 Qwen/Qwen2.5-7B-Instruct      # 首次运行会自动下载(~15GB)"
    echo "    $0 Qwen/Qwen3-8B"
    exit 1
  fi
  printf '  %s\n' "${CANDS[@]}"
  MODEL="$(printf '%s\n' "${CANDS[@]}" | grep -i qwen | head -1 || true)"
  [[ -z "$MODEL" ]] && MODEL="${CANDS[0]}"
  echo ">>> 自动选择: $MODEL (可 Ctrl+C 中止后手动指定)"
  sleep 3
fi

# 3) served-model-name: 默认取模型名尾段,便于 select_backend.sh 与 MODEL_NAME 对齐
if [[ -z "${SERVED_NAME:-}" ]]; then
  SERVED_NAME="$(basename "$MODEL")"
  SERVED_NAME="${SERVED_NAME%%.*}"   # 去掉如 .awq 等量化后缀
fi

echo
echo "启动 vLLM:  model=$MODEL  port=$PORT  parser=$PARSER  gpu_util=$GPU_UTIL  maxlen=$MAXLEN"
echo "启动后执行: docs/local-setup/select_backend.sh   # 自动写入实验 .env"
echo "提示: 若想让实验免配 MODEL_NAME,可改用 SERVED_NAME=qwen3:8b(provider 默认名)"
echo
exec vllm serve "$MODEL" \
  --host 0.0.0.0 --port "$PORT" \
  --served-model-name "$SERVED_NAME" \
  --enable-auto-tool-choice --tool-call-parser "$PARSER" \
  --gpu-memory-utilization "$GPU_UTIL" --max-model-len "$MAXLEN" \
  "$@"
