<#
run_cdc_randclk.ps1 —— CDC 随机时钟比/相位回归（只读 RTL/TB/向量）

编译一次 tb_des_cdc_randclk，然后按 10 组 (W_HALF,C_HALF,W_PHASE,C_PHASE)
分别以 plusargs 启动 xsim，每组独立日志 + 超时保护，最后打印汇总表。

用法：
  pwsh -NoProfile -ExecutionPolicy Bypass -File run_cdc_randclk.ps1
  pwsh ... -File run_cdc_randclk.ps1 -TimeoutSec 300
#>
param(
    [int]$TimeoutSec = 300,
    [string]$Snap = "tb_des_cdc_randclk"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$vbs  = 'D:\vivado2018.3\Vivado\2018.3\bin'
$proj = 'F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2'
$cdc  = Join-Path $proj 'cdc'
$tbd  = Join-Path $proj 'verify\tb_cdc'
$logd = Join-Path $proj 'verify\logs\cdc_randclk'
$work = Join-Path $proj ('verify\_sim_' + $Snap)

if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
if (-not (Test-Path -LiteralPath $logd)) { New-Item -ItemType Directory -Path $logd | Out-Null }

# 与现有 run_cdc.ps1 一致：向量拷进工作目录，$readmemh 用相对名
Get-ChildItem -LiteralPath (Join-Path $proj 'verify\vectors') -Filter '*.mem' |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $work -Force }

# (w_half, c_half, w_phase, c_phase)
$configs = @(
    @(5, 2, 0, 0),
    @(5, 2, 1, 3),
    @(5, 2, 3, 1),
    @(5, 3, 0, 2),
    @(4, 2, 1, 0),
    @(3, 2, 2, 1),
    @(6, 2, 3, 0),
    @(5, 1, 0, 1),
    @(7, 2, 2, 3),
    @(5, 4, 1, 2)
)

# ---------------- 编译一次 ----------------
$compileLog = Join-Path $logd '_compile.log'
$cout = New-Object System.Collections.Generic.List[string]
Push-Location $work
try {
    $r1 = & (Join-Path $vbs 'xvlog.bat') --nolog -sv -i $proj -i $cdc `
          "$proj\des_pipeline_fb.v" "$proj\key_ram_gen.v" "$proj\des_pipe_round_fb.v" `
          "$cdc\async_fifo.v" "$cdc\cdc_sync.v" "$cdc\des_cdc_top.v" `
          "$tbd\tb_des_cdc_randclk.v" 2>&1
    $cout.Add('=== xvlog -sv ==='); $cout.AddRange([string[]]$r1)
    if ($LASTEXITCODE -ne 0 -or (($r1 -join "`n") -match 'ERROR:')) {
        $cout.Add('!! xvlog FAILED'); $cout | Set-Content -LiteralPath $compileLog -Encoding utf8
        Write-Host '!! xvlog FAILED (see ' $compileLog ')'
        return
    }

    $r2 = & (Join-Path $vbs 'xelab.bat') --nolog "work.tb_des_cdc_randclk" -s $Snap 2>&1
    $cout.Add('=== xelab ==='); $cout.AddRange([string[]]$r2)
    if ($LASTEXITCODE -ne 0 -or (($r2 -join "`n") -match 'ERROR:')) {
        $cout.Add('!! xelab FAILED'); $cout | Set-Content -LiteralPath $compileLog -Encoding utf8
        Write-Host '!! xelab FAILED (see ' $compileLog ')'
        return
    }
} finally {
    Pop-Location
}
$cout.Add('=== compile OK ===')
$cout | Set-Content -LiteralPath $compileLog -Encoding utf8
Write-Host ("compile OK  -> " + $compileLog)

