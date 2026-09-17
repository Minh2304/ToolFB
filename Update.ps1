[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = $env:TOOLFB_DIR
if (-not $root -or -not (Test-Path $root)) {
    $root = $null
    if ($env:SCRIPT_DIR -and (Test-Path $env:SCRIPT_DIR)) {
        $root = $env:SCRIPT_DIR
    } elseif ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $root = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if (-not $root) {
        $root = (Get-Location).Path
    }
}
$root = $root.TrimEnd('\')

Write-Host ""
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host "           HỆ THỐNG TỰ ĐỘNG CẬP NHẬT TOOLFB (CHROME EXTENSIONS)        " -ForegroundColor Cyan
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------------------------------
# BƯỚC 1: LẤY THÔNG TIN ĐỊNH DANH MÁY TÍNH & BẢO TOÀN 100% KHÔNG BỊ MẤT
# -------------------------------------------------------------------------
$savedMachineId = $null
$savedRawGuid = $null

# 1.1 Tìm mã máy đã lưu trước đó nếu có
$searchPaths = @(
    (Join-Path $root "device_identity.json"),
    (Join-Path $root "AutoPost\device_identity.json"),
    (Join-Path $root "Sumary\device_identity.json"),
    (Join-Path $root "AutoPost_obfuscated\device_identity.json"),
    (Join-Path $root "Sumary_obfuscated\device_identity.json"),
    (Join-Path $root "extension_auto_poster\device_identity.json"),
    (Join-Path $root "extension_auto_poster_obfuscated\device_identity.json")
)

foreach ($sp in $searchPaths) {
    if (Test-Path $sp) {
        try {
            $content = Get-Content -Path $sp -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($content -and $content.machine_id -and ($content.machine_id -like "PC-WIN-*")) {
                $savedMachineId = $content.machine_id
                $savedRawGuid = $content.raw_guid
                break
            }
        } catch { }
    }
}

# 1.2 Nếu chưa từng lưu, lấy từ Windows MachineGuid hoặc phần cứng
if (-not $savedMachineId) {
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction SilentlyContinue
        if ($reg -and $reg.MachineGuid) {
            $savedRawGuid = [string]$reg.MachineGuid
        }
    } catch { }

    if (-not $savedRawGuid) {
        try {
            $cs = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
            if ($cs -and $cs.UUID) {
                $savedRawGuid = [string]$cs.UUID
            }
        } catch { }
    }

    if (-not $savedRawGuid) {
        $savedRawGuid = [System.Guid]::NewGuid().ToString()
    }

    $clean = ($savedRawGuid -replace '[^a-zA-Z0-9]', '').ToUpper()
    while ($clean.Length -lt 12) { $clean += '0' }
    $savedMachineId = "PC-WIN-$($clean.Substring(0,4))-$($clean.Substring(4,4))-$($clean.Substring(8,4))"
}

# Lưu ngay định danh vào thư mục hiện tại
$identityData = @{
    machine_id = $savedMachineId
    raw_guid   = $savedRawGuid
    updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
$jsonString = $identityData | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$localIdentityPath = Join-Path $root "device_identity.json"
[System.IO.File]::WriteAllText($localIdentityPath, $jsonString, $utf8NoBom)

# Tự động sao chép mã máy vào Clipboard để người dùng dán (Ctrl+V) vào tool
try {
    Set-Clipboard -Value $savedMachineId
} catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.Clipboard]::SetText($savedMachineId)
    } catch { }
}

Write-Host "   [*] MÃ MÁY CỦA BẠN: " -NoNewline -ForegroundColor White
Write-Host $savedMachineId -ForegroundColor Yellow
Write-Host "   [V] ĐÃ LƯU ĐỊNH DANH MÁY VÀ COPY VÀO BỘ NHỚ TẠM (CLIPBOARD)!" -ForegroundColor Green
Write-Host ""

# -------------------------------------------------------------------------
# BƯỚC 2: TẢI BẢN MỚI NHẤT CỦA 2 TOOL (ĐÃ MÃ HOÁ) TỪ NHÁNH RELEASE
# -------------------------------------------------------------------------
$updateSuccess = $false
$hasGit = $false
try {
    $gitVer = git --version 2>&1
    if ($LASTEXITCODE -eq 0) { $hasGit = $true }
} catch { }

