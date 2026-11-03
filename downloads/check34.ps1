# check34.ps1 — 第34课 企业安全加固：检查与证据采集
# 用法：在 DC1、SVR2、CLIENT1 上分别以管理员身份各运行一次（脚本按本机角色自动选检查项）
#   powershell -ExecutionPolicy Bypass -File check34.ps1
# 说明：防火墙/Sysmon 是每台机本地项；WEF 收集器与"转发的事件"在 DC1；SRP/USB/锁屏在 CLIENT1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson34" "第 34 课 · 企业安全加固"

$hn = $env:COMPUTERNAME
$role = if($hn -match "^DC"){ "DC" } elseif($hn -match "^SVR"){ "SVR2" } elseif($hn -match "^CLIENT"){ "CLIENT1" } else { "OTHER" }

Add-Task "运行位置"
Add-Item "本机角色" "INFO" "" "$hn（按 $role 角色检查）"

# ---------- 防火墙（DC1 / SVR2 都查） ----------
if($role -in "DC","SVR2"){
  Add-Task "任务1 · 防火墙白名单（$hn）"
  $blocked = @(Get-NetFirewallProfile | Where-Object { $_.DefaultInboundAction -eq "Block" })
  if($blocked.Count -eq 3){ Add-Item "三个配置文件默认入站 = Block" "PASS" "Block×3" (($blocked | ForEach-Object { "$($_.Name)=Block" }) -join ",") }
  else { Add-Item "三个配置文件默认入站 = Block" "FAIL" "Block×3" (((Get-NetFirewallProfile) | ForEach-Object { "$($_.Name)=$($_.DefaultInboundAction)" }) -join ",") "Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block（本课任务 1）" }

  $wantName = if($role -eq "DC"){ "DC1-TCP" } else { "SVR2-TCP" }
  $wantPorts = if($role -eq "DC"){ @("53","88","389","443","445","636","5985","5986") } else { @("21","80","443","445","5985","50000-50100") }
  $rule = Get-NetFirewallRule -DisplayName $wantName -EA SilentlyContinue
  if($rule){
    $have = ($rule | Get-NetFirewallPortFilter).LocalPort
    $miss = @($wantPorts | Where-Object { $_ -notin $have })
    if($miss.Count -eq 0){ Add-Item "白名单规则 $wantName 含关键端口" "PASS" ($wantPorts -join ",") ($have -join ",") }
    else { Add-Item "白名单规则 $wantName 含关键端口" "WARN" ($wantPorts -join ",") ($have -join ",") "缺少端口：$($miss -join ',')；按本课任务 1 的清单补齐" }
  } else { Add-Item "存在白名单规则 $wantName" "FAIL" "存在" "未找到" "New-NetFirewallRule -DisplayName $wantName -Direction Inbound -Action Allow -Protocol TCP -LocalPort <清单>（本课任务 1）" }

  # 遗留的"任意来源"宽规则应已禁用（白名单原则）
  $broad = @(Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -EA SilentlyContinue | Where-Object { $_.DisplayName -in "Allow-IIS","Allow HTTP 8080","Allow ICMPv4","Allow FTP","Allow FTP Passive","Allow RDP 3390","Allow WinRM HTTPS 5986","SMB-IT-Only" })
  if($broad.Count -eq 0){ Add-Item "早期课程的宽放行规则已收口" "PASS" "全部禁用" "无启用的宽规则" }
  else { Add-Item "早期课程的宽放行规则已收口" "WARN" "全部禁用" (($broad | ForEach-Object { $_.DisplayName }) -join ",") "白名单原则下这些 Any 来源旧规则应禁用：Disable-NetFirewallRule -DisplayName <名字>" }

  $bak = Test-Path C:\LabFiles\firewall-backup.wfw
  Add-Item "改前已备份防火墙" ($(if($bak){"PASS"}else{"WARN"})) "firewall-backup.wfw 存在" ($(if($bak){"已备份"}else{"未找到备份"})) "netsh advfirewall export C:\LabFiles\firewall-backup.wfw（第 16 课）"
}

