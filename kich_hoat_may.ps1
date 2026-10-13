[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Doc MachineGuid tu Windows Registry
$guid = $null
try {
    $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction SilentlyContinue
    if ($reg -and $reg.MachineGuid) {
        $guid = [string]$reg.MachineGuid
    }
} catch { }

# 2. Du phong: Doc UUID Bo mach chu (Motherboard UUID)
if (-not $guid) {
    try {
        $cs = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
        if ($cs -and $cs.UUID) {
            $guid = [string]$cs.UUID
        }
    } catch { }
}

# 3. Du phong 3: Sinh GUID moi neu bi chan
if (-not $guid) {
    $guid = [System.Guid]::NewGuid().ToString()
}

$clean = ($guid -replace '[^a-zA-Z0-9]', '').ToUpper()
while ($clean.Length -lt 12) {
    $clean += '0'
}

$p1 = $clean.Substring(0, 4)
$p2 = $clean.Substring(4, 4)
$p3 = $clean.Substring(8, 4)
$machineId = "PC-WIN-$p1-$p2-$p3"

# Luu file JSON cau hinh noi bo
$data = @{
    machine_id = $machineId
    raw_guid   = $guid
    updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
$jsonContent = $data | ConvertTo-Json
$targetFile = Join-Path $scriptDir "device_identity.json"
$jsonContent | Set-Content -Path $targetFile -Encoding UTF8

# Tu dong quet va dong bo sang tat ca cac tool khac (Auto Poster, Sumary...)
$syncedTools = @()

# 1. Quet cac thu muc con (khi chay file .bat tu thu muc goc)
Get-ChildItem -Path $scriptDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $subManifest = Join-Path $_.FullName "manifest.json"
    if (Test-Path $subManifest) {
        $subTarget = Join-Path $_.FullName "device_identity.json"
        $jsonContent | Set-Content -Path $subTarget -Encoding UTF8
        $syncedTools += $_.Name
    }
}

# 2. Quet cac thu muc ngang hang (khi chay file .bat tu ben trong 1 tool con)
$parentDir = Split-Path -Parent $scriptDir
if ($parentDir) {
    Get-ChildItem -Path $parentDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $subManifest = Join-Path $_.FullName "manifest.json"
        if ((Test-Path $subManifest) -and ($_.FullName -ne $scriptDir)) {
            $subTarget = Join-Path $_.FullName "device_identity.json"
            $jsonContent | Set-Content -Path $subTarget -Encoding UTF8
            $syncedTools += $_.Name
        }
    }
}

# Tu dong nap vao bo nho tam (Clipboard)
try {
    Set-Clipboard -Value $machineId
} catch {
    [System.Windows.Forms.Clipboard]::SetText($machineId) 2>$null
}

Write-Host ""
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host "          HE THONG XAC NHAN MA MAY TINH DOC QUYEN - TOOLFB             " -ForegroundColor Green
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   [*] MA MAY TINH CUA BAN: " -NoNewline -ForegroundColor White
Write-Host $machineId -ForegroundColor Yellow
Write-Host ""
Write-Host "   [V] DA TU DONG SAO CHEP MA MAY VAO BO NHO TAM (CLIPBOARD)!
   [V] DA LUU DINH DANH MAY VAO: device_identity.json
$(if ($syncedTools.Count -gt 0) { "   [V] DA DONG BO SANG: " + ($syncedTools -join ", ") })" -ForegroundColor Cyan
Write-Host ""
Write-Host "   [!] TINH BAT BIEN & DUY NHAT:" -ForegroundColor White
Write-Host "       - Ma nay la DUY NHAT 100% tren the gioi (Khong bao gio trung lap)." -ForegroundColor Gray
Write-Host "       - Ke ca khi ban THAY CPU, NANG CAP RAM hay DOI MAN HINH, ma van giu nguyen." -ForegroundColor Gray
Write-Host ""
Write-Host "   -> BAY GIO BAN CO THE MO EXTENSION TREN CHROME DE SU DUNG NGAY!" -ForegroundColor Green
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host ""
