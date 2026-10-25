#!/usr/bin/env bash
# verify_all.sh —— 本地 LLM 后端分层验证（WSL 侧运行）
#
# 验收分两级:
#   [问答级] /v1/models 可列出模型 + chat/completions 正常回话
#   [实验级] 上述通过 且 tool_calls 结构化返回正常 —— 消融实验的硬前提
#
# 用法:  ./verify_all.sh            # 全部检查
#        ./verify_all.sh --quick    # 跳过 chat/工具测试,只查端口与模型列表
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
QUICK="${1:-}"
PASS=0; FAIL=0; READY=""
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $1"; }
off()  { echo "  ⚪ $1"; }

json_models() {  # $1=base_url → 每行一个模型 id
  local body; body="$(curl -fsS --max-time 3 "$1/models" 2>/dev/null || true)"
  [[ -z "$body" ]] && return 1
  printf '%s' "$body" | python3 -c '
import sys, json
try:
    for m in json.load(sys.stdin).get("data", []):
        mid = m.get("id", "")
        if mid: print(mid)
except Exception: pass'
}

win_host_ip() {
  if command -v wslinfo >/dev/null 2>&1 \
     && [[ "$(wslinfo --networking-mode 2>/dev/null)" == "mirrored" ]]; then
    echo "127.0.0.1"; return
  fi
  local gw ns
  gw="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
  if [[ -n "$gw" ]] && json_models "http://$gw:11434/v1" >/dev/null 2>&1; then echo "$gw"; return; fi
  ns="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
  if [[ -n "$ns" ]] && json_models "http://$ns:11434/v1" >/dev/null 2>&1; then echo "$ns"; return; fi
  echo ""
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

chat_test() {  # $1=base  $2=model  $3=期望带工具(1/0) → 0=通过
  local base="$1" model="$2" want_tools="$3" body tools_json
  tools_json='{"type":"function","function":{"name":"calculator","description":"计算算术表达式","parameters":{"type":"object","properties":{"expr":{"type":"string","description":"如 3+4"}},"required":["expr"]}}}'
  if [[ "$want_tools" == "1" ]]; then
    body="{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"计算 3+4,必须调用工具\"}],\"tools\":[$tools_json],\"tool_choice\":\"auto\",\"max_tokens\":200,\"temperature\":0}"
  else
    body="{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"只回答数字: 1+1=?\"}],\"max_tokens\":16,\"temperature\":0}"
  fi
  curl -fsS --max-time 90 "$base/chat/completions" \
       -H 'Content-Type: application/json' -d "$body" 2>/dev/null | python3 -c '
import sys, json
d = json.load(sys.stdin)
msg = d["choices"][0]["message"]
tc = msg.get("tool_calls")
if tc:
    print("tool:" + tc[0]["function"]["name"] + " " + tc[0]["function"]["arguments"])
else:
    print("text:" + (msg.get("content") or "")[:40].replace("\n"," "))' 2>/dev/null
}

verify_backend() {  # $1=名称  $2=base_url
  local name="$1" base="$2" models model
  echo "―― [$name] $base"
  models="$(json_models "$base" 2>/dev/null)" || { off "$name 不可达(未部署或网络不通,若非目标后端可忽略)"; return 1; }
  local ver; ver="$(server_version "$base")"
  ok "服务存活${ver:+,server v$ver},模型: $(echo "$models" | head -3 | tr '\n' ' ')"
  [[ "$models" == "" ]] && { warn "$name 无模型,请 pull/serve 后重试"; return 1; }
  model="$(echo "$models" | head -1)"
  if [[ "$QUICK" == "--quick" ]]; then warn "--quick 模式跳过推理测试"; return 0; fi
  local chat; chat="$(chat_test "$base" "$model" 0)"
  if [[ "$chat" == text:* ]]; then ok "问答级通过: \"$chat\""
  else bad "问答级失败(见该后端日志)"; return 1; fi
  local tools; tools="$(chat_test "$base" "$model" 1)"
  if [[ "$tools" == tool:* ]]; then ok "实验级通过(结构化 tool_calls): $tools"; READY="$name"
  else bad "工具调用未返回 tool_calls —— 消融实验会失真"
       warn "vLLM: 补 --enable-auto-tool-choice --tool-call-parser hermes 重启"
       warn "Ollama: 确认模型支持工具(qwen3:8b / qwen2.5 系列均可)且版本较新"; fi
}

echo "======== ① 三个候选端点探测 ========"
WIN_IP="$(win_host_ip)"
verify_backend "vLLM(WSL)"       "http://localhost:8000/v1"    || true
verify_backend "Ollama(WSL)"     "http://localhost:11434/v1"   || true
verify_backend "Ollama(Windows)" "http://${WIN_IP:-unreachable}:11434/v1" || true

echo
echo "======== ② .env 受管块与 provider 解析 ========"
ENV_FILE="$REPO_ROOT/chapter1/context/.env"
if [[ ! -f "$ENV_FILE" ]] || ! grep -q "local-llm-backend" "$ENV_FILE"; then
  warn "尚未生成受管块 → 运行 docs/local-setup/select_backend.sh"
else
  ok ".env 受管块存在:"
  grep -A5 "local-llm-backend (managed" "$ENV_FILE" | tail -4 | sed 's/^/      /'
  # 按 load_dotenv 同样语义导出受管块,验证最终解析结果
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^(LLM_PROVIDER|OLLAMA_BASE_URL|OLLAMA_API_KEY|MODEL_NAME)$ ]] && export "$k=$v"
  done < <(sed -n '/local-llm-backend (managed/,/local-llm-backend <<</p' "$ENV_FILE" | grep '=')
  if ( cd "$REPO_ROOT" && python3 -c "
import sys; sys.path.insert(0, '.')
from agentbook.providers import resolve_backend
b = resolve_backend('ollama')
print('  ✅ provider 解析: base_url=%s | model=%s' % (b.base_url, b.model))
assert b.base_url.startswith('http'), 'base_url 异常'
" 2>/dev/null ); then PASS=$((PASS+1)); else bad "resolve_backend 解析失败(agentbook 不可达或 env 异常)"; fi
fi

echo
echo "======== ③ 实验级冒烟(可选,约 1 分钟) ========"
if [[ "$QUICK" != "--quick" ]]; then
  echo "  手动执行: cd chapter1/context && python main.py --mode single --provider ollama \\"
  echo "            --task '用计算器算 12*8 然后告诉我结果'"
fi

echo
echo "======== 结果: $PASS 通过 / $FAIL 失败 ========"
if [[ -n "$READY" ]]; then
  echo "✅ 实验级就绪后端: $READY。下一步: cd chapter1/context && python run_experiment_1_1.py"
  exit 0
fi
echo "❌ 没有后端达到实验级就绪。排障:"
echo "   Windows 侧(管理员 PowerShell):"
echo "     netstat -ano | findstr :11434            # 必须 0.0.0.0:11434"
echo "     Get-NetFirewallRule -DisplayName 'Ollama for WSL'"
echo "   WSL 侧:"
echo "     wslinfo --networking-mode                # nat→用网关IP / mirrored→用 localhost"
echo "     ip route show default                    # NAT 模式下网关 IP 即宿主机"
exit 1