# ---------- Sysmon（DC1 / SVR2 都查） ----------
if($role -in "DC","SVR2"){
  Add-Task "任务3 · Sysmon（$hn）"
  $sm = Get-Service Sysmon64 -EA SilentlyContinue
  if($sm -and $sm.Status -eq "Running"){ Add-Item "Sysmon64 正在运行" "PASS" "Running" "Running" }
  else { Add-Item "Sysmon64 正在运行" "FAIL" "Running" ($(if($sm){$sm.Status}else{"未安装"})) "C:\Tools\Sysinternals\Sysmon64.exe -accepteula -i C:\Tools\sysmon-config.xml（第 29 课）" }
}

# ---------- WEF 收集器（仅 DC1） ----------
if($role -eq "DC"){
  Add-Task "任务3 · 日志转发收集器（DC1）"
  $wec = Get-Service Wecsvc -EA SilentlyContinue
  if($wec -and $wec.Status -eq "Running"){ Add-Item "Wecsvc（收集器服务）运行中" "PASS" "Running" "Running" }
  else { Add-Item "Wecsvc（收集器服务）运行中" "FAIL" "Running" ($(if($wec){$wec.Status}else{"未找到"})) "wecutil qc（本课任务 3）" }
  $subs = @(wecutil es 2>$null)
  if($subs -contains "LabForward"){ Add-Item "存在订阅 LabForward" "PASS" "存在" ($subs -join ",") }
  else { Add-Item "存在订阅 LabForward" "FAIL" "存在" ($(if($subs){$subs -join ","}else{"无订阅"})) "wecutil cs C:\LabFiles\subscription.xml（本课任务 3）" }
  $fe = Get-WinEvent -ListLog ForwardedEvents -EA SilentlyContinue
  $cnt = if($fe){ $fe.RecordCount } else { 0 }
  if($cnt -gt 0){
    $srcs = @(Get-WinEvent -LogName ForwardedEvents -MaxEvents 200 -EA SilentlyContinue | Group-Object MachineName | ForEach-Object { $_.Name })
    Add-Item "转发的事件已收到源机日志" "PASS" ">0 条" "$cnt 条，来源：$($srcs -join ',')" }
  else { Add-Item "转发的事件已收到源机日志" "WARN" ">0 条" "0 条" "源机(SVR2)配好 SubscriptionManager 并重启 WinRM 后，等 1–2 分钟；在 SVR2 上制造登录事件再看" }
}

# ---------- WEF 源（仅 SVR2） ----------
if($role -eq "SVR2"){
  Add-Task "任务3 · 日志源配置（SVR2）"
  $sm = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager" -EA SilentlyContinue)."1"
  if($sm -match "DC-01"){ Add-Item "SubscriptionManager 指向 DC1 收集器" "PASS" "含 DC-01:5985" $sm }
  else { Add-Item "SubscriptionManager 指向 DC1 收集器" "FAIL" "含 DC-01:5985" ($(if($sm){$sm}else{"未设置"})) "设注册表 ...EventForwarding\SubscriptionManager 的值 1 = Server=http://DC-01.lab.local:5985/wsman/SubscriptionManager/WEC,Refresh=60" }
  $winrm = Get-Service WinRM -EA SilentlyContinue
  if($winrm.Status -eq "Running"){ Add-Item "WinRM 运行中（转发通道）" "PASS" "Running" "Running" }
  else { Add-Item "WinRM 运行中（转发通道）" "FAIL" "Running" "$($winrm.Status)" "winrm quickconfig" }
}

