# PowerShell スクリプトの順次実行

`OpenPowerShellSequentialExecution.ps1` と同じフォルダーに `PowerShellScriptList.txt` を作り、実行したい `.ps1` ファイルを１行に１つずつ書きます。例えば：

```text
Z:\muzudho-private-history\muzudho_backups\document-a\FileHashList.ps1
Z:\muzudho-private-history\muzudho_backups\document-b\FileHashList.ps1
Z:\muzudho-private-history\muzudho_backups\grayscale-z\FileHashList.ps1
```

PowerShell から実行します。

```powershell
.\OpenPowerShellSequentialExecution.ps1
```

一覧ファイルを別の場所に置く場合：

```powershell
.\OpenPowerShellSequentialExecution.ps1 -ListPath 'C:\path\to\my-scripts.txt'
```

空行と `#` で始まる行は無視します。相対パスは一覧ファイルのあるフォルダーを基準にします。実行前に全てのパスを確認します。各スクリプトは別の PowerShell プロセスで動き、１つが終了してから次を実行します。終了コードが 0 以外なら、その行で中止します。
