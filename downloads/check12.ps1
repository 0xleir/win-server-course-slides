# check12.ps1 — 第12课 FTP 服务器配置：任务检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check12.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson12" "第 12 课 · FTP 服务器配置"
Import-Module WebAdministration -EA SilentlyContinue
$root = "C:\FTPRoot"

# 原始 FTP 控制通道对话（不登录，只看服务器对 USER/PASS 的回应），用于验证"明文被拒"
function Ftp-Talk([string[]]$cmds){
  try {
    $c = New-Object Net.Sockets.TcpClient; $c.Connect("10.10.10.10", 21); $s = $c.GetStream(); $s.ReadTimeout = 5000
    $r = New-Object IO.StreamReader($s); $w = New-Object IO.StreamWriter($s); $w.NewLine = "`r`n"; $w.AutoFlush = $true
    $out = @($r.ReadLine())
    foreach($x in $cmds){ $w.WriteLine($x); $out += $r.ReadLine() }
    $c.Close(); return $out
  } catch { return @("连接失败: " + $_.Exception.Message.Split([char]10)[0]) }
}

Add-Task "任务1 · 安装与基础 FTP"
$f = Get-WindowsFeature Web-Ftp-Server
if($f.Installed){ Add-Item "FTP 服务器功能已安装" "PASS" "Installed" "Installed" } else { Add-Item "FTP 服务器功能已安装" "FAIL" "Installed" $f.InstallState "Install-WindowsFeature Web-Ftp-Server -IncludeAllSubFeature" }
$svc = Get-Service ftpsvc -EA SilentlyContinue
if($svc -and $svc.Status -eq "Running"){ Add-Item "ftpsvc 服务运行中" "PASS" "Running" "Running" } else { Add-Item "ftpsvc 服务运行中" "FAIL" "Running" ($(if($svc){$svc.Status}else{"不存在"})) }
$site = Get-Website -Name LabFTP -EA SilentlyContinue
if($site){
  $pp = [Environment]::ExpandEnvironmentVariables($site.physicalPath).TrimEnd('\')
  if($pp -ieq $root){ Add-Item "LabFTP 站点与路径" "PASS" $root $pp } else { Add-Item "LabFTP 站点与路径" "FAIL" $root $pp }
  $b = (Get-WebBinding -Name LabFTP -Protocol ftp).bindingInformation
  if($b -contains "*:21:"){ Add-Item "绑定 ftp *:21" "PASS" "*:21:" ($b -join " ; ") } else { Add-Item "绑定 ftp *:21" "FAIL" "*:21:" ($b -join " ; ") }
  if($site.state -eq "Started"){ Add-Item "LabFTP 已启动" "PASS" "Started" "Started" } else { Add-Item "LabFTP 已启动" "FAIL" "Started" $site.state }
  $basic = (Get-ItemProperty IIS:\Sites\LabFTP -Name ftpServer.security.authentication.basicAuthentication.enabled).Value
  $anon = (Get-ItemProperty IIS:\Sites\LabFTP -Name ftpServer.security.authentication.anonymousAuthentication.enabled).Value
  if($basic){ Add-Item "基本身份验证已启用" "PASS" "True" "True" } else { Add-Item "基本身份验证已启用" "FAIL" "True" "$basic" "否则 530 登录失败" }
  if(-not $anon){ Add-Item "匿名身份验证未启用" "PASS" "False" "False" } else { Add-Item "匿名身份验证未启用" "FAIL" "False" "True" "任何人都能连上" }
  $az = @(Get-WebConfiguration -PSPath IIS:\ -Location LabFTP -Filter system.ftpServer/security/authorization/add -EA SilentlyContinue)
  $users = @($az | Where-Object { $_.accessType -eq "Allow" } | ForEach-Object { $_.users -split '\s*,\s*' })
  $rw = @($az | Where-Object { $_.accessType -eq "Allow" -and "$($_.permissions)" -match "Read" -and "$($_.permissions)" -match "Write" })
  if(($users -contains "alice") -and ($users -contains "bob") -and $rw){ Add-Item "授权 alice, bob 读取+写入" "PASS" "alice,bob Read+Write" (($az | ForEach-Object { "$($_.accessType):$($_.users)$($_.roles):$($_.permissions)" }) -join " ; ") }
  else { Add-Item "授权 alice, bob 读取+写入" "FAIL" "alice,bob Read+Write" (($az | ForEach-Object { "$($_.accessType):$($_.users)$($_.roles):$($_.permissions)" }) -join " ; ") }
  if($users -contains "*" -or ($az | Where-Object { $_.roles -match "Everyone|Users" -and $_.accessType -eq "Allow" })){ Add-Item "授权范围没有放宽到所有用户" "WARN" "只授权 alice,bob" "含 * 或所有用户" "其他本地账户也能登录" }
} else { Add-Item "LabFTP 站点与路径" "FAIL" "存在" "不存在" "IIS 管理器 → 网站右键 → 添加 FTP 站点" }
$fw21 = Get-NetFirewallRule -DisplayName "Allow FTP" -EA SilentlyContinue
if($fw21 -and $fw21.Enabled -eq "True" -and (($fw21 | Get-NetFirewallPortFilter).LocalPort -eq "21")){ Add-Item "防火墙 Allow FTP (21)" "PASS" "入站 TCP 21" "已启用" } else { Add-Item "防火墙 Allow FTP (21)" "FAIL" "入站 TCP 21" "未找到或端口不对" }

Add-Task "任务2 · 用户隔离与目录权限"
foreach($u in "alice","bob"){
  if((Test-Path "$root\LocalUser\$u\readme.txt")){ Add-Item "LocalUser\$u\readme.txt" "PASS" "存在" "存在" } else { Add-Item "LocalUser\$u\readme.txt" "FAIL" "存在" "缺失" "目录名必须是 LocalUser（IIS 规定）" }
}
if($site){
  $mode = Get-ItemProperty IIS:\Sites\LabFTP -Name ftpServer.userIsolation.mode
  if($mode -eq "IsolateRootDirectoryOnly"){ Add-Item "隔离模式 = 用户名目录(禁用全局虚拟目录)" "PASS" "IsolateRootDirectoryOnly" $mode }
  elseif($mode -eq "IsolateAllDirectories"){ Add-Item "隔离模式 = 用户名目录(禁用全局虚拟目录)" "WARN" "IsolateRootDirectoryOnly" $mode "选成了「用户名目录(启用全局虚拟目录)」，隔离仍有效" }
  else { Add-Item "隔离模式 = 用户名目录(禁用全局虚拟目录)" "FAIL" "IsolateRootDirectoryOnly" $mode "选好后要点右侧「应用」" }
}
foreach($u in "alice","bob"){
  $acl = Get-Acl "$root\LocalUser\$u" -EA SilentlyContinue
  $ace = $acl.Access | Where-Object { $_.IdentityReference -match "\\$u$" -and $_.AccessControlType -eq "Allow" -and -not $_.IsInherited } | Select -First 1
  if($ace -and ($ace.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Modify) -eq [Security.AccessControl.FileSystemRights]::Modify -and "$($ace.InheritanceFlags)" -match "ContainerInherit" -and "$($ace.InheritanceFlags)" -match "ObjectInherit"){
    Add-Item "NTFS：$u 对自己目录 (OI)(CI)M" "PASS" "(OI)(CI)M" "$($ace.FileSystemRights) / $($ace.InheritanceFlags)" }
  else { Add-Item "NTFS：$u 对自己目录 (OI)(CI)M" "FAIL" "(OI)(CI)M" ($(if($ace){"$($ace.FileSystemRights) / $($ace.InheritanceFlags)"}else{"无显式条目"})) "PowerShell 里要加引号：icacls … /grant `"${u}:(OI)(CI)M`"" }
}
# 隔离实测：服务器端日志里 alice/bob 的 CWD 越界结果（学生在 CLIENT1 上做的测试）
$log = Get-ChildItem "C:\inetpub\logs\LogFiles\FTPSVC*\*.log" -EA SilentlyContinue | Sort LastWriteTime | Select -Last 3
$lines = @($log | ForEach-Object { Get-Content $_.FullName -EA SilentlyContinue } | Where-Object { $_ -match '[ \\](alice|bob) ' })
$stor = @($lines | Where-Object { $_ -match ' STOR .* 226 ' }); $retr = @($lines | Where-Object { $_ -match ' RETR .* 226 ' })
if($stor.Count -gt 0 -and $retr.Count -gt 0){ Add-Item "日志：客户端已成功 put / get" "PASS" "STOR 226 + RETR 226" "STOR $($stor.Count) 次 / RETR $($retr.Count) 次" }
else { Add-Item "日志：客户端已成功 put / get" "WARN" "STOR 226 + RETR 226" "STOR $($stor.Count) 次 / RETR $($retr.Count) 次" "在 CLIENT1 用 alice 登录做一次 put/get（任务 2 测试）" }
$up = @(Get-ChildItem "$root\LocalUser\alice","$root\LocalUser\bob" -File -EA SilentlyContinue | Where-Object { $_.Name -ne "readme.txt" })
Add-Item "用户上传到自己目录的文件（采集）" "INFO" "" ($(if($up){ ($up | ForEach-Object { $_.FullName.Replace("$root\LocalUser\","") }) -join ", " } else { "无" }))
$stray = @(Get-ChildItem $root -File -EA SilentlyContinue)
if($stray.Count -eq 0){ Add-Item "站点根 C:\FTPRoot 下没有散落文件" "PASS" "无文件" "无" } else { Add-Item "站点根 C:\FTPRoot 下没有散落文件" "WARN" "无文件" (($stray.Name) -join ", ") "隔离前上传的文件会落在根目录" }

Add-Task "任务3 · FTPS 与被动端口"
if($site){
  $ssl = Get-ItemProperty IIS:\Sites\LabFTP -Name ftpServer.security.ssl
  $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -ieq "$($ssl.serverCertHash)" } | Select -First 1
  if($cert -and $cert.FriendlyName -eq "Lab SSL Cert"){ Add-Item "FTP SSL 证书 = Lab SSL Cert" "PASS" "Lab SSL Cert" "$($cert.FriendlyName) $($cert.Thumbprint)" }
  elseif($cert){ Add-Item "FTP SSL 证书 = Lab SSL Cert" "WARN" "Lab SSL Cert" $cert.FriendlyName }
  else { Add-Item "FTP SSL 证书 = Lab SSL Cert" "FAIL" "Lab SSL Cert" ($(if($ssl.serverCertHash){"证书不存在: $($ssl.serverCertHash)"}else{"未选证书"})) }
  if("$($ssl.controlChannelPolicy)" -eq "SslRequire" -and "$($ssl.dataChannelPolicy)" -eq "SslRequire"){ Add-Item "SSL 策略 = 需要 SSL 连接" "PASS" "SslRequire" "控制=$($ssl.controlChannelPolicy) 数据=$($ssl.dataChannelPolicy)" }
  else { Add-Item "SSL 策略 = 需要 SSL 连接" "FAIL" "SslRequire" "控制=$($ssl.controlChannelPolicy) 数据=$($ssl.dataChannelPolicy)" "选「需要 SSL 连接」后点「应用」" }
}
$t = Ftp-Talk @("USER alice")
$resp = ($t | Select -Last 1)
if($resp -match '^534'){ Add-Item "实测：明文登录被拒绝" "PASS" "534 Policy requires SSL" $resp }
else { Add-Item "实测：明文登录被拒绝" "FAIL" "534" (($t) -join " / ") "明文 USER 没被拒绝 → SSL 策略未生效" }
$lo = (Get-WebConfigurationProperty -PSPath IIS:\ -Filter system.ftpServer/firewallSupport -Name lowDataChannelPort).Value
$hi = (Get-WebConfigurationProperty -PSPath IIS:\ -Filter system.ftpServer/firewallSupport -Name highDataChannelPort).Value
if($lo -eq 50000 -and $hi -eq 50100){ Add-Item "服务器级被动端口范围 50000-50100" "PASS" "50000-50100" "$lo-$hi" }
else { Add-Item "服务器级被动端口范围 50000-50100" "FAIL" "50000-50100" "$lo-$hi" "在服务器节点（不是 LabFTP）的「FTP 防火墙支持」设置，再 Restart-Service ftpsvc" }
$pv = Get-NetFirewallRule -DisplayName "Allow FTP Passive" -EA SilentlyContinue
if($pv){
  $ports = @(($pv | Get-NetFirewallPortFilter).LocalPort)
  $num = @($ports | ForEach-Object { if($_ -match '^(\d+)-(\d+)$'){ [int]$matches[1]..[int]$matches[2] } elseif($_ -match '^\d+$'){ [int]$_ } })
  $mn = ($num | Measure-Object -Minimum).Minimum; $mx = ($num | Measure-Object -Maximum).Maximum
  if($mn -eq 50000 -and $mx -eq 50100 -and $num.Count -eq 101){ Add-Item "防火墙 Allow FTP Passive 收窄到 50000-50100" "PASS" "101 个端口" "$mn-$mx（$($num.Count) 个）" }
  else { Add-Item "防火墙 Allow FTP Passive 收窄到 50000-50100" "FAIL" "50000-50100" "$mn-$mx（$($num.Count) 个）" }
} else { Add-Item "防火墙 Allow FTP Passive 收窄到 50000-50100" "FAIL" "存在" "规则不存在" "规则名必须和课件一致" }
$bi = Get-NetFirewallRule -DisplayName "FTP 服务器被动(FTP 被动流量入站)" -EA SilentlyContinue
if(-not $bi){ $bi = Get-NetFirewallRule -Name "IIS-WebServerRole-FTP-Passive-In-TCP" -EA SilentlyContinue }
if($bi -and $bi.Enabled -eq "True"){ Add-Item "IIS 自带被动规则（1024-65535）已禁用" "WARN" "Enabled=False" "Enabled=True" "这条自带规则对 FTP 服务放行 1024-65535，不禁用它，收窄 Allow FTP Passive 等于没收窄" }
else { Add-Item "IIS 自带被动规则（1024-65535）已禁用" "PASS" "Enabled=False" ($(if($bi){"已禁用"}else{"不存在"})) }

Add-Task "汇总（采集）"
Add-Item "FTP 相关入站规则（采集）" "INFO" "" ((Get-NetFirewallRule -Direction Inbound -EA SilentlyContinue | Where-Object { $_.DisplayName -match "FTP" } | ForEach-Object { "$($_.DisplayName)[$($_.Enabled)] " + (($_ | Get-NetFirewallPortFilter).LocalPort -join ',' -replace '^(\d+),.*,(\d+)$','$1..$2') }) -join " ; ")

Export-CheckReport
