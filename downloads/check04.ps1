# check04.ps1 — 第4课 本地安全策略：密码策略、账户锁定、审计 的任务检查与证据采集
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check04.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson04" "第 4 课 · 本地安全策略"

# ---------- 采集 net accounts ----------
$na = net accounts 2>$null
$naText = ($na -join "`n")

# 从 net accounts 文本里按关键字抽取第一个数字的小工具
function Get-NaLine { param([string[]]$Keys)
  foreach($k in $Keys){
    $line = $na | Select-String -SimpleMatch $k -EA SilentlyContinue | Select-Object -First 1
    if($line){ return $line.Line.Trim() }
  }
  return $null
}
function Get-NaNumber { param([string]$Line)
  if($Line){
    $m = [regex]::Match($Line, '(\d+)')
    if($m.Success){ return [int]$m.Value }
  }
  return $null
}

# ---------- 任务① 密码策略 ----------
Add-Task "任务1 · 密码策略（net accounts）"

Add-Item "net accounts 原始输出（采集）" "INFO" "" $naText

# 密码长度最小值 >= 8
$lnLen = Get-NaLine @("密码长度最小值","Minimum password length")
$vLen  = Get-NaNumber $lnLen
if($vLen -ne $null){
  if($vLen -ge 8){ Add-Item "密码长度最小值" "PASS" ">=8" "$vLen" }
  else           { Add-Item "密码长度最小值" "FAIL" ">=8" "$vLen" "密码最小长度未达到 8 位" }
} else {
  Add-Item "密码长度最小值" "INFO" ">=8" ("$lnLen") "未能从输出中解析出数值，请核对原始输出"
}

# 密码最长使用期限 = 90
$lnMaxAge = Get-NaLine @("密码最长使用期限","Maximum password age")
$vMaxAge  = Get-NaNumber $lnMaxAge
if($vMaxAge -ne $null){
  if($vMaxAge -eq 90){ Add-Item "密码最长使用期限（天）" "PASS" "90" "$vMaxAge" }
  else                { Add-Item "密码最长使用期限（天）" "WARN" "90" "$vMaxAge" "课程要求 90 天" }
} else {
  Add-Item "密码最长使用期限（天）" "INFO" "90" ("$lnMaxAge") "未能解析数值，请核对原始输出"
}

# 密码最短使用期限 = 1
$lnMinAge = Get-NaLine @("密码最短使用期限","Minimum password age")
$vMinAge  = Get-NaNumber $lnMinAge
if($vMinAge -ne $null){
  if($vMinAge -eq 1){ Add-Item "密码最短使用期限（天）" "PASS" "1" "$vMinAge" }
  else               { Add-Item "密码最短使用期限（天）" "WARN" "1" "$vMinAge" "课程要求 1 天" }
} else {
  Add-Item "密码最短使用期限（天）" "INFO" "1" ("$lnMinAge") "未能解析数值，请核对原始输出"
}

# 保持的密码历史 = 5
$lnHist = Get-NaLine @("保持的密码历史","Length of password history","密码历史")
$vHist  = Get-NaNumber $lnHist
if($vHist -ne $null){
  if($vHist -eq 5){ Add-Item "保持的密码历史（个）" "PASS" "5" "$vHist" }
  else             { Add-Item "保持的密码历史（个）" "WARN" "5" "$vHist" "课程要求 5 个" }
} else {
  Add-Item "保持的密码历史（个）" "INFO" "5" ("$lnHist") "未能解析数值，请核对原始输出"
}

# ---------- 任务② 账户锁定 ----------
Add-Task "任务2 · 账户锁定策略（net accounts）"

# 锁定阈值 = 5
$lnThr = Get-NaLine @("锁定阈值","Lockout threshold")
$vThr  = Get-NaNumber $lnThr
if($vThr -ne $null){
  if($vThr -eq 5){ Add-Item "账户锁定阈值（次）" "PASS" "5" "$vThr" }
  else            { Add-Item "账户锁定阈值（次）" "WARN" "5" "$vThr" "课程要求 5 次失败后锁定" }
} else {
  Add-Item "账户锁定阈值（次）" "INFO" "5" ("$lnThr") "未能解析数值（可能显示为『从不』表示未设置）"
}

