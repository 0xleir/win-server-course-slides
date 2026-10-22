# check18.ps1 — 第18课 域用户与组织单元（OU）：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check18.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson18" "第 18 课 · 域用户与组织单元（OU）"
Import-Module ActiveDirectory -EA SilentlyContinue
$company = "OU=Company,DC=lab,DC=local"

Add-Task "任务1 · OU 结构"
$needOU = "IT-Dept","Finance-Dept","HR-Dept","Servers"
$have = @()
foreach($o in $needOU){
  $exist = Get-ADOrganizationalUnit -Filter "Name -eq '$o'" -SearchBase $company -EA SilentlyContinue
  if($exist){ $have += $o }
}
if($have.Count -eq 4){ Add-Item "4 个部门 OU 都在 Company 下（IT/Finance/HR/Servers）" "PASS" "IT-Dept,Finance-Dept,HR-Dept,Servers" ($have -join ",") }
else { Add-Item "4 个部门 OU 都在 Company 下（IT/Finance/HR/Servers）" "FAIL" "4 个 OU" ($(if($have.Count){$have -join ","}else{"无"})) "New-ADOrganizationalUnit -Path 'OU=Company,DC=lab,DC=local'" }

Add-Task "任务2 · 域用户"
$needU = "wangwei","zhangsan","lisi","wangwu","zhaoliu","sunqi"
$uok = $true; $uev = @()
foreach($u in $needU){
  $o = Get-ADUser -Filter "SamAccountName -eq '$u'" -Properties Enabled -EA SilentlyContinue
  if(-not $o){ $uok=$false; $uev += "${u}:缺失" }
  elseif(-not $o.Enabled){ $uok=$false; $uev += "${u}:禁用" }
  else { $uev += "${u}:OK" }
}
if($uok){ Add-Item "6 个域用户已创建且启用" "PASS" "wangwei..sunqi 共6人启用" ($uev -join ",") }
else { Add-Item "6 个域用户已创建且启用" "FAIL" "6 人启用" ($uev -join ",") "New-ADUser ... -Enabled `$true -AccountPassword(Domain@2026!)" }

# 用户位于正确 OU
$locOk = $true; $locEv = @()
$map = @{ wangwei="IT-Dept"; sunqi="IT-Dept"; zhangsan="Finance-Dept"; lisi="Finance-Dept"; wangwu="HR-Dept"; zhaoliu="HR-Dept" }
foreach($u in $map.Keys){
  $o = Get-ADUser -Filter "SamAccountName -eq '$u'" -EA SilentlyContinue
  if($o -and "$($o.DistinguishedName)" -match ("OU=" + [regex]::Escape($map[$u]))){ $locEv += "${u}→$($map[$u])" }
  else { $locOk=$false; $locEv += "${u}:位置错" }
}
if($locOk){ Add-Item "用户位于对应部门 OU" "PASS" "各就各位" ($locEv -join " ") }
else { Add-Item "用户位于对应部门 OU" "WARN" "各就各位" ($locEv -join " ") "按 CSV 的 OU 列放置" }

Add-Task "任务2 · 安全组"
$g1 = Get-ADGroup -Filter {Name -eq "Domain-IT"} -Properties GroupCategory,GroupScope -EA SilentlyContinue
$m1 = @(); if($g1){ $m1 = @(Get-ADGroupMember "Domain-IT" -EA SilentlyContinue | ForEach-Object { $_.SamAccountName }) }
if($g1 -and "$($g1.GroupCategory)" -eq "Security" -and ($m1 -contains "wangwei") -and ($m1 -contains "sunqi")){ Add-Item "Domain-IT（安全组）含 wangwei、sunqi" "PASS" "Security + wangwei,sunqi" ($m1 -join ",") }
else { Add-Item "Domain-IT（安全组）含 wangwei、sunqi" "FAIL" "Security + wangwei,sunqi" ($(if($g1){"$($g1.GroupCategory): "+($m1 -join ",")}else{"组不存在"})) "New-ADGroup -GroupScope Global -GroupCategory Security; Add-ADGroupMember" }

$g2 = Get-ADGroup -Filter {Name -eq "Domain-Finance"} -Properties GroupCategory -EA SilentlyContinue
$m2 = @(); if($g2){ $m2 = @(Get-ADGroupMember "Domain-Finance" -EA SilentlyContinue | ForEach-Object { $_.SamAccountName }) }
if($g2 -and "$($g2.GroupCategory)" -eq "Security" -and ($m2 -contains "zhangsan") -and ($m2 -contains "lisi")){ Add-Item "Domain-Finance（安全组）含 zhangsan、lisi" "PASS" "Security + zhangsan,lisi" ($m2 -join ",") }
else { Add-Item "Domain-Finance（安全组）含 zhangsan、lisi" "FAIL" "Security + zhangsan,lisi" ($(if($g2){"$($g2.GroupCategory): "+($m2 -join ",")}else{"组不存在"})) }

Add-Task "任务3 · OU 委派"
# IT-Dept OU 的 ACL 是否含 wangwei 的管理 ACE
$delOk = $false; $delEv = "未检出委派"
try {
  $it = "OU=IT-Dept,OU=Company,DC=lab,DC=local"
  $sid = (Get-ADUser wangwei -EA Stop).SID
  $acl = Get-Acl ("AD:\$it")
  $ace = @($acl.Access | Where-Object {
    try { ($_.IdentityReference -is [Security.Principal.NTAccount]) -and ((New-Object Security.Principal.NTAccount($_.IdentityReference)).Translate([Security.Principal.SecurityIdentifier]).Value -eq "$sid") } catch { $false }
  })
  if($ace.Count -gt 0){ $delOk = $true; $delEv = "wangwei 在 IT-Dept 有 $($ace.Count) 条 ACE" } else { $delEv = "IT-Dept ACL 中无 wangwei" }
} catch { $delEv = "委派检查异常: " + $_.Exception.Message }
if($delOk){ Add-Item "wangwei 对 IT-Dept 有委派权限" "PASS" "IT-Dept ACL 含 wangwei" $delEv }
else { Add-Item "wangwei 对 IT-Dept 有委派权限" "FAIL" "IT-Dept ACL 含 wangwei" $delEv "dsa.msc → 右键 IT-Dept → 委派控制 → wangwei" }

Add-Task "汇总（采集）"
Add-Item "Company 下 OU（采集）" "INFO" "" ((Get-ADOrganizationalUnit -Filter * -SearchBase $company -EA SilentlyContinue | ForEach-Object { $_.Name }) -join " ; ")
Add-Item "Company 下域用户（采集）" "INFO" "" ((Get-ADUser -Filter * -SearchBase $company -EA SilentlyContinue | ForEach-Object { $_.SamAccountName }) -join " ; ")

Export-CheckReport
