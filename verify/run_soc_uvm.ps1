<#
run_soc_uvm.ps1 -- 双 agent（数据面 + 控制面）UVM 回归
编译顺序：uvm_pkg -> des_uvm_pkg -> axil agent -> RAL -> adapter -> env -> test
#>
param(
  [string]$TbTop = "tb_des_soc_uvm",
  [string]$TestName = "des_soc_reg_test"
)

$vbs  = 'D:\vivado2018.3\Vivado\2018.3\bin'
$proj = 'F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2'
$ver  = Join-Path $proj 'verify'
$sv   = Join-Path $ver  'sv'
$uvm  = Join-Path $ver  'uvm'
$usrc = Join-Path $ver  'uvm_lib\uvm-1.2-git\src'
$logd = Join-Path $ver  'logs'
$work = Join-Path $proj ("_sim_" + $TbTop)
if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
if (-not (Test-Path -LiteralPath $logd)) { New-Item -ItemType Directory -Path $logd | Out-Null }
$logf = Join-Path $logd ($TbTop + ".log")

Get-ChildItem -LiteralPath (Join-Path $ver 'vectors') -Filter '*.mem' |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $work -Force }

$out = New-Object System.Collections.Generic.List[string]
Push-Location $work
try {
  # +define+DES_XSIM：XSim randomize() workaround（见 des_uvm_pkg.sv 头注释）
  $r1 = & (Join-Path $vbs 'xvlog.bat') --nolog -sv -d UVM_NO_DPI -d DES_XSIM `
        -i $usrc -i $ver -i $sv -i $uvm `
        (Join-Path $usrc 'uvm_pkg.sv') `
        "$proj\des_pipe_round_fb.v" "$proj\des_pipeline_fb.v" "$proj\key_ram_gen.v" `
        "$proj\des_axis_wrap.v" "$proj\des_axil_regs.v" "$proj\des_soc_top.v" `
        "$sv\des_if.sv" "$sv\axil_if.sv" "$sv\axis_protocol_check.sv" `
        "$uvm\des_uvm_pkg.sv" `
        "$uvm\des_axil_agent_pkg.sv" `
        "$uvm\des_ral_frontdoor.sv" `
        "$uvm\des_ral_pkg.sv" `
        "$uvm\des_ral_adapter.sv" `
        "$uvm\des_soc_env_pkg.sv" `
        "$uvm\des_soc_test_pkg.sv" `
        "$uvm\$TbTop.sv" 2>&1
  $out.Add("=== xvlog -sv ==="); $out.AddRange([string[]]$r1)
  if ($LASTEXITCODE -ne 0 -or (($r1 -join "`n") -match 'ERROR:')) {
    $out.Add("!! xvlog FAILED"); $out | Set-Content -LiteralPath $logf -Encoding utf8
    $out | ForEach-Object { $_ }; return
  }
  $r2 = & (Join-Path $vbs 'xelab.bat') --nolog -timescale 1ns/1ps "work.$TbTop" -s $TbTop 2>&1
  $out.Add("=== xelab ==="); $out.AddRange([string[]]$r2)
  if ($LASTEXITCODE -ne 0 -or (($r2 -join "`n") -match 'ERROR:')) {
    $out.Add("!! xelab FAILED"); $out | Set-Content -LiteralPath $logf -Encoding utf8
    $out | ForEach-Object { $_ }; return
  }
  # test 名在 tb_des_soc_uvm.sv 里用 run_test() 直接指定，
  # 不走 plusarg——XSim 2018.3 的 --testplusarg 对 "NAME=VALUE" 形式会误判。
  $r3 = & (Join-Path $vbs 'xsim.bat') --nolog $TbTop -runall 2>&1
  $out.Add("=== xsim ($TestName) ==="); $out.AddRange([string[]]$r3)
}
finally { Pop-Location }

$out | Set-Content -LiteralPath $logf -Encoding utf8
$out | ForEach-Object { $_ }
Write-Output ""
Write-Output ("log -> " + $logf)
