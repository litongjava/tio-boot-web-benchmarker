<#
  通过「轻量部署平台」(http://192.168.31.97:10055) 的 REST API 部署本项目。

  平台把一次部署建模成：项目定义（Git + 命令列表）→ 执行 → 运行记录。
  本脚本做三件事：登录 → 按 scripts/project.json 创建或更新项目 → 触发一次执行并跟踪日志。

  用法（在项目根目录）：
    pwsh -File scripts/deploy.ps1                 # 创建/更新项目并执行一次
    pwsh -File scripts/deploy.ps1 -SkipRun        # 只创建/更新项目定义
    pwsh -File scripts/deploy.ps1 -OnlyRun        # 不碰项目定义，直接执行已有项目
    pwsh -File scripts/deploy.ps1 -LogRunId 123   # 只看某次运行的日志

  密码不写进仓库：默认从环境变量 DEPLOY_PASSWORD 读取，也可用 -Pass 传入。

  两个实测坑（来自平台自带文档 docs/API设计.md）：
    1. 平台的业务错误是 HTTP 200 + success=false，不能用 try/catch 判断业务失败，必须显式看 success。
    2. 请求体必须先转成 UTF-8 字节再发，否则 Windows PowerShell 5.1 会按默认代码页编码（中文变 ?）。
#>
param(
  [string]$Base = "http://192.168.31.97:10055/api/v1",
  [string]$User = "admin",
  [string]$Pass = $env:DEPLOY_PASSWORD,
  [string]$Definition = "$PSScriptRoot/project.json",
  [switch]$SkipRun,
  [switch]$OnlyRun,
  # 跳过 Git 准备阶段，直接用工作区里已有的代码。
  # 用途：这台服务器到 github.com 的连接是间歇性的（实测 "SSL connection timeout"），
  # 代码没变时没必要因为拉不动远端就卡住整个部署。
  [switch]$NoGit,
  [int]$LogRunId = 0,
  [int]$WaitSeconds = 3600
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Api {
  param([string]$Method, [string]$Url, [hashtable]$Headers = @{}, $Body = $null)
  $params = @{ Uri = $Url; Method = $Method; Headers = $Headers; UseBasicParsing = $true; TimeoutSec = 120 }
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

function Show-Text($raw) {
  $text = Get-LogText $raw
  if (-not $text) { Write-Host "(空)"; return }
  foreach ($line in ($text -split "`r?`n")) { Write-Host $line }
}

# ---------- 登录 ----------
$token = $null
if (Test-Path "$PSScriptRoot/.token") {
  $token = (Get-Content "$PSScriptRoot/.token" -Raw -Encoding UTF8).Trim()
}
if (-not $token) {
  if (-not $Pass) { throw "缺少密码：请设置环境变量 DEPLOY_PASSWORD，或用 -Pass 传入" }
  $boot = Api -Method GET -Url "$Base/auth/bootstrap-status"
  if (-not $boot.initialized) {
    $auth = Api -Method POST -Url "$Base/auth/bootstrap" -Body @{ username = $User; password = $Pass }
  } else {
    $auth = Api -Method POST -Url "$Base/auth/login" -Body @{ username = $User; password = $Pass }
  }
  $token = $auth.token
  # 不用 Set-Content -Encoding UTF8：Windows PowerShell 5.1 会写出 BOM，下次读取时会把 BOM 带进 token。
  [System.IO.File]::WriteAllText("$PSScriptRoot/.token", $token, (New-Object System.Text.UTF8Encoding($false)))
}
$H = @{ Authorization = $token }
$me = Api -Method GET -Url "$Base/auth/me" -Headers $H
Write-Host "已登录：$($me.username) / $($me.role)" -ForegroundColor Cyan

# ---------- 只看日志 ----------
if ($LogRunId -gt 0) {
  Show-Text (Api -Method GET -Url "$Base/runs/$LogRunId/log" -Headers $H)
  exit 0
}

# 把一段文本编码成 JSON 字符串字面量（含首尾引号）。
#
# 不用 ConvertTo-Json 来做这件事：Windows PowerShell 5.1 里
# `ConvertTo-Json -InputObject (Get-Content xxx -Raw)` 会把字符串当成带扩展属性的
# 对象序列化，产出 {"value":"...","Drives":[...],"ReadCount":1} 这种东西，
# 服务端于是报 "cannot unmarshal object into ... script of type string"。
# 手写转义只有几个分支，行为完全可预期。
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

# ---------- 项目定义 ----------
# 每条命令的脚本放在 scripts/commands/<file> 里，这里把定义里的 file 字段换成 script：
#   把 shell 脚本写成独立文件（而不是塞进 JSON 字符串）才能保持缩进与引号可读，
#   也让脚本可以单独检查。
#
# 替换刻意在「JSON 文本」这一层做，而不是解析成对象后改属性。踩过的坑：
# Windows PowerShell 5.1 里对 ConvertFrom-Json 出来的 PSCustomObject 做
# Add-Member / PSObject.Properties.Remove 之后，ConvertTo-Json 会直接挂死
# （不报错、不返回，实测卡满 3 分钟）。文本级替换完全绕开这个坑。
function Expand-CommandScripts($path) {
  $raw = Get-Content $path -Raw -Encoding UTF8
  $dir = Join-Path $PSScriptRoot 'commands'
  foreach ($f in (Get-ChildItem $dir -Filter *.sh -File)) {
    $needle = '"file": "' + $f.Name + '"'
    if ($raw.Contains($needle)) {
      $body = [string](Get-Content $f.FullName -Raw -Encoding UTF8)
      $raw = $raw.Replace($needle, '"script": ' + (ConvertTo-JsonString $body))
    }
  }
  return $raw
}

$key = $null
if (-not $OnlyRun) {
  $def = Expand-CommandScripts $Definition | ConvertFrom-Json
  $key = $def.key
  if ($NoGit) {
    # useGit 是已有属性，直接赋值安全；不要用 Add-Member/Remove，
    # 那会让 PS 5.1 的 ConvertTo-Json 挂死（见上面 Expand-CommandScripts 的注释）。
    Write-Host "已按 -NoGit 跳过 Git 准备阶段，直接使用工作区现有代码" -ForegroundColor Yellow
    $def.useGit = $false
  }
  $exists = $false
  try { $null = Api -Method GET -Url "$Base/projects/$key" -Headers $H; $exists = $true }
  catch { if ($_.Exception.Message -notmatch 'errorCode=40400') { throw }; $exists = $false }

  if ($exists) {
    Write-Host "项目 $key 已存在 → 更新定义" -ForegroundColor Cyan
    $p = Api -Method PUT -Url "$Base/projects/$key" -Headers $H -Body $def
  } else {
    Write-Host "项目 $key 不存在 → 创建" -ForegroundColor Cyan
    $p = Api -Method POST -Url "$Base/projects" -Headers $H -Body $def
  }
} else {
  $def = Get-Content $Definition -Raw -Encoding UTF8 | ConvertFrom-Json
  $key = $def.key
  $p = Api -Method GET -Url "$Base/projects/$key" -Headers $H
}

Write-Host "项目   : $($p.key) / $($p.name)"
Write-Host "类型   : kind=$($p.kind)  依赖=$([string]::Join(',', @($p.dependencies)))"
Write-Host "工作区 : $($p.workdir)"
Write-Host "Git    : useGit=$($p.useGit) $($p.gitUrl) @ $($p.gitBranch)"
$cmds = @($p.commands)
Write-Host "命令   : $($cmds.Count) 条"
foreach ($c in $cmds) { Write-Host ("   - [{0}] {1}" -f $c.sortOrder, $c.name) }

if ($SkipRun) { Write-Host "`n已跳过执行 (-SkipRun)" -ForegroundColor Yellow; exit 0 }

# ---------- 触发执行并跟踪 ----------
$run = Api -Method POST -Url "$Base/projects/$key/run" -Headers $H -Body @{ branch = $p.gitBranch }
$runId = $run.runId
Write-Host "`n触发执行：runId=$runId buildNumber=$($run.buildNumber)" -ForegroundColor Cyan

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
Write-Host "  git    : $($final.gitCommitShort) @ $($final.gitBranchResolved)"
if ($final.errorMsg) { Write-Host "  错误   : $($final.errorMsg)" -ForegroundColor Red }

if ($final.status -ne "success") { Write-Host "`n执行失败" -ForegroundColor Red; exit 1 }
Write-Host "`n执行成功" -ForegroundColor Green
exit 0
