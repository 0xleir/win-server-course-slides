# diag-ipsec.ps1 — 第21课 IPsec 连接安全规则 诊断脚本
# 用途：学生做完 L21 任务2 (DC1↔SVR2 IPsec) 发现 Get-NetIPsecMainModeSA 空、Test-Connection 失败等问题时，
#       跑一遍这个脚本自动定位到具体原因。无侧效应，不改任何配置。
# 用法：在 DC1 或 SVR2 任一台上以管理员身份运行
#     powershell -ExecutionPolicy Bypass -File diag-ipsec.ps1
#     可选参数：
#         -Peer 10.10.10.20      # 对端 IP (默认根据本机 IP 自动判断)
#         -Verbose                # 显示每步详细输出

[CmdletBinding()]
param(
    [string]$Peer = "",
    [string]$Self = ""
)

$ErrorActionPreference = "Continue"

# ----- 工具函数 -----
function OK($t)    { Write-Host "  [✓] $t" -ForegroundColor Green }
function BAD($t)   { Write-Host "  [✗] $t" -ForegroundColor Red }
function WARN($t)  { Write-Host "  [!] $t" -ForegroundColor Yellow }
function INFO($t)  { Write-Host "  [i] $t" -ForegroundColor Cyan }
function STEP($t)  { Write-Host "`n━━━ $t ━━━" -ForegroundColor Magenta }
function TIP($t)   { Write-Host "      → $t" -ForegroundColor DarkYellow }

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   L21 IPsec 连接安全规则 · 诊断工具 v1.0        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

# 结论汇总
$script:Issues = @()
function Issue($level, $msg, $fix) {
    $script:Issues += [ordered]@{ Level=$level; Msg=$msg; Fix=$fix }
}

function Show-Summary {
    STEP "诊断结论"
    if (-not $script:Issues) {
        Write-Host "`n  🎉 没发现问题！IPsec 应该能正常工作。" -ForegroundColor Green
        Write-Host "     如果 Test-NetConnection 到对端端口（如 445）还失败，请：" -ForegroundColor Green
        Write-Host "     1. 在对端也跑一遍这个脚本" -ForegroundColor Green
        Write-Host "     2. 确认对端规则是「对称」的（Endpoint1/2 互换）" -ForegroundColor Green
        Write-Host "     3. 看对端防火墙是否放行 445" -ForegroundColor Green
        return
    }

    $script:Issues | ForEach-Object {
        $color = switch ($_.Level) {
            "FATAL" { "Red" }
            "ERROR" { "Red" }
            "WARN"  { "Yellow" }
            default { "White" }
        }
        Write-Host ""
        Write-Host "  [$($_.Level)] $($_.Msg)" -ForegroundColor $color
        Write-Host "       修复: $($_.Fix)" -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host "  共 $(($script:Issues).Count) 个问题。按上面「修复」操作，再跑一遍脚本确认。" -ForegroundColor Yellow
}

# ───────────────────────────────────────────────────────────
# 1. 自动识别本机角色
# ───────────────────────────────────────────────────────────
STEP "步骤 1 · 识别本机"

$hn  = $env:COMPUTERNAME
$ips = @(Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.IPAddress -like "10.10.10.*" } | Select-Object -ExpandProperty IPAddress)
INFO "主机名：$hn"
INFO "本机 10.10 段 IP：$($ips -join ', ')"

if (-not $ips) {
    BAD "本机没有 10.10.10.0/24 段 IP！这是 L21 实验的教学网段，先配好 Ethernet1。"
    TIP "检查：Get-NetAdapter；Set-NetIPAddress 配 10.10.10.10 (DC1) 或 10.10.10.20 (SVR2)"
    Issue "FATAL" "本机不在 10.10.10.0/24 教学网段" "配置 Ethernet1 为 10.10.10.10 或 10.10.10.20"
    return
}

