# check01.ps1 — 第1课 安装与初始配置：任务检查与证据采集
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check01.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson01" "第 1 课 · Windows Server 2022 安装与初始配置"

Add-Task "任务2 · 计算机名"
$cn = $env:COMPUTERNAME
if($cn -match '^WIN-'){ Add-Item "计算机名已自定义" "WARN" "非默认 WIN-xxxxxxx" $cn "仍是安装时的随机名，应改为 DC-学号" }
else { Add-Item "计算机名已自定义" "PASS" "非默认 WIN-xxxxxxx" $cn }

Add-Task "任务2 · 网络配置（Lab 网卡）"
$v4 = Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like "10.10.10.*" -and $_.PrefixOrigin -eq "Manual"}
if($v4){
  Add-Item "Lab 网卡静态 IP (10.10.10.0/24)" "PASS" "10.10.10.x /24 手动" "$($v4.InterfaceAlias)=$($v4.IPAddress)/$($v4.PrefixLength)"
} else {
  $any = Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*"}
  Add-Item "Lab 网卡静态 IP (10.10.10.0/24)" "FAIL" "10.10.10.x /24 手动" (($any|ForEach-Object{"$($_.InterfaceAlias)=$($_.IPAddress)($($_.PrefixOrigin))"}) -join " ; ") "未发现 10.10.10.x 段的手动 IP"
}
$lab = $v4 | Select-Object -First 1
if($lab){
  $dns = (Get-DnsClientServerAddress -InterfaceAlias $lab.InterfaceAlias -AddressFamily IPv4 -EA SilentlyContinue).ServerAddresses -join ","
  if($dns -match '127\.0\.0\.1'){ Add-Item "首选 DNS 指向本机" "PASS" "127.0.0.1" $dns }
  else { Add-Item "首选 DNS 指向本机" "WARN" "127.0.0.1" $dns "课程要求 Lab 网卡 DNS=127.0.0.1" }
  $gw = (Get-NetIPConfiguration -InterfaceAlias $lab.InterfaceAlias -EA SilentlyContinue).IPv4DefaultGateway.NextHop
  if($gw){ Add-Item "Lab 网卡默认网关（应留空）" "WARN" "空" "$gw" "隔离实验网不应配网关" }
  else   { Add-Item "Lab 网卡默认网关（应留空）" "PASS" "空" "（空）" }
}
$nics = Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { "$($_.Name)[$($_.MacAddress)]" }
Add-Item "已启用网卡（采集）" "INFO" "" ($nics -join " ; ")

Add-Task "任务2 · IE 增强安全(ESC) 与 防火墙 ping"
$esc = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -EA SilentlyContinue).IsInstalled
if($esc -eq 0){ Add-Item "IE ESC（管理员）已关闭" "PASS" "已关闭(IsInstalled=0)" "IsInstalled=$esc" }
else { Add-Item "IE ESC（管理员）已关闭" "WARN" "已关闭(IsInstalled=0)" "IsInstalled=$esc" "注册表显示未关闭" }
$icmp = Get-NetFirewallRule -EA SilentlyContinue | Where-Object DisplayName -match "ICMP|ping|Allow ICMPv4"
if($icmp){ Add-Item "ICMP(ping) 入站放行规则" "PASS" "存在且启用" (($icmp|ForEach-Object{"$($_.DisplayName)[$($_.Enabled)]"}) -join " ; ") }
else { Add-Item "ICMP(ping) 入站放行规则" "FAIL" "存在且启用" "未找到含 ICMP/ping 的放行规则" }

Add-Task "任务3 · PowerShell 环境"
# 读机器级(LocalMachine)策略，避免被 powershell -ExecutionPolicy Bypass 启动参数干扰
$ep = Get-ExecutionPolicy -Scope LocalMachine
if($ep -eq "Undefined"){ $ep = Get-ExecutionPolicy }
if($ep -eq "RemoteSigned"){ Add-Item "脚本执行策略" "PASS" "RemoteSigned" $ep }
else { Add-Item "脚本执行策略" "WARN" "RemoteSigned" $ep "课程要求 RemoteSigned" }
$lf = Test-Path C:\LabFiles
if($lf){ Add-Item "实验目录 C:\LabFiles" "PASS" "存在" "存在" }
else { Add-Item "实验目录 C:\LabFiles" "WARN" "存在" "不存在" }
Add-Item "PowerShell 版本（采集）" "INFO" "" ($PSVersionTable.PSVersion.ToString())

Export-CheckReport
