<#
run_boundary.ps1 —— 只跑 DES 等价类/边界值定向回归 TB
用法:
  pwsh -NoProfile -ExecutionPolicy Bypass -File verify\run_boundary.ps1

依赖:
  verify/vectors_bnd/{bkeys,bins,bexps}.mem 已由 gen_boundary_vectors.py 生成
  （本脚本只跑 TB，不生成向量；缺文件会直接报错退出）

输出:
  verify/logs/tb_des_boundary.log
  仿真工作目录: _sim_tb_des_boundary（新建，不碰现有 _sim_*）
#>
$ErrorActionPreference = 'Stop'

$vbs  = 'D:\vivado2018.3\Vivado\2018.3\bin'
$proj = 'F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2'
$ver  = Join-Path $proj 'verify'
$vec  = Join-Path $ver  'vectors_bnd'
$logd = Join-Path $ver  'logs'
$work = Join-Path $proj '_sim_tb_des_boundary'
$logf = Join-Path $logd 'tb_des_boundary.log'

if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
if (-not (Test-Path -LiteralPath $logd)) { New-Item -ItemType Directory -Path $logd | Out-Null }

# 向量 .mem 拷到仿真工作目录（xsim 用相对路径读取）
foreach ($f in @('bkeys.mem', 'bins.mem', 'bexps.mem')) {
    $src = Join-Path $vec $f
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Output ("ERROR: missing vector file " + $src)
        Write-Output "       run: python verify\gen_boundary_vectors.py"
        exit 2
    }
    Copy-Item -LiteralPath $src -Destination $work -Force
}

$out = New-Object System.Collections.Generic.List[string]
Push-Location $work
try {
    $r1 = & (Join-Path $vbs 'xvlog.bat') --nolog -i $ver -i $proj `
            "$proj\des_pipe_round_fb.v" "$proj\des_pipeline_fb.v" `
            "$proj\key_ram_gen.v" "$ver\tb_des_boundary.v" 2>&1
    $out.Add("=== xvlog ==="); $out.AddRange([string[]]$r1)
    if ($LASTEXITCODE -ne 0 -or (($r1 -join "`n") -match 'ERROR:')) {
        $out.Add("!! xvlog FAILED")
        $out | Set-Content -LiteralPath $logf -Encoding utf8
        $out | ForEach-Object { $_ }
        exit 1
    }

    $r2 = & (Join-Path $vbs 'xelab.bat') --nolog "work.tb_des_boundary" -s tb_des_boundary 2>&1
    $out.Add("=== xelab ==="); $out.AddRange([string[]]$r2)
    if ($LASTEXITCODE -ne 0 -or (($r2 -join "`n") -match 'ERROR:')) {
        $out.Add("!! xelab FAILED")
        $out | Set-Content -LiteralPath $logf -Encoding utf8
        $out | ForEach-Object { $_ }
        exit 1
    }

    $r3 = & (Join-Path $vbs 'xsim.bat') --nolog tb_des_boundary -runall 2>&1
    $out.Add("=== xsim ==="); $out.AddRange([string[]]$r3)
}
finally {
    Pop-Location
}

$out | Set-Content -LiteralPath $logf -Encoding utf8
$out | ForEach-Object { $_ }
Write-Output ""
Write-Output ("log -> " + $logf)

$all = $out -join "`n"
if ($all -match 'BOUNDARY TB PASS\s*:\s*(\d+)/(\d+)') {
    Write-Output ("RESULT: PASS " + $Matches[1] + "/" + $Matches[2])
    exit 0
} else {
    Write-Output "RESULT: FAIL"
    exit 1
}
