# check06.ps1 — 第6课 NTFS 权限管理：任务检查与证据采集
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check06.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson06" "第 6 课 · NTFS 权限管理"

$root = "C:\CompanyData"

Add-Task "任务1 · 文件夹结构"
$need = @("$root","$root\IT","$root\Finance","$root\Public","$root\IT\Confidential")
$missing = @($need | Where-Object { -not (Test-Path $_) })
if($missing.Count -eq 0){ Add-Item "C:\CompanyData 及 4 个子文件夹" "PASS" "全部存在" "IT / Finance / Public / IT\Confidential 均存在" }
else { Add-Item "C:\CompanyData 及 4 个子文件夹" "FAIL" "全部存在" "缺失：$(($missing) -join ', ')" }
$files = @("$root\IT\readme.txt","$root\Finance\readme.txt","$root\Public\readme.txt","$root\IT\Confidential\secret.txt")
$fmiss = @($files | Where-Object { -not (Test-Path $_) })
if($fmiss.Count -eq 0){ Add-Item "四个示例文件存在（采集）" "INFO" "" "IT/Finance/Public/Confidential 下各 1 个文件均存在" }
else { Add-Item "四个示例文件存在（采集）" "INFO" "" "缺失：$(($fmiss) -join ', ')" }

Add-Task "任务2 · 禁用继承"
foreach($f in @("$root\IT","$root\Finance","$root\IT\Confidential")){
  $acl = Get-Acl $f -EA SilentlyContinue
  $name = $f.Replace("$root\","")
  if($acl){
    if($acl.AreAccessRulesProtected){ Add-Item "$name 已禁用继承" "PASS" "继承=已禁用" "AreAccessRulesProtected=True" }
    else { Add-Item "$name 已禁用继承" "WARN" "继承=已禁用" "AreAccessRulesProtected=False" "该文件夹仍在继承父权限" }
  } else { Add-Item "$name 已禁用继承" "FAIL" "继承=已禁用" "无法读取 ACL" }
}

Add-Task "任务2 · 各文件夹权限（icacls 采集）"
# IT：应含 IT-Users 修改
$itAcl = (icacls "$root\IT" 2>$null) -join " "
if($itAcl -match "IT-Users.*\(M\)|IT-Users:\(OI\)\(CI\)\(M\)"){ Add-Item "IT 文件夹 IT-Users 修改权限" "PASS" "IT-Users 含 (M)" "见采集" }
else { Add-Item "IT 文件夹 IT-Users 修改权限" "WARN" "IT-Users 含 (M)" ($itAcl) "未检测到 IT-Users 修改权限" }
Add-Item "IT 权限（采集）" "INFO" "" (((icacls "$root\IT" 2>$null) | Where-Object {$_ -match ':'}) -join " ; ")
# Finance：应无 IT-Users，含 Finance 修改
$finAcl = (icacls "$root\Finance" 2>$null) -join " "
if($finAcl -notmatch "IT-Users"){ Add-Item "Finance 文件夹已移除 IT-Users" "PASS" "不含 IT-Users" "Finance 权限中无 IT-Users" }
else { Add-Item "Finance 文件夹已移除 IT-Users" "WARN" "不含 IT-Users" $finAcl "Finance 仍含 IT-Users，继承可能未禁用" }
Add-Item "Finance 权限（采集）" "INFO" "" (((icacls "$root\Finance" 2>$null) | Where-Object {$_ -match ':'}) -join " ; ")
# Confidential：应无 IT-Users / Finance
$confAcl = (icacls "$root\IT\Confidential" 2>$null) -join " "
if($confAcl -notmatch "IT-Users" -and $confAcl -notmatch "DC.*Finance|\\Finance:"){ Add-Item "Confidential 仅限管理员/指定人" "PASS" "不含 IT-Users/Finance" "Confidential 已清理普通组" }
else { Add-Item "Confidential 仅限管理员/指定人" "WARN" "不含 IT-Users/Finance" $confAcl "Confidential 仍含普通部门组" }
Add-Item "Confidential 权限（采集）" "INFO" "" (((icacls "$root\IT\Confidential" 2>$null) | Where-Object {$_ -match ':'}) -join " ; ")
# Public：Everyone 修改
$pubAcl = (icacls "$root\Public" 2>$null) -join " "
if($pubAcl -match "Everyone"){ Add-Item "Public 文件夹 Everyone 修改" "PASS" "含 Everyone" "Public 含 Everyone" }
else { Add-Item "Public 文件夹 Everyone 修改" "WARN" "含 Everyone" $pubAcl "未检测到 Everyone" }

Add-Task "任务3 · ACL 备份"
if(Test-Path "C:\LabFiles\acl_backup.txt"){
  $len = (Get-Item "C:\LabFiles\acl_backup.txt").Length
  Add-Item "ACL 备份 C:\LabFiles\acl_backup.txt" "PASS" "存在" "存在，大小 $len 字节" }
else { Add-Item "ACL 备份 C:\LabFiles\acl_backup.txt" "WARN" "存在" "不存在" "未执行 icacls /save 备份" }

Export-CheckReport
