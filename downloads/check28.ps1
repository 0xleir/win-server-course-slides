# check28.ps1 — 第28课 密码攻击与防御：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check28.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson28" "第 28 课 · 密码攻击与防御"
Import-Module ActiveDirectory -EA SilentlyContinue

Add-Task "任务2 · 攻击检测证据(采集)"
$fail = @(Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625} -MaxEvents 200 -EA SilentlyContinue)
Add-Item "安全日志 4625(登录失败)事件(采集)" "INFO" "" ("共 " + $fail.Count + " 条")

if($fail.Count -gt 0){
  $top = $fail | Group-Object {try{$_.Properties[19].Value}catch{"?"}} | Sort-Object Count -Descending | Select-Object -First 1
  Add-Item "失败登录最多来源(采集)" "INFO" "" ("$($top.Name) 共 $($top.Count) 次")
}

Add-Task "任务3 · 细粒度密码策略 Strict-PSO"
$pso = Get-ADFineGrainedPasswordPolicy -Identity "Strict-PSO" -EA SilentlyContinue
if($pso){
  $ok = ($pso.MinPasswordLength -ge 12) -and ($pso.LockoutThreshold -eq 3) -and $pso.ComplexityEnabled
  if($ok){ Add-Item "Strict-PSO 已创建(长度≥12/锁定3次/复杂度)" "PASS" "MinLen≥12,Lockout=3,Complexity=True" ("MinLen=$($pso.MinPasswordLength) Lockout=$($pso.LockoutThreshold) Complexity=$($pso.ComplexityEnabled)") }
  else { Add-Item "Strict-PSO 已创建(长度≥12/锁定3次/复杂度)" "FAIL" "MinLen≥12,Lockout=3,Complexity=True" ("MinLen=$($pso.MinPasswordLength) Lockout=$($pso.LockoutThreshold) Complexity=$($pso.ComplexityEnabled)") "New-ADFineGrainedPasswordPolicy -Name Strict-PSO -MinPasswordLength 12 -LockoutThreshold 3 -ComplexityEnabled `$true" }

  $subjects = @(Get-ADFineGrainedPasswordPolicySubject -Identity "Strict-PSO" -EA SilentlyContinue | Select-Object -Expand Name)
  if($subjects -contains "Domain-IT"){ Add-Item "Strict-PSO 已应用到 Domain-IT 组" "PASS" "包含 Domain-IT" ($subjects -join ",") }
  else { Add-Item "Strict-PSO 已应用到 Domain-IT 组" "FAIL" "包含 Domain-IT" ($(if($subjects.Count){$subjects -join ","}else{"无"})) "Add-ADFineGrainedPasswordPolicySubject -Identity Strict-PSO -Subjects Domain-IT" }
}
else { Add-Item "Strict-PSO 已创建(长度≥12/锁定3次/复杂度)" "FAIL" "存在" "不存在" "New-ADFineGrainedPasswordPolicy -Name Strict-PSO ..." }

Add-Task "任务3 · 清理教学用弱口令账户"
$wu = Get-ADUser -Identity "weakuser" -EA SilentlyContinue
if(-not $wu){ Add-Item "weakuser 已删除" "PASS" "不存在" "不存在" }
else { Add-Item "weakuser 已删除" "FAIL" "不存在" "仍存在" "Remove-ADUser -Identity weakuser -Confirm:`$false" }

$locked = @(Search-ADAccount -LockedOut -EA SilentlyContinue)
if($locked.Count -eq 0){ Add-Item "没有遗留被锁定账户" "PASS" "0" "0" }
else { Add-Item "没有遗留被锁定账户" "WARN" "0" ($locked.Count.ToString() + " 个: " + (($locked | Select-Object -Expand SamAccountName) -join ",")) "Search-ADAccount -LockedOut | Unlock-ADAccount" }

Export-CheckReport
