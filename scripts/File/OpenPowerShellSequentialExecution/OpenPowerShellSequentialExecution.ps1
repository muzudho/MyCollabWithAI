[CmdletBinding()]
param(
    [string]$ListPath = (Join-Path $PSScriptRoot 'PowerShellScriptList.txt')
)

$ErrorActionPreference = 'Stop'

# 一覧ファイル内の相対パスは、一覧ファイルのあるフォルダーを基準にします。
$listFile = (Resolve-Path -LiteralPath $ListPath -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath $listFile -PathType Leaf)) {
    throw "一覧ファイルではありません: $listFile"
}
$listDirectory = Split-Path -Parent $listFile
$entries = New-Object 'System.Collections.Generic.List[object]'
$lineNumber = 0

foreach ($line in [System.IO.File]::ReadAllLines($listFile)) {
    $lineNumber++
    $path = $line.Trim()
    if ($path.Length -eq 0 -or $path.StartsWith('#')) { continue }

    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $path = Join-Path $listDirectory $path
    }
    try {
        $scriptFile = (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
        if (-not (Test-Path -LiteralPath $scriptFile -PathType Leaf) -or
            [System.IO.Path]::GetExtension($scriptFile) -ine '.ps1') {
            throw '既存の .ps1 ファイルを指定してください。'
        }
    } catch {
        throw "一覧の $lineNumber 行目を確認してください: $path`n$($_.Exception.Message)"
    }
    $entries.Add([pscustomobject]@{ Line = $lineNumber; Path = $scriptFile })
}

if ($entries.Count -eq 0) { throw "一覧に実行する .ps1 ファイルがありません: $listFile" }

# 子プロセスで実行し、各スクリプトの exit が一覧実行側を終了させないようにします。
$shellName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
$shellPath = (Get-Command $shellName -CommandType Application -ErrorAction Stop).Source
$index = 0
foreach ($entry in $entries) {
    $index++
    Write-Host "[$index/$($entries.Count)] 実行中 (一覧 $($entry.Line) 行目): $($entry.Path)"
    & $shellPath -NoProfile -ExecutionPolicy Bypass -File $entry.Path
    $result = $LASTEXITCODE
    if ($result -ne 0) {
        throw "一覧 $($entry.Line) 行目のスクリプトが終了コード $result で失敗しました: $($entry.Path)"
    }
}
Write-Host "完了: $($entries.Count) 件のスクリプトを順次実行しました。"
