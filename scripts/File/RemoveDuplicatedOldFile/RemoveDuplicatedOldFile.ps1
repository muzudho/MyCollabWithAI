[CmdletBinding()]
param([string]$CsvFileName, [string]$RootPath)

$ErrorActionPreference = 'Stop'
# FileHashList.ps1 と同じ対象フォルダーを使います。
if ([string]::IsNullOrWhiteSpace($RootPath)) { $RootPath = $PSScriptRoot }
$root = (Get-Item -LiteralPath $RootPath -ErrorAction Stop).FullName
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "対象フォルダーがありません: $RootPath"
}
$trash = Join-Path $root 'TrashCan'
$logPath = Join-Path $root 'RemoveDuplicatedOldFile.log'
$scanErrorLogPath = Join-Path $root 'FileHashList.errors.log'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

# 入力前に TrashCan を用意します。CSV 名は同じフォルダー内のファイル名だけを受け付けます。
[System.IO.Directory]::CreateDirectory($trash) | Out-Null
if (-not $PSBoundParameters.ContainsKey('CsvFileName')) {
    $CsvFileName = Read-Host 'CSV ファイル名を入力してください [FileHashList.csv]'
}
if ([string]::IsNullOrWhiteSpace($CsvFileName)) {
    $CsvFileName = 'FileHashList.csv'
}
if ([System.IO.Path]::GetFileName($CsvFileName) -cne $CsvFileName -or
    [System.IO.Path]::GetExtension($CsvFileName) -ine '.csv') {
    throw 'CSV ファイル名だけを指定してください（例: FileHashList.csv）。'
}
$csvPath = Join-Path $root $CsvFileName
if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV ファイルがありません: $csvPath"
}
if (Test-Path -LiteralPath $scanErrorLogPath -PathType Leaf) {
    throw "探索時に読み取りエラーがありました。移動前にログを確認して、FileHashList.ps1 を再実行してください: $scanErrorLogPath"
}

$header = Get-Content -LiteralPath $csvPath -Encoding UTF8 -TotalCount 1
if ($header -cnotmatch '^"?SHA256"?,"?ファイルパス"?,"?ファイル作成日時"?$') {
    throw 'CSV には「SHA256,ファイルパス,ファイル作成日時」の見出しが必要です。'
}
$rows = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$rootPrefix = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$trashPrefix = $trash.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

# 全行を先に検査し、CSV のパスが作業ディレクトリー外へ出ないようにします。
$entries = foreach ($row in $rows) {
    $hash = $row.SHA256
    $relative = $row.'ファイルパス'
    $created = $row.'ファイル作成日時'
    if ($hash -cnotmatch '^[0-9a-fA-F]{64}$') {
        throw "SHA256 の形式が正しくありません: $hash"
    }
    if ([string]::IsNullOrWhiteSpace($relative) -or
        [System.IO.Path]::IsPathRooted($relative) -or
        $relative -match '^[a-zA-Z]:' -or
        $relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "ファイルパスが不正です: $relative"
    }
    $source = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $source.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $source.StartsWith($trashPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $seen.Add($source)) {
        throw "ファイルパスが範囲外または重複しています: $relative"
    }
    $date = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($created, 'yyyy-MM-dd HH:mm:ss',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
        throw "ファイル作成日時の形式が正しくありません: $created"
    }
    [pscustomobject]@{ Hash = $hash.ToLowerInvariant(); Relative = $relative; Source = $source; Created = $date }
}

$log = New-Object 'System.Collections.Generic.List[string]'
$moved = 0
foreach ($group in @($entries | Group-Object -Property Hash | Where-Object { $_.Count -ge 2 })) {
    $members = @($group.Group | Sort-Object -Property @{ Expression = 'Created'; Descending = $true },
        @{ Expression = 'Relative'; Descending = $false })

    # CSV 作成後にファイルが変わっていたら、このグループには触れません。
    $valid = $true
    foreach ($member in $members) {
        try {
            $file = Get-Item -LiteralPath $member.Source -ErrorAction Stop
            if ($file.PSIsContainer -or
                ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss',
                    [System.Globalization.CultureInfo]::InvariantCulture) -cne
                    $member.Created.ToString('yyyy-MM-dd HH:mm:ss',
                        [System.Globalization.CultureInfo]::InvariantCulture) -or
                (Get-FileHash -LiteralPath $member.Source -Algorithm SHA256 -ErrorAction Stop).Hash -ine $member.Hash) {
                throw 'ファイルの種類、作成日時、またはハッシュが CSV と一致しません。'
            }
        } catch {
            $log.Add("スキップ: $($member.Relative) : $($_.Exception.Message)")
            $valid = $false
        }
    }
    if (-not $valid) { continue }

    # 最新の 1 件を残し、古いファイルだけ元の相対パスで TrashCan へ移します。
    foreach ($member in @($members | Select-Object -Skip 1)) {
        $destination = Join-Path $trash $member.Relative
        if (Test-Path -LiteralPath $destination) {
            $log.Add("衝突: $($member.Relative) -> $destination")
            continue
        }
        try {
            [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
            [System.IO.File]::Move($member.Source, $destination)
            $moved++
            Write-Output "移動しました: $($member.Relative)"
        } catch {
            $log.Add("移動失敗: $($member.Relative) : $($_.Exception.Message)")
        }
    }
}

if ($log.Count -gt 0) {
    [System.IO.File]::WriteAllText($logPath, (($log.ToArray() -join "`r`n") + "`r`n"), $utf8WithoutBom)
    Write-Output "ログを出力しました: $logPath ($($log.Count) 件)"
}
Write-Output "処理完了: $moved 件を TrashCan へ移動しました。"
