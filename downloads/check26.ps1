# check26.ps1 — 第26课 网络监控与抓包分析：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check26.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson26" "第 26 课 · 网络监控与抓包分析"

Add-Task "任务1 · 系统级网络监控工具"
$wireshark = (Get-Command "C:\Program Files\Wireshark\Wireshark.exe" -EA SilentlyContinue) -or (Test-Path "C:\Program Files\Wireshark\Wireshark.exe")
if($wireshark){ Add-Item "Wireshark 已安装" "PASS" "C:\Program Files\Wireshark\Wireshark.exe 存在" "存在" }
else { Add-Item "Wireshark 已安装" "FAIL" "C:\Program Files\Wireshark\Wireshark.exe 存在" "不存在" "从 wireshark.org 下载安装" }

$tcpview = Test-Path "C:\Tools\Sysinternals\tcpview.exe"
if($tcpview){ Add-Item "Sysinternals TCPView 可用" "PASS" "C:\Tools\Sysinternals\tcpview.exe 存在" "存在" }
else { Add-Item "Sysinternals TCPView 可用" "WARN" "C:\Tools\Sysinternals\tcpview.exe 存在" "不存在" "从 Sysinternals 下载 TCPView 放到 C:\Tools\Sysinternals" }

Add-Task "任务2 · Wireshark 抓包证据"
$pcap = "C:\LabFiles\Lesson26-capture.pcapng"
if(Test-Path $pcap){
  $sz = (Get-Item $pcap).Length
  if($sz -gt 2048){ Add-Item "C:\LabFiles\Lesson26-capture.pcapng 存在且非空" "PASS" "大小 > 2KB" ("大小=" + $sz + " 字节") }
  else { Add-Item "C:\LabFiles\Lesson26-capture.pcapng 存在且非空" "WARN" "大小 > 2KB" ("大小=" + $sz + " 字节(太小,可能没真正抓到流量)") "重新抓包,确保 VM3 访问过 http://10.10.10.10 等产生真实流量" }
}
else { Add-Item "C:\LabFiles\Lesson26-capture.pcapng 存在且非空" "FAIL" "文件存在" "不存在" "Wireshark 抓包后 File→Save As→C:\LabFiles\Lesson26-capture.pcapng" }

Add-Task "任务3 · 当前网络连接快照(采集,供人工核对任务1记录表)"
$conns = Get-NetTCPConnection -State Listen -EA SilentlyContinue | Select-Object LocalPort,OwningProcess
$list = $conns | ForEach-Object {
  $p = Get-Process -Id $_.OwningProcess -EA SilentlyContinue
  "$($_.LocalPort)=$($p.Name)"
} | Sort-Object
Add-Item "监听端口与进程(采集)" "INFO" "" ($list -join " ; ")

Export-CheckReport
