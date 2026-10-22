# check17.ps1 — 第17课 Active Directory 域搭建：检查与证据采集（在 DC1 上运行）
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check17.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson17" "第 17 课 · Active Directory 域搭建"
Import-Module ActiveDirectory -EA SilentlyContinue

Add-Task "任务2 · DC1 已提升为域控制器"
# 是否域控: ProductType = LanmanNT
$pt = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions" -Name ProductType -EA SilentlyContinue).ProductType
if($pt -eq "LanmanNT"){ Add-Item "本机是域控制器（ProductType=LanmanNT）" "PASS" "LanmanNT" "$pt" }
else { Add-Item "本机是域控制器（ProductType=LanmanNT）" "FAIL" "LanmanNT" "$pt" "Install-ADDSForest 提升为域控" }

# NTDS 服务运行
$ntds = Get-Service NTDS -EA SilentlyContinue
if($ntds -and $ntds.Status -eq "Running"){ Add-Item "AD DS 服务（NTDS）运行中" "PASS" "Running" "Running" }
else { Add-Item "AD DS 服务（NTDS）运行中" "FAIL" "Running" ($(if($ntds){$ntds.Status}else{"不存在"})) }

# 域名与 NetBIOS
$dom = $null; try { $dom = Get-ADDomain -EA Stop } catch {}
if($dom -and $dom.DNSRoot -eq "lab.local" -and $dom.NetBIOSName -eq "LAB"){ Add-Item "域为 lab.local（NetBIOS LAB）" "PASS" "lab.local / LAB" ($dom.DNSRoot + " / " + $dom.NetBIOSName) }
elseif($dom){ Add-Item "域为 lab.local（NetBIOS LAB）" "FAIL" "lab.local / LAB" ($dom.DNSRoot + " / " + $dom.NetBIOSName) }
else { Add-Item "域为 lab.local（NetBIOS LAB）" "FAIL" "lab.local / LAB" "Get-ADDomain 失败（AD 未就绪）" }

# DC 定位器健康(nltest)
$nl = (nltest /dsgetdc:lab.local 2>&1) -join "`n"
if($nl -match "成功|successful" -and $nl -match "lab\.local"){ Add-Item "DC 定位器正常（nltest /dsgetdc）" "PASS" "命令成功完成 + lab.local" "nltest OK（含 PDC/LDAP/KDC/DNS_DC 标志）" }
else { Add-Item "DC 定位器正常（nltest /dsgetdc）" "FAIL" "命令成功完成" ($nl.Substring(0,[Math]::Min(80,$nl.Length))) }

Add-Task "任务2 · DNS 集成"
# DNS 区域 lab.local
$zone = Get-DnsServerZone -Name "lab.local" -EA SilentlyContinue
if($zone){ Add-Item "DNS 区域 lab.local 存在" "PASS" "存在（AD 集成）" ("ZoneType=" + $zone.ZoneType + " ADIntegrated=" + $zone.IsDsIntegrated) }
else { Add-Item "DNS 区域 lab.local 存在" "FAIL" "存在" "无" "-InstallDns 会在提升时创建" }

# DC1 自身 DNS 指向(应指向自己/127.0.0.1 或 10.10.10.10)
$dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.ServerAddresses } | ForEach-Object { $_.ServerAddresses }) | Select-Object -Unique
if(($dns -contains "127.0.0.1") -or ($dns -contains "10.10.10.10")){ Add-Item "DC1 DNS 指向本机" "PASS" "127.0.0.1 或 10.10.10.10" ($dns -join ",") }
else { Add-Item "DC1 DNS 指向本机" "WARN" "127.0.0.1 或 10.10.10.10" ($dns -join ",") "域控应把首选 DNS 指向自身" }

Add-Task "任务3/4 · 成员机加入域"
# 从 DC 查 AD 计算机对象：SVR2 / CLIENT1 加域后一定出现在这里，能硬判定（不是采集）
$comps = @()
try { $comps = @(Get-ADComputer -Filter * -EA Stop | ForEach-Object { $_.Name }) } catch {}
$svr2  = @($comps | Where-Object { $_ -match "^SVR2$|^SVR-?2" }).Count -gt 0
$cli1  = @($comps | Where-Object { $_ -match "^CLIENT1$|^CLIENT-?1|^WIN10" }).Count -gt 0
if($svr2){ Add-Item "任务3 · SVR2 已加入域（AD 中有计算机账户）" "PASS" "AD 含 SVR2" ($comps -join ", ") }
else { Add-Item "任务3 · SVR2 已加入域（AD 中有计算机账户）" "FAIL" "AD 含 SVR2" ("当前计算机对象: " + ($comps -join ", ")) "在 SVR2 上 Add-Computer -DomainName lab.local -Restart" }
if($cli1){ Add-Item "任务4 · CLIENT1 已加入域（AD 中有计算机账户）" "PASS" "AD 含 CLIENT1" ($comps -join ", ") }
else { Add-Item "任务4 · CLIENT1 已加入域（AD 中有计算机账户）" "FAIL" "AD 含 CLIENT1" ("当前计算机对象: " + ($comps -join ", ")) "在 CLIENT1 上『设置 → 访问工作或学校 → 加入本地 AD 域 lab.local』" }

Add-Task "汇总（采集）"
Add-Item "域内全部计算机对象（采集）" "INFO" "" ($comps -join " ; ")

Export-CheckReport
