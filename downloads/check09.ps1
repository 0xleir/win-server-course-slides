# check09.ps1 — 第9课 IIS 安装与静态网站：任务检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check09.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson09" "第 9 课 · IIS 安装与静态网站"
Import-Module WebAdministration -EA SilentlyContinue

function Get-Http([string]$url){
  try { $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 0 -EA Stop; return @{ Code=[int]$r.StatusCode; Body=[string]$r.Content; Links=@($r.Links.href) } }
  catch { $c = 0; if($_.Exception.Response){ $c = [int]$_.Exception.Response.StatusCode }; return @{ Code=$c; Body=""; Links=@(); Err=$_.Exception.Message.Split([char]10)[0] } }
}

Add-Task "任务1 · 安装 IIS"
$ws = Get-WindowsFeature Web-Server
if($ws.Installed){ Add-Item "Web-Server (IIS) 已安装" "PASS" "Installed" "Installed" } else { Add-Item "Web-Server (IIS) 已安装" "FAIL" "Installed" $ws.InstallState "运行 Install-WindowsFeature Web-Server -IncludeManagementTools" }
$mgmt = Get-WindowsFeature Web-Mgmt-Console
if($mgmt.Installed){ Add-Item "IIS 管理器 (inetmgr) 已安装" "PASS" "Installed" "Installed" } else { Add-Item "IIS 管理器 (inetmgr) 已安装" "WARN" "Installed" $mgmt.InstallState "安装时漏了 -IncludeManagementTools" }
$sub = @("Web-Asp-Net45","Web-CGI","Web-ISAPI-Ext","Web-ISAPI-Filter","Web-Basic-Auth","Web-Windows-Auth","Web-Filtering","Web-IP-Security","Web-Stat-Compression","Web-Log-Libraries")
$miss = @($sub | Where-Object { -not (Get-WindowsFeature $_).Installed })
if($miss.Count -eq 0){ Add-Item "常用子功能（10 项）" "PASS" "全部已装" "10/10 已安装" }
else { Add-Item "常用子功能（10 项）" "WARN" "全部已装" "缺少：$($miss -join ', ')" "第 11 课的 IP 限制/请求筛选要用到，建议补装" }
$svc = Get-Service W3SVC -EA SilentlyContinue
if($svc -and $svc.Status -eq "Running"){ Add-Item "W3SVC 服务运行中" "PASS" "Running" "Running" }
else { Add-Item "W3SVC 服务运行中" "FAIL" "Running" ($(if($svc){$svc.Status}else{"不存在"})) "Start-Service W3SVC" }