# ---------- GPO 加固（仅 CLIENT1） ----------
if($role -eq "CLIENT1"){
  Add-Task "任务2 · 组策略加固（CLIENT1）"
  $usbK = "HKLM:\Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}"
  $dw = (Get-ItemProperty $usbK -EA SilentlyContinue).Deny_Write
  $dr = (Get-ItemProperty $usbK -EA SilentlyContinue).Deny_Read
  if($dw -eq 1 -and $dr -eq 1){ Add-Item "USB 可移动存储已禁用读写" "PASS" "Deny_Read=1 Deny_Write=1" "Deny_Read=$dr Deny_Write=$dw" }
  else { Add-Item "USB 可移动存储已禁用读写" "FAIL" "Deny_Read=1 Deny_Write=1" "Deny_Read=$dr Deny_Write=$dw" "GPO 计算机配置 › 管理模板 › 系统 › 可移动存储访问 › 可移动磁盘：拒绝读取/写入权限 = 已启用" }
  $lock = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -EA SilentlyContinue).InactivityTimeoutSecs
  if($lock -eq 600){ Add-Item "锁屏：不活动 600 秒" "PASS" "600" "$lock" }
  elseif($lock){ Add-Item "锁屏：不活动 600 秒" "WARN" "600" "$lock" "按课件设 600 秒（10 分钟）" }
  else { Add-Item "锁屏：不活动 600 秒" "FAIL" "600" "未设置" "GPO 安全选项 › 交互式登录：计算机不活动限制 = 600" }
  $srpK = "HKLM:\Software\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
  $srp = Get-ItemProperty $srpK -EA SilentlyContinue
  if($srp){
    $deny = @(Get-ChildItem "$srpK\0\Paths" -EA SilentlyContinue | ForEach-Object { (Get-ItemProperty $_.PSPath).ItemData })
    $hasLab = [bool]($deny | Where-Object { $_ -match "LabFiles" })
    if($hasLab){ Add-Item "SRP 禁止隔离区 C:\LabFiles 运行程序" "PASS" "有不允许规则 C:\LabFiles\*" ($deny -join ",") }
    else { Add-Item "SRP 禁止隔离区 C:\LabFiles 运行程序" "FAIL" "C:\LabFiles\*（不允许）" ($(if($deny){$deny -join ","}else{"无不允许规则"})) "SRP 新建路径规则 C:\LabFiles\* = 不允许（默认级别保持不受限）" }
  } else { Add-Item "已下发软件限制策略（SRP）" "FAIL" "存在" "未下发" "新建 GPO（本课命名 Hardening-Policy）配 SRP，并安全筛选只对 CLIENT1 应用" }
  $g = gpresult /r /scope computer 2>&1 | Out-String
  if($g -match "Hardening-Policy"){ Add-Item "gpresult 显示加固 GPO 已应用" "PASS" "含 Hardening-Policy" "已应用" }
  else { Add-Item "gpresult 显示加固 GPO 已应用" "WARN" "含 Hardening-Policy" "未列出" "gpupdate /force；确认 GPO 安全筛选含本机、且链接到能覆盖 CN=Computers 的位置（域根）" }
}

# ---------- 基线报告（DC1 / SVR2） ----------
if($role -in "DC","SVR2"){
  Add-Task "任务4 · 安全基线（$hn）"
  $smb1 = (Get-SmbServerConfiguration).EnableSMB1Protocol
  if($smb1 -eq $false){ Add-Item "SMBv1 已禁用" "PASS" "False" "False" } else { Add-Item "SMBv1 已禁用" "FAIL" "False" "$smb1" "Set-SmbServerConfiguration -EnableSMB1Protocol `$false（第 24 课，需重启生效）" }
  $rt = (Get-MpComputerStatus -EA SilentlyContinue).RealTimeProtectionEnabled
  if($rt){ Add-Item "Defender 实时保护开启" "PASS" "True" "True" } else { Add-Item "Defender 实时保护开启" "WARN" "True" "$rt" "第 22 课 Set-MpPreference -DisableRealtimeMonitoring `$false" }
  $lm = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -EA SilentlyContinue).LmCompatibilityLevel
  if($lm -eq 5){ Add-Item "LmCompatibilityLevel = 5" "PASS" "5" "$lm" } else { Add-Item "LmCompatibilityLevel = 5" "WARN" "5" ($(if($null -ne $lm){"$lm"}else{"未设置"})) "第 24 课：设 HKLM\SYSTEM\CurrentControlSet\Control\Lsa 的 LmCompatibilityLevel = 5" }
  Add-Item "SecurityReport.ps1 存在" ($(if(Test-Path C:\Scripts\SecurityReport.ps1){"PASS"}else{"WARN"})) "存在" ($(if(Test-Path C:\Scripts\SecurityReport.ps1){"C:\Scripts\SecurityReport.ps1"}else{"未找到"})) "从 DC1 用 445 把第 24 课的脚本拷到 SVR2：Copy-Item C:\Scripts\SecurityReport.ps1 \\SVR2\C`$\Scripts\"
}

Export-CheckReport
