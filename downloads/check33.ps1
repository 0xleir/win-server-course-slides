# check33.ps1 — 第33课 企业 Web 与文件服务整合：检查与证据采集（只需在 SVR2 上运行一次）
# 用法：在 SVR2 本机（控制台或远程桌面）以 LAB\Administrator 身份、管理员 PowerShell 运行
#   powershell -ExecutionPolicy Bypass -File check33.ps1
# GPO、SPN 通过 LDAP 向域控查询，DC1 的 21 端口从 SVR2 探测，不需要再去 DC1 上跑
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson33" "第 33 课 · 企业 Web 与文件服务整合"

$hostName = $env:COMPUTERNAME
$domainDN = "DC=lab,DC=local"
$dcIP = "10.10.10.10"

function Get-GpoByName($name){
  $s = New-Object DirectoryServices.DirectorySearcher([ADSI]"LDAP://CN=Policies,CN=System,$domainDN")
  $s.Filter = "(&(objectClass=groupPolicyContainer)(displayName=$name))"
  [void]$s.PropertiesToLoad.Add("cn"); [void]$s.PropertiesToLoad.Add("gPCFileSysPath")
  $r = $s.FindOne()
  if($r){ [pscustomobject]@{ Guid = "$($r.Properties['cn'][0])"; Path = "$($r.Properties['gpcfilesyspath'][0])" } } else { $null }
}
function Test-GpoLinked($guid, $targetDN){
  $o = [ADSI]"LDAP://$targetDN"
  "$($o.gPLink)" -match [regex]::Escape($guid)
}

Add-Task "运行位置"
if($hostName -match "^SVR"){ Add-Item "本脚本在 SVR2 上运行" "PASS" "SVR2" $hostName }
else { Add-Item "本脚本在 SVR2 上运行" "FAIL" "SVR2" $hostName "IIS/FTP 都在 SVR2 上，请把脚本拷到 SVR2 本机再运行" }
$adOk = $true
try { [void]([ADSI]"LDAP://$domainDN").distinguishedName } catch { $adOk = $false }
if(-not $adOk -or -not ([ADSI]"LDAP://$domainDN").distinguishedName){
  Add-Item "能查询 AD（本机会话）" "FAIL" "可查询" "查询失败" "请在 SVR2 控制台或远程桌面里以 LAB\Administrator 运行，不要放在 Enter-PSSession 远程会话里（远程会话不能再连 AD）"
}

Add-Task "任务1 · GPO 按部门映射驱动器"
$gDrv = Get-GpoByName "Dept-Drive-Maps"
if($gDrv){
  if(Test-GpoLinked $gDrv.Guid "OU=Company,$domainDN"){ Add-Item "GPO Dept-Drive-Maps 已链接到 Company" "PASS" "已链接" "已链接" }
  else { Add-Item "GPO Dept-Drive-Maps 已链接到 Company" "FAIL" "已链接" "未链接" "gpmc.msc 里右键 Company › 链接现有 GPO › Dept-Drive-Maps" }
  $xmlPath = Join-Path $gDrv.Path "User\Preferences\Drives\Drives.xml"
  $x = $null; try { [xml]$x = Get-Content $xmlPath -Raw -Encoding UTF8 -EA Stop } catch {}
  if($x){
    $drives = @($x.Drives.Drive)
    foreach($want in @(@{L="S";P="\\SVR2\IT-Share";G="Domain-IT"},@{L="F";P="\\SVR2\Finance-Share";G="Domain-Finance"})){
      $d = $drives | Where-Object { $_.Properties.letter -eq $want.L } | Select-Object -First 1
      $label = "$($want.L): → $($want.P)，目标组 $($want.G)"
      if(-not $d){ Add-Item $label "FAIL" "存在映射项" "没有 $($want.L): 映射项" "编辑 Dept-Drive-Maps › 用户配置 › 首选项 › 驱动器映射 › 新建 $($want.L):" ; continue }
      $pathOk = $d.Properties.path -ieq $want.P
      $grp = @($d.Filters.FilterGroup | ForEach-Object { $_.name })
      $grpOk = [bool]($grp | Where-Object { $_ -match "\\$($want.G)$" -or $_ -eq $want.G })
      if($pathOk -and $grpOk){ Add-Item $label "PASS" "$($want.P) / $($want.G)" "$($d.Properties.path) / $($grp -join ',')" }
      elseif(-not $pathOk){ Add-Item $label "FAIL" $want.P $d.Properties.path "映射项的位置要写 $($want.P)" }
      else { Add-Item $label "FAIL" "项目级别目标 = 安全组 $($want.G)" ($(if($grp){$grp -join ','}else{"未设项目级别目标"})) "映射项 › 常用 › 勾选项目级别目标 › 新建项目 › 安全组 › $($want.G)" }
    }
  } else { Add-Item "Dept-Drive-Maps 里有驱动器映射项" "FAIL" "Drives.xml" "未找到" "在 用户配置 › 首选项 › Windows 设置 › 驱动器映射 里新建 S: 和 F:" }
} else { Add-Item "GPO Dept-Drive-Maps 存在" "FAIL" "存在" "未找到" "gpmc.msc › 右键 Company › 在这个域中创建 GPO 并在此处链接 › Dept-Drive-Maps" }

