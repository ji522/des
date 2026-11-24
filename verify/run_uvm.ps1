<#
run_uvm.ps1 —— DES UVM 验证平台一键运行（UVM 1.2 / Accellera，XSim 手工编译 UVM 库）
#>
param(
    [string]$Snap = "tb_des_uvm",
    [int[]]$Seeds = @(20261018, 20261019, 20261020)
)

$vbs  = 'D:\vivado2018.3\Vivado\2018.3\bin'
$proj = 'F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2'
$ver  = Join-Path $proj 'verify'
$sv   = Join-Path $ver  'sv'
$uvm  = Join-Path $ver  'uvm'
$usrc = Join-Path $ver  'uvm_lib\uvm-1.2-git\src'
$logd = Join-Path $ver  'logs'
$work = Join-Path $proj ("_sim_" + $Snap)
if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
if (-not (Test-Path -LiteralPath $logd)) { New-Item -ItemType Directory -Path $logd | Out-Null }
$logf = Join-Path $logd ($Snap + ".log")
Remove-Item -LiteralPath $logf -ErrorAction SilentlyContinue

Get-ChildItem -LiteralPath (Join-Path $ver 'vectors') -Filter '*.mem' |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $work -Force }

$out = New-Object System.Collections.Generic.List[string]
$failed = $false
Push-Location $work
try {
  # +define+DES_XSIM：XSim 2018.3 的 workaround 开关。
  # uvm_object::randomize() 在 XSim 上会崩内核，因此 des_uvm_pkg.sv 里用
  # `ifdef DES_XSIM 切换到手写的等价分布；VCS/Questa 不加这个宏，
  # 走标准 constraint-random。
  $r1 = & (Join-Path $vbs 'xvlog.bat') --nolog -sv -d UVM_NO_DPI -d DES_XSIM `
        -i $usrc -i $ver -i $sv -i $uvm `
        (Join-Path $usrc 'uvm_pkg.sv') `
        "$proj\des_pipe_round_fb.v" "$proj\des_pipeline_fb.v" "$proj\key_ram_gen.v" `
        "$proj\des_axis_wrap.v" `
        "$sv\des_if.sv" "$sv\axis_protocol_check.sv" "$uvm\des_uvm_pkg.sv" "$uvm\tb_des_uvm.sv" 2>&1
  $out.Add("=== xvlog -sv (uvm_pkg + des) ==="); $out.AddRange([string[]]$r1)
  if ($LASTEXITCODE -ne 0 -or (($r1 -join "`n") -match 'ERROR:')) {
    $out.Add("!! xvlog FAILED")
    $failed = $true
  }
  if (-not $failed) {
    $r2 = & (Join-Path $vbs 'xelab.bat') --nolog -timescale 1ns/1ps "work.tb_des_uvm" -s $Snap 2>&1
    $out.Add("=== xelab ==="); $out.AddRange([string[]]$r2)
    if ($LASTEXITCODE -ne 0 -or (($r2 -join "`n") -match 'ERROR:')) {
      $out.Add("!! xelab FAILED")
      $failed = $true
    }
  }
  if (-not $failed) {
    $passCount = 0
    foreach ($seed in $Seeds) {
      $r3 = & (Join-Path $vbs 'xsim.bat') --nolog $Snap -runall --sv_seed $seed 2>&1
      $simExit = $LASTEXITCODE
      $seedText = [string[]]$r3
      $seedLog = Join-Path $logd ("{0}_seed_{1}.log" -f $Snap, $seed)
      $seedText | Set-Content -LiteralPath $seedLog -Encoding utf8
      $out.Add(("=== xsim seed {0} ===" -f $seed))
      $out.AddRange($seedText)
      $joined = $seedText -join "`n"
      # 注意：判据只能用 ASCII 锚点。XSim 2018.3 输出日志时会把源码里的中文
      # 写成非法字节（如 "总覆盖率" 变成 U+93AC 系列），任何中文正则都匹配不上，
      # 会造成"实际 PASS 却判 FAIL"的假失败。这里锚 "covergroup" + "100.00%"。
      $seedPass = ($simExit -eq 0) -and
                  ($joined -match 'UVM ENV PASS') -and
                  ($joined -match 'push / cmp\s*:\s*58 / 58') -and
                  ($joined -match 'covergroup.*100\.00%') -and
                  ($joined -match 'UVM_ERROR\s*:\s*0') -and
                  ($joined -match 'UVM_FATAL\s*:\s*0')
      if ($seedPass) { $passCount++ }
      $out.Add(("SEED {0}: {1}" -f $seed, $(if ($seedPass) { 'PASS' } else { 'FAIL' })))
    }
    $allSeedsPass = ($passCount -eq $Seeds.Count)
    $out.Add(("=== UVM REGRESSION {0}: {1}/{2} seeds PASS ===" -f
              $(if ($allSeedsPass) { 'PASS' } else { 'FAIL' }), $passCount, $Seeds.Count))
    if (-not $allSeedsPass) { $failed = $true }
  }
}
finally { Pop-Location }

$out | Set-Content -LiteralPath $logf -Encoding utf8
$out | ForEach-Object { $_ }
Write-Output ""
Write-Output ("log -> " + $logf)
if ($failed) { exit 1 }
