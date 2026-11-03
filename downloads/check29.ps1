# check29.ps1 — 第29课 日志分析与入侵检测：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check29.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson29" "第 29 课 · 日志分析与入侵检测"

Add-Task "任务1 · Sysmon 部署"
$svc = Get-Service Sysmon64 -EA SilentlyContinue
if($svc -and $svc.Status -eq "Running"){ Add-Item "Sysmon64 服务正在运行" "PASS" "Running" "Running" }
else { Add-Item "Sysmon64 服务正在运行" "FAIL" "Running" ($(if($svc){"$($svc.Status)"}else{"未安装"})) "C:\Tools\Sysinternals\Sysmon64.exe -accepteula -i C:\Tools\sysmon-config.xml" }

$evt = Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -MaxEvents 5 -EA SilentlyContinue
if($evt -and $evt.Count -gt 0){ Add-Item "Sysmon 日志有事件记录" "PASS" "至少1条" ("最近 " + $evt.Count + " 条") }
else { Add-Item "Sysmon 日志有事件记录" "FAIL" "至少1条" "0 条" "确认 Sysmon 服务已启动,等待几分钟产生事件" }

Add-Task "任务2 · 日志分析证据(采集)"
$p1 = @(Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -EA SilentlyContinue | Where-Object { $_.Id -eq 1 })
Add-Item "Sysmon Event 1(进程创建)数量(采集)" "INFO" "" ($p1.Count.ToString())

$recon = Test-Path "C:\Temp\recon.txt"
$users = Test-Path "C:\Temp\users.txt"
if($recon -and $users){ Add-Item "模拟可疑活动产物(recon.txt/users.txt)存在" "PASS" "都存在" "都存在" }
else { Add-Item "模拟可疑活动产物(recon.txt/users.txt)存在" "WARN" "都存在" ("recon=" + $recon + " users=" + $users) "按任务2脚本在DC1上执行 whoami /all > C:\Temp\recon.txt 等" }

$fail2 = @(Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625;StartTime=(Get-Date).AddHours(-2)} -EA SilentlyContinue)
Add-Item "近2小时内 4625 失败登录(采集)" "INFO" "" ($fail2.Count.ToString() + " 条")

Add-Task "任务3 · 事件转发 WEF"
$wecsvc = Get-Service Wecsvc -EA SilentlyContinue
if($wecsvc -and $wecsvc.Status -eq "Running"){ Add-Item "DC1 已配置为 WEF 收集器(wecutil qc, Wecsvc 运行中)" "PASS" "Running" "Running" }
else { Add-Item "DC1 已配置为 WEF 收集器(wecutil qc, Wecsvc 运行中)" "FAIL" "Running" ($(if($wecsvc){"$($wecsvc.Status)"}else{"未配置"})) "wecutil qc" }

# 真跑 SVR2 订阅检查: 1) 至少有一条 Active 的订阅, 2) ForwardedEvents 日志里能查到来自 SVR2 的事件
$subActive = $false; $subInfo = "无订阅"
try {
  $subs = & wecutil es 2>$null
  if($subs){
    foreach($name in $subs){
      $name = $name.Trim(); if(!$name){ continue }
      $gs = & wecutil gs "$name" 2>$null
      $enabled = ($gs | Where-Object { $_ -match 'Enabled:\s*true' })
      $status  = ($gs | Where-Object { $_ -match 'RuntimeStatus:\s*Active|Status:\s*Active' })
      if($enabled -and $status){ $subActive = $true; $subInfo = "订阅 $name = Active"; break }
    }
    if(!$subActive){ $subInfo = "订阅存在但无 Active: $($subs -join ',')" }
  }
} catch { $subInfo = "wecutil 执行失败: $($_.Exception.Message.Split([char]10)[0])" }

$fwdFromSvr2 = @(Get-WinEvent -LogName "ForwardedEvents" -MaxEvents 500 -EA SilentlyContinue |
  Where-Object { $_.MachineName -match '^SVR2' -or $_.MachineName -match '^svr2' })

if($subActive -and $fwdFromSvr2.Count -gt 0){
  Add-Item "SVR2 作为日志源的订阅是否生效" "PASS" "订阅 Active 且 ForwardedEvents 有 SVR2 日志" ("$subInfo; SVR2 事件 $($fwdFromSvr2.Count) 条")
} elseif($subActive){
  Add-Item "SVR2 作为日志源的订阅是否生效" "WARN" "订阅 Active 且 ForwardedEvents 有 SVR2 日志" ("$subInfo; 但 ForwardedEvents 中未见 SVR2 事件") "SVR2 侧确认: winrm quickconfig; 把 LAB\DC-01$ 加入 SVR2 的 Event Log Readers 组; 等几分钟或在 SVR2 产生新事件"
} else {
  Add-Item "SVR2 作为日志源的订阅是否生效" "FAIL" "订阅 Active 且 ForwardedEvents 有 SVR2 日志" $subInfo "DC1 上 wecutil cs C:\LabFiles\subscription.xml 导入订阅; SVR2 侧 winrm quickconfig + 把 LAB\DC-01$ 加入 Event Log Readers"
}

Export-CheckReport
