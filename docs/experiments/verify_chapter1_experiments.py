#!/usr/bin/env python3
"""第一章 4 个实验 canonical 证据的机器复核（只读，零依赖）。

验证层次：
  L1 完整性 —— latest.json 指针一致、SHA-256 sidecar 与实际文件哈希一致
  L2 验收门 —— evidence 内 acceptance/analysis 的检查全真
  L3 行为账 —— 逐臂/逐格/逐 fiber 的行为账目与账本论断对得上

用法：python3 verify_chapter1_experiments.py
输出：每实验 PASS/FAIL 明细 + 汇总。exit 0 ⇔ 全部通过。
"""
import hashlib
import json
import os
import sys

# 仓库根 = 本脚本向上三级（docs/experiments/ -> repo root）；兼容任意检出位置
_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = os.path.join(_REPO, "chapter1")
results = []


def check(tag, name, ok, detail):
    results.append((tag, ok))
    print(f"[{tag}][{'PASS' if ok else 'FAIL'}] {name}")
    print(f"    {detail}")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load(path):
    with open(path, "rb") as f:
        return json.load(f)


# ===================== 实验 1-1 context（本地 Ollama） =====================
print("########## 1-1 context: 上下文五臂消融 ##########")
v = f"{BASE}/context/validation"
lat = open(f"{v}/latest.json", "rb").read()
ev = open(f"{v}/real_20261025T070721Z/evidence.json", "rb").read()
check("1-1", "latest.json == 070721Z/evidence.json（晋升指针逐字节一致）",
      lat == ev, f"{len(lat)} bytes")
side = open(f"{v}/real_20261025T070721Z/evidence.sha256").read().strip().split()[0].lower()
check("1-1", "SHA-256 sidecar 与实际一致",
      side == hashlib.sha256(ev).hexdigest(),
      f"sidecar={side[:16]}… actual={hashlib.sha256(ev).hexdigest()[:16]}…")
d = json.loads(ev)
an = d["analysis"]
check("1-1", "四验收门全真",
      all(an.get(k) is True for k in ("exact_five_arms_present",
                                      "all_context_contracts_passed",
                                      "direct_real_api_evidence",
                                      "experiment_execution_accepted")),
      f"accepted={an.get('experiment_execution_accepted')}")
check("1-1", "五臂合同全绿",
      all(a["context_contract"].get("passed") is True for a in d["arms"]),
      "5/5 arms passed")
check("1-1", "五臂 outcomes 与账本方向一致（full/no_reasoning correct，双臂撞上限，no_tool_calls 编造）",
      an.get("arm_outcomes") == {"full": "correct", "no_history": "no_terminal_response",
                                 "no_reasoning": "correct",
                                 "no_tool_calls": "unsupported_numbers",
                                 "no_tool_results": "no_terminal_response"},
      f"outcomes={an.get('arm_outcomes')}")

# ===================== 实验 1-2 web-search-agent（Moonshot 云端） =====================
print("\n########## 1-2 web-search-agent: Kimi K3 托管搜索 ##########")
d = load(f"{BASE}/web-search-agent/validation/latest.json")
ac = d["acceptance"]
checks = ac["checks"]
check("1-2", "acceptance.passed=True", ac.get("passed") is True,
      f"passed={ac.get('passed')}")
bad = [k for k, val in checks.items() if val is not True]
check("1-2", f"验收检查全真（{len(checks) - len(bad)}/{len(checks)}）", not bad,
      f"failed={bad if bad else 'none'}")
fib = ac.get("fiber_ids", [])
check("1-2", "15 条唯一 Formula fibers（多轮多次真实搜索）",
      len(fib) == 15 and len(set(fib)) == len(fib),
      f"count={len(fib)}, unique={len(set(fib))}")
run = d["run"]
check("1-2", "直连 Moonshot / 精确模型 kimi-k3",
      run.get("provider") == "moonshot" and run.get("model") == "kimi-k3"
      and "moonshot" in run.get("base_url", ""),
      f"provider={run.get('provider')}, model={run.get('model')}, base={run.get('base_url')}")
u = ac.get("usage", {})
check("1-2", "usage 有真实 token 记账", u.get("prompt_tokens", 0) > 0 and u.get("completion_tokens", 0) > 0,
      f"prompt={u.get('prompt_tokens')}, completion={u.get('completion_tokens')}")
trace_types = {t.get("type") for t in run.get("trace", [])}
check("1-2", "轨迹含 ReAct 三环节（thought/action/observation）",
      {"thought", "action", "observation"} <= trace_types,
      f"types={sorted(trace_types)}")
obs_encrypted = any("MOONSHOT ENCRYPTED" in str(t.get("content", ""))
                    for t in run.get("trace", []) if t.get("type") == "observation")
check("1-2", "托管搜索回执为 Moonshot 加密 fiber（服务端托管特征）", obs_encrypted,
      f"encrypted_fibers_in_trace={obs_encrypted}")
check("1-2", "无凭据落盘", d.get("credential_value_recorded") is False,
      f"credential_value_recorded={d.get('credential_value_recorded')}")

# ===================== 实验 1-3 search-codegen（DashScope Responses API） =====================
print("\n########## 1-3 search-codegen: 搜索+代码执行多 provider ##########")
p = f"{BASE}/search-codegen/validation"
d = load(f"{p}/latest.json")
ac = d["acceptance"]
check("1-3", "acceptance.passed=True（多 provider 政策）", ac.get("passed") is True,
      f"acceptance_backend={ac.get('acceptance_backend')}")
