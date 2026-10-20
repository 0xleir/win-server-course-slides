# check16.ps1 — 第16课 远程访问安全加固：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check16.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson16" "第 16 课 · 远程访问安全加固"
$pol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$ts  = "HKLM:\System\CurrentControlSet\Control\Terminal Server"

Add-Task "任务1 · RDP 加固（会话与重定向）"
# 并发连接数 <= 2
$mic = (Get-ItemProperty $pol -Name MaxInstanceCount -EA SilentlyContinue).MaxInstanceCount
if($null -eq $mic){ $mic = (Get-ItemProperty $ts -Name MaxInstanceCount -EA SilentlyContinue).MaxInstanceCount }
if($null -ne $mic -and [int]$mic -ge 1 -and [int]$mic -le 2){ Add-Item "RDP 并发连接数限制 ≤ 2" "PASS" "1~2" "$mic" }
else { Add-Item "RDP 并发连接数限制 ≤ 2" "FAIL" "1~2" ($(if($null -ne $mic){"$mic"}else{"未设"})) "gpedit → 远程桌面会话主机 → 连接 → 限制连接的数量 = 2" }

# 禁用剪贴板重定向
$clip = (Get-ItemProperty $pol -Name fDisableClip -EA SilentlyContinue).fDisableClip
if($null -eq $clip){ $clip = (Get-ItemProperty $ts -Name fDisableClip -EA SilentlyContinue).fDisableClip }
if($clip -eq 1){ Add-Item "剪贴板重定向已禁用" "PASS" "fDisableClip=1" "1" }
else { Add-Item "剪贴板重定向已禁用" "FAIL" "fDisableClip=1" ($(if($null -ne $clip){"$clip"}else{"未设"})) "gpedit → 设备和资源重定向 → 不允许剪贴板重定向 = 已启用" }

Add-Task "任务2 · WinRM 安全加固"
# HTTPS 5986 监听器 + 证书
$https = @()
try {
  foreach($l in (Get-ChildItem WSMan:\localhost\Listener -EA Stop)){
    $props = Get-ChildItem ("WSMan:\localhost\Listener\" + $l.Name) -EA SilentlyContinue
    $t = ($props | Where-Object { $_.Name -eq "Transport" }).Value
    $p = ($props | Where-Object { $_.Name -eq "Port" }).Value
    $c = ($props | Where-Object { $_.Name -eq "CertificateThumbprint" }).Value
    if($t -eq "HTTPS"){ $https += @{ port="$p"; cert="$c" } }
  }
} catch {}
$hok = [bool]($https | Where-Object { $_.port -eq "5986" -and $_.cert })
if($hok){ Add-Item "WinRM HTTPS 监听器存在（5986 + 证书）" "PASS" "HTTPS:5986 + 证书" (($https | ForEach-Object { "HTTPS:$($_.port) cert=$($_.cert)" }) -join "; ") }
else { Add-Item "WinRM HTTPS 监听器存在（5986 + 证书）" "FAIL" "HTTPS:5986 + 证书" ($(if($https.Count){"有HTTPS但端口/证书不符"}else{"无 HTTPS 监听器"})) "New-WSManInstance winrm/config/Listener ... Transport=HTTPS" }

# IPv4Filter 来源过滤
$f4 = ""
try { $f4 = "" + (Get-Item WSMan:\localhost\Service\IPv4Filter -EA Stop).Value } catch {}
if($f4 -match "^\s*10\.10\.10\.\d+\s*-\s*10\.10\.10\.\d+\s*$"){ Add-Item "WinRM 来源过滤 IPv4Filter（限 10.10.10.0/24）" "PASS" "10.10.10.1-10.10.10.254" $f4 }
elseif($f4 -eq "*" -or $f4 -eq ""){ Add-Item "WinRM 来源过滤 IPv4Filter（限 10.10.10.0/24）" "FAIL" "10.10.10.1-10.10.10.254" ($(if($f4){$f4}else{"(空)"})) 'Set-Item WSMan:\localhost\Service\IPv4Filter -Value "10.10.10.1-10.10.10.254"（只认范围, 不认 10.10.10.*）' }
else { Add-Item "WinRM 来源过滤 IPv4Filter（限 10.10.10.0/24）" "WARN" "10.10.10.1-10.10.10.254" $f4 "值不是标准实验网段范围" }

Add-Task "任务3 · 防火墙基线"
$prof = @(Get-NetFirewallProfile -EA SilentlyContinue)
$blocked = @($prof | Where-Object { "$($_.DefaultInboundAction)" -eq "Block" } | ForEach-Object { $_.Name })
if($blocked.Count -ge 3){ Add-Item "防火墙默认入站策略 = 阻止（三个配置文件）" "PASS" "Domain/Public/Private 都 Block" ($blocked -join ",") }
else { Add-Item "防火墙默认入站策略 = 阻止（三个配置文件）" "FAIL" "Domain/Public/Private 都 Block" ($(if($blocked.Count){$blocked -join ","}else{"无(仍为默认)"})) "Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block" }

# 必要放行规则仍在(封默认前的前提)
$need = @{}
foreach($pr in 3390,5986,5985){
  $r = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -EA SilentlyContinue | ForEach-Object {
    $pf = $_ | Get-NetFirewallPortFilter -EA SilentlyContinue
    if($pf -and "$($pf.Protocol)" -eq "TCP" -and (("$($pf.LocalPort)") -split ',') -contains "$pr"){ $_.DisplayName }
  })
  $need["$pr"] = $r.Count -gt 0
}
if($need["3390"] -and $need["5986"]){ Add-Item "关键端口放行规则在位（3390/5986）" "PASS" "3390,5986 已放行" ("3390=" + $need["3390"] + " 5986=" + $need["5986"] + " 5985=" + $need["5985"]) }
else { Add-Item "关键端口放行规则在位（3390/5986）" "WARN" "3390,5986 已放行" ("3390=" + $need["3390"] + " 5986=" + $need["5986"]) "封默认入站前必须先放行, 否则远程全断" }

Add-Task "汇总（采集）"
Add-Item "WinRM 监听器（采集）" "INFO" "" (($https | ForEach-Object { "HTTPS:$($_.port)" }) -join " ; ")
Add-Item "防火墙各配置文件默认入站（采集）" "INFO" "" (($prof | ForEach-Object { "$($_.Name)=$($_.DefaultInboundAction)" }) -join " ; ")

Export-CheckReport
