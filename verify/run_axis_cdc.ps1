<#
run_axis_cdc.ps1 —— AXI4-Stream 封装 + 跨时钟域 合并顶层一键仿真
用法：pwsh -NoProfile -ExecutionPolicy Bypass -File run_axis_cdc.ps1
#>
param([string]$Snap = "tb_des_axis_cdc")

$vbs  = 'D:\vivado2018.3\Vivado\2018.3\bin'
$proj = 'F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2'
$cdc  = Join-Path $proj 'cdc'
$tbd  = Join-Path $proj 'verify\tb_cdc'
$logd = Join-Path $proj 'verify\logs'
$work = Join-Path $proj ("verify\_sim_" + $Snap)
if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
if (-not (Test-Path -LiteralPath $logd)) { New-Item -ItemType Directory -Path $logd | Out-Null }
$logf = Join-Path $logd ($Snap + ".log")

Get-ChildItem -LiteralPath (Join-Path $proj 'verify\vectors') -Filter '*.mem' |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $work -Force }

$out = New-Object System.Collections.Generic.List[string]
Push-Location $work
try {
  $r1 = & (Join-Path $vbs 'xvlog.bat') --nolog -sv -i $proj -i $cdc `
        "$proj\des_pipe_round_fb.v" "$proj\des_pipeline_fb.v" "$proj\key_ram_gen.v" `
        "$proj\des_axis_wrap.v" "$proj\des_axil_regs.v" `
        "$cdc\async_fifo.v" "$cdc\cdc_sync.v" "$cdc\des_axis_cdc_top.v" `
        "$tbd\tb_des_axis_cdc.v" 2>&1
  $out.Add("=== xvlog -sv ==="); $out.AddRange([string[]]$r1)
  if ($LASTEXITCODE -ne 0 -or (($r1 -join "`n") -match 'ERROR:')) {
    $out.Add("!! xvlog FAILED"); $out | Set-Content -LiteralPath $logf -Encoding utf8
    $out | ForEach-Object { $_ }; return
  }

  $r2 = & (Join-Path $vbs 'xelab.bat') --nolog "work.$Snap" -s $Snap 2>&1
  $out.Add("=== xelab ==="); $out.AddRange([string[]]$r2)
  if ($LASTEXITCODE -ne 0 -or (($r2 -join "`n") -match 'ERROR:')) {
    $out.Add("!! xelab FAILED"); $out | Set-Content -LiteralPath $logf -Encoding utf8
    $out | ForEach-Object { $_ }; return
  }

  $r3 = & (Join-Path $vbs 'xsim.bat') $Snap -R 2>&1
  $out.Add("=== xsim ==="); $out.AddRange([string[]]$r3)
  $out | Set-Content -LiteralPath $logf -Encoding utf8
  $out | Select-Object -Last 30 | ForEach-Object { $_ }
}
finally { Pop-Location }
