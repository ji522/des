<#
run_axis_cdc_uvm.ps1 —— 合并版顶层 des_axis_cdc_top 的 UVM 回归
  DUT : cdc/des_axis_cdc_top（慢域 AXIS slave + 快域 AXIL/AXIS master，双时钟 CDC）
  ENV : verify/uvm/axis_cdc/axis_cdc_pkg.sv（慢域数据 agent + 快域 AXIL agent
        + 反压驱动 + 计分板 + 覆盖率 + virtual sequencer）
  向量: verify/vectors/*.mem（28 加密 + 14 解密 = 42 笔）

编译顺序：uvm_pkg -> RTL -> axil_if -> axis_cdc_if -> des_axil_pkg -> axis_cdc_pkg -> TB
用法：pwsh -NoProfile -ExecutionPolicy Bypass -File verify\run_axis_cdc_uvm.ps1
#>
param(
  [string]$TbTop = "tb_des_axis_cdc_uvm",
  [string]$TestName = "axis_cdc_test"
)

$vbs  = 'D:\vivado2018.3\Vivado\2018.3\bin'
$proj = 'F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2'
$ver  = Join-Path $proj 'verify'
$sv   = Join-Path $ver  'sv'
$uvm  = Join-Path $ver  'uvm'
$acdc = Join-Path $uvm  'axis_cdc'
$cdc  = Join-Path $proj 'cdc'
$usrc = Join-Path $ver  'uvm_lib\uvm-1.2-git\src'
$logd = Join-Path $ver  'logs'
$work = Join-Path $proj ("_sim_" + $TbTop)

if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
if (-not (Test-Path -LiteralPath $logd)) { New-Item -ItemType Directory -Path $logd | Out-Null }
$logf = Join-Path $logd ($TbTop + ".log")
Remove-Item -LiteralPath $logf -ErrorAction SilentlyContinue

# 向量必须在 work 目录（$readmemh 用相对路径）
Get-ChildItem -LiteralPath (Join-Path $ver 'vectors') -Filter '*.mem' |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $work -Force }

$out = New-Object System.Collections.Generic.List[string]
$failed = $false
Push-Location $work
try {
  # +define+DES_XSIM：XSim randomize() workaround（本包本来就不 randomize，
  # 保留该宏是为了与项目其它 UVM 回归口径一致）
  $r1 = & (Join-Path $vbs 'xvlog.bat') --nolog -sv -d UVM_NO_DPI -d DES_XSIM `
        -i $usrc -i $ver -i $sv -i $uvm -i $acdc -i $proj -i $cdc `
        (Join-Path $usrc 'uvm_pkg.sv') `
        "$proj\des_pipe_round_fb.v" "$proj\des_pipeline_fb.v" "$proj\key_ram_gen.v" `
        "$proj\des_axis_wrap.v" "$proj\des_axil_regs.v" `
        "$cdc\async_fifo.v" "$cdc\cdc_sync.v" "$cdc\des_axis_cdc_top.v" `
        "$sv\axil_if.sv" `
        "$acdc\axis_cdc_if.sv" `
        "$uvm\des_axil_agent_pkg.sv" `
        "$acdc\axis_cdc_pkg.sv" `
        "$acdc\$TbTop.sv" 2>&1
  $out.Add("=== xvlog -sv ==="); $out.AddRange([string[]]$r1)
  if ($LASTEXITCODE -ne 0 -or (($r1 -join "`n") -match 'ERROR:')) {
    $out.Add("!! xvlog FAILED"); $failed = $true
  }

  if (-not $failed) {
    $r2 = & (Join-Path $vbs 'xelab.bat') --nolog -timescale 1ns/1ps "work.$TbTop" -s $TbTop 2>&1
    $out.Add("=== xelab ==="); $out.AddRange([string[]]$r2)
    if ($LASTEXITCODE -ne 0 -or (($r2 -join "`n") -match 'ERROR:')) {
      $out.Add("!! xelab FAILED"); $failed = $true
    }
  }

  if (-not $failed) {
    # test 名在 TB 里用 run_test() 直接指定，不走 plusarg（XSim 2018.3 限制）
    $r3 = & (Join-Path $vbs 'xsim.bat') --nolog $TbTop -runall 2>&1
    $simExit = $LASTEXITCODE
    $out.Add("=== xsim ($TestName) ==="); $out.AddRange([string[]]$r3)
    $joined = ([string[]]$r3) -join "`n"

    # 判定锚点只用 ASCII：XSim 2018.3 日志里的中文可能变成非法字节
    $patterns = @(
      'AXIS CDC UVM PASS',
      'beats pushed/cmp\s*:\s*42 / 42',
      'data errors\s*:\s*0',
      'TLAST errors\s*:\s*0',
      'X/Z\s*:\s*0',
      'extra outputs\s*:\s*0',
      'stalls\s*:\s*[1-9][0-9]*',
      'coverage\s*:\s*[0-9]+\.[0-9]+%',
      'UVM_ERROR\s*:\s*0',
      'UVM_FATAL\s*:\s*0'
    )
    $miss = @($patterns | Where-Object { $joined -notmatch $_ })
    if (($simExit -ne 0) -or ($miss.Count -ne 0)) {
      $out.Add("!! SIM CHECK FAILED (exit=$simExit, missing=$($miss -join '; '))")
      $failed = $true
    } else {
      $out.Add("SIM CHECK: PASS")
    }
  }
}
finally { Pop-Location }

$out | Set-Content -LiteralPath $logf -Encoding utf8
$out | ForEach-Object { $_ }
Write-Output ""
Write-Output ("log -> " + $logf)
if ($failed) {
  Write-Output "AXIS-CDC UVM RUN: FAIL"
  exit 1
} else {
  Write-Output "AXIS-CDC UVM RUN: PASS"
  exit 0
}
