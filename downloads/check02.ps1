# check02.ps1 — 第2课 服务器管理器与角色/功能(DHCP/DNS)：任务检查与证据采集
# 用法：以管理员身份运行  powershell -ExecutionPolicy Bypass -File check02.ps1
. "$PSScriptRoot\checklib.ps1"
Start-CheckReport "Lesson02" "第 2 课 · 服务器管理器与角色/功能"

Add-Task "任务1 · 角色/功能安装"
# DHCP Server 角色
$dhcpFeat = Get-WindowsFeature DHCP -EA SilentlyContinue
if($dhcpFeat -and $dhcpFeat.Installed){
  Add-Item "DHCP Server 角色已安装" "PASS" "已安装" "Installed=True"
} else {
  Add-Item "DHCP Server 角色已安装" "FAIL" "已安装" "Installed=False" "未安装 DHCP Server 角色"
}
$dhcpSvc = Get-Service DHCPServer -EA SilentlyContinue
if($dhcpSvc){
  if($dhcpSvc.Status -eq "Running"){
    Add-Item "DHCP 服务(DHCPServer)运行中" "PASS" "Running" "$($dhcpSvc.Status)"
  } else {
    Add-Item "DHCP 服务(DHCPServer)运行中" "WARN" "Running" "$($dhcpSvc.Status)" "服务未处于运行状态"
  }
} else {
  Add-Item "DHCP 服务(DHCPServer)运行中" "FAIL" "Running" "<服务不存在>" "未找到 DHCPServer 服务"
}

# DNS Server 角色
$dnsFeat = Get-WindowsFeature DNS -EA SilentlyContinue
if($dnsFeat -and $dnsFeat.Installed){
  Add-Item "DNS Server 角色已安装" "PASS" "已安装" "Installed=True"
} else {
  Add-Item "DNS Server 角色已安装" "FAIL" "已安装" "Installed=False" "未安装 DNS Server 角色"
}
$dnsSvc = Get-Service DNS -EA SilentlyContinue
if($dnsSvc){
  if($dnsSvc.Status -eq "Running"){
    Add-Item "DNS 服务(DNS)运行中" "PASS" "Running" "$($dnsSvc.Status)"
  } else {
    Add-Item "DNS 服务(DNS)运行中" "WARN" "Running" "$($dnsSvc.Status)" "服务未处于运行状态"
  }
} else {
  Add-Item "DNS 服务(DNS)运行中" "FAIL" "Running" "<服务不存在>" "未找到 DNS 服务"
}

# Telnet-Client 功能
$telnet = Get-WindowsFeature Telnet-Client -EA SilentlyContinue
if($telnet -and $telnet.Installed){
  Add-Item "Telnet-Client 功能已安装" "PASS" "已安装" "Installed=True"
} else {
  Add-Item "Telnet-Client 功能已安装" "WARN" "已安装" "Installed=False" "课程要求安装 Telnet-Client 功能"
}

# 采集：当前已安装的所有角色清单
$roles = Get-WindowsFeature -EA SilentlyContinue | Where-Object {$_.Installed -and $_.FeatureType -eq 'Role'} | ForEach-Object Name
Add-Item "已安装角色清单(采集)" "INFO" "" (($roles) -join " ; ")

Add-Task "任务2 · DHCP 作用域"
$scopes = Get-DhcpServerv4Scope -EA SilentlyContinue
if($scopes){
  $scopeInfo = ($scopes | ForEach-Object { "$($_.ScopeId) [$($_.StartRange)-$($_.EndRange)] State=$($_.State)" }) -join " ; "
  $target = $scopes | Where-Object { $_.StartRange -eq "10.10.10.100" -and $_.EndRange -eq "10.10.10.200" -and $_.State -eq "Active" }
  if($target){
    Add-Item "DHCP 作用域(10.10.10.100-200/Active)" "PASS" "10.10.10.100-200 State=Active" $scopeInfo
  } else {
    Add-Item "DHCP 作用域(10.10.10.100-200/Active)" "WARN" "10.10.10.100-200 State=Active" $scopeInfo "未发现范围/状态完全匹配的作用域"
  }
  # 006 DNS 选项
  $sid = ($scopes | Select-Object -First 1).ScopeId.IPAddressToString
  $dnsOpt = Get-DhcpServerv4OptionValue -ScopeId $sid -OptionId 6 -EA SilentlyContinue
  if($dnsOpt){
    Add-Item "作用域 006 DNS 选项(采集)" "INFO" "" "ScopeId=$sid 006 DNS=$(($dnsOpt.Value) -join ',')"
  } else {
    Add-Item "作用域 006 DNS 选项(采集)" "INFO" "" "ScopeId=$sid 未设置 006 DNS 选项"
  }
} else {
  Add-Item "DHCP 作用域(10.10.10.100-200/Active)" "FAIL" "10.10.10.100-200 State=Active" "<未发现任何 IPv4 作用域>" "DHCP 未配置作用域"
}

Add-Task "任务3 · DNS 区域和记录"
$zone = Get-DnsServerZone -Name lab.local -EA SilentlyContinue
if($zone){
  Add-Item "lab.local 主要区域存在" "PASS" "存在(主要区域)" "ZoneName=$($zone.ZoneName) ZoneType=$($zone.ZoneType)"
} else {
  Add-Item "lab.local 主要区域存在" "FAIL" "存在(主要区域)" "<未找到 lab.local 区域>" "未创建 lab.local 正向查找区域"
}

# dc1 A 记录解析
$res = Resolve-DnsName dc1.lab.local -Server 127.0.0.1 -EA SilentlyContinue | Where-Object {$_.IPAddress}
if($res){
  $ipList = ($res | ForEach-Object { $_.IPAddress }) -join ","
  $lab = $res | Where-Object { $_.IPAddress -like "10.10.10.*" }
  if($lab){
    Add-Item "dc1.lab.local 解析到 10.10.10.x" "PASS" "10.10.10.x" $ipList
  } else {
    Add-Item "dc1.lab.local 解析到 10.10.10.x" "WARN" "10.10.10.x" $ipList "解析成功但不在 10.10.10.0/24 段"
  }
} else {
  Add-Item "dc1.lab.local 解析到 10.10.10.x" "FAIL" "10.10.10.x" "<无法解析 dc1.lab.local>" "DNS 未解析出 dc1 的 A 记录"
}

# 采集 lab.local 区域所有 A 记录
$aRecords = Get-DnsServerResourceRecord -ZoneName lab.local -RRType A -EA SilentlyContinue | ForEach-Object { "$($_.HostName)=$($_.RecordData.IPv4Address)" }
if($aRecords){
  Add-Item "lab.local A 记录清单(采集)" "INFO" "" (($aRecords) -join " ; ")
} else {
  Add-Item "lab.local A 记录清单(采集)" "INFO" "" "<未采集到 A 记录>"
}

Export-CheckReport
