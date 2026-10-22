# check19.ps1 — 第19课 组策略（GPO）配置：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check19.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson19" "第 19 课 · 组策略（GPO）配置"
Import-Module GroupPolicy -EA SilentlyContinue
Import-Module ActiveDirectory -EA SilentlyContinue

function Get-LinkedGpos([string]$target){
  try { return @((Get-GPInheritance -Target $target -EA Stop).GpoLinks | ForEach-Object { $_.DisplayName }) } catch { return @() }
}
$company = "OU=Company,DC=lab,DC=local"
$fin     = "OU=Finance-Dept,OU=Company,DC=lab,DC=local"
$it      = "OU=IT-Dept,OU=Company,DC=lab,DC=local"

Add-Task "任务1 · GPO 创建与链接"
# Lab-Security-Policy 存在 + 链接 Company
$g1 = Get-GPO -Name "Lab-Security-Policy" -EA SilentlyContinue
$l1 = Get-LinkedGpos $company
if($g1 -and ($l1 -contains "Lab-Security-Policy")){ Add-Item "Lab-Security-Policy 存在且链接到 Company OU" "PASS" "存在+链接Company" ("Company链接: " + ($l1 -join ",")) }
else { Add-Item "Lab-Security-Policy 存在且链接到 Company OU" "FAIL" "存在+链接Company" ($(if($g1){"存在但未链Company: "+($l1 -join ",")}else{"GPO不存在"})) "New-GPO; New-GPLink -Target 'OU=Company,DC=lab,DC=local'" }

# Standard-Desktop 链接 Finance-Dept
$g2 = Get-GPO -Name "Standard-Desktop" -EA SilentlyContinue
$l2 = Get-LinkedGpos $fin
if($g2 -and ($l2 -contains "Standard-Desktop")){ Add-Item "Standard-Desktop 链接到 Finance-Dept OU" "PASS" "链接Finance-Dept" ("Finance链接: " + ($l2 -join ",")) }
else { Add-Item "Standard-Desktop 链接到 Finance-Dept OU" "FAIL" "链接Finance-Dept" ($(if($g2){"存在但未链Finance: "+($l2 -join ",")}else{"GPO不存在"})) "New-GPLink -Name Standard-Desktop -Target '...Finance-Dept...'" }

# IT-LoginScript 链接 IT-Dept
$g3 = Get-GPO -Name "IT-LoginScript" -EA SilentlyContinue
$l3 = Get-LinkedGpos $it
if($g3 -and ($l3 -contains "IT-LoginScript")){ Add-Item "IT-LoginScript 链接到 IT-Dept OU" "PASS" "链接IT-Dept" ("IT链接: " + ($l3 -join ",")) }
else { Add-Item "IT-LoginScript 链接到 IT-Dept OU" "FAIL" "链接IT-Dept" ($(if($g3){"存在但未链IT: "+($l3 -join ",")}else{"GPO不存在"})) "New-GPLink -Name IT-LoginScript -Target '...IT-Dept...'" }

Add-Task "任务1 · 域密码策略（域级别）"
$pp = Get-ADDefaultDomainPasswordPolicy -EA SilentlyContinue
$min = $pp.MinPasswordLength
if($null -ne $min -and [int]$min -ge 10){ Add-Item "域密码策略最短长度 >= 10" "PASS" ">=10" "$min" }
else { Add-Item "域密码策略最短长度 >= 10" "FAIL" ">=10" ($(if($null -ne $min){"$min"}else{"查询失败"})) "Set-ADDefaultDomainPasswordPolicy -Identity lab.local -MinPasswordLength 10（账户策略只认域级别）" }

Add-Task "任务2 · 登录脚本"
$netlogon = "C:\Windows\SYSVOL\sysvol\lab.local\scripts\it-login.bat"
if(Test-Path $netlogon){
  $txt = Get-Content $netlogon -Raw -EA SilentlyContinue
  if($txt -match "net use"){ Add-Item "NETLOGON 中存在 it-login.bat（含盘符映射）" "PASS" "存在+含net use" "it-login.bat 已就位" }
  else { Add-Item "NETLOGON 中存在 it-login.bat（含盘符映射）" "WARN" "含 net use" "文件在但未见 net use" }
}
else { Add-Item "NETLOGON 中存在 it-login.bat（含盘符映射）" "FAIL" "存在" "无" "脚本放到 \\lab.local\NETLOGON（SYSVOL\...\scripts），-Encoding ASCII" }
$itU = @(Get-ADGroupMember -Identity "IT-Users" -EA SilentlyContinue | ForEach-Object { $_.SamAccountName })
if($itU -contains "Domain-IT"){ Add-Item "Domain-IT 已嵌套进 IT-Users（sunqi 可写 IT-Share 日志）" "PASS" "包含 Domain-IT" "包含" }
else { Add-Item "Domain-IT 已嵌套进 IT-Users（sunqi 可写 IT-Share 日志）" "FAIL" "包含 Domain-IT" ($(if($itU){"成员: " + ($itU -join ",")}else{"查询失败"})) "Add-ADGroupMember -Identity IT-Users -Members Domain-IT（AGDLP：全局组进本地域组）" }

Add-Task "汇总（采集）"
Add-Item "全部 GPO（采集）" "INFO" "" ((Get-GPO -All -EA SilentlyContinue | ForEach-Object { $_.DisplayName } | Sort-Object) -join " ; ")
Add-Item "各 OU 的 GPO 链接（采集）" "INFO" "" ("Company[" + ((Get-LinkedGpos $company) -join ",") + "] Finance[" + ((Get-LinkedGpos $fin) -join ",") + "] IT[" + ((Get-LinkedGpos $it) -join ",") + "]")

Export-CheckReport
