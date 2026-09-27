[CmdletBinding()]
param(
    # 指定しない場合は実行時に入力します。空欄なら FileList.csv を使います。
    [string]$CsvFileName
)

$ErrorActionPreference = 'Stop'

# CSV を確認してから移動します。対象の CSV と PNG はスクリプトと同じフォルダーに置きます。
if (-not $PSBoundParameters.ContainsKey('CsvFileName')) {
    $CsvFileName = Read-Host '移動対象の CSV ファイル名を入力してください [FileList.csv]'
}
if ([string]::IsNullOrWhiteSpace($CsvFileName)) {
    $CsvFileName = 'FileList.csv'
}
if ([System.IO.Path]::GetFileName($CsvFileName) -cne $CsvFileName -or
    [System.IO.Path]::GetExtension($CsvFileName) -ine '.csv') {
    throw 'CSV ファイル名だけを指定してください（例: FileList.csv）。'
}

$csvPath = Join-Path $PSScriptRoot $CsvFileName
if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV ファイルがありません: $csvPath"
}

# FileList.ps1 の見出しと同じであることを、空の CSV でも確認します。
$header = Get-Content -LiteralPath $csvPath -Encoding UTF8 -TotalCount 1
if ($header -cnotmatch '^"?生成年月"?,"?ファイル名"?$') {
    throw 'CSV には「生成年月,ファイル名」の見出しが必要です。'
}
$rows = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)

# 不正な行があった場合に途中まで移動しないよう、全行を先に検査します。
$seen = @{}
foreach ($row in $rows) {
    $month = $row.'生成年月'
    $name = $row.'ファイル名'
    if ($month -cnotmatch '^[0-9]{4}-(0[1-9]|1[0-2])$') {
        throw "生成年月は YYYY-MM で指定してください: $month"
    }
    if ([string]::IsNullOrWhiteSpace($name) -or
        [System.IO.Path]::GetFileName($name) -cne $name -or
        [System.IO.Path]::GetExtension($name) -ine '.png') {
        throw "ファイル名は同じフォルダー内の PNG 名だけにしてください: $name"
    }
    if ($seen.ContainsKey($name)) {
        throw "CSV に同じファイル名が複数あります: $name"
    }
    $seen[$name] = $true
}

foreach ($row in $rows) {
    $month = $row.'生成年月'
    $name = $row.'ファイル名'
    $source = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Output "元の PNG がないため移動しません: $name"
        continue
    }

    # 移動先の年月は現在の作成日時ではなく、CSV に記録された値を使います。
    $monthDirectory = Join-Path $PSScriptRoot $month
    if (-not (Test-Path -LiteralPath $monthDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $monthDirectory -ErrorAction Stop | Out-Null
    }

    $destination = Join-Path $monthDirectory $name
    # 同名ファイルを上書きせず、元の PNG をその場に残します。
    if (Test-Path -LiteralPath $destination) {
        Write-Output "同名ファイルがあるため移動しません: $destination"
        continue
    }

    # 存在確認の直後に同名ファイルが作られても、File.Move は上書きを拒否します。
    [System.IO.File]::Move($source, $destination)
    Write-Output "移動しました: $name -> $month"
}
