# check11.ps1 — 第11课 IIS 安全加固：任务检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check11.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson11" "第 11 课 · IIS 安全加固"
Import-Module WebAdministration -EA SilentlyContinue

# curl.exe 不受 PowerShell 5.1 TLS/证书回调限制；-k 接受自签名证书
function Probe([string]$url, [string]$from = ""){
  $a = @("-k","-s","-o","NUL","-w","%{http_code}|%{redirect_url}","--max-time","8")
  if($from){ $u = [Uri]$url; $a += @("--interface",$from,"--resolve","$($u.Host):$($u.Port):$from") }
  $o = & curl.exe @a $url 2>$null; $p = "$o".Split('|'); return @{ Code = [int]("0" + $p[0]); Loc = $p[1] }
}

Add-Task "任务1 · 自签名证书与 HTTPS 绑定"
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq "Lab SSL Cert" } | Sort NotAfter | Select -Last 1
if($cert){
  Add-Item "证书 Lab SSL Cert 在 LocalMachine\My" "PASS" "存在" "Thumbprint=$($cert.Thumbprint)"
  $dns = @($cert.DnsNameList | ForEach-Object { $_.Unicode })
  if(($dns -contains "www.lab.local") -and ($dns -contains "hr.lab.local")){ Add-Item "证书含 www/hr 两个名字" "PASS" "www.lab.local, hr.lab.local" ($dns -join ", ") }
  else { Add-Item "证书含 www/hr 两个名字" "WARN" "www.lab.local, hr.lab.local" ($dns -join ", ") "-DnsName 要写两个名字" }
  $days = [int]($cert.NotAfter - (Get-Date)).TotalDays
  if($days -ge 600){ Add-Item "证书有效期约 2 年" "PASS" "NotAfter≈两年后" "$($cert.NotAfter.ToString('yyyy-MM-dd'))（剩 $days 天）" }
  else { Add-Item "证书有效期约 2 年" "WARN" "NotAfter≈两年后" "$($cert.NotAfter.ToString('yyyy-MM-dd'))（剩 $days 天）" "默认只有 1 年，漏了 -NotAfter" }
} else {
  $any = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match "www.lab.local" } | Select -First 1
  Add-Item "证书 Lab SSL Cert 在 LocalMachine\My" "FAIL" "存在" ($(if($any){"有 www.lab.local 证书但 FriendlyName=$($any.FriendlyName)"}else{"不存在"})) "IIS 只从 LocalMachine\My 找证书"
}
$https = @(Get-WebBinding -Name CompanySite -Protocol https -EA SilentlyContinue)
$h443 = $https | Where-Object { $_.bindingInformation -match '^\*:443:(www\.lab\.local)?$' } | Select -First 1
if($h443){
  Add-Item "CompanySite 有 https 443 绑定" "PASS" "*:443:www.lab.local" $h443.bindingInformation
  $hash = "$($h443.certificateHash)"
  if($hash -and $cert -and $hash -ieq $cert.Thumbprint){ Add-Item "https 绑定使用 Lab SSL Cert" "PASS" $cert.Thumbprint $hash }
  elseif($hash){ Add-Item "https 绑定使用 Lab SSL Cert" "WARN" "Lab SSL Cert" $hash "绑定了别的证书" }
  else { Add-Item "https 绑定使用 Lab SSL Cert" "FAIL" "已选证书" "未绑定证书" "编辑 https 绑定，在 SSL 证书下拉框选 Lab SSL Cert" }
} else { Add-Item "CompanySite 有 https 443 绑定" "FAIL" "*:443:www.lab.local" (($https.bindingInformation) -join " ; ") "CompanySite → 绑定 → 添加 https" }
$fw = Get-NetFirewallRule -Name "IIS-WebServerRole-HTTPS-In-TCP" -EA SilentlyContinue
if($fw -and $fw.Enabled -eq "True"){ Add-Item "防火墙放行 HTTPS 443" "PASS" "已启用" $fw.DisplayName } else { Add-Item "防火墙放行 HTTPS 443" "WARN" "已启用" "未启用" "CLIENT1 打不开 https" }
$r = Probe "https://www.lab.local/"
if($r.Code -eq 200){ Add-Item "https://www.lab.local 返回 200" "PASS" "200" "200" } else { Add-Item "https://www.lab.local 返回 200" "FAIL" "200" "$($r.Code) $($r.Loc)" ($(if($r.Code -eq 301){"https 也被重定向 = 重定向循环，见本课排障页"}else{""})) }

