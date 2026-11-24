<#
run_axil.ps1 -- DES AXI4-Lite 寄存器块回归
#>
param(
  [string]$TbTop = "tb_des_axil",
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

$out = New-Object System.Collections.Generic.List[string]
Push-Location $work
try {
  $r1 = & (Join-Path $vbs 'xvlog.bat') --nolog -sv -i $ver `
        "$proj\des_axil_regs.v" `
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
