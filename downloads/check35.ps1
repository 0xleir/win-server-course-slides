# check35.ps1 — 第35课 渗透测试与应急响应：检测与证据核对
# 用法：在 DC1、SVR2、CLIENT1 上分别以管理员身份各运行一次（脚本按本机角色自动选检查项）
#   powershell -ExecutionPolicy Bypass -File check35.ps1
# 作用：核对本次攻击是否在日志里留痕（供"自我检测率"计算），以及应急响应是否做了封禁
# 约定：攻击源 Kali = 10.10.10.50
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson35" "第 35 课 · 渗透测试与应急响应"

$hn = $env:COMPUTERNAME
$role = if($hn -match "^DC"){ "DC" } elseif($hn -match "^SVR"){ "SVR2" } elseif($hn -match "^CLIENT"){ "CLIENT1" } else { "OTHER" }
$kali = "10.10.10.50"

Add-Task "运行位置"
Add-Item "本机角色" "INFO" "" "$hn（按 $role 角色检查）"

# ---------- SVR2：应用服务日志里是否留下攻击痕迹 ----------
if($role -eq "SVR2"){
  Add-Task "检测 · SVR2 应用日志里的攻击痕迹"
  $iisHits = 0
  Get-ChildItem C:\inetpub\logs\LogFiles -Recurse -Filter *.log -EA SilentlyContinue | ForEach-Object {
    $iisHits += @(Select-String -Path $_.FullName -Pattern $kali -EA SilentlyContinue).Count }
  if($iisHits -gt 0){ Add-Item "IIS 日志记录到 Kali($kali) 的请求" "PASS" ">0 条" "$iisHits 条" }
  else { Add-Item "IIS 日志记录到 Kali($kali) 的请求" "WARN" ">0 条" "0 条" "阶段 1 要先从 Kali 对 SVR2 的网站发起扫描/访问，日志才有痕迹（约 1 分钟缓冲）" }

  $ftpHits = 0
  Get-ChildItem C:\inetpub\logs\LogFiles -Recurse -Filter *.log -EA SilentlyContinue | Where-Object { $_.FullName -match "FTPSVC" } | ForEach-Object {
    $ftpHits += @(Select-String -Path $_.FullName -Pattern $kali -EA SilentlyContinue).Count }
  if($ftpHits -gt 0){ Add-Item "FTP 日志记录到 Kali 的登录尝试" "PASS" ">0 条" "$ftpHits 条" }
  else { Add-Item "FTP 日志记录到 Kali 的登录尝试" "INFO" "" "未发现（若本次没打 FTP 则正常）" }

  $pf = "C:\Windows\System32\LogFiles\Firewall\pfirewall.log"
  if(Test-Path $pf){
    $drop = @(Select-String -Path $pf -Pattern "DROP.*$kali" -EA SilentlyContinue).Count
    if($drop -gt 0){ Add-Item "防火墙日志有拦截 Kali 的 DROP 记录" "PASS" ">0 条" "$drop 条" }
    else { Add-Item "防火墙日志有拦截 Kali 的 DROP 记录" "INFO" "" "0 条（扫描可能都命中了放行端口）" }
  } else { Add-Item "防火墙日志已开启(pfirewall.log)" "WARN" "存在" "未找到" "第 34 课应已开 LogBlocked；Set-NetFirewallProfile -LogBlocked True" }

  $sm = Get-Service Sysmon64 -EA SilentlyContinue
  Add-Item "Sysmon 在运行(可取证进程/网络)" ($(if($sm -and $sm.Status -eq 'Running'){"PASS"}else{"WARN"})) "Running" ($(if($sm){$sm.Status}else{"未安装"})) "第 34 课部署 Sysmon"

  Add-Task "应急响应 · SVR2 修复项(可选)"
  Import-Module WebAdministration -EA SilentlyContinue
  $dft = Get-Website -Name "Default Web Site" -EA SilentlyContinue
  if($dft -and $dft.State -eq "Stopped"){ Add-Item "匿名默认 IIS 站点(80)已停" "PASS" "Stopped" "Stopped" }
  elseif($dft){ Add-Item "匿名默认 IIS 站点(80)已停" "INFO" "" "仍 Started（修复项：Stop-Website 'Default Web Site'）" }
  $sign = (Get-SmbServerConfiguration).RequireSecuritySignature
  if($sign){ Add-Item "SMB 签名已改为强制" "PASS" "True" "True" }
  else { Add-Item "SMB 签名已改为强制" "INFO" "" "False（修复项：Set-SmbServerConfiguration -RequireSecuritySignature `$true）" }
}

