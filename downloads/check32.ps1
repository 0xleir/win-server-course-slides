# check32.ps1 — 第32课 企业域环境全流程搭建：检查与证据采集（只需在 SVR2 上运行一次）
# 用法：在 SVR2 上以 LAB\Administrator 身份、管理员 PowerShell 运行  powershell -ExecutionPolicy Bypass -File check32.ps1
# DNS 记录通过向 DC1(10.10.10.10) 发查询来检查，不需要再去 DC1 上跑
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson32" "第 32 课 · 企业域环境全流程搭建"

$hostName = $env:COMPUTERNAME
$dnsSrv = "10.10.10.10"

Add-Task "运行位置"
if($hostName -match "^SVR"){ Add-Item "本脚本在 SVR2 上运行" "PASS" "SVR2" $hostName }
else { Add-Item "本脚本在 SVR2 上运行" "FAIL" "SVR2" $hostName "IIS/证书/共享都在 SVR2 上，请把脚本拷到 SVR2 再运行" }

Add-Task "任务1 · IIS 安装状态（SVR2）"
$feat = Get-WindowsFeature -Name Web-Server -EA SilentlyContinue
if($feat -and $feat.InstallState -eq "Installed"){ Add-Item "Web-Server 角色已安装" "PASS" "Installed" "Installed" }
else { Add-Item "Web-Server 角色已安装" "FAIL" "Installed" ($(if($feat){"$($feat.InstallState)"}else{"未找到"})) "在 SVR2 上运行 Install-WindowsFeature Web-Server -IncludeManagementTools（第32课任务1）" }

$w3svc = Get-Service W3SVC -EA SilentlyContinue
if($w3svc -and $w3svc.Status -eq "Running"){ Add-Item "W3SVC 服务运行中" "PASS" "Running" "Running" }
else { Add-Item "W3SVC 服务运行中" "FAIL" "Running" ($(if($w3svc){"$($w3svc.Status)"}else{"未找到服务"})) "Start-Service W3SVC；若装完就能跑，先确认角色是否真的装成功" }

Add-Task "任务2 · HTTPS 绑定与证书（SVR2）"
Import-Module WebAdministration -EA SilentlyContinue
$bindings = @(Get-WebBinding -EA SilentlyContinue | Where-Object { $_.protocol -eq "https" })
if($bindings.Count -gt 0){ Add-Item "存在 HTTPS(443) 绑定" "PASS" "存在" ($bindings | ForEach-Object { $_.bindingInformation } | Select-Object -Unique | Out-String).Trim() }
else { Add-Item "存在 HTTPS(443) 绑定" "FAIL" "存在" "未找到" "在 IIS 管理器里为站点添加 https/443 绑定并选择已签发的证书（第32课任务2）" }

$certs = @(Get-ChildItem Cert:\LocalMachine\My -EA SilentlyContinue | Where-Object { $_.Issuer -match "Lab-Root-CA" })
if($certs.Count -gt 0){ Add-Item "本机存在 Lab-Root-CA 签发的证书" "PASS" "存在" ($certs | ForEach-Object { $_.Subject } | Select-Object -Unique | Out-String).Trim() }
else { Add-Item "本机存在 Lab-Root-CA 签发的证书" "FAIL" "存在" "未找到" "按课件用 web.inf + certreq -new/-submit/-accept 申请（-config <DC计算机名>.lab.local\Lab-Root-CA）（第32课任务2）" }