# 锁定持续时间 = 30
$lnDur = Get-NaLine @("锁定持续时间","Lockout duration")
$vDur  = Get-NaNumber $lnDur
if($vDur -ne $null){
  if($vDur -eq 30){ Add-Item "锁定持续时间（分钟）" "PASS" "30" "$vDur" }
  else             { Add-Item "锁定持续时间（分钟）" "WARN" "30" "$vDur" "课程要求 30 分钟" }
} else {
  Add-Item "锁定持续时间（分钟）" "INFO" "30" ("$lnDur") "未能解析数值，请核对原始输出"
}

# 锁定观测窗口 / 重置计数器 = 15
$lnWin = Get-NaLine @("锁定观测窗口","重置计数器","重置帐户锁定计数器","Lockout observation window")
$vWin  = Get-NaNumber $lnWin
if($vWin -ne $null){
  if($vWin -eq 15){ Add-Item "锁定观测窗口/重置计数器（分钟）" "PASS" "15" "$vWin" }
  else             { Add-Item "锁定观测窗口/重置计数器（分钟）" "WARN" "15" "$vWin" "课程要求 15 分钟" }
} else {
  Add-Item "锁定观测窗口/重置计数器（分钟）" "INFO" "15" ("$lnWin") "未能解析数值，请核对原始输出"
}

# ---------- 任务③ 审计 ----------
Add-Task "任务3 · 审计策略（auditpol）"

$apAll = auditpol /get /category:* 2>$null
$apKey = $apAll | Select-String -Pattern "登录|Logon|凭据|Credential|账户管理|Account Management" -EA SilentlyContinue
if($apKey){
  $apText = (($apKey | ForEach-Object { $_.Line.Trim() }) -join "`n")
  Add-Item "审计子类配置（登录/凭据/账户管理，采集）" "INFO" "" $apText
} else {
  Add-Item "审计子类配置（登录/凭据/账户管理，采集）" "INFO" "" ("$apAll" | Out-String) "未匹配到关键子类，输出全文供核对"
}

Add-Task "任务3 · 安全日志关键事件（Get-WinEvent）"

$evt = $null
# 分别统计每个事件 ID 的真实总数：不能用混合查询 + MaxEvents，
# 否则海量的 4624(登录成功) 会把 4625/4720 挤出取样窗口，导致漏采。
$c4624 = (Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624} -EA SilentlyContinue | Measure-Object).Count
$c4625 = (Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625} -EA SilentlyContinue | Measure-Object).Count
$c4720 = (Get-WinEvent -FilterHashtable @{LogName='Security';Id=4720} -EA SilentlyContinue | Measure-Object).Count
$cntStr = "4624=$c4624 ; 4625=$c4625 ; 4720=$c4720（安全日志中各 ID 总数）"
Add-Item "安全日志事件计数（采集）" "INFO" "" $cntStr

# 4624 登录成功
if($c4624 -gt 0){ Add-Item "事件 4624（登录成功）" "PASS" ">=1" "$c4624 条" }
else            { Add-Item "事件 4624（登录成功）" "WARN" ">=1" "0 条" "未采集到登录成功事件，请确认已开启『登录/注销』审计并产生一次登录" }

# 4625 登录失败
if($c4625 -gt 0){ Add-Item "事件 4625（登录失败）" "PASS" ">=1" "$c4625 条" }
else            { Add-Item "事件 4625（登录失败）" "WARN" ">=1" "0 条" "未采集到登录失败事件，请故意输错一次密码以生成该事件" }

# 4720 创建用户
if($c4720 -gt 0){ Add-Item "事件 4720（创建用户账户）" "PASS" ">=1" "$c4720 条" }
else            { Add-Item "事件 4720（创建用户账户）" "WARN" ">=1" "0 条" "未采集到创建用户事件，请确认已开启『账户管理』审计并新建过用户" }

Export-CheckReport