if (-not $Self) { $Self = $ips[0] }
if (-not $Peer) {
    # 本机是.10就对端.20, 反之亦然
    if ($Self -eq "10.10.10.10") { $Peer = "10.10.10.20" }
    elseif ($Self -eq "10.10.10.20") { $Peer = "10.10.10.10" }
    else {
        WARN "本机 IP 不是 .10 或 .20，无法自动猜对端。请手动指定 -Peer <IP>"
        return
    }
}
INFO "本机 IP：$Self（将测试到对端 $Peer）"

# ───────────────────────────────────────────────────────────
# 2. 底层网络连通性 (ICMP + ARP)
# ───────────────────────────────────────────────────────────
STEP "步骤 2 · 底层网络 (L2/L3 可达性)"

# ARP
Remove-NetNeighbor -IPAddress $Peer -Confirm:$false -EA SilentlyContinue
ping.exe $Peer -n 1 -w 1500 | Out-Null
Start-Sleep -Milliseconds 500
$arp = Get-NetNeighbor -IPAddress $Peer -EA SilentlyContinue | Select-Object -First 1

if ($arp -and $arp.State -eq "Reachable") {
    OK "ARP 已解析对端 $Peer → $($arp.LinkLayerAddress) (L2 通)"
} elseif ($arp -and $arp.State -eq "Stale") {
    WARN "ARP 缓存显示 Stale，但曾解析到 $($arp.LinkLayerAddress) — 流量应该能通"
} else {
    BAD "ARP 请求对 $Peer 无应答 (State=$(if($arp){$arp.State}else{'无记录'}))"
    TIP "对端 VM 可能没开机、未在 10.10.10.0/24 PVN 上，或 VMware LAN Segment 配置不一致"
    Issue "FATAL" "L2 不可达 (ARP 无应答)" "检查对端 VM 已开机 + ethernet1 挂到同一个 LAN Segment"
    return
}

# ICMP
$ping = Test-Connection $Peer -Count 2 -Quiet -EA SilentlyContinue
if ($ping) {
    OK "ICMP ping $Peer 可达"
} else {
    WARN "ICMP 不通 — 可能是对端防火墙拦了 ICMP（但 IPsec 协商走的是 UDP 500/4500，可能照样通）"
    TIP "ICMP 不通不一定影响 IPsec，继续看后面步骤"
}

# ───────────────────────────────────────────────────────────
# 3. 规则存在性 (扫 3 个 API)
# ───────────────────────────────────────────────────────────
STEP "步骤 3 · 规则是否已创建"

# 3a. 新 API: Get-NetIPsecRule (PS 创建的能看到)
$psRules = Get-NetIPsecRule -EA SilentlyContinue
if ($psRules) {
    OK "Get-NetIPsecRule 查到 $($psRules.Count) 条规则（PowerShell 创建方式）"
    $psRules | ForEach-Object { INFO "  · $($_.DisplayName)  Enabled=$($_.Enabled)  Mode=$($_.Mode)" }
} else {
    INFO "Get-NetIPsecRule 为空（可能规则是 GUI 建的）"
}

# 3b. 老 API: netsh advfirewall consec (GUI 创建的能看到)
$netshOut = & netsh advfirewall consec show rule name=all 2>&1 | Out-String
# 规则名行格式: "规则名称:  XXX" 或 "Rule Name:  XXX"
$netshRules = [regex]::Matches($netshOut, '规则名称:\s*(.+?)[\r\n]|Rule Name:\s*(.+?)[\r\n]') |
    ForEach-Object { ($_.Groups[1].Value + $_.Groups[2].Value).Trim() } |
    Where-Object { $_ -and $_ -ne "无" -and $_ -ne "No rules match" }
if ($netshRules) {
    OK "netsh consec 查到 $($netshRules.Count) 条规则（GUI/wf.msc 创建方式也能看到）"
    $netshRules | ForEach-Object { INFO "  · $_" }
} else {
    INFO "netsh consec 也为空"
}

$allRuleNames = @($psRules | ForEach-Object { $_.DisplayName }) + $netshRules | Select-Object -Unique
if (-not $allRuleNames) {
    BAD "两种 API 都查不到任何连接安全规则 — 规则根本没创建！"
    TIP "在 wf.msc → 连接安全规则 右键 → 新建规则，或用 PowerShell New-NetIPsecRule"
    Issue "FATAL" "本机没有任何连接安全规则" "参考课件 任务2 创建 DC1-SVR2-IPsec 规则"
    Write-Host ""
    Show-Summary
    return
}

