# ＡＩと共同作業するわたしの開発所

プロンプト集です。  

例：  重複ファイルを削除するスクリプトを作ってほしいんだぜ（＾▽＾）  

## 依頼チャット

雑用を頼んでいいかだぜ（＾～＾）？  
作ってほしい PowerShell スクリプトが２つあるんだぜ（＾▽＾）  

（１） 📄 `FileHashList.ps1`  
このスクリプトを実行したら、このスクリプトが置いてあるディレクトリーにあるサブディレクトリーや、ファイルを探索し、  
その後、  
ファイルの basename と、ファイルサイズが一致しているファイルについて、 MD5 ハッシュ値を計算してくれだぜ（＾▽＾）  
ほんでハッシュ値、ファイルパス、ファイルの作成日時を CSV 形式で出力してくれだぜ（＾▽＾）
ハッシュ値別にグループ化してくれだぜ（＾▽＾）  
ほんで、要素を２つ以上持つグループだけを抽出してくれだぜ（＾▽＾）  
それを、 Windows の改行 CRLF かつ、UTF-8（BOM無し）エンコードで、 CSV 形式で出力してくれだぜ（＾▽＾）  
フォーマットは以下の通りだぜ（＾▽＾）  

📄 `FileHashList.csv`:  
| MD5              | ファイルパス     | ファイル作成日時    |
|------------------|------------------|---------------------|
| d131dd02c5e6eec4 | dir1/example.png | 2026-09-01 12:34:56 |

（２） 📄 `RemoveDuplicatedOldFile.ps1`
このスクリプトを実行したら、  
TrashCan というフォルダーを作ってくれだぜ（＾▽＾）  
そんで、`FileHashList.csv` ファイル名の入力を促すようなプロンプトをだしてくれだぜ（＾▽＾）  
デフォルトは `FileHashList.csv` で（＾▽＾）  
そして、ハッシュ値が同じファイルのうち、ファイル作成日時が新しいものだけを残して、古いものは、  
現在のディレクトリーからみた相対ディレクトリーを保ったまま TrashCan フォルダーへ移動してくれだぜ（＾～＾）  
衝突するようなら、移動しなくていいぜ（＾▽＾）  
その場合、ログファイルを作ってくれると親切だな（＾▽＾）  
そんで、スクリプトの中にはコメントを書いておいてくれだぜ（＾▽＾）  
作ったらとりあえずリポジトリーの scripts フォルダーに `File/RemoveDuplicatedOldFile` フォルダーを作って、その下に置いておいてくれだぜ（＾～＾）  


［ー＿ー］  
PowerShell スクリプトの実行を許可させる時は、以下のようにしてくれだぜ［ー＿ー］  
```powershell
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "D:\github.com\muzudho\MyCollabWithAI\scripts\File\RemoveDuplicatedOldFile\FileHashList.ps1" -RootPath "Z:\muzudho-private-history\muzudho_backups"
```

## 回答チャット

