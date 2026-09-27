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
$scanErrors = @()
$scanCount = 0
$count = 0

Write-Output "探索を開始します: $root"
Write-Output 'まずファイル名とサイズで候補を絞ります。'

# 移動済みのファイルと前回の出力は、次回の重複判定に含めません。
$files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Continue -ErrorVariable +scanErrors |
    Where-Object {
        ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -and
        -not $_.FullName.StartsWith((Join-Path $root 'TrashCan') + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($_.FullName, $csvPath, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($_.FullName, (Join-Path $root 'RemoveDuplicatedOldFile.log'),
            [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($_.FullName, $errorLogPath, [System.StringComparison]::OrdinalIgnoreCase)
    } |
    ForEach-Object {
        $scanCount++
        if ($scanCount % 100 -eq 0) {
            Write-Progress -Activity 'ファイル名とサイズを探索中' -Status "$scanCount 件を確認"
        }
        $_
    })
Write-Progress -Activity 'ファイル名とサイズを探索中' -Completed
foreach ($scanError in $scanErrors) {
    $issues.Add("探索失敗: $($scanError.ToString())")
}

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
                Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm MD5 -ErrorAction Stop).Hash.ToLowerInvariant()
                Name = $file.Name
                Length = $file.Length
                Path = $file.FullName.Substring($root.Length).TrimStart('\', '/')
                Created = $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
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
