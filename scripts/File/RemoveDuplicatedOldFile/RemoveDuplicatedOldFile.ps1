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

function ConvertTo-ExtendedPath([string]$path) {
    if ($path.StartsWith('\\?\')) { return $path }
    if ($path.StartsWith('\\')) { return '\\?\UNC\' + $path.Substring(2) }
    return '\\?\' + $path
}

function Get-Md5([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        return [System.BitConverter]::ToString($md5.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
    } finally {
        $md5.Dispose()
        $stream.Dispose()
    }
}

function Remove-EmptySourceDirectories([string]$sourcePath, [string]$rootDirectoryPrefix) {
    $directory = [System.IO.Path]::GetDirectoryName((ConvertTo-ExtendedPath $sourcePath))
    $removed = 0
    while ($directory.StartsWith($rootDirectoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        # 空でない場所やリンク先には触れず、空のディレクトリーだけを非再帰で削除します。
        if (([System.IO.File]::GetAttributes($directory) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            break
        }
        $enumerator = [System.IO.Directory]::EnumerateFileSystemEntries($directory).GetEnumerator()
        try {
            $hasEntries = $enumerator.MoveNext()
        } finally {
            $enumerator.Dispose()
        }
        if ($hasEntries) { break }
        [System.IO.Directory]::Delete($directory, $false)
        $removed++
        $directory = [System.IO.Path]::GetDirectoryName($directory)
    }
    return $removed
}

# CSV 名は対象フォルダー内のファイル名だけを受け付けます。
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
if ($header -cnotmatch '^"?MD5"?,"?ファイルパス"?,"?ファイル作成日時"?$') {
    throw 'CSV には「MD5,ファイルパス,ファイル作成日時」の見出しが必要です。FileHashList.ps1 で CSV を作り直してください。'
}
$rows = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$rootPrefix = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$extendedRootPrefix = (ConvertTo-ExtendedPath $root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$trashPrefix = $trash.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

# 全行を先に検査し、CSV のパスが作業ディレクトリー外へ出ないようにします。
$entries = foreach ($row in $rows) {
    $hash = $row.MD5
    $relative = $row.'ファイルパス'
    $created = $row.'ファイル作成日時'
    if ($hash -cnotmatch '^[0-9a-fA-F]{32}$') {
        throw "MD5 の形式が正しくありません: $hash"
    }
    if ([string]::IsNullOrWhiteSpace($relative) -or
        [System.IO.Path]::IsPathRooted($relative) -or
        $relative -match ':' -or
        $relative -match '(^|[\\/])\.{1,2}([\\/]|$)') {
        throw "ファイルパスが不正です: $relative"
    }
    $source = Join-Path $root $relative
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
    [pscustomobject]@{
        Hash = $hash.ToLowerInvariant()
        Name = [System.IO.Path]::GetFileName($source)
        Relative = $relative
        Source = $source
        Created = $date
    }
}

Write-Output '同名・同サイズで MD5 が一致するファイルは、（意図的に複数用意してるものであっても）作成日時が最も新しい 1 件を残します。'
Write-Output '古いファイルを TrashCan に移動し、移動後に空になった元のフォルダーも削除します。'
while ($true) {
    $answer = Read-Host '続行しますか？ [Y/n]'
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -imatch '^(y|yes)$') { break }
    if ($answer -imatch '^(n|no)$') {
        Write-Output '中止しました。'
        return
    }
    Write-Output 'Y または n を入力してください。'
}
[System.IO.Directory]::CreateDirectory($trash) | Out-Null

$log = New-Object 'System.Collections.Generic.List[string]'
$moved = 0
$removedDirectories = 0
foreach ($group in @($entries | Group-Object -Property Hash, Name | Where-Object { $_.Count -ge 2 })) {
    $members = @($group.Group | Sort-Object -Property @{ Expression = 'Created'; Descending = $true },
        @{ Expression = 'Relative'; Descending = $false })

    # CSV 作成後にファイルが変わっていたら、このグループには触れません。
    $valid = $true
    $expectedLength = $null
    foreach ($member in $members) {
        try {
            $file = New-Object System.IO.FileInfo((ConvertTo-ExtendedPath $member.Source))
            if (-not $file.Exists) { throw '元ファイルがありません。' }
            if ($null -eq $expectedLength) { $expectedLength = $file.Length }
            if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                $file.Length -ne $expectedLength -or
                $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss',
                    [System.Globalization.CultureInfo]::InvariantCulture) -cne
                    $member.Created.ToString('yyyy-MM-dd HH:mm:ss',
                        [System.Globalization.CultureInfo]::InvariantCulture) -or
                (Get-Md5 (ConvertTo-ExtendedPath $member.Source)) -ine $member.Hash) {
                throw 'ファイルの種類、サイズ、作成日時、または MD5 が CSV と一致しません。'
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
        $extendedDestination = ConvertTo-ExtendedPath $destination
        if ([System.IO.File]::Exists($extendedDestination) -or
            [System.IO.Directory]::Exists($extendedDestination)) {
            $log.Add("衝突: $($member.Relative) -> $destination")
            continue
        }
        try {
            [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($extendedDestination)) | Out-Null
            [System.IO.File]::Move((ConvertTo-ExtendedPath $member.Source), $extendedDestination)
            $moved++
            Write-Output "移動しました: $($member.Relative)"
        } catch {
            $log.Add("移動失敗: $($member.Relative) : $($_.Exception.Message)")
            continue
        }
        try {
            $removedDirectories += Remove-EmptySourceDirectories $member.Source $extendedRootPrefix
        } catch {
            $log.Add("空フォルダーの削除失敗: $($member.Relative) : $($_.Exception.Message)")
        }
    }
}

if ($log.Count -gt 0) {
    [System.IO.File]::WriteAllText($logPath, (($log.ToArray() -join "`r`n") + "`r`n"), $utf8WithoutBom)
    Write-Output "ログを出力しました: $logPath ($($log.Count) 件)"
}
Write-Output "処理完了: $moved 件を TrashCan へ移動し、空のフォルダーを $removedDirectories 件削除しました。"
