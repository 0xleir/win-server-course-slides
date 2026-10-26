# check21.ps1 — 第21课 Windows 防火墙高级配置：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check21.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson21" "第 21 课 · Windows 防火墙高级配置"

function Rule($n){ Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue }

Add-Task "任务1 · 精细入站规则（SMB）"
$a = Rule "SMB-IT-Only"
if($a){
  $pf = $a | Get-NetFirewallPortFilter; $af = $a | Get-NetFirewallAddressFilter
  $ok = ("$($a.Action)" -eq "Allow") -and ((("$($pf.LocalPort)") -split ',') -contains "445") -and ("$($af.RemoteAddress)" -match "10\.10\.10\.")
  if($ok){ Add-Item "SMB-IT-Only（允许 445 来自 10.10.10.0/24）" "PASS" "Allow 445 RemoteAddr=10.10.10.0/24" ("Action=$($a.Action) Port=$($pf.LocalPort) Remote=$($af.RemoteAddress)") }
  else { Add-Item "SMB-IT-Only（允许 445 来自 10.10.10.0/24）" "WARN" "Allow 445 10.10.10.0/24" ("Action=$($a.Action) Port=$($pf.LocalPort) Remote=$($af.RemoteAddress)") }
}
else { Add-Item "SMB-IT-Only（允许 445 来自 10.10.10.0/24）" "FAIL" "存在" "无" "New-NetFirewallRule -DisplayName SMB-IT-Only ..." }

$b = Rule "SMB-Block-Others"
if($b){
  # slides 要求创建后停用（否则 SYSVOL/GPO/文件传输都断）
  if("$($b.Enabled)" -eq "False"){ Add-Item "SMB-Block-Others（阻止规则存在且已停用）" "PASS" "存在+已停用" ("Action=$($b.Action) Enabled=$($b.Enabled)") }
  else { Add-Item "SMB-Block-Others（阻止规则存在且已停用）" "WARN" "存在+已停用" ("Enabled=$($b.Enabled)——仍启用会挡住 10.10.10.0/24 的 445（阻止优先）") "Disable-NetFirewallRule -DisplayName SMB-Block-Others" }
}
else { Add-Item "SMB-Block-Others（阻止规则存在且已停用）" "FAIL" "存在" "无" "New-NetFirewallRule -DisplayName SMB-Block-Others -Action Block；再 Disable" }

Add-Task "任务1 · 按程序 / 出站 / 日志"
$c = Rule "Allow-IIS"
if($c){ $prg = ($c | Get-NetFirewallApplicationFilter).Program; Add-Item "Allow-IIS（按程序放行 w3wp.exe）" "PASS" "含 w3wp" "$prg" }
else { Add-Item "Allow-IIS（按程序放行 w3wp.exe）" "FAIL" "存在" "无" "New-NetFirewallRule -Program w3wp.exe -Action Allow" }

$d = Rule "Block-Outbound-Social"
if($d){
  if("$($d.Enabled)" -eq "False"){ Add-Item "Block-Outbound-Social（出站规则存在且未启用）" "PASS" "存在+未启用" ("Dir=$($d.Direction) Enabled=$($d.Enabled)") }
  else { Add-Item "Block-Outbound-Social（出站规则存在且未启用）" "WARN" "未启用（演示用）" ("Enabled=$($d.Enabled)——启用会断所有 HTTPS 出站") }
}
else { Add-Item "Block-Outbound-Social（出站规则存在且未启用）" "FAIL" "存在" "无" "New-NetFirewallRule -Direction Outbound -RemotePort 443 -Action Block -Enabled False" }

$pdom = Get-NetFirewallProfile -Profile Domain
if("$($pdom.LogAllowed)" -eq "True" -and "$($pdom.LogBlocked)" -eq "True"){ Add-Item "域配置文件已开启 允许+阻止 日志" "PASS" "LogAllowed+LogBlocked=True" ("Allowed=$($pdom.LogAllowed) Blocked=$($pdom.LogBlocked)") }
else { Add-Item "域配置文件已开启 允许+阻止 日志" "FAIL" "都 True" ("Allowed=$($pdom.LogAllowed) Blocked=$($pdom.LogBlocked)") "Set-NetFirewallProfile -Profile Domain -LogAllowed True -LogBlocked True" }

Add-Task "任务2 · 连接安全规则（IPsec）"
$ip = Get-NetIPsecRule -DisplayName "DC1-SVR2-IPsec" -EA SilentlyContinue
if($ip){
  $af = $ip | Get-NetFirewallAddressFilter -EA SilentlyContinue
  $okEp = ("$($af.LocalAddress)" -match "10\.10\.10\.10") -and ("$($af.RemoteAddress)" -match "10\.10\.10\.20")
  if($okEp -and "$($ip.InboundSecurity)" -eq "Require"){ Add-Item "DC1↔SVR2 连接安全规则存在（Require，Kerberos）" "PASS" "10.10.10.10↔10.10.10.20 Require" ("In=$($ip.InboundSecurity) Out=$($ip.OutboundSecurity) $($af.LocalAddress)<->$($af.RemoteAddress)") }
  else { Add-Item "DC1↔SVR2 连接安全规则存在（Require，Kerberos）" "WARN" "终结点/要求认证" ("In=$($ip.InboundSecurity) $($af.LocalAddress)<->$($af.RemoteAddress)") }
}
else { Add-Item "DC1↔SVR2 连接安全规则存在（Require，Kerberos）" "FAIL" "存在" "无" "New-NetIPsecRule -LocalAddress 10.10.10.10 -RemoteAddress 10.10.10.20 -InboundSecurity Require -OutboundSecurity Require" }

# IPsec SA：需要两端都配 + 有流量才会产生；单机环境无 SVR2 则为空，硬判定
$mm = @(Get-NetIPsecMainModeSA -EA SilentlyContinue | Where-Object { "$($_.RemoteEndpoint)" -match "10\.10\.10\.20" -or "$($_.LocalEndpoint)" -match "10\.10\.10\.20" })
if($mm.Count -gt 0){ Add-Item "IPsec 主模式 SA 已建立（需 SVR2 对端 + 流量）" "PASS" "有 10.10.10.20 的 SA" ("SA 数=" + $mm.Count) }
else { Add-Item "IPsec 主模式 SA 已建立（需 SVR2 对端 + 流量）" "FAIL" "有 SA" "无（SVR2 未配对端或未产生流量）" "两端都配规则后在 DC1 Test-NetConnection 10.10.10.20 -Port 445 产生流量" }

Add-Task "汇总（采集）"
Add-Item "本课防火墙规则（采集）" "INFO" "" ((Get-NetFirewallRule -DisplayName "SMB*","Allow-IIS","Block-Outbound-Social" -EA SilentlyContinue | ForEach-Object { "$($_.DisplayName)[$($_.Enabled)/$($_.Action)]" }) -join " ; ")
Add-Item "连接安全规则（采集）" "INFO" "" ((Get-NetIPsecRule -EA SilentlyContinue | ForEach-Object { "$($_.DisplayName)[$($_.Enabled)]" }) -join " ; ")

Export-CheckReport
