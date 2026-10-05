<#
  通过「轻量部署平台」的 REST API 运行【任务】（不是项目）。

  平台上的分工：
    项目（Project）= 构建与部署，可以有 Git 准备阶段与依赖构建；
    任务（Task）   = 执行某一个作业（压测、巡检……），没有 Git、没有依赖。

  本脚本做三件事：登录 → 按 scripts/task.json 创建或更新任务 → 触发一次并跟踪日志。
  步骤脚本放在 scripts/tasks/ 下，用 "file" 字段引用。

  用法：
    powershell -ExecutionPolicy Bypass -File scripts/task.ps1
    powershell -ExecutionPolicy Bypass -File scripts/task.ps1 -SkipRun    # 只同步任务定义
    powershell -ExecutionPolicy Bypass -File scripts/task.ps1 -LogRunId 12
#>
param(
  [string]$Base = "http://192.168.31.97:10055/api/v1",
  [string]$User = "admin",
  [string]$Pass = $env:DEPLOY_PASSWORD,
  [string]$Definition = "$PSScriptRoot/task.json",
  [switch]$SkipRun,
  [int]$LogRunId = 0,
  [int]$WaitSeconds = 3600
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Api {
  param([string]$Method, [string]$Url, [hashtable]$Headers = @{}, $Body = $null)
  $params = @{ Uri = $Url; Method = $Method; Headers = $Headers; UseBasicParsing = $true; TimeoutSec = 180 }
  if ($null -ne $Body) {
    $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 12 -Compress }
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
    $params.ContentType = "application/json; charset=utf-8"
  }
  $resp = Invoke-WebRequest @params
  $parsed = $null
  if ($resp.Content) { $parsed = $resp.Content | ConvertFrom-Json }
  if ($resp.StatusCode -ge 400 -or ($parsed -and $parsed.success -eq $false)) {
    $code = if ($parsed) { $parsed.errorCode } else { $resp.StatusCode }
    $msg = if ($parsed) { $parsed.errorMessage } else { "$($resp.StatusCode)" }
    throw "[$Method $Url] HTTP $($resp.StatusCode) errorCode=$code : $msg"
  }
  if ($parsed) { return $parsed.data }
  return $null
}

function Get-LogText($raw) {
  if ($null -eq $raw) { return "" }
  if ($raw -is [string]) { return $raw }
  foreach ($p in @("data", "log", "text", "content")) {
    if ($raw.PSObject.Properties.Name -contains $p -and $raw.$p) { return [string]$raw.$p }
  }
  return ($raw | ConvertTo-Json -Depth 6)
}

