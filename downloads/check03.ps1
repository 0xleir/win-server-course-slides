# check03.ps1 — 第3课 本地用户和组的管理：任务检查与证据采集
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check03.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson03" "第 3 课 · 本地用户和组的管理"

Add-Task "任务1/2 · 命名用户创建"
$named = @("alice","bob","charlie","dave","eve","frank")
$found = @()
foreach($u in $named){
  $lu = Get-LocalUser -Name $u -EA SilentlyContinue
  if($lu){ $found += $lu.Name }
}
$foundStr = ($found -join ", ")
if($found.Count -eq 6){
  Add-Item "命名用户 alice/bob/charlie/dave/eve/frank" "PASS" "6 个全部存在" "存在 $($found.Count) 个：$foundStr"
} elseif($found.Count -gt 0){
  Add-Item "命名用户 alice/bob/charlie/dave/eve/frank" "WARN" "6 个全部存在" "存在 $($found.Count) 个：$foundStr" "部分用户缺失，请补建"
} else {
  Add-Item "命名用户 alice/bob/charlie/dave/eve/frank" "FAIL" "6 个全部存在" "一个都没找到" "未创建任何命名用户"
}
$allUsers = Get-LocalUser -EA SilentlyContinue | ForEach-Object { "$($_.Name)[Enabled=$($_.Enabled)]" }
Add-Item "全部本地用户（采集）" "INFO" "" ($allUsers -join " ; ")

Add-Task "任务 · 本地组及成员"
$groups = @("IT-Admins","IT-Users","Finance","Developers")
foreach($g in $groups){
  $lg = Get-LocalGroup -Name $g -EA SilentlyContinue
  if($lg){
    $members = Get-LocalGroupMember -Group $g -EA SilentlyContinue | ForEach-Object { $_.Name }
    $memStr = ($members -join ", ")
    if(-not $memStr){ $memStr = "（无成员）" }
    Add-Item "组 $g 已创建" "PASS" "存在" "成员：$memStr"
  } else {
    Add-Item "组 $g 已创建" "FAIL" "存在" "组不存在" "请创建该本地组"
  }
}
# 期望成员判定：IT-Admins 含 alice
$itaMembers = Get-LocalGroupMember -Group "IT-Admins" -EA SilentlyContinue | ForEach-Object { ($_.Name -split '\\')[-1] }
$itaStr = ($itaMembers -join ", ")
if($itaMembers -contains "alice"){
  Add-Item "IT-Admins 含 alice" "PASS" "成员含 alice" "成员：$itaStr"
} else {
  Add-Item "IT-Admins 含 alice" "WARN" "成员含 alice" "成员：$itaStr" "未检测到 alice 在 IT-Admins 中"
}
# 期望成员判定：Developers 含 dave 和 frank
$devMembers = Get-LocalGroupMember -Group "Developers" -EA SilentlyContinue | ForEach-Object { ($_.Name -split '\\')[-1] }
$devStr = ($devMembers -join ", ")
if(($devMembers -contains "dave") -and ($devMembers -contains "frank")){
  Add-Item "Developers 含 dave 和 frank" "PASS" "成员含 dave、frank" "成员：$devStr"
} else {
  Add-Item "Developers 含 dave 和 frank" "WARN" "成员含 dave、frank" "成员：$devStr" "未同时检测到 dave 和 frank"
}

Add-Task "任务 · Guest 账户"
$guest = Get-LocalUser -Name "Guest" -EA SilentlyContinue
if($guest){
  if($guest.Enabled -eq $false){
    Add-Item "Guest 账户已禁用" "PASS" "False(已禁用)" "Enabled=$($guest.Enabled)"
  } else {
    Add-Item "Guest 账户已禁用" "FAIL" "False(已禁用)" "Enabled=$($guest.Enabled)" "Guest 处于启用状态，存在安全风险"
  }
} else {
  Add-Item "Guest 账户已禁用" "INFO" "False(已禁用)" "未找到 Guest 账户"
}

Add-Task "任务3 · CSV 批量创建"
$csv = "C:\LabFiles\users.csv"
if(Test-Path $csv){
  $rows = @(Import-Csv $csv -EA SilentlyContinue)
  Add-Item "CSV 文件 C:\LabFiles\users.csv" "PASS" "存在" "存在，数据行数=$($rows.Count)"
} else {
  Add-Item "CSV 文件 C:\LabFiles\users.csv" "WARN" "存在" "不存在" "未发现批量导入用的 CSV 文件"
}
# 批量创建的学员账户：课件有 student1-5 或 user01-05 两种叫法，用通配符采集
$batch = Get-LocalUser -EA SilentlyContinue | Where-Object { $_.Name -match '^(student|user)\d+$' }
$batchNames = $batch | ForEach-Object { $_.Name }
$batchStr = ($batchNames -join ", ")
if(-not $batchStr){ $batchStr = "（无）" }
if($batch.Count -ge 5){
  Add-Item "批量学员账户 student/user NN" "PASS" "约 5 个" "共 $($batch.Count) 个：$batchStr"
} elseif($batch.Count -gt 0){
  Add-Item "批量学员账户 student/user NN" "WARN" "约 5 个" "共 $($batch.Count) 个：$batchStr" "批量账户数量偏少，确认 CSV 导入是否成功"
} else {
  Add-Item "批量学员账户 student/user NN" "WARN" "约 5 个" "未发现 student/user 开头的批量账户" "未完成 CSV 批量创建"
}

Export-CheckReport