# ---------- DC1：转发的事件里是否收到失败登录 + 封禁规则 ----------
if($role -eq "DC"){
  Add-Task "检测 · DC1 转发的事件（集中日志）"
  $fe = Get-WinEvent -ListLog ForwardedEvents -EA SilentlyContinue
  $cnt = if($fe){ $fe.RecordCount } else { 0 }
  if($cnt -gt 0){ Add-Item "转发的事件已收到源机日志" "PASS" ">0 条" "$cnt 条" }
  else { Add-Item "转发的事件已收到源机日志" "FAIL" ">0 条" "0 条" "第 34 课的日志转发没生效；确认 Wecsvc 自动启动、SVR2 的 SubscriptionManager 指向 DC1" }
  $bad = @(Get-WinEvent -FilterHashtable @{LogName='ForwardedEvents';Id=4625} -MaxEvents 200 -EA SilentlyContinue)
  if($bad.Count -gt 0){
    $users = @($bad | ForEach-Object { $_.Properties[5].Value } | Where-Object { $_ } | Select-Object -Unique)
    Add-Item "集中日志里有失败登录(4625)" "PASS" ">0 条" "$($bad.Count) 条，账户：$($users -join ',')" }
  else { Add-Item "集中日志里有失败登录(4625)" "WARN" ">0 条" "0 条" "阶段 1 用 mount.cifs/hydra 带错密码打 SVR2 的共享，产生 4625 再等 1-2 分钟" }

  Add-Task "应急响应 · DC1 封禁与账户恢复"
  $block = Get-NetFirewallRule -DisplayName "Block-Attacker" -EA SilentlyContinue
  if($block){
    $ra = ($block | Get-NetFirewallAddressFilter).RemoteAddress
    if("$ra" -match "10\.10\.10\.50" -and $block.Action -eq "Block"){ Add-Item "已建封禁规则 Block-Attacker→Kali" "PASS" "Block 10.10.10.50" "Block $ra" }
    else { Add-Item "已建封禁规则 Block-Attacker→Kali" "WARN" "Block 10.10.10.50" "Action=$($block.Action) 来源=$ra" "封禁要精准到攻击源 10.10.10.50" }
  } else { Add-Item "已建封禁规则 Block-Attacker→Kali" "INFO" "" "未找到（阶段 2 的封禁步骤：New-NetFirewallRule -DisplayName Block-Attacker -Direction Inbound -RemoteAddress 10.10.10.50 -Action Block）" }
  $locked = @(Search-ADAccount -LockedOut -EA SilentlyContinue)
  if($locked.Count -eq 0){ Add-Item "无被锁定的合法账户(已恢复)" "PASS" "0" "0" }
  else { Add-Item "无被锁定的合法账户(已恢复)" "WARN" "0" (($locked | ForEach-Object SamAccountName) -join ",") "Search-ADAccount -LockedOut | Unlock-ADAccount" }
}

# ---------- CLIENT1：加固是否仍在（攻击未能攻破端点） ----------
if($role -eq "CLIENT1"){
  Add-Task "端点 · CLIENT1 加固仍在位"
  $rdp = (Get-NetFirewallRule -Direction Inbound -Enabled True -EA SilentlyContinue | Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -contains 3389 } | Where-Object Action -eq "Allow")
  if(-not $rdp){ Add-Item "RDP(3389) 未对外放行(扫描扫不到)" "PASS" "无放行规则" "无" }
  else { Add-Item "RDP(3389) 未对外放行(扫描扫不到)" "INFO" "" "存在放行规则：$(($rdp|ForEach-Object DisplayName) -join ',')" }
  $srp = Get-ChildItem 'HKLM:\Software\Policies\Microsoft\Windows\Safer\CodeIdentifiers\0\Paths' -EA SilentlyContinue
  Add-Item "SRP 隔离区规则仍在(挡落地工具)" ($(if($srp){"PASS"}else{"WARN"})) "存在" ($(if($srp){"有不允许路径规则"}else{"未下发"})) "第 34 课的 Hardening-Policy SRP"
  $usb = (Get-ItemProperty 'HKLM:\Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}' -EA SilentlyContinue).Deny_Write
  Add-Item "USB 存储仍禁用(挡摆渡工具)" ($(if($usb -eq 1){"PASS"}else{"WARN"})) "Deny_Write=1" "Deny_Write=$usb" "第 34 课的 Hardening-Policy USB 禁用"
}

Export-CheckReport
