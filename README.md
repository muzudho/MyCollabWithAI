# ＡＩと共同作業するわたしの開発所

AI と共同作業するときの依頼文（プロンプト）と、作成したスクリプトを集めた開発所です。
PNG 画像の年月別整理や、重複ファイルの整理など、日々のファイル管理を PowerShell で自動化します。
依頼・回答の記録、使い方、開発日誌を残し、次の共同作業に役立てます。

開発中の画面のスクリーンショットは、現在未掲載です。

想定環境：Windows / PowerShell 5.1 以降。

## 一般_このプロジェクトに興味はないが関心はある人

AI にどのように作業を依頼し、何を作ったのかを公開しています。活動の様子は [2026 年９月の開発日誌](./docs/dev/log/2026/09.md) で読めます。

一般向けのお知らせは `docs/pub/` にまとめます。

## ユーザー_すぐ使いたい人

目的に合うスクリプトの説明を開いてください。

| やりたいこと | スクリプト・説明 |
|---|---|
| PNG 画像を作成年月のフォルダーへ整理する | [画像ファイルを年月フォルダーへ整理するスクリプト](./scripts/File/TransferPng/README.md) |
| 重複ファイルのうち新しいものを残し、古いものを TrashCan へ移動する | [重複ファイルを削除するスクリプト](./scripts/File/RemoveDuplicatedOldFile/README.md) |
| 複数の PowerShell スクリプトを順番に実行する | [PowerShell スクリプトの順次実行](./scripts/File/OpenPowerShellSequentialExecution/README.md) |
| 対話型スクリプトへの入力と応答待ちを自動化する | [PowerShell の対話を JSON で実行](./scripts/File/OpenPowerShellAutoDialogue/README.md) |

各ツールの説明はスクリプトと同じフォルダーにあります。共通の利用ガイドは `docs/user/` にまとめます。

## リサーチャー_しっかり理解したい人

画像整理と重複ファイル整理の説明には、元の依頼文と回答の記録もあります。入力する CSV の形式や、移動・重複判定の条件を確認できます。

* [画像整理の依頼・回答](./scripts/File/TransferPng/README.md)
* [重複ファイル整理の依頼・回答](./scripts/File/RemoveDuplicatedOldFile/README.md)

仕組みを詳しく説明する独立した資料は `docs/ref/` にまとめます。

## デベロッパー_開発に興味がある人

* [スクリプトのソースコード](./scripts/File/)
* [2026 年９月の開発日誌](./docs/dev/log/2026/09.md)
* [開発日誌を依頼するプロンプト例](./docs/dev/development-log-prompt.md)
* [GitHub リポジトリーの Web サイト設計](./docs/dev/github-repository-website-design/README.md)

開発方針、共同作業の例、開発日誌は `docs/dev/` にまとめます。
