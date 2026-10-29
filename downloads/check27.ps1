# check27.ps1 — 第27课 端口扫描与漏洞发现：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check27.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson27" "第 27 课 · 端口扫描与漏洞发现"

Add-Task "任务3 · 防火墙日志中应有扫描痕迹"
$log = "C:\Windows\System32\LogFiles\Firewall\pfirewall.log"
if(Test-Path $log){
  $hits = @(Get-Content $log -Tail 2000 -EA SilentlyContinue | Where-Object { $_ -match "10\.10\.10\.50" })
  if($hits.Count -gt 0){ Add-Item "pfirewall.log 中含 10.10.10.50(Kali)记录" "PASS" "至少1条" ("命中 " + $hits.Count + " 条") }
  else { Add-Item "pfirewall.log 中含 10.10.10.50(Kali)记录" "FAIL" "至少1条" "0 条" "确认已在 Kali 上对 10.10.10.10 执行过 nmap 扫描,且第21课的防火墙日志记录已开启" }
}
else { Add-Item "pfirewall.log 中含 10.10.10.50(Kali)记录" "FAIL" "日志文件存在" "不存在" "第21课配置: Set-NetFirewallProfile -LogFileName/-LogAllowed/-LogBlocked" }

Add-Task "任务3 · 安全日志(采集,供人工核对)"
$sec = @(Get-WinEvent -LogName Security -MaxEvents 200 -EA SilentlyContinue | Where-Object { $_.Message -match "10\.10\.10\.50" })
Add-Item "安全日志中 10.10.10.50 相关事件(采集)" "INFO" "" ("命中 " + $sec.Count + " 条(可能为0,纯端口扫描不一定产生登录事件)")

Add-Task "任务 1-2 · Kali 扫描报告(人工核对清单,本脚本在 DC1 运行无法直接验证 Kali 侧文件)"
Add-Item "Kali(10.10.10.50) 上是否有 scan-dc1.nmap/.xml/.gnmap" "INFO" "" "需到 Kali(10.10.10.50) 上人工核对 /home/vagrant/scan-dc1.*"

Export-CheckReport
