# ============================================================
#  checklib.ps1 — 课程作业检查脚本公共库
#  被各课 checkNN.ps1 点源引用。负责：采集记录、汇总、导出 HTML/PDF。
#  设计原则：以“采集证据”为主，能判定则判定(PASS/WARN/INFO)，不臆断学号/IP 等个性化值。
# ============================================================
$script:Lesson   = ""
$script:LessonTitle = ""
$script:Tasks    = @()      # 任务段：@{Name;Items=@()}
$script:CurTask  = $null

function Start-CheckReport { param([string]$Lesson,[string]$Title)
  $script:Lesson=$Lesson; $script:LessonTitle=$Title; $script:Tasks=@(); $script:CurTask=$null
}
function Add-Task { param([string]$Name)
  $script:CurTask = @{ Name=$Name; Items=@() }
  $script:Tasks += $script:CurTask
}
# status: PASS / WARN / FAIL / INFO
function Add-Item { param([string]$Name,[string]$Status,$Expected="",$Actual="",[string]$Note="")
  $script:CurTask.Items += [ordered]@{
    Name=$Name; Status=$Status; Expected=[string]$Expected; Actual=[string]$Actual; Note=$Note }
}
# 安全执行采集：出错也不中断，记为 INFO/FAIL
function Try-Collect { param([string]$Name,[scriptblock]$Script,[string]$Expected="")
  try { $v = & $Script; return [string]$v }
  catch { Add-Item $Name "FAIL" $Expected "<采集失败: $($_.Exception.Message.Split([char]10)[0])>"; return $null }
}