# ---------------- 逐组运行 ----------------
$results = @()
foreach ($cfg in $configs) {
    $w = $cfg[0]; $c = $cfg[1]; $wp = $cfg[2]; $cp = $cfg[3]
    $name = ("w{0}_c{1}_wp{2}_cp{3}" -f $w, $c, $wp, $cp)
    $log  = Join-Path $logd ($name + '.log')
    $errl = Join-Path $logd ($name + '.err.log')
    if (Test-Path -LiteralPath $errl) { Remove-Item -LiteralPath $errl -Force }

    # 注意：xsim 的参数解析会把未加引号的 a=b 拆成两个词（"Expected a switch but found b"），
    # 所以整行必须手工拼成带双引号的字符串，Start-Process 原样传给 xsim.bat。
    $argLine = "$Snap -R " +
        "-testplusarg `"W_HALF=$w`" -testplusarg `"C_HALF=$c`" " +
        "-testplusarg `"W_PHASE=$wp`" -testplusarg `"C_PHASE=$cp`""

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath (Join-Path $vbs 'xsim.bat') -ArgumentList $argLine `
         -WorkingDirectory $work -NoNewWindow -PassThru `
         -RedirectStandardOutput $log -RedirectStandardError $errl
    $ok = $p.WaitForExit($TimeoutSec * 1000)
    $timedOut = $false
    if (-not $ok) {
        $timedOut = $true
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
        Start-Sleep -Milliseconds 800
    } else {
        $p.WaitForExit()   # 确保重定向缓冲全部刷出
    }
    $sw.Stop()
    $ec = if ($timedOut) { -1 } else { $p.ExitCode }

    $text = ''
    if (Test-Path -LiteralPath $log)  { $text += (Get-Content -LiteralPath $log -Raw) }
    if (Test-Path -LiteralPath $errl) {
        $et = Get-Content -LiteralPath $errl -Raw
        if ($et) { $text += "`n--- stderr ---`n" + $et }
    }

    $m = [regex]::Match($text,
        'RANDCLK\s+(PASS|FAIL)\s+push=(\d+)/cmp=(\d+)/mismatch=(\d+)/x=(\d+)/extra=(\d+)\s+wfull=(\d+)')
    if ($timedOut) {
        $status = 'TIMEOUT'
        $push = 0; $cmpv = 0; $mm = 0; $xx = 0; $ex = 0; $wf = 0
    } elseif ($m.Success) {
        $status = $m.Groups[1].Value
        $push = [int]$m.Groups[2].Value
        $cmpv = [int]$m.Groups[3].Value
        $mm   = [int]$m.Groups[4].Value
        $xx   = [int]$m.Groups[5].Value
        $ex   = [int]$m.Groups[6].Value
        $wf   = [int]$m.Groups[7].Value
    } else {
        $status = if ($ec -ne 0) { "ERROR(exit=$ec)" } else { 'NO-RESULT' }
        $push = 0; $cmpv = 0; $mm = 0; $xx = 0; $ex = 0; $wf = 0
    }

    $results += [pscustomobject]@{
        Name = $name; W = $w; C = $c; WP = $wp; CP = $cp
        Status = $status; Push = $push; Cmp = $cmpv
        Mismatch = $mm; X = $xx; Extra = $ex; WFull = $wf
        Sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Log = $log
    }
    Write-Host ("[RUN] {0,-22} {1,-10} push={2} cmp={3} mismatch={4} x={5} extra={6} wfull={7} ({8}s)" -f `
        $name, $status, $push, $cmpv, $mm, $xx, $ex, $wf, [math]::Round($sw.Elapsed.TotalSeconds, 1))
}

# ---------------- 汇总 ----------------
$passN = ($results | Where-Object { $_.Status -eq 'PASS' }).Count
Write-Host ''
Write-Host '================= CDC RANDCLK SUMMARY ================='
Write-Host ('{0,-22} {1,-10} {2,-8} {3,-8} {4,-9} {5,-5} {6,-6} {7,-7}' -f `
    'config','result','push','cmp','mismatch','x','extra','wfull')
foreach ($r in $results) {
    Write-Host ('{0,-22} {1,-10} {2,-8} {3,-8} {4,-9} {5,-5} {6,-6} {7,-7}' -f `
        $r.Name, $r.Status, $r.Push, $r.Cmp, $r.Mismatch, $r.X, $r.Extra, $r.WFull)
}
Write-Host ('TOTAL: {0}/{1} PASS' -f $passN, $results.Count)
Write-Host ('logs : ' + $logd)
Write-Host '======================================================='

$results | Export-Csv -LiteralPath (Join-Path $logd '_summary.csv') -NoTypeInformation -Encoding utf8