Add-Task "任务2 · 部署 CompanySite"
$site = Get-Website -Name "CompanySite" -EA SilentlyContinue
if($site){
  Add-Item "站点 CompanySite 存在" "PASS" "存在" "ID=$($site.id)"
  $pp = [Environment]::ExpandEnvironmentVariables($site.physicalPath).TrimEnd('\')
  if($pp -ieq "C:\WebSites\CompanySite"){ Add-Item "物理路径" "PASS" "C:\WebSites\CompanySite" $pp } else { Add-Item "物理路径" "FAIL" "C:\WebSites\CompanySite" $pp }
  if($site.state -eq "Started"){ Add-Item "CompanySite 已启动" "PASS" "Started" "Started" } else { Add-Item "CompanySite 已启动" "FAIL" "Started" $site.state "先停 Default Web Site 再启动 CompanySite" }
  $b = @(Get-WebBinding -Name "CompanySite" -Protocol http)
  $b80 = $b | Where-Object { $_.bindingInformation -match '^\*:80:' }
  if($b80){ Add-Item "绑定 http *:80" "PASS" "*:80:(主机名可空)" (($b.bindingInformation) -join " ; ") }
  else { Add-Item "绑定 http *:80" "FAIL" "*:80:" (($b.bindingInformation) -join " ; ") }
} else { Add-Item "站点 CompanySite 存在" "FAIL" "存在" "不存在" "在 IIS 管理器中添加网站，名称必须是 CompanySite" }
$dws = Get-Website -Name "Default Web Site" -EA SilentlyContinue
if(-not $dws){ Add-Item "Default Web Site 已停止" "PASS" "Stopped" "已删除" }
elseif($dws.state -eq "Stopped"){ Add-Item "Default Web Site 已停止" "PASS" "Stopped" "Stopped" }
else { Add-Item "Default Web Site 已停止" "WARN" "Stopped" $dws.state "它也占用 *:80，会与 CompanySite 冲突" }
$idx = "C:\WebSites\CompanySite\index.html"
if(Test-Path $idx){
  $t = Get-Content $idx -Raw
  if($t -match "Welcome to Lab Company"){ Add-Item "index.html 内容" "PASS" "含 Welcome to Lab Company" "$((Get-Item $idx).Length) 字节" }
  else { Add-Item "index.html 内容" "WARN" "含 Welcome to Lab Company" "未找到标题文字" }
} else { Add-Item "index.html 内容" "FAIL" "文件存在" "不存在" }
$fw = @(Get-NetFirewallRule -Name "IIS-WebServerRole-HTTP-In-TCP" -EA SilentlyContinue)
if($fw -and $fw[0].Enabled -eq "True"){ Add-Item "防火墙放行 HTTP 80 入站" "PASS" "规则已启用" $fw[0].DisplayName }
else { Add-Item "防火墙放行 HTTP 80 入站" "WARN" "规则已启用" "未找到或未启用" "CLIENT1 会连接超时" }
$r = Get-Http "http://localhost/"
if($r.Code -eq 200){ Add-Item "http://localhost 返回 200" "PASS" "200" "200" } else { Add-Item "http://localhost 返回 200" "FAIL" "200" "$($r.Code) $($r.Err)" }
$r10 = Get-Http "http://10.10.10.10/"
if($r10.Code -eq 200){ Add-Item "http://10.10.10.10 返回 200" "PASS" "200" "200" } else { Add-Item "http://10.10.10.10 返回 200" "WARN" "200" "$($r10.Code) $($r10.Err)" "Lab 网卡 IP 或绑定不对" }

Add-Task "任务3 · 目录浏览与默认文档"
$docs = "C:\WebSites\CompanySite\docs"
if((Test-Path "$docs\file1.txt") -and (Test-Path "$docs\file2.txt")){ Add-Item "docs\file1.txt / file2.txt" "PASS" "存在" "存在" } else { Add-Item "docs\file1.txt / file2.txt" "FAIL" "存在" "缺失" }
$dbDocs = (Get-WebConfigurationProperty -PSPath "IIS:\Sites\CompanySite\docs" -Filter system.webServer/directoryBrowse -Name enabled -EA SilentlyContinue).Value
$dbRoot = (Get-WebConfigurationProperty -PSPath "IIS:\Sites\CompanySite" -Filter system.webServer/directoryBrowse -Name enabled -EA SilentlyContinue).Value
if($dbDocs){ Add-Item "/docs 已启用目录浏览" "PASS" "True" "True" } else { Add-Item "/docs 已启用目录浏览" "FAIL" "True" "$dbDocs" "选中 docs 节点 → 目录浏览 → 启用" }
if(-not $dbRoot){ Add-Item "站点根目录未开目录浏览" "PASS" "False" "False" } else { Add-Item "站点根目录未开目录浏览" "WARN" "False" "True" "整站目录都能被浏览，属于信息泄露" }
$rd = Get-Http "http://localhost/docs/"
$seen = @($rd.Links | Where-Object { $_ -match 'file[12]\.txt' })
if($rd.Code -eq 200 -and $seen.Count -ge 2){ Add-Item "访问 /docs/ 看到文件列表" "PASS" "200 + file1/file2" "200, 列表: $(($rd.Links | Where-Object { $_ -ne '/' }) -join ', ')" }
else { Add-Item "访问 /docs/ 看到文件列表" "FAIL" "200 + file1/file2" "$($rd.Code) $($rd.Err)" }
$dd = @((Get-WebConfigurationProperty -PSPath "IIS:\Sites\CompanySite" -Filter system.webServer/defaultDocument/files -Name Collection -EA SilentlyContinue).value)
if($dd.Count -gt 0 -and $dd[0] -ieq "home.html"){ Add-Item "默认文档首位为 home.html" "PASS" "home.html 在第 1 位" ($dd -join " > ") }
else { Add-Item "默认文档首位为 home.html" "FAIL" "home.html 在第 1 位" ($dd -join " > ") "IIS 管理器 → 默认文档 → 添加 home.html 并上移到顶部" }
if($r.Body -match "This is home.html"){ Add-Item "根目录显示 home.html" "PASS" "This is home.html" "This is home.html" }
else { Add-Item "根目录显示 home.html" "WARN" "This is home.html" ($r.Body.Trim() -replace '\s+',' ').Substring(0,[Math]::Min(80,($r.Body.Trim()).Length)) }

Add-Task "环境（采集）"
Add-Item "全部站点（采集）" "INFO" "" ((Get-Website | ForEach-Object { "$($_.name)[$($_.state)] $((Get-WebBinding -Name $_.name).bindingInformation -join ',')" }) -join " ; ")
Add-Item "IIS 版本（采集）" "INFO" "" ("IIS " + (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\InetStp -EA SilentlyContinue).VersionString)

Export-CheckReport
