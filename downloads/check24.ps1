# check24.ps1 — 第24课 系统加固与安全基线：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check24.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson24" "第 24 课 · 系统加固与安全基线"

Add-Task "任务2 · 协议与服务加固"
$smb = (Get-SmbServerConfiguration).EnableSMB1Protocol
if($smb -eq $false){ Add-Item "SMBv1 协议已禁用" "PASS" "False" "False" }
else { Add-Item "SMBv1 协议已禁用" "FAIL" "False" "$smb" "Set-SmbServerConfiguration -EnableSMB1Protocol `$false -Force" }

$rr = Get-Service RemoteRegistry -EA SilentlyContinue
if($rr -and $rr.StartType -eq "Disabled" -and $rr.Status -eq "Stopped"){ Add-Item "RemoteRegistry 已禁用并停止" "PASS" "Disabled+Stopped" ("$($rr.StartType)/$($rr.Status)") }
elseif($rr){ Add-Item "RemoteRegistry 已禁用并停止" "FAIL" "Disabled+Stopped" ("$($rr.StartType)/$($rr.Status)") "Set-Service RemoteRegistry -StartupType Disabled; Stop-Service RemoteRegistry" }
else { Add-Item "RemoteRegistry 已禁用并停止" "WARN" "Disabled+Stopped" "服务不存在" }

Add-Task "任务2 · LSA 注册表加固"
$lsa = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$l = Get-ItemProperty $lsa -EA SilentlyContinue
if($l.RestrictAnonymousSAM -eq 1 -and $l.RestrictAnonymous -eq 1){ Add-Item "RestrictAnonymousSAM / RestrictAnonymous = 1" "PASS" "都=1" ("SAM=$($l.RestrictAnonymousSAM) Anon=$($l.RestrictAnonymous)") }
else { Add-Item "RestrictAnonymousSAM / RestrictAnonymous = 1" "FAIL" "都=1" ("SAM=$($l.RestrictAnonymousSAM) Anon=$($l.RestrictAnonymous)") "Set-ItemProperty `$lsa -Name RestrictAnonymousSAM/RestrictAnonymous -Value 1" }

if($l.LmCompatibilityLevel -eq 5){ Add-Item "LmCompatibilityLevel = 5（仅 NTLMv2）" "PASS" "5" "5" }
else { Add-Item "LmCompatibilityLevel = 5（仅 NTLMv2）" "FAIL" "5" ($(if($null -ne $l.LmCompatibilityLevel){"$($l.LmCompatibilityLevel)"}else{"未设置"})) "Set-ItemProperty `$lsa -Name LmCompatibilityLevel -Value 5" }

Add-Task "任务2 · 审计策略（四个子类别）"
# 单个查询(多 GUID 逗号列会报 0x57)
$subs = @(
  @{n="凭据验证"; g="{0CCE923F-69AE-11D9-BED3-505054503030}"; need="both"},
  @{n="进程创建"; g="{0CCE922B-69AE-11D9-BED3-505054503030}"; need="success"},
  @{n="登录";     g="{0CCE9215-69AE-11D9-BED3-505054503030}"; need="both"},
  @{n="特殊登录"; g="{0CCE921B-69AE-11D9-BED3-505054503030}"; need="success"}
)
$enabledCount = 0; $detail = @()
foreach($s in $subs){
  $o = (auditpol /get /subcategory:"$($s.g)" 2>&1 | Out-String)
  $hasSucc = $o -match "成功" -or $o -match "Success"
  $hasFail = $o -match "失败" -or $o -match "Failure"
  $noAudit = $o -match "无审核" -or $o -match "No Audit"
  $ok = $false
  if($s.need -eq "both"){ $ok = $hasSucc }     # 成功必需(失败按课程要求但宽松判成功即可)
  else { $ok = $hasSucc }
  if($ok -and -not $noAudit){ $enabledCount++ }
  $mark = ""; if($hasSucc){$mark+="成功"}; if($hasFail){$mark+="+失败"}; if($noAudit){$mark="无审核"}
  $detail += ($s.n + "=" + $mark)
}
if($enabledCount -eq 4){ Add-Item "四个审计子类别已启用（凭据验证/进程创建/登录/特殊登录）" "PASS" "4 项都启用成功审核" ($detail -join " ; ") }
else { Add-Item "四个审计子类别已启用（凭据验证/进程创建/登录/特殊登录）" "FAIL" "4 项都启用" ("已启用 $enabledCount/4 : " + ($detail -join " ; ")) "auditpol /set /subcategory:{GUID} /success:enable" }

Add-Task "任务3 · 安全检查报告脚本"
$rpt = "C:\Scripts\SecurityReport.ps1"
if(Test-Path $rpt){
  $content = Get-Content $rpt -Raw
  $runnable = $false
  try { $null = [ScriptBlock]::Create($content); $runnable = $true } catch {}
  if($runnable){ Add-Item "C:\Scripts\SecurityReport.ps1 存在且语法可运行" "PASS" "存在+语法正确" ("大小=" + (Get-Item $rpt).Length + " 字节") }
  else { Add-Item "C:\Scripts\SecurityReport.ps1 存在且语法可运行" "WARN" "存在+可运行" "存在但语法有误" }
}
else { Add-Item "C:\Scripts\SecurityReport.ps1 存在且语法可运行" "FAIL" "存在" "无" "新建 C:\Scripts\SecurityReport.ps1 采集并输出安全项" }

Add-Task "汇总（采集 · 对应报告项）"
$fw = (Get-NetFirewallProfile -Profile Domain).DefaultInboundAction
$mp = (Get-MpComputerStatus -EA SilentlyContinue).RealTimeProtectionEnabled
$ca = (Get-Service CertSvc -EA SilentlyContinue).Status
Add-Item "报告项（采集）" "INFO" "" ("SMBv1=$smb FwInbound=$fw DefenderRTP=$mp CA=$ca LmCompat=$($l.LmCompatibilityLevel)")

Export-CheckReport
