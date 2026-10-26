# check22.ps1 — 第22课 Windows Defender 与恶意软件防护：检查与证据采集（在被配置机上运行，本实验为 DC1）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check22.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson22" "第 22 课 · Windows Defender 与恶意软件防护"
$m = Get-MpPreference -EA SilentlyContinue
$s = Get-MpComputerStatus -EA SilentlyContinue

Add-Task "任务1 · 本地防护状态与扫描计划"
if($s -and $s.RealTimeProtectionEnabled){ Add-Item "实时保护已启用" "PASS" "RealTimeProtectionEnabled=True" "True" }
else { Add-Item "实时保护已启用" "FAIL" "True" ($(if($s){"$($s.RealTimeProtectionEnabled)"}else{"状态不可用"})) "Set-MpPreference -DisableRealtimeMonitoring `$false" }

$day = $m.ScanScheduleDay; $tm = "$($m.ScanScheduleTime)"
if($day -eq 1 -and $tm -match "02:00:00"){ Add-Item "扫描计划 = 周日 02:00" "PASS" "Day=1(周日) Time=02:00" ("Day=$day Time=$tm") }
else { Add-Item "扫描计划 = 周日 02:00" "WARN" "Day=1 Time=02:00:00" ("Day=$day Time=$tm") "Set-MpPreference -ScanScheduleDay 1 -ScanScheduleTime 02:00:00" }

Add-Task "任务1 · 排除项（三类）"
$ep = @($m.ExclusionPath); $ee = @($m.ExclusionExtension); $epr = @($m.ExclusionProcess)
$pOk = $ep -contains "C:\LabFiles"
$eOk = ($ee | ForEach-Object { $_.TrimStart('.') }) -contains "log"
$prOk = ($epr | ForEach-Object { $_.ToLower() }) -contains "w3wp.exe"
if($pOk -and $eOk -and $prOk){ Add-Item "三类排除项已配置（路径/扩展名/进程）" "PASS" "C:\LabFiles + .log + w3wp.exe" ("Path=[$($ep -join ',')] Ext=[$($ee -join ',')] Proc=[$($epr -join ',')]") }
else { Add-Item "三类排除项已配置（路径/扩展名/进程）" "FAIL" "C:\LabFiles + .log + w3wp.exe" ("Path=[$($ep -join ',')] Ext=[$($ee -join ',')] Proc=[$($epr -join ',')]") "Add-MpPreference -ExclusionPath/-ExclusionExtension/-ExclusionProcess" }

Add-Task "任务2 · GPO 集中管理"
Import-Module GroupPolicy -EA SilentlyContinue
$g = Get-GPO -Name "Defender-Policy" -EA SilentlyContinue
$linked = @()
try { $linked = @((Get-GPInheritance -Target "OU=Company,DC=lab,DC=local" -EA Stop).GpoLinks | ForEach-Object { $_.DisplayName }) } catch {}
if($g -and ($linked -contains "Defender-Policy")){ Add-Item "GPO Defender-Policy 已链接到 Company OU" "PASS" "存在+链接Company" ("Company链接: " + ($linked -join ",")) }
else { Add-Item "GPO Defender-Policy 已链接到 Company OU" "FAIL" "存在+链接Company" ($(if($g){"存在但未链: "+($linked -join ",")}else{"GPO不存在"})) "New-GPO Defender-Policy; New-GPLink -Target OU=Company,..." }

Add-Task "任务2/3 · ASR 规则与 EICAR 检测"
$ids = @($m.AttackSurfaceReductionRules_Ids); $acts = @($m.AttackSurfaceReductionRules_Actions)
$asrOk = $false
for($i=0;$i -lt $ids.Count;$i++){ if("$($ids[$i])" -match "BE9BA2D9" -and ("$($acts[$i])" -eq "1" -or "$($acts[$i])" -eq "Enabled")){ $asrOk=$true } }
if($asrOk){ Add-Item "ASR 规则已启用（阻止邮件可执行内容）" "PASS" "BE9BA2D9... = Enabled" ("ids=" + ($ids -join ",") + " actions=" + ($acts -join ",")) }
else { Add-Item "ASR 规则已启用（阻止邮件可执行内容）" "FAIL" "BE9BA2D9...=Enabled" ("ids=" + ($ids -join ",") + " actions=" + ($acts -join ",")) "Set-MpPreference -AttackSurfaceReductionRules_Ids BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550 -AttackSurfaceReductionRules_Actions Enabled" }

$det = @(Get-MpThreatDetection -EA SilentlyContinue)
$eicar = @($det | Where-Object { "$($_.Resources)" -match "eicar" -or "$($_.ThreatID)" -eq "2147519003" })
$thr = @(Get-MpThreat -EA SilentlyContinue | Where-Object { "$($_.ThreatName)" -match "EICAR" })
if($eicar.Count -gt 0 -or $thr.Count -gt 0){ $tn = ($thr | ForEach-Object { $_.ThreatName }) -join ","; Add-Item "EICAR 测试有检测记录（Defender 已检出）" "PASS" "有 EICAR 威胁记录" ("检测数=" + $det.Count + " " + $tn) }
else { Add-Item "EICAR 测试有检测记录（Defender 已检出）" "FAIL" "有 EICAR 威胁记录" ("检测记录数=" + $det.Count) "把 EICAR 写到非排除路径(如 C:\EicarTest)后由实时保护检出" }

Add-Task "汇总（采集）"
Add-Item "Defender 状态（采集）" "INFO" "" ($(if($s){"AV=$($s.AntivirusEnabled) RTP=$($s.RealTimeProtectionEnabled) 签名=$($s.AntivirusSignatureVersion)"}else{"不可用"}))
Add-Item "威胁记录（采集）" "INFO" "" ((@(Get-MpThreat -EA SilentlyContinue) | ForEach-Object { $_.ThreatName }) -join " ; ")

Export-CheckReport
