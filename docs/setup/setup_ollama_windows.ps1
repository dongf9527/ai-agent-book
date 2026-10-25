# setup_ollama_windows.ps1 —— Windows 宿主机 Ollama 配置(供 WSL 访问)
#
# 以管理员身份在 PowerShell 执行:
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\setup_ollama_windows.ps1                       # 默认拉取 qwen3:8b
#   .\setup_ollama_windows.ps1 -Models qwen3:8b,qwen2.5:7b-instruct
#
# 做四件事: ① 安装/检查 Ollama ② 监听 0.0.0.0(默认仅 127.0.0.1,WSL 连不进来)
#           ③ 防火墙放行 WSL 子网 ④ 拉取模型并自检,打印 WSL 侧连接地址
param([string[]]$Models = @("qwen3:8b"))
$ErrorActionPreference = "Stop"

# 0) 管理员检查(防火墙规则需要)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Warning "建议以管理员身份运行(步骤③需要)。继续尝试,失败处会提示。" }

# 1) 安装/检查 Ollama
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
  Write-Host ">>> 未安装 Ollama,经 winget 安装..."
  winget install --id Ollama.Ollama -e --accept-package-agreements --accept-source-agreements
  # 刷新当前会话 PATH
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [Environment]::GetEnvironmentVariable("Path", "User")
}
Write-Host ">>> Ollama 版本: $(ollama -v)"

# 2) 监听 0.0.0.0 —— 关键步骤
#    Windows 版 Ollama 默认仅绑定 127.0.0.1,WSL 发起的请求会被拒绝
[Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0:11434", "User")
$env:OLLAMA_HOST = "0.0.0.0:11434"   # 供本会话启动的进程继承
Write-Host ">>> 已设置 OLLAMA_HOST=0.0.0.0:11434 (用户级持久化)"

# 重启 Ollama 使新配置生效(托盘常驻进程 + 后台 serve 一并处理)
Get-Process | Where-Object { $_.ProcessName -like "*ollama*" } |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
Start-Sleep -Seconds 3
Write-Host ">>> Ollama 已重启并监听 0.0.0.0:11434"

# 3) 防火墙放行 WSL 发起的连接(仅限 WSL IP,不暴露到局域网)
$wslIp = ((wsl.exe hostname -I 2>$null | Out-String).Trim() -split "\s+")[0]
$remote = if ($wslIp) { $wslIp } else { "172.16.0.0/12" }   # 兜底: WSL NAT 常用段
if (-not (Get-NetFirewallRule -DisplayName "Ollama for WSL" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "Ollama for WSL" -Direction Inbound -Protocol TCP `
    -LocalPort 11434 -RemoteAddress $remote -Action Allow | Out-Null
  Write-Host ">>> 防火墙已放行来自 WSL($remote) 的 11434 端口"
} else {
  Write-Host ">>> 防火墙规则已存在,跳过"
}

# 4) 拉取模型并自检
foreach ($m in $Models) {
  Write-Host ">>> 拉取模型 $m (首次下载可能较大)..."
  ollama pull $m
}
Write-Host "`n>>> 自检 —— 本机 /v1/models 可用模型:"
(Invoke-RestMethod "http://localhost:11434/v1/models").data.id | ForEach-Object { Write-Host "    - $_" }

# 打印 WSL 侧应使用的连接地址
$hostIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.InterfaceAlias -like "vEthernet (WSL*" } |
           Select-Object -First 1).IPAddress
Write-Host "`n=============================================="
Write-Host "WSL 侧连接地址(写入选型脚本会自动探测,无需手工配置):"
if ($hostIp) { Write-Host "    NAT 模式:      http://$hostIp:11434/v1" }
Write-Host "    镜像网络模式:  http://localhost:11434/v1"
Write-Host "WSL 内手工验证: curl http://$hostIp`:11434/v1/models"
Write-Host "==============================================`n"
