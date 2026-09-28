#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DialoguePath = (Join-Path $PSScriptRoot 'OpenPowerShellAutoDialogue.json'),
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
$jsonPath = (Resolve-Path -LiteralPath $DialoguePath -ErrorAction Stop).ProviderPath
$items = @((Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json).dialogue)
if ($items.Count -eq 0) { throw 'dialogue に項目がありません。' }
# request と response が別の要素でも、同じ要素に並んでいても順番どおりに扱います。
$events = New-Object 'System.Collections.Generic.List[object]'
foreach ($item in $items) {
    $hasRequest = $null -ne $item.PSObject.Properties['request']
    $hasResponse = $null -ne $item.PSObject.Properties['response']
    if (-not $hasRequest -and -not $hasResponse) { throw '各要素に request または response が必要です。' }
    if ($hasRequest) {
        if ($item.request -isnot [string]) { throw 'request は文字列にしてください。' }
        $events.Add([pscustomobject]@{ Kind = 'request'; Value = $item.request; Regex = $false })
    }
    if ($hasResponse) {
        if ($item.response -isnot [string] -and $item.response -isnot [array]) {
            throw 'response は文字列または文字列の配列にしてください。'
        }
        $events.Add([pscustomobject]@{ Kind = 'response'; Value = $item.response; Regex = [bool]$item.regexp })
    }
}
if ($events.Count % 2 -ne 0) { throw 'request と response の数が一致しません。' }
for ($i = 0; $i -lt $events.Count; $i++) {
    $expectedKind = if ($i % 2 -eq 0) { 'request' } else { 'response' }
    if ($events[$i].Kind -ne $expectedKind) { throw 'request と response を交互に並べてください。' }
}
$target = [string]$events[0].Value
if ([string]::IsNullOrWhiteSpace($target)) { throw '最初の request には .ps1 のパスが必要です。' }
if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path -Parent $jsonPath) $target }
$target = (Resolve-Path -LiteralPath $target -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
    [System.IO.Path]::GetExtension($target) -ine '.ps1') { throw "対象が .ps1 ファイルではありません: $target" }
# Read-Host の表示は改行を含まないので、標準出力を非同期で読みます。
$process = New-Object System.Diagnostics.Process
$info = $process.StartInfo
$shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
$info.FileName = (Get-Command $shell -CommandType Application -ErrorAction Stop).Source
$safeTarget = $target.Replace("'", "''")
# リダイレクト時に Read-Host が質問文を出さないため、通常の文字列入力を扱う関数に置き換えます。
$command = '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false); function Read-Host { param([string]$Prompt) [Console]::Write($Prompt + '': ''); [Console]::ReadLine() }; & ''' + $safeTarget + ''''
$info.Arguments = '-NoProfile -ExecutionPolicy Bypass -Command "' + $command + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardInput = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
$buffer = New-Object char[] 1024
$output = New-Object System.Text.StringBuilder
$cursor = 0
$readTask = $null
$clock = [System.Diagnostics.Stopwatch]::StartNew()

function Wait-ForText([string]$pattern, [bool]$regex) {
    if ($pattern.Length -eq 0) { throw '空の response は指定できません。' }
    while ($true) {
        $available = $output.ToString().Substring($script:cursor)
        if ($regex) {
            $found = [regex]::Match($available, $pattern)
            if ($found.Success) { $script:cursor += $found.Index + $found.Length; return }
        } else {
            $foundAt = $available.IndexOf($pattern, [System.StringComparison]::Ordinal)
            if ($foundAt -ge 0) { $script:cursor += $foundAt + $pattern.Length; return }
        }
        if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw "応答待ちが $TimeoutSeconds 秒を超えました: $pattern" }
        if ($null -eq $script:readTask) {
            $script:readTask = $process.StandardOutput.ReadAsync($buffer, 0, $buffer.Length)
        }
        if ($script:readTask.Wait(100)) {
            $count = $script:readTask.Result
            $script:readTask = $null
            if ($count -eq 0) { throw "応答が出る前に終了しました: $pattern" }
            $part = New-Object string ($buffer, 0, $count)
            [void]$output.Append($part)
            Write-Host -NoNewline $part
        }
    }
}

try {
    [void]$process.Start()
    $errorTask = $process.StandardError.ReadToEndAsync()
    for ($index = 1; $index -lt $events.Count; $index++) {
        $event = $events[$index]
        if ($event.Kind -eq 'request') {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(([string]$event.Value) + "`n")
            $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
            $process.StandardInput.BaseStream.Flush()
        } else {
            foreach ($expected in @($event.Value)) { Wait-ForText ([string]$expected) $event.Regex }
        }
    }
    $process.StandardInput.Close()
    $remaining = [Math]::Max(1, [int](($TimeoutSeconds - $clock.Elapsed.TotalSeconds) * 1000))
    if (-not $process.WaitForExit($remaining)) { throw "終了待ちが $TimeoutSeconds 秒を超えました。" }
    if ($null -ne $readTask) {
        $count = $readTask.GetAwaiter().GetResult()
        if ($count -gt 0) { Write-Host -NoNewline (New-Object string ($buffer, 0, $count)) }
    }
    $tail = $process.StandardOutput.ReadToEnd()
    if ($tail.Length -gt 0) { Write-Host -NoNewline $tail }
    $errors = $errorTask.GetAwaiter().GetResult()
    if ($errors.Length -gt 0) { [Console]::Error.Write($errors) }
    if ($process.ExitCode -ne 0) { throw "対象スクリプトが終了コード $($process.ExitCode) で失敗しました。" }
    Write-Host '対話が完了しました。'
} finally {
    if ($process.StartInfo -and -not $process.HasExited) { $process.Kill() }
    $process.Dispose()
}
