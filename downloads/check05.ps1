# check05.ps1 — 第5课 用户权限分配与 UAC：任务检查与证据采集
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check05.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson05" "第 5 课 · 用户权限分配与 UAC"

# 导出用户权限分配供解析
$inf = "$env:TEMP\l5check.inf"
secedit /export /cfg $inf /areas USER_RIGHTS /quiet 2>$null | Out-Null
$infText = @()
if(Test-Path $inf){ $infText = Get-Content $inf }
$interactive = ($infText | Select-String "SeInteractiveLogonRight").Line
$denyRemote  = ($infText | Select-String "SeDenyRemoteInteractiveLogonRight").Line
$itaSid = (Get-LocalGroup "IT-Admins" -EA SilentlyContinue).SID.Value
$finSid = (Get-LocalGroup "Finance" -EA SilentlyContinue).SID.Value

Add-Task "任务1 · 用户权限分配"
# 允许本地登录应含 IT-Admins（名字或 SID 皆可）
$okInt = $false
if($interactive){
  if($interactive -match "IT-Admins"){ $okInt = $true }
  if($itaSid -and ($interactive -match [regex]::Escape($itaSid))){ $okInt = $true }
}
if($okInt){ Add-Item "允许本地登录 含 IT-Admins" "PASS" "SeInteractiveLogonRight 含 IT-Admins" $interactive }
elseif($interactive){ Add-Item "允许本地登录 含 IT-Admins" "WARN" "SeInteractiveLogonRight 含 IT-Admins" $interactive "未检测到 IT-Admins，请在用户权限分配中添加" }
else { Add-Item "允许本地登录 含 IT-Admins" "FAIL" "SeInteractiveLogonRight 含 IT-Admins" "未读取到该权限行" }

$okDeny = $false
if($denyRemote){
  if($denyRemote -match "Finance"){ $okDeny = $true }
  if($finSid -and ($denyRemote -match [regex]::Escape($finSid))){ $okDeny = $true }
}
if($okDeny){ Add-Item "拒绝远程桌面登录 含 Finance" "PASS" "SeDenyRemoteInteractiveLogonRight 含 Finance" $denyRemote }
elseif($denyRemote){ Add-Item "拒绝远程桌面登录 含 Finance" "WARN" "SeDenyRemoteInteractiveLogonRight 含 Finance" $denyRemote "未检测到 Finance" }
else { Add-Item "拒绝远程桌面登录 含 Finance" "WARN" "SeDenyRemoteInteractiveLogonRight 含 Finance" "未读取到该权限行" "任务1未配置拒绝远程桌面" }

Add-Task "任务2 · UAC（用户账户控制）"
$sys = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -EA SilentlyContinue
$lua = $sys.EnableLUA
if($lua -eq 1){ Add-Item "UAC 已启用 (EnableLUA=1)" "PASS" "1" "EnableLUA=$lua" }
else { Add-Item "UAC 已启用 (EnableLUA=1)" "WARN" "1" "EnableLUA=$lua" "UAC 未启用" }
Add-Item "ConsentPromptBehaviorAdmin（采集）" "INFO" "" ("$($sys.ConsentPromptBehaviorAdmin)")
Add-Item "PromptOnSecureDesktop（采集）" "INFO" "" ("$($sys.PromptOnSecureDesktop)")

Add-Task "任务3 · 受限服务账户 svc_backup"
$svc = Get-LocalUser -Name "svc_backup" -EA SilentlyContinue
if($svc){ Add-Item "svc_backup 账户存在" "PASS" "存在" "Enabled=$($svc.Enabled)" }
else { Add-Item "svc_backup 账户存在" "FAIL" "存在" "不存在" "请创建受限服务账户 svc_backup" }
$boMembers = Get-LocalGroupMember -Group "Backup Operators" -EA SilentlyContinue | ForEach-Object { ($_.Name -split '\\')[-1] }
$admMembers = Get-LocalGroupMember -Group "Administrators" -EA SilentlyContinue | ForEach-Object { ($_.Name -split '\\')[-1] }
if($boMembers -contains "svc_backup"){ Add-Item "svc_backup 属于 Backup Operators" "PASS" "是" "Backup Operators 成员：$(($boMembers) -join ', ')" }
else { Add-Item "svc_backup 属于 Backup Operators" "WARN" "是" "Backup Operators 成员：$(($boMembers) -join ', ')" "未加入 Backup Operators" }
if($admMembers -contains "svc_backup"){ Add-Item "svc_backup 不在 Administrators（最小权限）" "WARN" "不在" "却在 Administrators 中" "服务账户不应有管理员权限" }
else { Add-Item "svc_backup 不在 Administrators（最小权限）" "PASS" "不在" "不在 Administrators 中" }

Export-CheckReport
