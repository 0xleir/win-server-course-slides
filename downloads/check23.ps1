# check23.ps1 — 第23课 证书服务 AD CS：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check23.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson23" "第 23 课 · 证书服务 AD CS"
Import-Module WebAdministration -EA SilentlyContinue

Add-Task "任务1 · 企业根 CA"
$svc = Get-Service CertSvc -EA SilentlyContinue
if($svc -and $svc.Status -eq "Running"){ Add-Item "CertSvc（证书服务）运行中" "PASS" "Running" "Running" }
else { Add-Item "CertSvc（证书服务）运行中" "FAIL" "Running" ($(if($svc){$svc.Status}else{"不存在"})) "Install-AdcsCertificationAuthority" }

$caName = ""
try { $caName = (certutil -getconfig 2>&1 | Out-String); if($caName -notmatch "Lab-Root-CA"){ $caName = (certutil 2>&1 | Out-String) } } catch {}
$caOk = ($caName -match "Lab-Root-CA")
# 更稳：从注册表读 CA 名
$caReg = (Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration" -EA SilentlyContinue | Select-Object -First 1).PSChildName
if($caReg -eq "Lab-Root-CA"){ $caOk = $true }
if($caOk){ Add-Item "CA 名称为 Lab-Root-CA（企业根 CA）" "PASS" "Lab-Root-CA" ($(if($caReg){$caReg}else{"Lab-Root-CA"})) }
else { Add-Item "CA 名称为 Lab-Root-CA（企业根 CA）" "FAIL" "Lab-Root-CA" ($(if($caReg){$caReg}else{"未知"})) }

Add-Task "任务2 · 模板与证书"
$tpls = @(); try { $tpls = @(certutil -CATemplates 2>&1) -join "`n" } catch {}
if($tpls -match "WebServer|Web Server|LabWebServer|Lab Web Server"){ Add-Item "CA 已发布 Web 服务器证书模板" "PASS" "含 WebServer/Lab Web Server" "已发布" }
else { Add-Item "CA 已发布 Web 服务器证书模板" "FAIL" "含 Web 服务器模板" "未发布" "certsrv.msc → 证书模板 → 新建 → 发布" }

# CompanySite https 绑定使用 Lab-Root-CA 签发的证书
$webcert = Get-ChildItem Cert:\LocalMachine\My -EA SilentlyContinue | Where-Object { $_.Subject -match "www\.lab\.local" -and $_.Issuer -match "Lab-Root-CA" } | Select-Object -First 1
$httpsBind = Get-WebBinding -Name CompanySite -Protocol https -EA SilentlyContinue
$boundThumb = ""
if($httpsBind){ try { $boundThumb = ($httpsBind.certificateHash) } catch {} }
if(-not $boundThumb){
  $b = Get-ChildItem IIS:\SslBindings -EA SilentlyContinue | Where-Object { $_.Port -eq 443 } | Select-Object -First 1
  if($b){ $boundThumb = $b.Thumbprint }
}
if($webcert -and ($boundThumb -eq $webcert.Thumbprint)){ Add-Item "CompanySite https 绑定使用 Lab-Root-CA 签发的证书" "PASS" "绑定 www.lab.local(Lab-Root-CA)" ("issuer=" + $webcert.Issuer) }
elseif($webcert){ Add-Item "CompanySite https 绑定使用 Lab-Root-CA 签发的证书" "WARN" "绑定该证书" ("证书已签发但绑定指纹=" + $boundThumb + " 证书指纹=" + $webcert.Thumbprint) }
else { Add-Item "CompanySite https 绑定使用 Lab-Root-CA 签发的证书" "FAIL" "www.lab.local 由 Lab-Root-CA 签发并绑定" "未找到该证书" "IIS 创建域证书 CN=www.lab.local，CA 选 Lab-Root-CA，绑定到 CompanySite" }

Add-Task "任务3 · GPO 自动注册与根证书分发"
$ae = (Get-GPRegistryValue -Name "Default Domain Policy" -Key "HKLM\Software\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "AEPolicy" -EA SilentlyContinue).Value
if($ae -ge 1){ Add-Item "GPO 已启用证书自动注册（AEPolicy）" "PASS" "AEPolicy>=1" "AEPolicy=$ae" }
else { Add-Item "GPO 已启用证书自动注册（AEPolicy）" "FAIL" "AEPolicy>=1(7=启用+续订+更新)" ($(if($null -ne $ae){"$ae"}else{"未配置"})) "GPO 公钥策略 → 证书服务客户端-自动注册 → 已启用" }

$rootPub = $false
try { $rootPub = ((certutil -store -enterprise Root 2>&1 | Select-String "Lab-Root-CA" | Measure-Object).Count -gt 0) } catch {}
$rootLocal = @(Get-ChildItem Cert:\LocalMachine\Root -EA SilentlyContinue | Where-Object { $_.Subject -match "Lab-Root-CA" }).Count -gt 0
if($rootPub -or $rootLocal){ Add-Item "根 CA 证书已分发（AD 企业存储/受信任根）" "PASS" "在企业Root/本机受信任根" ("企业AD=$rootPub 本机Root=$rootLocal") }
else { Add-Item "根 CA 证书已分发（AD 企业存储/受信任根）" "FAIL" "已分发" "未检出" "GPO 导入根证书到『受信任的根证书颁发机构』" }

# CLIENT1 无警告：需 CLIENT1 加域+信任根。单机环境用"本机能否验证证书链"做诚实代理判定
$chainOk = $false
if($webcert){ try { $chainOk = [bool]($webcert.Verify()) } catch { $chainOk = $false } }
if($chainOk){ Add-Item "证书链可信（根已信任，CLIENT1 访问应无警告）" "PASS" "证书链验证通过" "www.lab.local 证书链验证成功（根受信任）" }
else { Add-Item "证书链可信（根已信任，CLIENT1 访问应无警告）" "FAIL" "链验证通过" "链验证失败或证书缺失（需 CLIENT1 加域 + gpupdate 后在客户端实测）" "在 CLIENT1 上 gpupdate /force 后访问 https://www.lab.local" }

Add-Task "汇总（采集）"
Add-Item "CA 已发布模板（采集）" "INFO" "" (($tpls -split "`n" | Where-Object { $_ -match "TemplatePropCommonName|模板" } | Select-Object -First 6) -join " ")
Add-Item "www 服务器证书（采集）" "INFO" "" ($(if($webcert){"Subject=$($webcert.Subject) Issuer=$($webcert.Issuer) 到期=$($webcert.NotAfter)"}else{"无"}))

Export-CheckReport
