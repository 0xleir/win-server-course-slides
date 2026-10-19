# check15.ps1 — 第15课 远程管理工具（WinRM / PowerShell Remoting）：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check15.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson15" "第 15 课 · 远程管理工具"

Add-Task "任务1 · WinRM 服务与监听器"
$svc = Get-Service WinRM -EA SilentlyContinue
if($svc -and $svc.Status -eq "Running"){ Add-Item "WinRM 服务运行中" "PASS" "Running" "Running" }
else { Add-Item "WinRM 服务运行中" "FAIL" "Running" ($(if($svc){$svc.Status}else{"不存在"})) "Enable-PSRemoting -Force" }

# HTTP 5985 监听器
$httpPorts = @()
try {
  foreach($l in (Get-ChildItem WSMan:\localhost\Listener -EA Stop)){
    $props = Get-ChildItem ("WSMan:\localhost\Listener\" + $l.Name) -EA SilentlyContinue
    $t = ($props | Where-Object { $_.Name -eq "Transport" }).Value
    $p = ($props | Where-Object { $_.Name -eq "Port" }).Value
    if($t -eq "HTTP"){ $httpPorts += "$p" }
  }
} catch {}
if($httpPorts -contains "5985"){ Add-Item "WinRM HTTP 监听器（端口 5985）" "PASS" "HTTP:5985" ("HTTP:" + ($httpPorts -join ",")) }
else { Add-Item "WinRM HTTP 监听器（端口 5985）" "FAIL" "HTTP:5985" ($(if($httpPorts.Count){"HTTP:"+($httpPorts -join ",")}else{"无 HTTP 监听器"})) "Enable-PSRemoting -Force 会自动创建" }

# 防火墙放行 5985 入站
$fw = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -EA SilentlyContinue | ForEach-Object {
    $pf = $_ | Get-NetFirewallPortFilter -EA SilentlyContinue
    if($pf -and "$($pf.Protocol)" -eq "TCP" -and (("$($pf.LocalPort)") -split ',') -contains "5985"){ $_.DisplayName }
})
if($fw.Count -gt 0){ Add-Item "防火墙放行 5985 入站" "PASS" "有放行5985的入站规则" ($fw -join ", ") }
else { Add-Item "防火墙放行 5985 入站" "WARN" "有放行5985的入站规则" "未显式检出（可能在 WINRM-HTTP-In 组内）" "Enable-PSRemoting 会配好；或检查 Windows 远程管理(HTTP-In)规则" }

Add-Task "任务1 · TrustedHosts"
$th = ""
try { $th = "" + (Get-Item WSMan:\localhost\Client\TrustedHosts -EA Stop).Value } catch {}
if($th -match "10\.10\.10\.\*" -or $th -match "(^|,)\s*10\.10\.10\.10\s*(,|$)"){ Add-Item "TrustedHosts 已配置（含实验网段）" "PASS" "含 10.10.10.* 或 10.10.10.10" $th }
else { Add-Item "TrustedHosts 已配置（含实验网段）" "FAIL" "含 10.10.10.* 或 10.10.10.10" ($(if($th){$th}else{"(空)"})) 'Set-Item WSMan:\localhost\Client\TrustedHosts -Value "10.10.10.*" -Force' }

Add-Task "任务2 · PowerShell Remoting 可用"
# 本机对自身发起一次远程会话, 验证 Remoting 端到端可用
$ok = $false; $ev = ""
try {
  $r = Invoke-Command -ComputerName 10.10.10.10 -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
  if("$r" -match "DC"){ $ok = $true; $ev = "Invoke-Command 返回 $r" } else { $ev = "返回 $r" }
} catch {
  try { $w = Test-WSMan -ComputerName 10.10.10.10 -ErrorAction Stop; $ok = $true; $ev = "Test-WSMan OK（Invoke-Command 需凭据，WinRM 端点就绪）" }
  catch { $ev = "Test-WSMan 失败：WinRM 端点不可达" }
}
if($ok){ Add-Item "PowerShell Remoting 可用（WinRM 端点就绪）" "PASS" "可远程执行/Test-WSMan OK" $ev }
else { Add-Item "PowerShell Remoting 可用（WinRM 端点就绪）" "FAIL" "可远程执行/Test-WSMan OK" $ev "检查 WinRM 服务、5985 监听与防火墙" }

Add-Task "汇总（采集）"
Add-Item "WinRM 监听器（采集）" "INFO" "" (($httpPorts | ForEach-Object { "HTTP:$_" }) -join " ; ")
Add-Item "WinRM 相关入站防火墙规则（采集）" "INFO" "" ((Get-NetFirewallRule -Direction Inbound -Enabled True -EA SilentlyContinue | Where-Object { $_.DisplayName -match "远程管理|Remote Management|WinRM|5985" } | ForEach-Object { $_.DisplayName }) -join " ; ")

Export-CheckReport
