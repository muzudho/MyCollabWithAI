[CmdletBinding()]
param([string]$RootPath)

$ErrorActionPreference = 'Stop'
# 省略時はスクリプトの場所を使い、-RootPath で NAS なども指定できます。
if ([string]::IsNullOrWhiteSpace($RootPath)) { $RootPath = $PSScriptRoot }
$root = (Get-Item -LiteralPath $RootPath -ErrorAction Stop).FullName
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "対象フォルダーがありません: $RootPath"
}
$csvPath = Join-Path $root 'FileHashList.csv'
$errorLogPath = Join-Path $root 'FileHashList.errors.log'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
$issues = New-Object 'System.Collections.Generic.List[string]'
$scanCount = 0
$count = 0

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

Write-Output "探索を開始します: $root"
Write-Output 'まずファイル名とサイズで候補を絞ります。'

# 長いパスでも列挙できるよう、拡張パスで各ディレクトリーをたどります。
$files = New-Object 'System.Collections.Generic.List[object]'
$directories = New-Object 'System.Collections.Generic.Stack[string]'
$directories.Push((ConvertTo-ExtendedPath $root))
$trashPath = ConvertTo-ExtendedPath (Join-Path $root 'TrashCan')
while ($directories.Count -gt 0) {
    $directory = $directories.Pop()
    try {
        foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($directory)) {
            try {
                $attributes = [System.IO.File]::GetAttributes($path)
                if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    if (-not [string]::Equals($path, $trashPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $directories.Push($path)
                    }
                    continue
                }
                $normalPath = if ($path.StartsWith('\\?\UNC\')) {
                    '\\' + $path.Substring(8)
                } else {
                    $path.Substring(4)
                }
                if ([string]::Equals($normalPath, $csvPath, [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($normalPath, (Join-Path $root 'RemoveDuplicatedOldFile.log'),
                        [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($normalPath, $errorLogPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $info = New-Object System.IO.FileInfo($path)
                $files.Add([pscustomobject]@{
                    FullName = $normalPath
                    ExtendedPath = $path
                    Name = $info.Name
                    Length = $info.Length
                    Created = $info.CreationTime.ToString('yyyy-MM-dd HH:mm:ss',
                        [System.Globalization.CultureInfo]::InvariantCulture)
                })
                $scanCount++
                if ($scanCount % 100 -eq 0) {
                    Write-Progress -Activity 'ファイル名とサイズを探索中' -Status "$scanCount 件を確認"
                }
            } catch {
                $issues.Add("ファイル情報の取得失敗: $path : $($_.Exception.Message)")
            }
        }
    } catch {
        $issues.Add("探索失敗: $directory : $($_.Exception.Message)")
    }
}
Write-Progress -Activity 'ファイル名とサイズを探索中' -Completed

# 同じ basename とサイズのファイルだけをハッシュ計算の対象にします。
$candidates = @($files | Group-Object -Property Name, Length |
    Where-Object { $_.Count -ge 2 } |
    ForEach-Object { $_.Group })
Write-Output "探索したファイル: $($files.Count) 件 / MD5 計算候補: $($candidates.Count) 件"

$entries = @($candidates | ForEach-Object {
        $file = $_
        $count++
        Write-Progress -Activity 'ファイルの MD5 を計算中' -Status "$count / $($candidates.Count) 件: $($file.FullName)" -PercentComplete (100 * $count / $candidates.Count)
        try {
            [pscustomobject]@{
                Hash = Get-Md5 $file.ExtendedPath
                Name = $file.Name
                Length = $file.Length
                Path = $file.FullName.Substring($root.Length).TrimStart('\', '/')
                Created = $file.Created
            }
        } catch {
            $issues.Add("ハッシュ計算失敗: $($file.FullName) : $($_.Exception.Message)")
        }
    })
Write-Progress -Activity 'ファイルの MD5 を計算中' -Completed

# 同名・同サイズ・同ハッシュのグループだけを CSV に出します。
$rows = @($entries | Group-Object -Property Hash, Name, Length |
    Where-Object { $_.Count -ge 2 } |
    Sort-Object -Property Name |
    ForEach-Object { $_.Group | Sort-Object -Property Path } |
    ForEach-Object {
        [pscustomobject][ordered]@{
            'MD5' = $_.Hash
            'ファイルパス' = $_.Path
            'ファイル作成日時' = $_.Created
        }
    })

# 空の場合も見出しだけの CSV を出力します。
$lines = if ($rows.Count -eq 0) {
    @('"MD5","ファイルパス","ファイル作成日時"')
} else {
    @($rows | ConvertTo-Csv -NoTypeInformation)
}
[System.IO.File]::WriteAllText($csvPath, (($lines -join "`r`n") + "`r`n"), $utf8WithoutBom)
Write-Output "CSV を出力しました: $csvPath ($($rows.Count) 件)"
if ($issues.Count -gt 0) {
    # 一部のファイルを読めなかった場合、CSV は部分的な結果です。
    [System.IO.File]::WriteAllText($errorLogPath, (($issues.ToArray() -join "`r`n") + "`r`n"), $utf8WithoutBom)
    Write-Warning "読み取りエラーが $($issues.Count) 件あります。詳細: $errorLogPath"
} elseif (Test-Path -LiteralPath $errorLogPath) {
    Remove-Item -LiteralPath $errorLogPath -Force
}
