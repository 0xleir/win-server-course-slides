# check10.ps1 — 第10课 IIS 多站点与虚拟目录：任务检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check10.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson10" "第 10 课 · IIS 多站点与虚拟目录"
Import-Module WebAdministration -EA SilentlyContinue

# 按主机名访问本机站点：直连 10.10.10.10，手工带 Host 头（不依赖 DC1 自己的 DNS 客户端设置）
function Get-Site([string]$hostName, [int]$port = 80, [string]$path = "/"){
  try {
    $c = New-Object Net.Sockets.TcpClient; $c.ReceiveTimeout = 8000; $c.Connect("10.10.10.10", $port)
    $s = $c.GetStream(); $req = "GET $path HTTP/1.1`r`nHost: $hostName`r`nConnection: close`r`n`r`n"
    $b = [Text.Encoding]::ASCII.GetBytes($req); $s.Write($b, 0, $b.Length)
    $ms = New-Object IO.MemoryStream; $s.CopyTo($ms); $c.Close()
    $raw = $ms.ToArray(); $txt = [Text.Encoding]::ASCII.GetString($raw)
    $code = [int]([regex]::Match($txt, '^HTTP/1\.\d (\d{3})').Groups[1].Value)
    $i = $txt.IndexOf("`r`n`r`n"); $body = @(); if($i -ge 0){ $body = $raw[($i+4)..($raw.Length-1)] }
    $enc = [Text.Encoding]::UTF8; if($body.Count -ge 2 -and $body[0] -eq 0xFF -and $body[1] -eq 0xFE){ $enc = [Text.Encoding]::Unicode }
    $t = $enc.GetString([byte[]]$body) -replace '<[^>]+>', ' ' -replace '[\s\uFEFF]+', ' '
    return @{ Code = $code; Text = $t.Trim() }
  } catch { return @{ Code = 0; Text = "连接失败: " + $_.Exception.Message.Split([char]10)[0] } }
}
function Short($t){ if($t.Length -gt 60){ $t.Substring(0,60) + "…" } else { $t } }

