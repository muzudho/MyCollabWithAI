[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$csvPath = Join-Path $root 'FileHashList.csv'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

# 移動済みのファイルと前回の出力は、次回の重複判定に含めません。
$files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop |
    Where-Object {
        ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -and
        -not $_.FullName.StartsWith((Join-Path $root 'TrashCan') + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($_.FullName, $csvPath, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($_.FullName, (Join-Path $root 'RemoveDuplicatedOldFile.log'),
            [System.StringComparison]::OrdinalIgnoreCase)
    })

$entries = foreach ($file in $files) {
    [pscustomobject]@{
        Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        Path = $file.FullName.Substring($root.Length).TrimStart('\', '/')
        Created = $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    }
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