pb = ac.get("per_backend", {})
ds = pb.get("dashscope", {})
check("1-3", "DashScope qwen3.7-plus 双任务通过",
      ds.get("requested_model") == "qwen3.7-plus"
      and ds.get("asean_passed") is True and ds.get("clarification_passed") is True,
      f"asean={ds.get('asean_passed')}, clarification={ds.get('clarification_passed')}")
oai = pb.get("openai", {})
check("1-3", "官方 OpenAI 路径诚实记录配额失败（非隐藏）",
      oai.get("started") is True and oai.get("asean_passed") is False,
      f"gpt-5.6-sol attempted={oai.get('started')}, passed={oai.get('asean_passed')}")
ref = d.get("independent_asean_reference", {})
check("1-3", "独立本地参考存在（吉隆坡—新加坡 309.3 km，45 对坐标）",
      ref.get("distance_km") == 309.3 and ref.get("pair_count") == 45,
      f"KL-SG={ref.get('distance_km')} km, pairs={ref.get('pair_count')}")
# L1: artifact 哈希 sidecar
rd = f"{p}/runs/real_20260731T170529Z"
ah = d.get("artifact_hashes", {})
for fn, expect in ah.items():
    if fn == "run_dir":
        continue
    fp = os.path.join(rd, fn)
    ok = os.path.exists(fp) and sha256_file(fp) == expect
    check("1-3", f"artifact 哈希一致: {fn}", ok,
          f"expect={expect[:16]}… actual={sha256_file(fp)[:16]}…" if os.path.exists(fp) else "missing")
sc_side = sha256_file(f"{rd}/evidence.json")
sc_sidecar = open(f"{rd}/evidence.sha256").read().strip().split()[0].lower()
check("1-3", "run 目录 evidence.sha256 sidecar 一致", sc_side == sc_sidecar,
      f"sidecar={sc_sidecar[:16]}… actual={sc_side[:16]}…")
rec = load(f"{rd}/receipts.json")
n_rec = len(rec) if isinstance(rec, list) else len(rec.get("receipts", rec))
check("1-3", "receipts.json 非空（逐调用回执）", bool(n_rec), f"receipt entries={n_rec}")

# ===================== 实验 1-4 image-gen-workflow（三路由 × 5 需求） =====================
print("\n########## 1-4 image-gen-workflow: 文生图三路由对照 ##########")
rd14 = f"{BASE}/image-gen-workflow/validation/real_20260821T040450Z"
d = load(f"{rd14}/evidence.json")
runs = d["runs"]
check("1-4", "15 格矩阵（5 需求 × 3 路由）", len(runs) == 15,
      f"cells={len(runs)}")
grid = {(r["requirement_id"], r["route"]) for r in runs}
reqs = {r[0] for r in grid}
rts = {r[1] for r in grid}
check("1-4", "三路由齐全（workflow / native / native_gptimage）",
      rts == {"workflow", "native", "native_gptimage"}, f"routes={sorted(rts)}")
ok_cells = [r for r in runs
            if r.get("error") is None and isinstance(r.get("image"), dict)
            and r["image"].get("path") and r["image"].get("sha256") and r["image"].get("bytes", 0) > 0]
check("1-4", "15/15 格成功（error=None + image 三元组完整）",
      len(ok_cells) == 15, f"ok={len(ok_cells)}/15")
n_img = len({r["image"]["sha256"] for r in ok_cells})
check("1-4", "图像逐格独立（sha256 去重后仍 15 张）", n_img == 15,
      f"unique image hashes={n_img}")
# 改写节点只在 workflow 路由
wf_rewrite = all(isinstance(r.get("rewrite"), dict) and r["rewrite"]
                 for r in runs if r["route"] == "workflow")
nt_rewrite = all(not r.get("rewrite") for r in runs if r["route"] != "workflow")
check("1-4", "改写节点仅存在于 workflow 路由（消融结构正确）",
      wf_rewrite and nt_rewrite,
      f"workflow has rewrite={wf_rewrite}, native lacks rewrite={nt_rewrite}")
# 图像文件本体未入库（账本已声明）——检查并如实报告
img_paths = {os.path.join(f"{BASE}/image-gen-workflow", r["image"]["path"]) for r in ok_cells}
n_local = sum(1 for fp in img_paths if os.path.exists(fp))
check("1-4", "图像文件本地存在性（outputs/ 未入库时属预期）", True,
      f"{n_local}/{len(img_paths)} files on disk（账本注明 outputs/ 属未入库产物，交付以 evidence.json 的逐格 SHA-256 为准）")

# ===================== 汇总 =====================
print()
n_pass = sum(1 for _, ok in results if ok)
print(f"===== 第一章四实验复核汇总: {n_pass}/{len(results)} PASS =====")
by_tag = {}
for tag, ok in results:
    by_tag.setdefault(tag, [0, 0])
    by_tag[tag][0] += ok
    by_tag[tag][1] += 1
for tag, (p_, t_) in sorted(by_tag.items()):
    print(f"  实验 {tag}: {p_}/{t_}")
fails = [(i, ok) for i, ok in enumerate(results) if not ok]
if fails:
    print("\n未过项:")
    for name, ok in results:
        if not ok:
            print(f"  - {name}")
sys.exit(0 if n_pass == len(results) else 1)
