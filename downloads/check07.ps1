# check07.ps1 — 第7课 共享文件夹与网络访问：任务检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check07.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson07" "第 7 课 · 共享文件夹与网络访问"

function ShareInfo($name){ Get-SmbShare -Name $name -EA SilentlyContinue }
function AccList($name){ Get-SmbShareAccess -Name $name -EA SilentlyContinue }

Add-Task "任务1 · 创建共享"
# Public$ 隐藏共享
$pub = ShareInfo "Public$"
if($pub){ Add-Item "隐藏共享 Public\$ 存在" "PASS" "存在" "Path=$($pub.Path)（名以 \$ 结尾=隐藏共享）" }
else { Add-Item "隐藏共享 Public\$ 存在" "FAIL" "存在" "不存在" "请用高级共享创建 Public\$" }
if($pub){
  $pa = AccList "Public$"
  $ev = $pa | Where-Object { $_.AccountName -match "Everyone" }
  if($ev -and $ev.AccessRight -match "Change"){ Add-Item "Public\$ 共享权限 Everyone 更改" "PASS" "Everyone=Change" "见采集" }
  else { Add-Item "Public\$ 共享权限 Everyone 更改" "WARN" "Everyone=Change" (($pa|ForEach-Object{"$($_.AccountName):$($_.AccessControlType)/$($_.AccessRight)"}) -join " ; ") }
}
# IT-Share
$it = ShareInfo "IT-Share"
if($it){ Add-Item "IT-Share 存在" "PASS" "存在" "Path=$($it.Path)" } else { Add-Item "IT-Share 存在" "FAIL" "存在" "不存在" "请用 New-SmbShare 创建 IT-Share" }
if($it){ Add-Item "IT-Share 共享权限（采集）" "INFO" "" ((AccList "IT-Share" | ForEach-Object{"$($_.AccountName):$($_.AccessControlType)/$($_.AccessRight)"}) -join " ; ") }
# Finance-Share + NoAccess 伏笔
$fin = ShareInfo "Finance-Share"
if($fin){ Add-Item "Finance-Share 存在" "PASS" "存在" "Path=$($fin.Path)" } else { Add-Item "Finance-Share 存在" "FAIL" "存在" "不存在" "请用 New-SmbShare 创建 Finance-Share" }
if($fin){
  $fa = AccList "Finance-Share"
  $deny = $fa | Where-Object { $_.AccountName -match "IT-Users" -and $_.AccessControlType -match "Deny" }
  if($deny){ Add-Item "Finance-Share 对 IT-Users 拒绝（NoAccess 伏笔）" "PASS" "IT-Users=Deny" "已生成拒绝条目——charlie 虽在 Finance 组也会被拒绝优先挡住" }
  else { Add-Item "Finance-Share 对 IT-Users 拒绝（NoAccess 伏笔）" "WARN" "IT-Users=Deny" (($fa|ForEach-Object{"$($_.AccountName):$($_.AccessControlType)/$($_.AccessRight)"}) -join " ; ") "未检测到对 IT-Users 的拒绝条目" }
  Add-Item "Finance-Share 共享权限（采集）" "INFO" "" (($fa|ForEach-Object{"$($_.AccountName):$($_.AccessControlType)/$($_.AccessRight)"}) -join " ; ")
}

Add-Task "任务4 · ABE（基于访问的枚举）"
foreach($n in @("IT-Share","Finance-Share","Public$")){
  $s = ShareInfo $n
  if(-not $s){ continue }
  if($s.FolderEnumerationMode -eq "AccessBased"){ Add-Item "$n 已启用 ABE" "PASS" "AccessBased" "FolderEnumerationMode=AccessBased" }
  else { Add-Item "$n 已启用 ABE" "WARN" "AccessBased" "FolderEnumerationMode=$($s.FolderEnumerationMode)" "任务4未启用 ABE（可选任务）" }
}

Add-Task "环境 · 默认共享（采集）"
$def = net share 2>$null | Select-String 'C\$|ADMIN\$|IPC\$'
Add-Item "系统默认管理共享 C\$/ADMIN\$/IPC\$（采集）" "INFO" "" (($def | ForEach-Object { ($_ -split '\s{2,}')[0] }) -join " ")

Export-CheckReport