function Export-CheckReport {
  Add-Type -AssemblyName System.Web
  function E([object]$s){ if($null -eq $s){ return "" }; return [System.Web.HttpUtility]::HtmlEncode([string]$s) }
  $host0 = $env:COMPUTERNAME
  $now   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $ips = (Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue |
          ? {$_.IPAddress -ne "127.0.0.1" -and $_.IPAddress -notlike "169.254.*"} |
          % { "$($_.InterfaceAlias)=$($_.IPAddress)/$($_.PrefixLength)" }) -join " ; "
  $osc = (Get-CimInstance Win32_OperatingSystem).Caption
  # 统计
  $all = @($script:Tasks | ForEach-Object { $_.Items })
  $nP=@($all|Where-Object{$_.Status -eq "PASS"}).Count; $nW=@($all|Where-Object{$_.Status -eq "WARN"}).Count
  $nF=@($all|Where-Object{$_.Status -eq "FAIL"}).Count; $nI=@($all|Where-Object{$_.Status -eq "INFO"}).Count
  $badge = @{PASS="#36b37e";WARN="#ffab00";FAIL="#ff5630";INFO="#6b7a90"}
  $icon  = @{PASS="&#10004;";WARN="&#9888;";FAIL="&#10008;";INFO="&#8505;"}
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append(@"
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>$($script:Lesson) 作业检查报告 - $host0</title>
<style>
 *{box-sizing:border-box} body{font-family:"Microsoft YaHei",Segoe UI,sans-serif;color:#1a2230;margin:0;padding:28px 34px;font-size:13px}
 h1{font-size:21px;margin:0 0 4px} .sub{color:#6b7a90;margin:0 0 16px}
 .meta{border:1px solid #d7dee8;border-radius:10px;padding:12px 16px;margin:0 0 18px;background:#f6f8fb}
 .meta table{border-collapse:collapse;width:100%} .meta td{padding:3px 8px;vertical-align:top} .meta td.k{color:#6b7a90;width:120px}
 .summary{display:flex;gap:10px;margin:0 0 22px;flex-wrap:wrap}
 .pill{border-radius:999px;padding:6px 16px;color:#fff;font-weight:700}
 h2{font-size:15px;margin:20px 0 8px;padding-bottom:5px;border-bottom:2px solid #e2e8f1}
 table.items{border-collapse:collapse;width:100%;margin:0 0 6px}
 table.items th{background:#eef2f7;text-align:left;padding:7px 10px;font-size:12px;color:#45526a}
 table.items td{padding:7px 10px;border-bottom:1px solid #edf1f6;vertical-align:top}
 .st{font-weight:700;white-space:nowrap} .mono{font-family:Consolas,monospace;font-size:12px;word-break:break-all}
 .note{color:#6b7a90;font-size:12px} .foot{margin-top:24px;color:#9aa7b8;font-size:11px;border-top:1px solid #e2e8f1;padding-top:8px}
</style></head><body>
<h1>$(E ($script:LessonTitle))</h1>
<p class="sub">$($script:Lesson) · 作业检查与证据采集报告</p>
<div class="meta"><table>
 <tr><td class="k">计算机名</td><td class="mono">$host0</td><td class="k">生成时间</td><td class="mono">$now</td></tr>
 <tr><td class="k">操作系统</td><td class="mono">$(E ($osc))</td><td class="k">当前用户</td><td class="mono">$(E ((whoami)))</td></tr>
 <tr><td class="k">IPv4 地址</td><td class="mono" colspan="3">$(E ($ips))</td></tr>
</table></div>
<div class="summary">
 <span class="pill" style="background:$($badge.PASS)">$($icon.PASS) 达成 $nP</span>
 <span class="pill" style="background:$($badge.WARN)">$($icon.WARN) 需关注 $nW</span>
 <span class="pill" style="background:$($badge.FAIL)">$($icon.FAIL) 未完成/失败 $nF</span>
 <span class="pill" style="background:$($badge.INFO)">$($icon.INFO) 已采集 $nI</span>
</div>
"@)
  foreach($t in $script:Tasks){
    [void]$sb.Append("<h2>$(E ($t.Name))</h2><table class='items'><tr><th style='width:30px'></th><th>检查项</th><th>期望</th><th>实际采集值</th><th>说明</th></tr>")
    foreach($i in $t.Items){
      $c=$badge[$i.Status]; $ic=$icon[$i.Status]
      [void]$sb.Append("<tr><td class='st' style='color:$c'>$ic</td><td>$(E ($i.Name))</td><td class='mono'>$(E ($i.Expected))</td><td class='mono'>$(E ($i.Actual))</td><td class='note'>$(E ($i.Note))</td></tr>")
    }
    [void]$sb.Append("</table>")
  }
  [void]$sb.Append("<div class='foot'>本报告由课程检查脚本自动生成，用于作业提交。采集项反映脚本运行时刻该机的真实配置。</div></body></html>")
  $dir = "C:\LabFiles\Reports"; New-Item -ItemType Directory -Force $dir | Out-Null
  $base = "$dir\$($script:Lesson)_$($host0)_$stamp"
  $html = "$base.html"; $pdf = "$base.pdf"
  Set-Content $html $sb.ToString() -Encoding UTF8
  # 转 PDF（优先 Edge/Chrome headless；加 --no-pdf-header-footer，轮询等待文件生成，失败再回退）
  $browsers = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
  ) | ?{ Test-Path $_ }
  $pdfOk = $false
  $fileUrl = "file:///$($html -replace '\\','/')"
  foreach($b in $browsers){
    if($pdfOk){ break }
    Remove-Item $pdf -EA SilentlyContinue
    $prof = Join-Path $env:TEMP ("chk_pdf_" + [guid]::NewGuid().ToString("N"))
    # --no-pdf-header-footer 去掉页眉页脚；--user-data-dir 给个独立 profile，避开已运行实例/无 profile 的问题
    $args = @("--headless=new","--disable-gpu","--no-first-run","--no-pdf-header-footer","--user-data-dir=`"$prof`"","--print-to-pdf=`"$pdf`"","`"$fileUrl`"")
    try { Start-Process -FilePath $b -ArgumentList $args -Wait -WindowStyle Hidden -EA Stop } catch {}
    # 轮询最多 15 秒等 PDF 落盘
    for($w=0; $w -lt 15 -and -not $pdfOk; $w++){ Start-Sleep 1; if((Test-Path $pdf) -and ((Get-Item $pdf).Length -gt 1kb)){ $pdfOk = $true } }
    # 旧版 Edge 不认 --headless=new，再试一次 --headless
    if(-not $pdfOk){
      $args2 = @("--headless","--disable-gpu","--no-pdf-header-footer","--user-data-dir=`"$prof`"","--print-to-pdf=`"$pdf`"","`"$fileUrl`"")
      try { Start-Process -FilePath $b -ArgumentList $args2 -Wait -WindowStyle Hidden -EA Stop } catch {}
      for($w=0; $w -lt 15 -and -not $pdfOk; $w++){ Start-Sleep 1; if((Test-Path $pdf) -and ((Get-Item $pdf).Length -gt 1kb)){ $pdfOk = $true } }
    }
    Remove-Item $prof -Recurse -Force -EA SilentlyContinue
  }
  Write-Host ""
  Write-Host "========== 检查完成 =========="
  Write-Host ("达成 {0} / 需关注 {1} / 未完成 {2} / 已采集 {3}" -f $nP,$nW,$nF,$nI)
  Write-Host "HTML 报告: $html"
  if($pdfOk){ Write-Host "PDF  报告: $pdf  (提交此文件)" } else { Write-Host "PDF 生成失败，请用浏览器打开 HTML 后『打印→另存为 PDF』提交。" }
  Write-Host "=============================="
}
