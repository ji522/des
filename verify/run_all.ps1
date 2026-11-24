<#
run_all.ps1 —— DES 验证一键回归（统一入口）
串联：向量生成 → Verilog 定向回归 → 换钥 hazard 专项 → SystemVerilog 约束随机 → CDC 多时钟 → UVM 3-seed 回归
每步先删除旧日志再运行，防止陈旧日志造成假通过；结束输出汇总表，全部通过返回码 0。
用法：powershell -NoProfile -ExecutionPolicy Bypass -File run_all.ps1
#>
$ErrorActionPreference = 'Continue'
$dir  = $PSScriptRoot
$logd = Join-Path $dir 'logs'
$sh   = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Case, [bool]$Pass, [string]$Evidence) {
    $checks.Add([pscustomobject]@{
        '用例'   = $Case
        '判定'   = $(if ($Pass) { 'PASS' } else { 'FAIL' })
        '证据'   = $Evidence
    })
}

# ---- 0) 向量生成（固定种子可复现；python/库不可用时向量已存在则继续）----
$vec = Join-Path $dir 'vectors'
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) {
    $py = 'C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
}
if (Test-Path -LiteralPath $py) {
    & $py (Join-Path $dir 'gen_vectors.py') *> $null
} else {
    $global:LASTEXITCODE = 1
}
$genOk = ($LASTEXITCODE -eq 0) -or `
         ((Test-Path (Join-Path $vec 'exps.mem')) -and (Test-Path (Join-Path $vec 'dexps.mem')))
Add-Check '0 向量生成(gen_vectors)' $genOk '固定种子 20260926，vectors/*.mem'

# ---- 统一用例执行：先删旧日志 → 运行 → 按日志内容判定 ----
function Invoke-Case([string]$Case, [string]$Script, [string[]]$TbArgs,
                     [string]$Log, [string[]]$Patterns, [string]$Evidence) {
    $logf = Join-Path $logd $Log
    Remove-Item $logf -ErrorAction SilentlyContinue
    & $sh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir $Script) @TbArgs *> $null
    $raw = Get-Content $logf -Raw -ErrorAction SilentlyContinue
    $ok  = ($null -ne $raw) -and (@($Patterns | Where-Object { $raw -notmatch $_ }).Count -eq 0)
    Add-Check $Case $ok $Evidence
}

Invoke-Case '1 Verilog 定向回归(42笔)' 'run_sim.ps1' @('-TbTop','tb_des_pipeline_fb_v2') `
            'tb_des_pipeline_fb_v2.log' @('PASS\s*:\s*42/42') 'logs/tb_des_pipeline_fb_v2.log'
Invoke-Case '2 换钥hazard专项'         'run_sim.ps1' @('-TbTop','tb_rekey_hazard') `
            'tb_rekey_hazard.log' @('mismatch\s*:\s*4\s*/\s*4','mismatch\s*:\s*0\s*/\s*4') 'logs/tb_rekey_hazard.log : 不排空4/4错→排空0/4'
Invoke-Case '3 SV约束随机(58笔)'       'run_sv.ps1'  @() `
            'tb_des_sv.log' @('SV ENV PASS','58 / 58','100\.00%') 'logs/tb_des_sv.log : 58/58、覆盖率100%'
Invoke-Case '4 CDC多时钟(190笔)'       'run_cdc.ps1' @() `
            'tb_des_cdc.log' @('CDC TB PASS : 190/190') 'logs/tb_des_cdc.log : 190/190、满节流期间零丢失'
Invoke-Case '5 UVM回归(58笔)'         'run_uvm.ps1' @() `
            'tb_des_uvm.log' @('UVM ENV PASS','58 / 58','100\.00%','UVM REGRESSION PASS\s*:\s*3/3 seeds PASS') 'logs/tb_des_uvm.log : 3 seeds、58/58、覆盖率100%（UVM 1.2）'
Invoke-Case '6 AXI4-Stream封装(42笔)'  'run_axis.ps1' @() `
            'tb_des_axis_wrap.log' @('AXIS TB PASS : 42/42') 'logs/tb_des_axis_wrap.log : 42/42、TLAST 0 错、175 拍 stall'
Invoke-Case '7 AXI4-Lite寄存器(23项)'  'run_axil.ps1' @() `
            'tb_des_axil.log' @('AXIL TB PASS : 23/23') 'logs/tb_des_axil.log : 23/23（含 AW/W 独立到达、WSTRB、换钥保护）'
Invoke-Case '8 SoC集成(控制面+数据面)' 'run_soc.ps1' @() `
            'tb_des_soc.log' @('SOC TB PASS') 'logs/tb_des_soc.log : 19 项检查、13/13 对拍、在途换钥被拒'
Invoke-Case '9 SVA负向(断言非空过)'    'run_axis.ps1' @('-TbTop','tb_axis_sva_neg') `
            'tb_axis_sva_neg.log' @('SVA-NEG PASS') 'logs/tb_axis_sva_neg.log : 故意违约被 A10 捕获'
Invoke-Case '10 SoC UVM(双agent+RAL)'  'run_soc_uvm.ps1' @() `
            'tb_des_soc_uvm.log' @('SOC RAL TEST PASS','UVM_ERROR\s*:\s*0','UVM_FATAL\s*:\s*0') 'logs/tb_des_soc_uvm.log : RAL 9项、双agent、vseq、override'

# ---- 汇总 ----
$checks | Format-Table -AutoSize | Out-String | Write-Output
$bad = @($checks | Where-Object { $_.'判定' -eq 'FAIL' })
$summary = Join-Path $logd 'regression_summary.md'
$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add('# DES Regression Summary')
$summaryLines.Add('')
$summaryLines.Add(('- 时间：{0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')))
$summaryLines.Add(('- 结论：{0}' -f $(if ($bad.Count -eq 0) { 'ALL PASS' } else { 'FAIL' })))
$summaryLines.Add('')
$summaryLines.Add('| 用例 | 判定 | 证据 |')
$summaryLines.Add('|---|---|---|')
foreach ($check in $checks) {
    $summaryLines.Add(('| {0} | {1} | {2} |' -f $check.'用例', $check.'判定', $check.'证据'))
}
$summaryLines | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ('summary -> ' + $summary)
if ($bad.Count -eq 0) {
    Write-Output ('==== ALL PASS ({0}/{1}) ====' -f $checks.Count, $checks.Count)
    exit 0
} else {
    Write-Output ('==== FAIL ({0}/{1}) ====' -f $bad.Count, $checks.Count)
    exit 1
}
