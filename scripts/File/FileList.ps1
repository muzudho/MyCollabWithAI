[CmdletBinding()]
param()

# このスクリプトと同じフォルダー直下の PNG だけを一覧にします。
# 「生成年月」は Windows が記録する作成日時のローカル年月です。
$ErrorActionPreference = 'Stop'
$csvPath = Join-Path $PSScriptRoot 'FileList.csv'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

# 年月、ファイル名の順に並べると、同じ月のファイルがまとまります。
$rows = @(Get-ChildItem -LiteralPath $PSScriptRoot -File |
    Where-Object { $_.Extension -ieq '.png' } |
    ForEach-Object {
        [pscustomobject][ordered]@{
            '生成年月' = $_.CreationTime.ToString('yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)
            'ファイル名' = $_.Name
        }
    } |
    Sort-Object -Property '生成年月', 'ファイル名')

# PNG がない場合も見出し行だけの CSV を作ります。
$lines = if ($rows.Count -eq 0) {
    @('"生成年月","ファイル名"')
} else {
    @($rows | ConvertTo-Csv -NoTypeInformation)
}

# ConvertTo-Csv の適切な引用符を使い、改行と文字コードを明示して保存します。
[System.IO.File]::WriteAllText($csvPath, (($lines -join "`r`n") + "`r`n"), $utf8WithoutBom)
Write-Output "CSV を出力しました: $csvPath ($($rows.Count) 件)"