Add-Task "任务1 · 基于主机头的多站点"
$zone = Get-DnsServerZone -Name lab.local -EA SilentlyContinue
if(-not $zone){ Add-Item "DNS 区域 lab.local" "FAIL" "存在" "不存在" "第 2 课应已创建 lab.local 区域" }
foreach($n in "www","hr"){
  $rr = @(Get-DnsServerResourceRecord -ZoneName lab.local -Name $n -RRType A -EA SilentlyContinue)
  $ips = @($rr | ForEach-Object { $_.RecordData.IPv4Address.IPAddressToString })
  if($ips -contains "10.10.10.10"){ Add-Item "DNS A 记录 $n.lab.local" "PASS" "10.10.10.10" ($ips -join ",") }
  else { Add-Item "DNS A 记录 $n.lab.local" "FAIL" "10.10.10.10" ($(if($ips){$ips -join ","}else{"无记录"})) "Add-DnsServerResourceRecordA -ZoneName lab.local -Name $n -IPv4Address 10.10.10.10" }
}
$hr = Get-Website -Name HRPortal -EA SilentlyContinue
if($hr){
  $pp = [Environment]::ExpandEnvironmentVariables($hr.physicalPath).TrimEnd('\')
  if($pp -ieq "C:\WebSites\HRPortal"){ Add-Item "HRPortal 站点与路径" "PASS" "C:\WebSites\HRPortal" $pp } else { Add-Item "HRPortal 站点与路径" "FAIL" "C:\WebSites\HRPortal" $pp }
  $hb = (Get-WebBinding -Name HRPortal -Protocol http).bindingInformation
  if($hb -contains "*:80:hr.lab.local"){ Add-Item "HRPortal 绑定主机名 hr.lab.local" "PASS" "*:80:hr.lab.local" ($hb -join " ; ") }
  else { Add-Item "HRPortal 绑定主机名 hr.lab.local" "FAIL" "*:80:hr.lab.local" ($hb -join " ; ") "主机名要完整写 hr.lab.local，不带 http://" }
} else { Add-Item "HRPortal 站点与路径" "FAIL" "存在" "不存在" "IIS 管理器 → 添加网站 HRPortal" }
$cb = @((Get-WebBinding -Name CompanySite -Protocol http).bindingInformation)
if($cb -contains "*:80:www.lab.local"){ Add-Item "CompanySite 绑定主机名 www.lab.local" "PASS" "*:80:www.lab.local" ($cb -join " ; ") }
else { Add-Item "CompanySite 绑定主机名 www.lab.local" "FAIL" "*:80:www.lab.local" ($cb -join " ; ") "CompanySite → 绑定 → 编辑或添加主机名 www.lab.local" }
if($cb -contains "*:80:"){ Add-Item "CompanySite 是否保留无主机名绑定（采集）" "INFO" "" "保留了 *:80:（用 IP 访问仍打开 CompanySite）" }
else { Add-Item "CompanySite 是否保留无主机名绑定（采集）" "INFO" "" "未保留（用 IP 访问 80 端口返回 404，属正常）" }
$rw = Get-Site "www.lab.local"
if($rw.Code -eq 200 -and $rw.Text -notmatch "HR Portal|Dev Environment"){ Add-Item "按名字访问 www.lab.local → CompanySite" "PASS" "200 公司首页" "200 $(Short $rw.Text)" }
else { Add-Item "按名字访问 www.lab.local → CompanySite" "FAIL" "200 公司首页" "$($rw.Code) $(Short $rw.Text)" }
$rh = Get-Site "hr.lab.local"
if($rh.Code -eq 200 -and $rh.Text -match "HR Portal"){ Add-Item "按名字访问 hr.lab.local → HRPortal" "PASS" "200 HR Portal" "200 $(Short $rh.Text)" }
else { Add-Item "按名字访问 hr.lab.local → HRPortal" "FAIL" "200 HR Portal" "$($rh.Code) $(Short $rh.Text)" "打开的是别的站 = 绑定问题，不是 DNS 问题" }

Add-Task "任务2 · 基于端口的多站点"
$dev = Get-Website -Name DevSite -EA SilentlyContinue
if($dev){
  $db = (Get-WebBinding -Name DevSite -Protocol http).bindingInformation
  if($db -contains "*:8080:"){ Add-Item "DevSite 绑定 *:8080（无主机名）" "PASS" "*:8080:" ($db -join " ; ") } else { Add-Item "DevSite 绑定 *:8080（无主机名）" "FAIL" "*:8080:" ($db -join " ; ") }
} else { Add-Item "DevSite 绑定 *:8080（无主机名）" "FAIL" "存在" "DevSite 不存在" }
$fw = @(Get-NetFirewallRule -DisplayName "Allow HTTP 8080" -EA SilentlyContinue)
if($fw -and $fw[0].Enabled -eq "True" -and $fw[0].Direction -eq "Inbound" -and $fw[0].Action -eq "Allow"){
  $port = ($fw[0] | Get-NetFirewallPortFilter).LocalPort
  if($port -eq "8080"){ Add-Item "防火墙规则 Allow HTTP 8080" "PASS" "入站 TCP 8080 允许" "Enabled, LocalPort=$port" } else { Add-Item "防火墙规则 Allow HTTP 8080" "WARN" "LocalPort=8080" "LocalPort=$port" }
} else { Add-Item "防火墙规则 Allow HTTP 8080" "FAIL" "入站 TCP 8080 允许" "未找到或未启用" "CLIENT1 打不开 8080 的典型原因" }
$rd = Get-Site "10.10.10.10" 8080
if($rd.Code -eq 200 -and $rd.Text -match "Dev Environment"){ Add-Item "http://10.10.10.10:8080 → Dev Environment" "PASS" "200 Dev Environment" "200 $(Short $rd.Text)" }
else { Add-Item "http://10.10.10.10:8080 → Dev Environment" "FAIL" "200 Dev Environment" "$($rd.Code) $(Short $rd.Text)" }

Add-Task "任务3 · 虚拟目录"
$vd = Get-WebVirtualDirectory -Site CompanySite -Name shared -EA SilentlyContinue
if($vd){
  if($vd.physicalPath.TrimEnd('\') -ieq "C:\SharedDocs"){ Add-Item "/shared 虚拟目录 → C:\SharedDocs" "PASS" "C:\SharedDocs" $vd.physicalPath } else { Add-Item "/shared 虚拟目录 → C:\SharedDocs" "FAIL" "C:\SharedDocs" $vd.physicalPath }
} else {
  $app = Get-WebApplication -Site CompanySite -Name shared -EA SilentlyContinue
  if($app){ Add-Item "/shared 虚拟目录 → C:\SharedDocs" "WARN" "虚拟目录" "建成了「应用程序」: $($app.PhysicalPath)" "能访问，但本课要求的是虚拟目录" }
  else { Add-Item "/shared 虚拟目录 → C:\SharedDocs" "FAIL" "存在" "不存在" "CompanySite → 右键 → 添加虚拟目录，别名 shared" }
}
if(-not (Test-Path "C:\SharedDocs\shared.txt")){ Add-Item "C:\SharedDocs\shared.txt" "FAIL" "存在" "不存在" }
$rs = Get-Site "www.lab.local" 80 "/shared/shared.txt"
if($rs.Code -eq 200 -and $rs.Text -match "Shared Document"){ Add-Item "www.lab.local/shared/shared.txt" "PASS" "200 Shared Document" "200 $(Short $rs.Text)" }
else { Add-Item "www.lab.local/shared/shared.txt" "FAIL" "200 Shared Document" "$($rs.Code) $(Short $rs.Text)" "401/500 多半是 IIS_IUSRS 无权读取 C:\SharedDocs" }

Add-Task "汇总 · 站点与绑定（采集）"
$need = "CompanySite","HRPortal","DevSite"
$run = @($need | Where-Object { (Get-Website -Name $_ -EA SilentlyContinue).state -eq "Started" })
if($run.Count -eq 3){ Add-Item "3 个站点运行中" "PASS" "CompanySite/HRPortal/DevSite = Started" "3/3 Started" }
else { Add-Item "3 个站点运行中" "FAIL" "3/3 Started" "运行中: $($run -join ', ')" "站点启动失败通常是绑定冲突" }
Add-Item "Get-WebBinding（采集）" "INFO" "" ((Get-Website | ForEach-Object { $n=$_.name; (Get-WebBinding -Name $n | ForEach-Object { "$n[$($_.protocol)] $($_.bindingInformation)" }) -join " ; " }) -join " ; ")

Export-CheckReport
