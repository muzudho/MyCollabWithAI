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
$count = 0

Write-Output "探索を開始します: $root"
Write-Output 'NAS では全ファイルの読み取りが終わるまで時間がかかる場合があります。'

# 移動済みのファイルと前回の出力は、次回の重複判定に含めません。
$entries = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Continue -ErrorVariable +scanErrors |
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
        $file = $_
        $count++
        Write-Progress -Activity 'ファイルの SHA-256 を計算中' -Status "$count 件: $($file.FullName)"
        try {
            [pscustomobject]@{
                Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                Path = $file.FullName.Substring($root.Length).TrimStart('\', '/')
                Created = $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
            }
        } catch {
            $issues.Add("ハッシュ計算失敗: $($file.FullName) : $($_.Exception.Message)")
        }
    })
Write-Progress -Activity 'ファイルの SHA-256 を計算中' -Completed
foreach ($scanError in $scanErrors) {
    $issues.Add("探索失敗: $($scanError.ToString())")
}

# ハッシュ順に並べると、同じ内容のファイルが CSV 上で連続します。
$rows = @($entries | Group-Object -Property Hash |
    Where-Object { $_.Count -ge 2 } |
    Sort-Object -Property Name |
    ForEach-Object { $_.Group | Sort-Object -Property Path } |
    ForEach-Object {
        [pscustomobject][ordered]@{
            'SHA256' = $_.Hash
            'ファイルパス' = $_.Path
            'ファイル作成日時' = $_.Created
        }
    })

# 空の場合も見出しだけの CSV を出力します。
$lines = if ($rows.Count -eq 0) {
    @('"SHA256","ファイルパス","ファイル作成日時"')
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