Add-Task "任务2 · 内部网站集成认证"
Import-Module WebAdministration -EA SilentlyContinue
$wa = Get-WindowsFeature Web-Windows-Auth -EA SilentlyContinue
if($wa -and $wa.InstallState -eq "Installed"){ Add-Item "Web-Windows-Auth 已安装" "PASS" "Installed" "Installed" }
else { Add-Item "Web-Windows-Auth 已安装" "FAIL" "Installed" ($(if($wa){"$($wa.InstallState)"}else{"未找到"})) "Install-WindowsFeature Web-Windows-Auth" }
$site = "IntranetSite"
if(Get-Website -Name $site -EA SilentlyContinue){
  $anon = (Get-WebConfigurationProperty -PSPath IIS:\ -Location $site -Filter system.webServer/security/authentication/anonymousAuthentication -Name enabled -EA SilentlyContinue).Value
  $win  = (Get-WebConfigurationProperty -PSPath IIS:\ -Location $site -Filter system.webServer/security/authentication/windowsAuthentication -Name enabled -EA SilentlyContinue).Value
  if($anon -eq $false){ Add-Item "IntranetSite 匿名身份验证已禁用" "PASS" "False" "False" } else { Add-Item "IntranetSite 匿名身份验证已禁用" "FAIL" "False" "$anon" "IIS 管理器 › IntranetSite › 身份验证 › 匿名身份验证 › 禁用" }
  if($win -eq $true){ Add-Item "IntranetSite Windows 身份验证已启用" "PASS" "True" "True" } else { Add-Item "IntranetSite Windows 身份验证已启用" "FAIL" "True" "$win" "IIS 管理器 › IntranetSite › 身份验证 › Windows 身份验证 › 启用（没有这一项先装 Web-Windows-Auth 并重开 IIS 管理器）" }
} else { Add-Item "IntranetSite 存在" "FAIL" "存在" "未找到" "第 32 课任务 2 建的站点不在了，先补做第 32 课" }
try {
  $req = [Net.HttpWebRequest]::Create("https://web.lab.local/"); $req.Timeout = 10000
  $null = $req.GetResponse(); Add-Item "匿名访问 https://web.lab.local 返回 401" "FAIL" "401" "200（匿名能进）" "匿名身份验证还开着"
} catch [Net.WebException] {
  $code = if($_.Exception.Response){ [int]$_.Exception.Response.StatusCode } else { 0 }
  $hdr  = if($_.Exception.Response){ $_.Exception.Response.Headers["WWW-Authenticate"] } else { $_.Exception.Message }
  if($code -eq 401){ Add-Item "匿名访问 https://web.lab.local 返回 401" "PASS" "401 Negotiate" "401 $hdr" }
  else { Add-Item "匿名访问 https://web.lab.local 返回 401" "FAIL" "401" "$code $hdr" "检查 https 443 绑定与证书（第 32 课任务 2）" }
}
$s = New-Object DirectoryServices.DirectorySearcher([ADSI]"LDAP://$domainDN")
$s.Filter = "(&(objectClass=computer)(sAMAccountName=SVR2$))"; [void]$s.PropertiesToLoad.Add("servicePrincipalName")
$spns = @(); try { $spns = @($s.FindOne().Properties["serviceprincipalname"] | ForEach-Object { "$_".ToLower() }) } catch {}
foreach($n in "http/web.lab.local","http/intranet.lab.local"){
  if($spns -contains $n){ Add-Item "SVR2 已注册 SPN $($n.Replace('http','HTTP'))" "PASS" "已注册" "已注册" }
  else { Add-Item "SVR2 已注册 SPN $($n.Replace('http','HTTP'))" "FAIL" "已注册" "未注册" "在 DC1 上运行 setspn -S $($n.Replace('http','HTTP')) SVR2（不注册会回退 NTLM）" }
}
$gSso = Get-GpoByName "Intranet-SSO"
if($gSso){
  if(Test-GpoLinked $gSso.Guid $domainDN){ Add-Item "GPO Intranet-SSO 已链接到域" "PASS" "链接到 lab.local" "已链接" }
  else { Add-Item "GPO Intranet-SSO 已链接到域" "FAIL" "链接到 lab.local" "未链接到域根" "New-GPLink -Name Intranet-SSO -Target `"DC=lab,DC=local`"（CLIENT1 在 Computers 容器里，链接到 Company 到不了它）" }
  $pol = $null; try { $pol = [IO.File]::ReadAllBytes((Join-Path $gSso.Path "Machine\Registry.pol")) } catch {}
  $txt = if($pol){ [Text.Encoding]::Unicode.GetString($pol) } else { "" }
  $zoneOk = $txt -match [regex]::Escape("https://*.lab.local")
  $edgeOk = ($txt -match "AuthServerAllowlist") -and ($txt -match [regex]::Escape("*.lab.local"))
  if($zoneOk){ Add-Item "Intranet-SSO：https://*.lab.local → 本地 Intranet" "PASS" "已配置" "已配置" } else { Add-Item "Intranet-SSO：https://*.lab.local → 本地 Intranet" "FAIL" "已配置" "未找到" "按任务 2 详细步骤第四步的 Set-GPRegistryValue（ZoneMapKey）" }
  if($edgeOk){ Add-Item "Intranet-SSO：Edge AuthServerAllowlist = *.lab.local" "PASS" "已配置" "已配置" } else { Add-Item "Intranet-SSO：Edge AuthServerAllowlist = *.lab.local" "FAIL" "已配置" "未找到" "按任务 2 详细步骤第四步的 Set-GPRegistryValue（Edge AuthServerAllowlist）" }
} else { Add-Item "GPO Intranet-SSO 存在" "FAIL" "存在" "未找到" "按任务 2 详细步骤第四步新建 Intranet-SSO 并链接到域" }

Add-Task "任务3 · FTP 迁移到 SVR2"
$ftp = Get-Website | Where-Object { $_.bindings.Collection | Where-Object { $_.protocol -eq "ftp" } } | Select-Object -First 1
if($ftp){
  Add-Item "SVR2 上有 FTP 站点" "PASS" "存在" "$($ftp.Name)（$($ftp.physicalPath)，$($ftp.State)）"
  $p = "IIS:\Sites\$($ftp.Name)"
  $basic = (Get-ItemProperty $p -Name ftpServer.security.authentication.basicAuthentication.enabled).Value
  $anonF = (Get-ItemProperty $p -Name ftpServer.security.authentication.anonymousAuthentication.enabled).Value
  if($basic -and -not $anonF){ Add-Item "FTP 基本认证开、匿名关" "PASS" "基本=True 匿名=False" "基本=$basic 匿名=$anonF" }
  else { Add-Item "FTP 基本认证开、匿名关" "FAIL" "基本=True 匿名=False" "基本=$basic 匿名=$anonF" "FTP 身份验证里只启用「基本」" }
  $rules = @(Get-WebConfiguration -PSPath IIS:\ -Location $ftp.Name -Filter system.ftpServer/security/authorization/add -EA SilentlyContinue)
  $roles = ($rules | Where-Object { $_.accessType -eq "Allow" } | ForEach-Object { "$($_.roles) $($_.users)" }) -join ","
  $everyone = $rules | Where-Object { $_.accessType -eq "Allow" -and ($_.users -eq "*" -or $_.roles -match "Everyone|^\*$") }
  if($roles -match "Domain-IT" -and $roles -match "Domain-Finance" -and -not $everyone){ Add-Item "FTP 授权给 Domain-IT 与 Domain-Finance" "PASS" "两个部门组" $roles.Trim() }
  else { Add-Item "FTP 授权给 Domain-IT 与 Domain-Finance" "FAIL" "两个部门组，不含所有用户" ($(if($roles){$roles}else{"无授权规则"})) "FTP 授权规则 › 添加允许规则 › 指定角色或用户组 LAB\Domain-IT,LAB\Domain-Finance" }
  $ctl = "$(Get-ItemProperty $p -Name ftpServer.security.ssl.controlChannelPolicy)"; $dat = "$(Get-ItemProperty $p -Name ftpServer.security.ssl.dataChannelPolicy)"
  $hash = (Get-ItemProperty $p -Name ftpServer.security.ssl.serverCertHash).Value
  $fc = if($hash){ Get-Item "Cert:\LocalMachine\My\$hash" -EA SilentlyContinue } else { $null }
  if($ctl -eq "SslRequire" -and $dat -eq "SslRequire"){ Add-Item "FTP 需要 SSL（控制+数据通道）" "PASS" "SslRequire" "$ctl / $dat" }
  else { Add-Item "FTP 需要 SSL（控制+数据通道）" "FAIL" "SslRequire" "$ctl / $dat" "FTP SSL 设置 › 需要 SSL 连接" }
  if($fc -and $fc.Issuer -match "Lab-Root-CA"){ Add-Item "FTP 证书由 Lab-Root-CA 签发" "PASS" "Lab-Root-CA" "$($fc.Subject) SAN=$(($fc.DnsNameList | ForEach-Object Unicode) -join ',')" }
  else { Add-Item "FTP 证书由 Lab-Root-CA 签发" "FAIL" "Lab-Root-CA" ($(if($fc){$fc.Issuer}else{"未选证书"})) "FTP SSL 设置里选第 32 课的 Intranet-SAN 证书" }
  $iso = "$(Get-ItemProperty $p -Name ftpServer.userIsolation.mode)"
  if($iso -match "IsolateAllDirectories|IsolateRootDirectoryOnly"){ Add-Item "FTP 用户隔离已开启" "PASS" "用户名目录" $iso }
  else { Add-Item "FTP 用户隔离已开启" "FAIL" "用户名目录" $iso "FTP 用户隔离 › 用户名目录（禁用全局虚拟目录）" }
  $ftpHome = Join-Path $ftp.physicalPath.Replace("%SystemDrive%",$env:SystemDrive) "LAB"
  $users = @(Get-ChildItem $ftpHome -Directory -EA SilentlyContinue | ForEach-Object Name)
  if(($users -contains "sunqi") -and ($users -contains "zhangsan")){ Add-Item "家目录 根目录\LAB\sunqi、zhangsan" "PASS" "两个目录" "$ftpHome\{$($users -join ',')}" }
  else { Add-Item "家目录 根目录\LAB\sunqi、zhangsan" "FAIL" "两个目录" ($(if($users){$users -join ','}else{"$ftpHome 不存在"})) "隔离模式下域用户家目录必须是 根目录\LAB\用户名" }
} else { Add-Item "SVR2 上有 FTP 站点" "FAIL" "存在" "未找到" "按任务 3 安装 FTP 并添加 FTP 站点 CorpFTP" }
$lo = (Get-WebConfigurationProperty -PSPath IIS:\ -Filter system.ftpServer/firewallSupport -Name lowDataChannelPort -EA SilentlyContinue).Value
$hi = (Get-WebConfigurationProperty -PSPath IIS:\ -Filter system.ftpServer/firewallSupport -Name highDataChannelPort -EA SilentlyContinue).Value
if($lo -eq 50000 -and $hi -eq 50100){ Add-Item "服务器级被动端口 50000-50100" "PASS" "50000-50100" "$lo-$hi" }
else { Add-Item "服务器级被动端口 50000-50100" "FAIL" "50000-50100" "$lo-$hi" "点左侧服务器节点 › FTP 防火墙支持 › 数据通道端口范围 50000-50100，然后 Restart-Service ftpsvc" }
$fwP = Get-NetFirewallRule -DisplayName "Allow FTP Passive" -EA SilentlyContinue
$fwPort = if($fwP){ ($fwP | Get-NetFirewallPortFilter).LocalPort -join "," } else { "" }
$builtin = Get-NetFirewallRule -DisplayName "FTP 服务器被动(FTP 被动流量入站)" -EA SilentlyContinue
$builtinOn = $builtin -and ($builtin | Where-Object { $_.Enabled -eq "True" })
if($fwP -and $fwPort -eq "50000-50100" -and -not $builtinOn){ Add-Item "防火墙只放行 21 + 50000-50100" "PASS" "内置被动规则已禁用" "Allow FTP Passive=$fwPort；内置规则禁用" }
else { Add-Item "防火墙只放行 21 + 50000-50100" "FAIL" "Allow FTP Passive=50000-50100，内置被动规则禁用" "Allow FTP Passive=$fwPort；内置规则启用=$([bool]$builtinOn)" "Disable-NetFirewallRule -DisplayName `"FTP 服务器被动(FTP 被动流量入站)`"" }
$dc21 = Test-NetConnection $dcIP -Port 21 -WarningAction SilentlyContinue -InformationLevel Quiet
if(-not $dc21){ Add-Item "DC1 旧 LabFTP 已停用（21 不通）" "PASS" "不通" "不通" }
else { Add-Item "DC1 旧 LabFTP 已停用（21 不通）" "FAIL" "不通" "DC1 21 端口仍在监听" "DC1 的 IIS 管理器 › LabFTP › 右侧「停止」（Stop-Website 停不掉 FTP 站点）" }

Add-Task "证据采集"
$ftpLog = if($ftp){ Get-ChildItem "C:\inetpub\logs\LogFiles\FTPSVC$($ftp.id)" -EA SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 } else { $null }
if($ftpLog){
  $ok = @(Get-Content $ftpLog.FullName -EA SilentlyContinue | Where-Object { $_ -match " PASS " -and $_ -match " 230 " } | ForEach-Object { ($_ -split ' ')[3] } | Select-Object -Unique)
  Add-Item "FTP 日志里成功登录过的账号（采集）" "INFO" "" ($(if($ok){$ok -join ', '}else{"暂无（日志约 1 分钟后才写入）"}))
}
$webLog = Get-ChildItem "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website -Name $site -EA SilentlyContinue).id)" -EA SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
if($webLog){
  $who = @(Get-Content $webLog.FullName -EA SilentlyContinue | Where-Object { $_ -notmatch '^#' } | ForEach-Object { $f = $_ -split ' '; if($f.Count -gt 11 -and $f[7] -ne '-' -and $f[11] -eq '200'){ $f[7] } } | Select-Object -Unique)
  Add-Item "网站日志里以域账号访问成功的用户（采集）" "INFO" "" ($(if($who){$who -join ', '}else{"暂无（先在 CLIENT1 用 Edge 打开网站）"}))
}

Export-CheckReport