$isGitRepo = Test-Path (Join-Path $root ".git")

# Cách 2.1: Nếu đang trong Git repo, fetch từ nhánh release
if ($hasGit -and $isGitRepo) {
    Write-Host "   [*] Đang kiểm tra bản cập nhật trên Git (nhánh 'release')..." -ForegroundColor Cyan
    $fetchOut = git fetch origin release 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   [V] Đã tìm thấy nhánh 'release' trên GitHub!" -ForegroundColor Green
        
        $targetFolders = @("AutoPost", "Sumary", "AutoPost_obfuscated", "Sumary_obfuscated", "extension_auto_poster", "extension_auto_poster_obfuscated")
        $foldersToCheckout = @()
        foreach ($f in $targetFolders) {
            $foldersToCheckout += $f
        }

        $checkoutOut = git checkout --force origin/release -- $foldersToCheckout 2>&1
        if ($LASTEXITCODE -eq 0) {
            $updateSuccess = $true
            Write-Host "   [V] Đã đồng bộ mã nguồn 2 extension từ nhánh 'release'!" -ForegroundColor Green
        }
    }
}

# Cách 2.2: Tải file nén zip trực tiếp từ nhánh release trên GitHub
if (-not $updateSuccess) {
    Write-Host "   [*] Đang tải 2 Tool đã mã hóa mới nhất từ nhánh 'release' trên GitHub..." -ForegroundColor Cyan
    $zipUrl = "https://github.com/Minh2304/ToolFB/archive/refs/heads/release.zip"
    $tempZip = Join-Path $env:TEMP "ToolFB_release_update.zip"
    $tempExtract = Join-Path $env:TEMP "ToolFB_release_extracted"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $headers = @{}
        if ($env:GITHUB_TOKEN) {
            $headers["Authorization"] = "token $($env:GITHUB_TOKEN)"
        }

        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -Headers $headers -TimeoutSec 45 -ErrorAction Stop
        
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        $extractedRoot = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
        if ($extractedRoot) {
            # Tìm nguồn 2 tool trong gói nén
            $srcPoster = $null
            $srcSumary = $null

            # Ưu tiên thư mục obfuscated hoặc thư mục chính
            $candidatePoster = @(
                (Join-Path $extractedRoot.FullName "AutoPost"),
                (Join-Path $extractedRoot.FullName "AutoPost_obfuscated"),
                (Join-Path $extractedRoot.FullName "extension_auto_poster"),
                (Join-Path $extractedRoot.FullName "extension_auto_poster_obfuscated")
            )
            foreach ($p in $candidatePoster) {
                if (Test-Path $p) { $srcPoster = $p; break }
            }

            $candidateSumary = @(
                (Join-Path $extractedRoot.FullName "Sumary"),
                (Join-Path $extractedRoot.FullName "Sumary_obfuscated")
            )
            foreach ($s in $candidateSumary) {
                if (Test-Path $s) { $srcSumary = $s; break }
            }

            # Sao chép AutoPost vào thư mục hiện tại
            if ($srcPoster) {
                $destPoster = Join-Path $root "AutoPost"
                if (-not (Test-Path $destPoster)) { New-Item -ItemType Directory -Path $destPoster -Force | Out-Null }
                Copy-Item -Path "$srcPoster\*" -Destination $destPoster -Recurse -Force
                
                # Nếu người dùng có thư mục _obfuscated, cập nhật luôn
                $destPosterObf = Join-Path $root "AutoPost_obfuscated"
                if (Test-Path $destPosterObf) {
                    Copy-Item -Path "$srcPoster\*" -Destination $destPosterObf -Recurse -Force
                }
            }

            # Sao chép Sumary vào thư mục hiện tại
            if ($srcSumary) {
                $destSumary = Join-Path $root "Sumary"
                if (-not (Test-Path $destSumary)) { New-Item -ItemType Directory -Path $destSumary -Force | Out-Null }
                Copy-Item -Path "$srcSumary\*" -Destination $destSumary -Recurse -Force

                # Nếu người dùng có thư mục _obfuscated, cập nhật luôn
                $destSumaryObf = Join-Path $root "Sumary_obfuscated"
                if (Test-Path $destSumaryObf) {
                    Copy-Item -Path "$srcSumary\*" -Destination $destSumaryObf -Recurse -Force
                }
            }

            $updateSuccess = $true
            Write-Host "   [V] Đã tải và giải nén 2 Tool về thư mục thành công!" -ForegroundColor Green
        }
    } catch {
        Write-Host "   [!] Lỗi khi tải trực tiếp: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Message -like "*404*") {
            Write-Host "   [i] Gợi ý: Nếu repo đang ở chế độ Private, vui lòng set repository sang Public hoặc thiết lập biến môi trường GITHUB_TOKEN." -ForegroundColor Yellow
        }
    } finally {
        if (Test-Path $tempZip) { Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# -------------------------------------------------------------------------
# BƯỚC 3: ĐỒNG BỘ ĐỊNH DANH MÁY VÀO 2 EXTENSION ĐỂ CHROME TỰ NHẬN DIỆN
# -------------------------------------------------------------------------
$restoreFolders = @(
    (Join-Path $root "AutoPost"),
    (Join-Path $root "Sumary"),
    (Join-Path $root "AutoPost_obfuscated"),
    (Join-Path $root "Sumary_obfuscated"),
    (Join-Path $root "extension_auto_poster"),
    (Join-Path $root "extension_auto_poster_obfuscated")
)

$syncedList = @()
foreach ($folder in $restoreFolders) {
    if (Test-Path $folder) {
        $targetFile = Join-Path $folder "device_identity.json"
        [System.IO.File]::WriteAllText($targetFile, $jsonString, $utf8NoBom)
        $syncedList += (Split-Path -Leaf $folder)
    }
}

Write-Host ""
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host "                   KẾT QUẢ CẬP NHẬT TOOLFB                             " -ForegroundColor Green
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host ""
if ($updateSuccess) {
    Write-Host "   [V] TRẠNG THÁI: TẢI & CẬP NHẬT 2 TOOL THÀNH CÔNG!" -ForegroundColor Green
} else {
    Write-Host "   [!] TRẠNG THÁI: CHƯA TẢI ĐƯỢC BẢN MỚI TỪ GITHUB (KIỂM TRA LẠI KẾT NỐI/REPO)" -ForegroundColor Yellow
}
Write-Host "   [V] ĐÃ ĐỒNG BỘ MÃ MÁY VÀO: $($syncedList -join ', ')" -ForegroundColor Cyan
Write-Host "   [V] MÃ MÁY HIỆN TẠI : " -NoNewline -ForegroundColor White
Write-Host "$savedMachineId (ĐÃ LƯU VÀ CÓ SẴN TRONG CLIPBOARD)" -ForegroundColor Yellow
Write-Host ""
Write-Host "   -> HƯỚNG DẪN DÙNG TOOL TRÊN TRÌNH DUYỆT CHROME:" -ForegroundColor Cyan
Write-Host "      1. Mở trình duyệt Chrome, vào địa chỉ: chrome://extensions" -ForegroundColor White
Write-Host "      2. Bật công tắc 'Chế độ dành cho nhà phát triển' (Developer mode)" -ForegroundColor White
Write-Host "      3. NẾU LẦN ĐẦU CÀI TOOL:" -ForegroundColor Yellow
Write-Host "         - Bấm 'Tải tiện ích đã giải nén' (Load unpacked)" -ForegroundColor White
Write-Host "         - Chọn lần lượt 2 thư mục 'AutoPost' và 'Sumary' trong thư mục này" -ForegroundColor White
Write-Host "      4. NẾU ĐÃ CÀI VÀ VỪA CẬP NHẬT:" -ForegroundColor Yellow
Write-Host "         - Chỉ cần bấm nút 'Tải lại' (biểu tượng xoay tròn) của 2 extension" -ForegroundColor White
Write-Host "      5. Mở tiện ích lên, mã máy sẽ được tự động nhận diện để đăng nhập!" -ForegroundColor Green
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host ""