Add-Task "任务2 · HTTP 跳转到 HTTPS"
$r = Probe "http://www.lab.local/"
if($r.Code -eq 301 -and $r.Loc -match '^https://www\.lab\.local'){ Add-Item "http://www.lab.local → 301 到 https" "PASS" "301 → https://www.lab.local" "$($r.Code) → $($r.Loc)" }
elseif($r.Code -in 302,307,308 -and $r.Loc -match '^https://'){ Add-Item "http://www.lab.local → 301 到 https" "WARN" "301" "$($r.Code) → $($r.Loc)" "能跳转，但不是永久(301)" }
else { Add-Item "http://www.lab.local → 301 到 https" "FAIL" "301 → https" "$($r.Code) $($r.Loc)" }
$r2 = Probe "http://www.lab.local/docs/"
if($r2.Code -eq 301 -and $r2.Loc -match '^https://www\.lab\.local/docs/'){ Add-Item "子路径保留：/docs/ → https://…/docs/" "PASS" "保留路径" $r2.Loc }
else { Add-Item "子路径保留：/docs/ → https://…/docs/" "WARN" "保留路径" "$($r2.Code) $($r2.Loc)" "勾选了「仅重定向到此目标」会把所有路径都跳到首页" }
$loop = Probe "https://www.lab.local/docs/"
if($loop.Code -eq 200){ Add-Item "https 不再被重定向（无循环）" "PASS" "200" "200" } else { Add-Item "https 不再被重定向（无循环）" "FAIL" "200" "$($loop.Code) → $($loop.Loc)" "HTTP 重定向不要开在 CompanySite 上" }
$rs = @(Get-Website | Where-Object { $_.name -ne "CompanySite" -and (Get-WebBinding -Name $_.name -Protocol http).bindingInformation -contains "*:80:www.lab.local" })
Add-Item "谁接住 http://www.lab.local（采集）" "INFO" "" ($(if($rs){ "跳转站点: " + (($rs | ForEach-Object { "$($_.name)[$($_.state)] " + (Get-WebConfigurationProperty -PSPath "IIS:\Sites\$($_.name)" -Filter system.webServer/httpRedirect -Name destination).Value }) -join " ; ") } else { "CompanySite 自身" }))

