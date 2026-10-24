param([string]$GameDirectory, [switch]$NoGui)
$ErrorActionPreference = 'Stop'
function Get-PatchHash([string]$LiteralPath, [string]$Algorithm = 'SHA256') {
    $stream = [IO.File]::OpenRead($LiteralPath)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [pscustomobject]@{Hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')} }
    finally { $sha.Dispose(); $stream.Dispose() }
}
$packageRoot = $PSScriptRoot
$allowedFiles = @('dxgi.dll','sp26/dxgi.dll','sp26/trdata2.bin')
function Assert-OrdinaryPath([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        if ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Bağlantı yolu desteklenmiyor: $Path" }
    }
}
function Install-Patch([string]$SelectedDirectory) {
    if (-not $SelectedDirectory -or -not (Test-Path -LiteralPath $SelectedDirectory -PathType Container)) { throw 'Oyun klasörünü seçin.' }
    $target = (Get-Item -LiteralPath $SelectedDirectory).FullName.TrimEnd('\')
    foreach ($part in @($target,(Join-Path $target 'sp26'))) { Assert-OrdinaryPath $part }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'cod.exe') -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $target 'sp26\sp26-cod.exe') -PathType Leaf)) { throw 'cod.exe ve sp26\sp26-cod.exe dosyalarını içeren ana oyun klasörünü seçin.' }
    $running = @(Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($target + '\',[StringComparison]::OrdinalIgnoreCase) })
    if ($running.Count) { throw 'Kurulumdan önce oyunu ve başlatıcısını kapatın.' }
    $manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'dosyalar.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $rows = @($manifest.files)
    if ($rows.Count -ne 3 -or @($rows.path | Sort-Object -Unique).Count -ne 3) { throw 'Paket dosya listesi geçersiz.' }
    foreach ($row in $rows) {
        if ($allowedFiles -cnotcontains $row.path) { throw 'Geçersiz paket yolu.' }
        $source = Join-Path (Join-Path $packageRoot 'dosyalar') $row.path
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Get-PatchHash -LiteralPath $source -Algorithm SHA256).Hash -ne $row.sha256) { throw "Paket doğrulaması başarısız: $($row.path). ZIP paketini yeniden çıkarın." }
        $destination = Join-Path $target $row.path
        Assert-OrdinaryPath $destination
        if (Test-Path -LiteralPath $destination) {
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "Hedef normal dosya değil: $($row.path)" }
            if ($row.path.EndsWith('.dll') -and $manifest.knownLoaderHashes -notcontains (Get-PatchHash -LiteralPath $destination -Algorithm SHA256).Hash) { throw "Farklı bir yükleyici mevcut: $($row.path). Önce kullandığınız diğer modun kurulumunu kontrol edin." }
        }
    }
    $backup = Join-Path $target ('TurkceYama-Yedek-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item -ItemType Directory -Path $backup | Out-Null
    $state = @()
    foreach ($row in $rows) {
        $destination = Join-Path $target $row.path
        $existed = Test-Path -LiteralPath $destination -PathType Leaf
        $oldHash = $null
        if ($existed) {
            $saved = Join-Path $backup $row.path
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved) | Out-Null
            $oldHash = (Get-PatchHash -LiteralPath $destination -Algorithm SHA256).Hash
            Copy-Item -LiteralPath $destination -Destination $saved
            if ((Get-PatchHash -LiteralPath $saved -Algorithm SHA256).Hash -ne $oldHash) { throw 'Yedek doğrulanamadı; oyun dosyaları değiştirilmedi.' }
        }
        $state += [pscustomobject]@{path=$row.path;existed=$existed;originalSHA256=$oldHash;installedSHA256=$row.sha256}
    }
    [pscustomobject]@{version=$manifest.version;gameDirectory=$target;files=$state} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'kurulum-kaydi.json') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $packageRoot 'Geri-Al.ps1') -Destination $backup
    Copy-Item -LiteralPath (Join-Path $packageRoot 'Geri-Al.cmd') -Destination $backup
    $changed = @()
    try {
        foreach ($row in $rows) {
            $changed += $row.path
            $destination = Join-Path $target $row.path
            Copy-Item -LiteralPath (Join-Path (Join-Path $packageRoot 'dosyalar') $row.path) -Destination $destination -Force
            if ((Get-PatchHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $row.sha256) { throw "Kopya doğrulanamadı: $($row.path)" }
        }
    } catch {
        $failure = $_.Exception.Message
        $rollbackErrors = @()
        foreach ($relative in $changed) {
            try {
                $entry = $state | Where-Object { $_.path -eq $relative }
                $destination = Join-Path $target $relative
                if ($entry.existed) { Copy-Item -LiteralPath (Join-Path $backup $relative) -Destination $destination -Force }
                elseif (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
            } catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count) { throw "$failure`nGeri alma tamamlanamadı. Yedek: $backup" }
        throw "$failure`nDeğişiklikler geri alındı. Yedek: $backup"
    }
    return "Kurulum tamamlandı. Oyunu başlatabilirsiniz.`r`n`r`nYedek: $backup"
}
if ($NoGui) { Install-Patch $GameDirectory; exit }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Modern Warfare 4 Türkçe Yama — gggg-unit'
$form.ClientSize = New-Object Drawing.Size(640,240)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$intro = New-Object Windows.Forms.Label
$intro.SetBounds(20,18,600,56)
$intro.Text = 'Oyunu kapatın ve ana oyun klasörünü seçin. Mevcut yama dosyaları yedeklenir; kurulum çevrimdışı yapılır.'
$pathBox = New-Object Windows.Forms.TextBox
$pathBox.SetBounds(20,90,470,30)
if ($GameDirectory) { $pathBox.Text = $GameDirectory }
$browse = New-Object Windows.Forms.Button
$browse.SetBounds(500,87,120,34)
$browse.Text = 'Klasör seç'
$browse.Add_Click({
    $picker = New-Object Windows.Forms.FolderBrowserDialog
    $picker.Description = 'cod.exe ve sp26 klasörünü içeren ana oyun klasörünü seçin'
    if ($picker.ShowDialog() -eq 'OK') { $pathBox.Text = $picker.SelectedPath }
    $picker.Dispose()
})
$install = New-Object Windows.Forms.Button
$install.SetBounds(440,165,180,42)
$install.Text = 'Yedekle ve kur'
$install.Add_Click({
    $install.Enabled = $false
    try {
        $message = Install-Patch $pathBox.Text
        [Windows.Forms.MessageBox]::Show($message,'Kurulum tamamlandı','OK','Information') | Out-Null
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Kurulum tamamlanamadı','OK','Error') | Out-Null }
    finally { $install.Enabled = $true }
})
$form.Controls.AddRange(@($intro,$pathBox,$browse,$install))
[void]$form.ShowDialog()
$form.Dispose()
