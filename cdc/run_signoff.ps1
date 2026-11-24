<#
run_signoff.ps1 —— CDC 封装综合/实现 + CDC/时序签署（非工程批处理）
用法：powershell -NoProfile -ExecutionPolicy Bypass -File cdc\run_signoff.ps1
产物：cdc\_signoff\reports\{timing_summary, cdc_report, utilization}.rpt + dcp
注1：启动前清理 Git Bash / MSYS / Anaconda 的 PATH 与 Tcl 环境变量，
     否则 Vivado 内部 Tcl 会报 TclStackFree 崩溃（从 Git Bash 环境链启动时的已知冲突）。
注2：工程路径含中文，Vivado 2018.3 对非 ASCII 路径支持有缺陷（综合收尾阶段确定性
     崩溃），故用 subst 将工程映射为纯 ASCII 的 X: 盘后再运行。
#>
$vbs      = 'D:\vivado2018.3\Vivado\2018.3\bin'
$realProj = 'F:\DeskTop\IC项目\des_final_version\des_pipeline'
$out      = Join-Path $realProj 'cdc\_signoff'
if (-not (Test-Path -LiteralPath $out)) { New-Item -ItemType Directory -Path $out | Out-Null }
if (-not (Test-Path -LiteralPath (Join-Path $out 'reports'))) { New-Item -ItemType Directory -Path (Join-Path $out 'reports') | Out-Null }

# 清理会污染 Vivado 内部 Tcl 的 PATH 条目与环境变量
$env:PATH = ($env:PATH -split ';' |
    Where-Object { $_ -and ($_ -notmatch '(?i)msys|git|cygwin|anaconda|miniconda|python') }) -join ';'
foreach ($v in 'TCL_LIBRARY','TK_LIBRARY','PYTHONHOME','PYTHONPATH','PYTHONEXECUTABLE') {
    Remove-Item ("Env:" + $v) -ErrorAction SilentlyContinue
}

# 中文路径规避：映射 X: 盘指向工程根（ASCII 路径运行）
$madeSubst = $false
if (Test-Path 'X:\cdc') {
    Write-Output 'X: 已映射到工程根，直接使用'
} elseif (Test-Path 'X:\') {
    throw 'X: 已被其他卷/映射占用，请换盘符'
} else {
    subst 'X:' $realProj | Out-Null
    if (-not (Test-Path 'X:\cdc')) { throw 'subst 后仍无法访问 X:\cdc' }
    $madeSubst = $true
    Write-Output '已创建 X: 盘映射'
}

$proj = 'X:\'
Push-Location $proj
try {
    cmd /c 'call "D:\vivado2018.3\Vivado\2018.3\bin\vivado.bat" -mode batch -source cdc/cdc_signoff.tcl -log cdc/_signoff/vivado.log -journal cdc/_signoff/vivado.jour' | Out-Null
    Write-Output ("vivado exit code: " + $LASTEXITCODE)
}
finally { Pop-Location }

if (Test-Path (Join-Path $out 'reports\cdc_report.rpt')) {
    Write-Output 'reports ready'
} else {
    Write-Output 'reports MISSING - check cdc/_signoff/vivado.log'
}

if ($madeSubst) {
    Start-Sleep -Seconds 2
    subst 'X:' '/d' | Out-Null
    Write-Output 'X: 盘映射已移除'
}