Add-Task "任务3 · HRPortal 只允许内网"
$ip = @(Get-WebConfiguration -PSPath IIS:\ -Location HRPortal -Filter system.webServer/security/ipSecurity/add -EA SilentlyContinue)
$allowLan = $ip | Where-Object { $_.ipAddress -eq "10.10.10.0" -and $_.subnetMask -eq "255.255.255.0" -and $_.allowed }
if($allowLan){ Add-Item "允许条目 10.10.10.0/255.255.255.0" "PASS" "允许 10.10.10.0/24" "10.10.10.0/255.255.255.0 允许" }
else { Add-Item "允许条目 10.10.10.0/255.255.255.0" "FAIL" "允许 10.10.10.0/24" ($(if($ip){($ip | ForEach-Object { "$($_.ipAddress)/$($_.subnetMask) allowed=$($_.allowed)" }) -join "; "}else{"无条目"})) "掩码要写 255.255.255.0" }
$unl = (Get-WebConfigurationProperty -PSPath IIS:\ -Location HRPortal -Filter system.webServer/security/ipSecurity -Name allowUnlisted -EA SilentlyContinue).Value
if($unl -eq $false){ Add-Item "未指定的客户端 = 拒绝" "PASS" "allowUnlisted=False" "False" }
else { Add-Item "未指定的客户端 = 拒绝" "FAIL" "allowUnlisted=False" "$unl" "只加允许条目、不改功能设置 = 什么都没限制" }
$in = Probe "http://hr.lab.local/" "10.10.10.10"
if($in.Code -eq 200){ Add-Item "内网来源访问 hr.lab.local" "PASS" "200" "源 10.10.10.10 → 200" } else { Add-Item "内网来源访问 hr.lab.local" "FAIL" "200" "源 10.10.10.10 → $($in.Code)" }
$nat = (Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.IPAddress -notlike "10.10.10.*" -and $_.IPAddress -ne "127.0.0.1" -and $_.IPAddress -notlike "169.254.*" } | Select -First 1).IPAddress
if($nat){
  $out = Probe "http://hr.lab.local/" $nat
  if($out.Code -eq 403){ Add-Item "非内网来源被拒绝（反向测试）" "PASS" "403" "源 $nat → 403（IIS 日志里记为 403.503：IP 被拒绝）" }
  else { Add-Item "非内网来源被拒绝（反向测试）" "FAIL" "403" "源 $nat → $($out.Code)" }
} else { Add-Item "非内网来源被拒绝（反向测试）" "INFO" "" "本机没有第二个网段的地址，跳过" }

Add-Task "任务3 · CompanySite 请求筛选"
$ext = @(Get-WebConfiguration -PSPath "IIS:\Sites\CompanySite" -Filter system.webServer/security/requestFiltering/fileExtensions/add -EA SilentlyContinue)
foreach($e in ".bak",".config",".sql"){
  $m = $ext | Where-Object { $_.fileExtension -eq $e } | Select -Last 1
  if($m -and -not $m.allowed){ Add-Item "拒绝扩展名 $e" "PASS" "allowed=False" "已拒绝$(if($e -eq '.config'){'（IIS 默认即拒绝）'})" }
  else { Add-Item "拒绝扩展名 $e" "FAIL" "allowed=False" ($(if($m){"allowed=True"}else{"未配置"})) "请求筛选 → 文件扩展名 → 拒绝文件扩展名" }
}
$seg = @((Get-WebConfiguration -PSPath "IIS:\Sites\CompanySite" -Filter system.webServer/security/requestFiltering/hiddenSegments/add -EA SilentlyContinue).segment)
foreach($s in "bin","App_Data"){
  if($seg -contains $s){ Add-Item "隐藏段 $s" "PASS" "存在" "存在（IIS 默认已含）" } else { Add-Item "隐藏段 $s" "FAIL" "存在" "未配置" }
}
$probeFile = "C:\WebSites\CompanySite\_check11_probe.bak"
"probe" | Out-File $probeFile -Encoding ascii
$b = Probe "https://www.lab.local/_check11_probe.bak"
Remove-Item $probeFile -Force -EA SilentlyContinue
if($b.Code -eq 404){ Add-Item "实测：存在的 .bak 文件下载不到" "PASS" "404" "404" } else { Add-Item "实测：存在的 .bak 文件下载不到" "FAIL" "404" "$($b.Code)" "规则可能加到了别的站点" }
if(Test-Path "C:\WebSites\CompanySite\test.bak"){
  $t = Probe "https://www.lab.local/test.bak"
  Add-Item "test.bak（课堂测试文件）" "INFO" "" "存在；访问 → $($t.Code)（IIS 日志子状态 404.7=扩展名被拒，404.8=隐藏段；日志约 1 分钟后写入）"
} else { Add-Item "test.bak（课堂测试文件）" "INFO" "" "未创建（任务 3 测试步骤）" }

Add-Task "汇总（采集）"
Add-Item "全部站点与绑定（采集）" "INFO" "" ((Get-Website | ForEach-Object { $n=$_.name; "$n[$($_.state)] " + ((Get-WebBinding -Name $n | ForEach-Object { "$($_.protocol)/$($_.bindingInformation)" }) -join ",") }) -join " ; ")

Export-CheckReport