# 绑定在 443 上的证书必须带 SAN，且覆盖 web 和 intranet 两个名字（Edge/Chrome 只认 SAN）
$sslHash = ($bindings | Select-Object -First 1).certificateHash
$bound = if($sslHash){ Get-Item "Cert:\LocalMachine\My\$sslHash" -EA SilentlyContinue } else { $null }
$sanNames = if($bound){ @($bound.DnsNameList | ForEach-Object { $_.Unicode.ToLower() }) } else { @() }
$hasSanExt = $bound -and ($bound.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.17" })
if($bound -and $hasSanExt -and ($sanNames -contains "web.lab.local") -and ($sanNames -contains "intranet.lab.local")){
  Add-Item "443 证书 SAN 含 web 与 intranet" "PASS" "web.lab.local + intranet.lab.local" ($sanNames -join ", ") }
elseif($bound){
  Add-Item "443 证书 SAN 含 web 与 intranet" "FAIL" "web.lab.local + intranet.lab.local" ($(if($hasSanExt){"SAN: " + ($sanNames -join ", ")}else{"无 SAN（只有 CN=" + $bound.Subject + "）"})) "IIS「创建域证书」加不了 SAN，Edge 会报 ERR_CERT_COMMON_NAME_INVALID；按课件 web.inf（2.5.29.17 行）用 certreq 重新申请并绑定" }
else { Add-Item "443 证书 SAN 含 web 与 intranet" "FAIL" "已绑定证书" "443 绑定未选证书" "绑定 https 443 时选友好名称 Intranet-SAN 的证书" }

Add-Task "任务3 · 部门共享（共享权限 + NTFS，SVR2）"
$shareNames = @("IT-Share","Finance-Share")
foreach($sn in $shareNames){
  $sh = Get-SmbShare -Name $sn -EA SilentlyContinue
  if($sh){ Add-Item "共享 $sn 存在" "PASS" "存在" $sh.Path }
  else { Add-Item "共享 $sn 存在" "FAIL" "存在" "未找到" "New-SmbShare -Name `"$sn`" -Path <目录> -ChangeAccess <域组>（第32课任务3，共享名必须精确，第33课要用）" }
}
$itAcl = Get-SmbShareAccess -Name "IT-Share" -EA SilentlyContinue
if($itAcl -and ($itAcl | Where-Object { $_.AccountName -match "Domain-IT" })){ Add-Item "IT-Share 共享权限授予 Domain-IT" "PASS" "存在" "存在" }
else { Add-Item "IT-Share 共享权限授予 Domain-IT" "WARN" "存在" "未找到或共享不存在" "检查共享权限是否授予了 LAB\Domain-IT" }


Add-Task "任务4 · DNS 记录（向 DC1 查询）"
$aAns = @(Resolve-DnsName "web.lab.local" -Type A -Server $dnsSrv -DnsOnly -EA SilentlyContinue | Where-Object { $_.Section -eq "Answer" -and $_.Type -eq "A" })
if($aAns.IPAddress -contains "10.10.10.20"){ Add-Item "web A 记录 → 10.10.10.20" "PASS" "10.10.10.20" ($aAns.IPAddress -join ",") }
else { Add-Item "web A 记录 → 10.10.10.20" "FAIL" "10.10.10.20" ($(if($aAns){$aAns.IPAddress -join ","}else{"未找到"})) "在 DC1 上运行 Add-DnsServerResourceRecordA -ZoneName lab.local -Name web -IPv4Address 10.10.10.20" }

# 注意：查 CNAME 时，如果 intranet 其实是 A 记录，服务器会回一条 SOA(Authority 段)，所以只认 Answer 段里的 CNAME
$cnAns = @(Resolve-DnsName "intranet.lab.local" -Type CNAME -Server $dnsSrv -DnsOnly -EA SilentlyContinue | Where-Object { $_.Section -eq "Answer" -and $_.Type -eq "CNAME" })
$cnTarget = ($cnAns | ForEach-Object { $_.NameHost.TrimEnd('.') }) -join ","
$intrA = @(Resolve-DnsName "intranet.lab.local" -Type A -Server $dnsSrv -DnsOnly -EA SilentlyContinue | Where-Object { $_.Section -eq "Answer" -and $_.Type -eq "A" -and $_.Name -eq "intranet.lab.local" })
if($cnTarget -eq "web.lab.local"){ Add-Item "intranet 是 CNAME → web.lab.local" "PASS" "web.lab.local" $cnTarget }
elseif($intrA.Count -gt 0){ Add-Item "intranet 是 CNAME → web.lab.local" "FAIL" "CNAME web.lab.local" "intranet 是 A 记录" "intranet 被建成了 A 记录（可能是第13课遗留），在 DC1 的 DNS 管理器里删掉后用 Add-DnsServerResourceRecordCName 重建" }
else { Add-Item "intranet 是 CNAME → web.lab.local" "FAIL" "web.lab.local" ($(if($cnTarget){$cnTarget}else{"未找到"})) "在 DC1 上运行 Add-DnsServerResourceRecordCName -ZoneName lab.local -Name intranet -HostNameAlias web.lab.local" }

Clear-DnsClientCache -EA SilentlyContinue
$res = @(Resolve-DnsName "intranet.lab.local" -DnsOnly -EA SilentlyContinue | Where-Object { $_.Type -eq "A" })
if($res.IPAddress -contains "10.10.10.20"){ Add-Item "intranet.lab.local 最终解析到 10.10.10.20" "PASS" "10.10.10.20" ($res.IPAddress -join ",") }
else { Add-Item "intranet.lab.local 最终解析到 10.10.10.20" "FAIL" "10.10.10.20" ($(if($res){$res.IPAddress -join ","}else{"解析失败"})) "检查 SVR2 的 DNS 是否指向 10.10.10.10，再查上面两条记录" }

$ns = (cmd /c "nslookup intranet.lab.local $dnsSrv 2>&1" | Out-String).Trim()
Add-Item "nslookup intranet.lab.local（原始输出）" "INFO" "" $ns

Export-CheckReport
