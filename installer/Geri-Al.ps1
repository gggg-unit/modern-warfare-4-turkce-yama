param([switch]$NoGui)
$ErrorActionPreference = 'Stop'
function Get-PatchHash([string]$LiteralPath, [string]$Algorithm = 'SHA256') {
    $stream = [IO.File]::OpenRead($LiteralPath)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [pscustomobject]@{Hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')} }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Restore-Patch {
    $backup = (Get-Item -LiteralPath $PSScriptRoot).FullName
    $state = Get-Content -LiteralPath (Join-Path $backup 'kurulum-kaydi.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $target = (Get-Item -LiteralPath $state.gameDirectory).FullName.TrimEnd('\')
    if ((Split-Path -Parent $backup) -ne $target -or (Split-Path -Leaf $backup) -notlike 'TurkceYama-Yedek-*') { throw 'Yedek konumu geçersiz.' }
    $allowed = @('dxgi.dll','sp26/dxgi.dll','sp26/trdata2.bin')
    if (@($state.files).Count -ne 3 -or @($state.files.path | Sort-Object -Unique).Count -ne 3) { throw 'Yedek kaydı geçersiz.' }
    if (@(Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase) }).Count) { throw 'Önce oyunu ve başlatıcısını kapatın.' }
    foreach ($part in @($target,(Join-Path $target 'sp26'),$backup,(Join-Path $backup 'sp26'))) {
        if ((Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Bağlantı yolu desteklenmiyor.' }
    }
    foreach ($row in $state.files) {
        if ($allowed -cnotcontains $row.path) { throw 'Geçersiz yedek yolu.' }
        $destination = Join-Path $target $row.path
        $saved = Join-Path $backup $row.path
        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Hedef normal dosya değil.' }
            $hash = (Get-PatchHash -LiteralPath $destination -Algorithm SHA256).Hash
            if ($hash -ne $row.installedSHA256 -and $hash -ne $row.originalSHA256) { throw "Kurulumdan sonra değiştirilmiş dosya var: $($row.path). Otomatik geri alınmadı." }
        }
        if ($row.existed) {
            if (-not (Test-Path -LiteralPath $saved -PathType Leaf) -or (Get-PatchHash -LiteralPath $saved -Algorithm SHA256).Hash -ne $row.originalSHA256) { throw "Yedek doğrulanamadı: $($row.path)" }
            if ((Get-Item -LiteralPath $saved -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Yedek normal dosya değil.' }
        }
    }
    foreach ($row in $state.files) {
        $destination = Join-Path $target $row.path
        if ($row.existed) {
            Copy-Item -LiteralPath (Join-Path $backup $row.path) -Destination $destination -Force
            if ((Get-PatchHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $row.originalSHA256) { throw 'Geri yükleme doğrulanamadı.' }
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
    }
    return 'Yama kurulumu geri alındı.'
}
if ($NoGui) { Restore-Patch; exit }
Add-Type -AssemblyName System.Windows.Forms
try { [Windows.Forms.MessageBox]::Show((Restore-Patch),'gggg-unit','OK','Information') | Out-Null }
catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Geri alma tamamlanamadı','OK','Error') | Out-Null; exit 1 }
