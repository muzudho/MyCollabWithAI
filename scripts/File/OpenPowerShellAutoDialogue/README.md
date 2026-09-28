# PowerShell の対話を JSON で実行

`OpenPowerShellAutoDialogue.ps1` と同じフォルダーに `OpenPowerShellAutoDialogue.json` を置きます。最初の `request` は起動する `.ps1` のパスです。その後の `request` は、直前の `response` が表示された後に入力する文字列です。空文字列は Enter キーだけを送ります。

```json
{
  "dialogue": [
    { "request": "Z:\\muzudho-private-history\\muzudho_backups\\document-a\\RemoveDuplicatedOldFile.ps1" },
    { "response": "CSV ファイル名を入力してください [FileHashList.csv]" },
    { "request": "" },
    {
      "response": [
        "同名・同サイズで MD5 が一致するファイルは、（意図的に複数用意してるものであっても）作成日時が最も新しい 1 件を残します。",
        "古いファイルを TrashCan に移動し、移動後に空になった元のフォルダーも削除します。",
        "続行しますか？ [Y/n]"
      ]
    },
    { "request": "" },
    { "response": "処理完了: .*", "regexp": true }
  ]
}
```

`request` と `response` は交互に並べます。同じ要素に `request` と `response` を書く形にも対応しています。`response` が文字列ならその文字列を待ち、配列なら各文字列を順に待ちます。`"regexp": true` を付けると正規表現として照合します。スクリプトのパスは絶対パスで指定できます。

```powershell
.\OpenPowerShellAutoDialogue.ps1
```

別の JSON を使う場合は `-DialoguePath 'C:\path\to\dialogue.json'` を指定します。通常の文字列入力を使う `Read-Host` に対応しています。既定の待機時間は全体で 3600 秒です。長い処理には `-TimeoutSeconds 86400` のように指定してください。