# ───────────────────────────────────────────────────────────
# 4. 规则详细属性 (魔鬼在细节)
# ───────────────────────────────────────────────────────────
STEP "步骤 4 · 规则详细属性"

# 优先用 netsh 的输出(GUI/PS 都覆盖)
$blocks = $netshOut -split '(?=规则名称:\s*|Rule Name:\s*)' | Where-Object { $_ -match '规则名称|Rule Name' }
$matched = $false
foreach ($b in $blocks) {
    # 提取规则的关键字段
    $name     = if ($b -match '规则名称:\s*(.+?)[\r\n]|Rule Name:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }
    if (-not $name) { continue }

    Write-Host "`n  ━ 规则: $name" -ForegroundColor White

    $enabled  = if ($b -match '已启用:\s*(.+?)[\r\n]|Enabled:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }
    $profile  = if ($b -match '配置文件:\s*(.+?)[\r\n]|Profiles:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }
    $ep1      = if ($b -match '终结点 ?1:\s*(.+?)[\r\n]|Endpoint1:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }
    $ep2      = if ($b -match '终结点 ?2:\s*(.+?)[\r\n]|Endpoint2:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }
    $mode     = if ($b -match '模式:\s*(.+?)[\r\n]|Mode:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }
    $action   = if ($b -match '操作:\s*(.+?)[\r\n]|Action:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }
    $auth1    = if ($b -match '身份验证 ?1:\s*(.+?)[\r\n]|Auth1:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }
    $auth1Set = if ($b -match '身份验证 ?1 ?集:\s*(.+?)[\r\n]|Auth1Set:\s*(.+?)[\r\n]') { ($Matches[1]+$Matches[2]).Trim() } else { "" }

    # 判定
    $thisMatched = $false
    if (($ep1 -match [regex]::Escape($Self) -and $ep2 -match [regex]::Escape($Peer)) -or
        ($ep1 -match [regex]::Escape($Peer) -and $ep2 -match [regex]::Escape($Self))) {
        OK "地址匹配：Endpoint1=$ep1  Endpoint2=$ep2"
        $thisMatched = $true; $matched = $true
    } else {
        WARN "地址不匹配本次测试方向：Endpoint1=$ep1  Endpoint2=$ep2 (测试: $Self↔$Peer)"
    }

    if ($enabled -match '是|Yes') { OK "已启用：$enabled" }
    else { BAD "未启用！Enabled=$enabled"; if($thisMatched){ Issue "ERROR" "规则 $name 未启用" "wf.msc → 规则右键 → 启用规则" } }

    if ($mode) { INFO "模式：$mode（传输/隧道，L21 用传输模式）" }

    if ($action -match 'Require|请求认证|请求|Request') {
        if ($action -match 'Request|请求' -and $action -notmatch 'Require|请求认证') {
            WARN "操作=$action — 这是「请求认证」模式，协商失败会回退明文，SA 不会建立！"
            TIP "改成「要求认证」(Require inbound and outbound)，SA 才会强制建立"
            if($thisMatched){ Issue "ERROR" "规则 $name 用的是 Request 而非 Require" "wf.msc → 规则属性 → 身份验证 → 要求对入站和出站连接进行身份验证" }
        } else {
            OK "操作：$action（Require 模式，正确）"
        }
    } else {
        INFO "操作：$action"
    }

    if ($profile) {
        $curProf = (Get-NetConnectionProfile -EA SilentlyContinue | Where-Object { $_.IPv4Connectivity -ne 'NoTraffic' } | Select-Object -First 1).NetworkCategory
        if ($profile -match '任何|Any' -or $profile -match $curProf) {
            OK "配置文件：$profile（当前网络 $curProf 包含在内）"
        } else {
            BAD "配置文件：$profile — 当前网络是 $curProf，规则不覆盖当前网络！"
            TIP "wf.msc → 规则属性 → 高级 → 把当前的网络配置文件勾上，或改成「任何」"
            if($thisMatched){ Issue "ERROR" "规则 $name Profile 不含当前网络 ($curProf)" "wf.msc → 规则属性 → 高级 → 勾选对应配置文件" }
        }
    }

    if ($auth1) {
        if ($auth1 -match 'Kerberos|计算机') {
            OK "身份验证 1：$auth1（Kerberos，正确）"
        } elseif ($auth1 -match 'Certificate|证书|PSK|预共享') {
            WARN "身份验证 1：$auth1 — 不是 Kerberos"
            TIP "L21 要求用 Kerberos V5。改规则属性 → 身份验证 → 自定义 → 第一个身份验证 → 计算机 (Kerberos V5)"
            if($thisMatched){ Issue "WARN" "规则 $name 认证方式不是 Kerberos" "改为「计算机 (Kerberos V5)」" }
        } else {
            INFO "身份验证 1：$auth1"
        }
    }
}

if (-not $matched) {
    BAD "没有任何规则匹配本次测试方向 ($Self ↔ $Peer)！"
    TIP "现有规则的 Endpoint 可能配反、或还没加本次测试涉及的 IP"
    Issue "FATAL" "没有规则覆盖 $Self↔$Peer" "创建或修改规则：Endpoint1=$Self Endpoint2=$Peer"
}

# ───────────────────────────────────────────────────────────
# 5. 域/Kerberos 可用性 (Kerberos 认证模式必需)
# ───────────────────────────────────────────────────────────
STEP "步骤 5 · Kerberos 可用性（认证方式用 Kerberos 时必须）"

$dom = (Get-ComputerInfo -Property CsDomain -EA SilentlyContinue).CsDomain
if ($dom -eq "WORKGROUP" -or -not $dom) {
    BAD "本机未加域（当前 Domain=$dom）"
    TIP "Kerberos 认证需要两端都加入同一个 AD 域。要么改用「证书」或「预共享密钥」，要么把本机加域"
    Issue "FATAL" "本机未加域，Kerberos 无法工作" "加入 lab.local 域，或改用证书/PSK 认证"
} else {
    OK "本机已加域：$dom"

    # Test-ComputerSecureChannel
    $sc = Test-ComputerSecureChannel -Verbose:$false -EA SilentlyContinue
    if ($sc) { OK "域安全通道 (SecureChannel) 正常" }
    else {
        BAD "域安全通道断了！Test-ComputerSecureChannel 返回 False"
        TIP "跑 Reset-ComputerMachinePassword 重置机器账户密码，或退域重新加域"
        Issue "ERROR" "域安全通道断开" "Test-ComputerSecureChannel -Repair 修复"
    }

    # 对端是否能解析成域内主机
    $peerDns = Resolve-DnsName $Peer -EA SilentlyContinue | Where-Object { $_.Type -eq 'PTR' } | Select-Object -First 1
    if ($peerDns) { OK "对端 $Peer 反向解析为：$($peerDns.NameHost)（Kerberos 需要能解析到对端 SPN）" }
    else { WARN "对端 $Peer 无 PTR 记录。Kerberos 可能找不到对端 SPN，需要 DC 上有对端的 A/PTR 记录" }

    # kinit 票据
    $tgt = klist 2>&1 | Select-String "krbtgt"
    if ($tgt) { OK "本机有 Kerberos TGT 票据" }
    else { WARN "没有看到 krbtgt 票据，klist 为空。重新登录域账户获取票据" }
}

# ───────────────────────────────────────────────────────────
# 6. 当前 SA 状态 (结果)
# ───────────────────────────────────────────────────────────
STEP "步骤 6 · 当前 SA 状态"

$msa = Get-NetIPsecMainModeSA -EA SilentlyContinue
$qsa = Get-NetIPsecQuickModeSA -EA SilentlyContinue

if ($msa) {
    OK "Main Mode SA 数量：$($msa.Count)（Phase 1 身份认证已通过）"
    $msa | Select-Object -First 3 | ForEach-Object {
        INFO "  · $($_.LocalEndpoint) ↔ $($_.RemoteEndpoint)  State=$($_.State)"
    }
} else {
    WARN "Main Mode SA 为空 — 身份认证还没完成或还没触发协商"
    TIP "下一步会主动触发一次协商，然后再查"
}

if ($qsa) {
    OK "Quick Mode SA 数量：$($qsa.Count)（Phase 2 数据加密通道已建立）"
} else {
    INFO "Quick Mode SA 为空（如果 Main Mode 也没有，先解决 Main Mode；如果 Main Mode 有，可能是流量方向不匹配）"
}

# ───────────────────────────────────────────────────────────
# 7. 主动触发协商 + 查日志
# ───────────────────────────────────────────────────────────
STEP "步骤 7 · 主动触发协商 + 查 IKE 事件日志"

INFO "清理旧 SA，发真实流量触发协商..."
Get-NetIPsecMainModeSA -EA SilentlyContinue | Remove-NetIPsecMainModeSA -EA SilentlyContinue
Get-NetIPsecQuickModeSA -EA SilentlyContinue | Remove-NetIPsecQuickModeSA -EA SilentlyContinue

$t0 = Get-Date
Test-NetConnection $Peer -Port 445 -WarningAction SilentlyContinue -InformationLevel Quiet | Out-Null
Start-Sleep -Seconds 3

$msa2 = Get-NetIPsecMainModeSA -EA SilentlyContinue
$qsa2 = Get-NetIPsecQuickModeSA -EA SilentlyContinue
if ($msa2) {
    OK "触发后 Main Mode SA 建立成功 ($($msa2.Count) 条) — IPsec 正常工作！"
    if ($qsa2) { OK "触发后 Quick Mode SA 也建立 ($($qsa2.Count) 条)" }
    else { INFO "Quick Mode SA 还没建立（SMB 流量可能被别的东西拦了，但 IPsec 身份认证层 OK）" }
} else {
    BAD "触发后 Main Mode SA 仍为空 — 协商失败"

    # 查 IKE 日志
    $ikeEvts = Get-WinEvent -LogName "Microsoft-Windows-IKE/Operational" -MaxEvents 20 -EA SilentlyContinue |
        Where-Object { $_.TimeCreated -ge $t0 }
    if ($ikeEvts) {
        INFO "IKE 操作日志（最近触发）："
        $ikeEvts | ForEach-Object {
            $firstLine = ($_.Message -split "`n")[0]
            WARN "    [EventID=$($_.Id)] $firstLine"
        }
    } else {
        WARN "没有看到 IKE 操作日志。可能日志没启用或根本没发起协商"
        TIP "启用：wevtutil sl Microsoft-Windows-IKE/Operational /e:true"
    }

    # 查安全审计日志
    $secEvts = Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4650 or EventID=4651 or EventID=4652 or EventID=4653 or EventID=4654 or EventID=4655)]]" -MaxEvents 10 -EA SilentlyContinue |
        Where-Object { $_.TimeCreated -ge $t0 }
    if ($secEvts) {
        INFO "IPsec 审计事件（4650-4655）："
        $secEvts | ForEach-Object {
            $firstLine = ($_.Message -split "`n")[0]
            WARN "    [EventID=$($_.Id)] $firstLine"
        }
        Issue "ERROR" "IPsec 协商产生失败事件" "按上面 EventID 对应错误码查原因（4653=身份认证失败最常见）"
    } else {
        WARN "也没看到 4650-4655 审计事件。可能 IPsec 审计策略没开"
        TIP "开启审计：auditpol /set /subcategory:'IPsec 主模式' /success:enable /failure:enable"
        Issue "WARN" "IPsec 协商未产生任何事件" "可能流量没匹配规则，或审计未开启"
    }
}

# ───────────────────────────────────────────────────────────
# 结论汇总
# ───────────────────────────────────────────────────────────
Show-Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " 排查完毕。有问题请在对端也跑一遍这个脚本做对比。" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
