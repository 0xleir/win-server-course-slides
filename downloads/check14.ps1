# check14.ps1 — 第14课 远程桌面服务（RDS）：任务检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check14.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson14" "第 14 课 · 远程桌面服务（RDS）"
$ts  = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
$rdp = "$ts\WinStations\RDP-Tcp"

Add-Task "任务1 · 启用远程桌面与授权"
$deny = (Get-ItemProperty -Path $ts -Name fDenyTSConnections -EA SilentlyContinue).fDenyTSConnections
if($deny -eq 0){ Add-Item "远程桌面已启用" "PASS" "fDenyTSConnections=0" "0" }
else { Add-Item "远程桌面已启用" "FAIL" "fDenyTSConnections=0" "$deny" 'Set-ItemProperty "'+$ts+'" fDenyTSConnections 0' }

$nla = (Get-ItemProperty -Path $rdp -Name UserAuthentication -EA SilentlyContinue).UserAuthentication
if($nla -eq 1){ Add-Item "NLA 已启用（仅网络级别身份验证）" "PASS" "UserAuthentication=1" "1" }
else { Add-Item "NLA 已启用（仅网络级别身份验证）" "FAIL" "UserAuthentication=1" "$nla" '勾选"仅允许使用网络级别身份验证的远程桌面连接"' }

$rdu = @()
try { $rdu = @(Get-LocalGroupMember -Group "Remote Desktop Users" -EA Stop | ForEach-Object { ($_.Name -split '\\')[-1] }) } catch {}
if($rdu -contains "IT-Admins"){ Add-Item "IT-Admins 在 Remote Desktop Users 组中" "PASS" "含 IT-Admins" ($rdu -join ",") }
else { Add-Item "IT-Admins 在 Remote Desktop Users 组中" "FAIL" "含 IT-Admins" ($(if($rdu.Count){$rdu -join ","}else{"(空)"})) 'Add-LocalGroupMember "Remote Desktop Users" "IT-Admins"' }

Add-Task "任务2 · 改端口 3390 并放行防火墙"
$port = (Get-ItemProperty -Path $rdp -Name PortNumber -EA SilentlyContinue).PortNumber
$listen = @(Get-NetTCPConnection -LocalPort 3390 -State Listen -EA SilentlyContinue)
if($port -eq 3390 -and $listen.Count -gt 0){ Add-Item "RDP 端口已改为 3390 且在监听" "PASS" "PortNumber=3390 + Listen" "PortNumber=$port; 3390监听=$($listen.Count)" }
elseif($port -eq 3390){ Add-Item "RDP 端口已改为 3390 且在监听" "FAIL" "PortNumber=3390 + Listen" "PortNumber=3390 但未监听3390" "改端口后要重启 UmRdpService 和 TermService" }
else { Add-Item "RDP 端口已改为 3390 且在监听" "FAIL" "PortNumber=3390 + Listen" "PortNumber=$port" 'Set-ItemProperty "'+$rdp+'" PortNumber 3390; Restart-Service TermService -Force' }

$fw = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -EA SilentlyContinue | ForEach-Object {
    $pf = $_ | Get-NetFirewallPortFilter -EA SilentlyContinue
    if($pf -and "$($pf.Protocol)" -eq "TCP" -and (("$($pf.LocalPort)") -split ',') -contains "3390"){ $_.DisplayName }
})
if($fw.Count -gt 0){ Add-Item "防火墙放行 TCP 3390 入站" "PASS" "有放行3390的入站规则" ($fw -join ", ") }
else { Add-Item "防火墙放行 TCP 3390 入站" "FAIL" "有放行3390的入站规则" "无" 'New-NetFirewallRule -DisplayName "Allow RDP 3390" -Direction Inbound -Protocol TCP -LocalPort 3390 -Action Allow' }

Add-Task "任务3 · RD Gateway 角色"
$gw = Get-WindowsFeature RDS-Gateway -EA SilentlyContinue
if($gw -and $gw.Installed){ Add-Item "RD Gateway 角色已安装" "PASS" "Installed" "Installed" }
else { Add-Item "RD Gateway 角色已安装" "FAIL" "Installed" ($(if($gw){$gw.InstallState}else{"查询失败"})) "Install-WindowsFeature RDS-Gateway -IncludeManagementTools" }

Add-Task "汇总（采集）"
Add-Item "远程桌面相关防火墙规则（采集）" "INFO" "" ((Get-NetFirewallRule -Direction Inbound -Enabled True -EA SilentlyContinue | Where-Object { $_.DisplayGroup -match "远程桌面|Remote Desktop" -or $_.DisplayName -match "3390" } | ForEach-Object { "$($_.DisplayName)[$($_.Enabled)]" }) -join " ; ")
Add-Item "TermService 服务状态（采集）" "INFO" "" ("TermService=" + (Get-Service TermService -EA SilentlyContinue).Status)

Export-CheckReport
