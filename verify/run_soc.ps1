<#
run_soc.ps1 -- DES 控制面（AXI4-Lite）+ 数据面（AXI4-Stream）集成回归
#>
param(
  [string]$TbTop = "tb_des_soc",
  [string]$Snap  = ""
)
if ([string]::IsNullOrWhiteSpace($Snap)) { $Snap = $TbTop }

$vbs  = 'D:\vivado2018.3\Vivado\2018.3\bin'
$proj = 'F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2'
$ver  = Join-Path $proj 'verify'
$logd = Join-Path $ver  'logs'
$work = Join-Path $proj ("_sim_" + $Snap)
if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
if (-not (Test-Path -LiteralPath $logd)) { New-Item -ItemType Directory -Path $logd | Out-Null }
$logf = Join-Path $logd ($Snap + ".log")

Get-ChildItem -LiteralPath (Join-Path $ver 'vectors') -Filter '*.mem' |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $work -Force }

$out = New-Object System.Collections.Generic.List[string]
Push-Location $work
try {
  $r1 = & (Join-Path $vbs 'xvlog.bat') --nolog -sv -i $ver -i (Join-Path $ver 'sv') `
        "$proj\des_pipe_round_fb.v" "$proj\des_pipeline_fb.v" `
        "$proj\key_ram_gen.v" "$proj\des_axis_wrap.v" `
        "$proj\des_axil_regs.v" "$proj\des_soc_top.v" `
        "$ver\sv\axis_protocol_check.sv" `
        "$ver\$TbTop.v" 2>&1
  $out.Add("=== xvlog ==="); $out.AddRange([string[]]$r1)
  if ($LASTEXITCODE -ne 0 -or (($r1 -join "`n") -match 'ERROR:')) {
    $out.Add("!! xvlog FAILED"); $out | Set-Content -LiteralPath $logf -Encoding utf8
    $out | ForEach-Object { $_ }; return
  }
  $r2 = & (Join-Path $vbs 'xelab.bat') --nolog "work.$TbTop" -s $Snap 2>&1
  $out.Add("=== xelab ==="); $out.AddRange([string[]]$r2)
  if ($LASTEXITCODE -ne 0 -or (($r2 -join "`n") -match 'ERROR:')) {
    $out.Add("!! xelab FAILED"); $out | Set-Content -LiteralPath $logf -Encoding utf8
    $out | ForEach-Object { $_ }; return
  }
  $r3 = & (Join-Path $vbs 'xsim.bat') --nolog $Snap -runall 2>&1
  $out.Add("=== xsim ==="); $out.AddRange([string[]]$r3)
}
finally { Pop-Location }

$out | Set-Content -LiteralPath $logf -Encoding utf8
$out | ForEach-Object { $_ }
Write-Output ""
Write-Output ("log -> " + $logf)