# 把脚本文件内联进 JSON。刻意在文本层做替换，理由见 scripts/deploy.ps1 的同名函数。
function ConvertTo-JsonString([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    if ($ch -eq '"') { [void]$sb.Append('\"') }
    elseif ($ch -eq '\') { [void]$sb.Append('\\') }
    elseif ($ch -eq "`n") { [void]$sb.Append('\n') }
    elseif ($ch -eq "`r") { [void]$sb.Append('\r') }
    elseif ($ch -eq "`t") { [void]$sb.Append('\t') }
    elseif ([int]$ch -lt 32) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) }
    else { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}

function Expand-StepScripts($path) {
  $raw = Get-Content $path -Raw -Encoding UTF8
  $dir = Join-Path $PSScriptRoot 'tasks'
  foreach ($f in (Get-ChildItem $dir -Filter *.sh -File)) {
    $needle = '"file": "' + $f.Name + '"'
    if ($raw.Contains($needle)) {
      $body = [string](Get-Content $f.FullName -Raw -Encoding UTF8)
      $raw = $raw.Replace($needle, '"script": ' + (ConvertTo-JsonString $body))
    }
  }
  return $raw
}

# ---------- 登录 ----------
$token = $null
if (Test-Path "$PSScriptRoot/.token") {
  $token = (Get-Content "$PSScriptRoot/.token" -Raw -Encoding UTF8).Trim()
}
if (-not $token) {
  if (-not $Pass) { throw "缺少密码：请设置环境变量 DEPLOY_PASSWORD，或用 -Pass 传入" }
  $auth = Api -Method POST -Url "$Base/auth/login" -Body @{ username = $User; password = $Pass }
  $token = $auth.token
  [System.IO.File]::WriteAllText("$PSScriptRoot/.token", $token, (New-Object System.Text.UTF8Encoding($false)))
}
$H = @{ Authorization = $token }
$me = Api -Method GET -Url "$Base/auth/me" -Headers $H
Write-Host "已登录：$($me.username) / $($me.role)" -ForegroundColor Cyan

if ($LogRunId -gt 0) {
  $raw = Api -Method GET -Url "$Base/runs/$LogRunId/log" -Headers $H
  foreach ($line in ((Get-LogText $raw) -split "`r?`n")) { Write-Host $line }
  exit 0
}

# ---------- 任务定义 ----------
$def = Expand-StepScripts $Definition | ConvertFrom-Json
$key = $def.key
$exists = $false
try { $null = Api -Method GET -Url "$Base/tasks/$key" -Headers $H; $exists = $true }
catch { if ($_.Exception.Message -notmatch 'errorCode=40400') { throw }; $exists = $false }

if ($exists) {
  Write-Host "任务 $key 已存在 → 更新定义" -ForegroundColor Cyan
  $t = Api -Method PUT -Url "$Base/tasks/$key" -Headers $H -Body $def
} else {
  Write-Host "任务 $key 不存在 → 创建" -ForegroundColor Cyan
  $t = Api -Method POST -Url "$Base/tasks" -Headers $H -Body $def
}

Write-Host "任务   : $($t.key) / $($t.name)"
Write-Host "工作区 : $($t.workdir)"
Write-Host "步骤   : $($t.steps.Count) 步"
foreach ($s in $t.steps) { Write-Host ("   - [{0}] {1}" -f $s.sortOrder, $s.name) }

if ($SkipRun) { Write-Host "`n已跳过执行 (-SkipRun)" -ForegroundColor Yellow; exit 0 }

# ---------- 触发并跟踪 ----------
$run = Api -Method POST -Url "$Base/tasks/$key/run" -Headers $H -Body @{}
$runId = $run.runId
Write-Host "`n触发任务：runId=$runId buildNumber=$($run.buildNumber) targetKind=$($run.targetKind)" -ForegroundColor Cyan

$shown = 0
$final = $null
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 1500
  $r = Api -Method GET -Url "$Base/runs/$runId" -Headers $H
  $text = Get-LogText (Api -Method GET -Url "$Base/runs/$runId/log" -Headers $H)
  if ($text.Length -gt $shown) {
    $chunk = $text.Substring($shown)
    $shown = $text.Length
    foreach ($line in ($chunk -split "`r?`n")) { if ($line -ne "") { Write-Host "  | $line" } }
  }
  if ($r.status -notin @("queued", "running")) { $final = $r; break }
}

if ($null -eq $final) { Write-Host "超时：运行未在 $WaitSeconds 秒内结束" -ForegroundColor Red; exit 1 }

Write-Host "`n---- 摘要 ----"
Write-Host "  状态   : $($final.status)"
Write-Host "  退出码 : $($final.exitCode)"
Write-Host "  耗时   : $([math]::Round($final.durationMs / 1000, 1))s"
Write-Host "  目标   : $($final.targetKind) / $($final.targetKey)"
if ($final.errorMsg) { Write-Host "  错误   : $($final.errorMsg)" -ForegroundColor Red }

if ($final.status -ne "success") { Write-Host "`n任务执行失败" -ForegroundColor Red; exit 1 }
Write-Host "`n任务执行成功" -ForegroundColor Green
exit 0
