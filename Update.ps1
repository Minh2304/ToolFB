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
Write-Host "           HE THONG TU DONG CAP NHAT TOOLFB (CHROME EXTENSIONS)        " -ForegroundColor Cyan
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------------------------------
# BUOC 1: LAY THONG TIN DINH DANH MAY TINH & BAO TOAN 100% KHONG BI MAT
# -------------------------------------------------------------------------
$savedMachineId = $null
$savedRawGuid = $null

$searchPaths = @(
    (Join-Path $root "device_identity.json"),
    (Join-Path $root "AutoPost\device_identity.json"),
    (Join-Path $root "Sumary\device_identity.json"),
    (Join-Path $root "PostVideo\device_identity.json"),
    (Join-Path $root "GenImage\device_identity.json"),
    (Join-Path $root "AutoPost_obfuscated\device_identity.json"),
    (Join-Path $root "Sumary_obfuscated\device_identity.json"),
    (Join-Path $root "PostVideo_obfuscated\device_identity.json"),
    (Join-Path $root "GenImage_obfuscated\device_identity.json"),
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

$identityData = @{
    machine_id = $savedMachineId
    raw_guid   = $savedRawGuid
    updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
$jsonString = $identityData | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$localIdentityPath = Join-Path $root "device_identity.json"
[System.IO.File]::WriteAllText($localIdentityPath, $jsonString, $utf8NoBom)

try {
    Set-Clipboard -Value $savedMachineId
} catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.Clipboard]::SetText($savedMachineId)
    } catch { }
}

Write-Host "   [*] MA MAY CUA BAN: " -NoNewline -ForegroundColor White
Write-Host $savedMachineId -ForegroundColor Yellow
Write-Host "   [V] DA LUU DINH DANH MAY VA COPY VAO BO NHO TAM (CLIPBOARD)!" -ForegroundColor Green
Write-Host ""

# -------------------------------------------------------------------------
# BUOC 2: TAI BAN MOI NHAT CUA BO TOOL (AUTOPOST, SUMARY, POSTVIDEO) TU RELEASE
# -------------------------------------------------------------------------
$updateSuccess = $false
$hasGit = $false
try {
    $gitVer = git --version 2>&1
    if ($LASTEXITCODE -eq 0) { $hasGit = $true }
} catch { }

$isGitRepo = Test-Path (Join-Path $root ".git")

# Cach 2.1: Neu dang trong Git repo, fetch tu nhanh release
if ($hasGit -and $isGitRepo) {
    Write-Host "   [*] Dang kiem tra ban cap nhat tren Git (nhanh 'release')..." -ForegroundColor Cyan
    $fetchOut = git fetch origin release 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   [V] Da tim thay nhanh 'release' tren GitHub!" -ForegroundColor Green

        $targetFolders = @("AutoPost", "Sumary", "PostVideo", "GenImage", "AutoPost_obfuscated", "Sumary_obfuscated", "PostVideo_obfuscated", "GenImage_obfuscated")
        try {
            $remoteDirs = git ls-tree -d --name-only origin/release 2>$null
            if ($LASTEXITCODE -eq 0 -and $remoteDirs) {
                foreach ($rd in ($remoteDirs -split "`r?`n")) {
                    $cleanRd = $rd.Trim()
                    if ($cleanRd -and ($targetFolders -notcontains $cleanRd)) {
                        $targetFolders += $cleanRd
                    }
                }
            }
        } catch { }

        $foldersToCheckout = @()
        foreach ($f in $targetFolders) {
            git cat-file -e "origin/release:$f" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $foldersToCheckout += $f
            }
        }

        if ($foldersToCheckout.Count -gt 0 -and ($foldersToCheckout -contains "GenImage")) {
            $checkoutOut = git checkout --force origin/release -- $foldersToCheckout 2>&1
            if ($LASTEXITCODE -eq 0) {
                $updateSuccess = $true
                Write-Host "   [V] Da dong bo ma nguon cac extension ($($foldersToCheckout -join ', ')) tu nhanh 'release'!" -ForegroundColor Green
            }
        }
    }
}

# Cach 2.2: Tai file nen zip truc tiep tu nhanh release tren GitHub
if (-not $updateSuccess) {
    Write-Host "   [*] Dang tai bo Tool (AutoPost, Sumary, PostVideo, GenImage) moi nhat tu GitHub..." -ForegroundColor Cyan
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
            $srcPoster = $null
            $srcSumary = $null
            $srcPostVideo = $null
            $srcGenImage = $null

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

            $candidatePostVideo = @(
                (Join-Path $extractedRoot.FullName "PostVideo"),
                (Join-Path $extractedRoot.FullName "PostVideo_obfuscated")
            )
            foreach ($v in $candidatePostVideo) {
                if (Test-Path $v) { $srcPostVideo = $v; break }
            }

            $candidateGenImage = @(
                (Join-Path $extractedRoot.FullName "GenImage"),
                (Join-Path $extractedRoot.FullName "GenImage_obfuscated")
            )
            foreach ($g in $candidateGenImage) {
                if (Test-Path $g) { $srcGenImage = $g; break }
            }

            if ($srcPoster) {
                $destPoster = Join-Path $root "AutoPost"
                if (-not (Test-Path $destPoster)) { New-Item -ItemType Directory -Path $destPoster -Force | Out-Null }
                Copy-Item -Path "$srcPoster\*" -Destination $destPoster -Recurse -Force

                $destPosterObf = Join-Path $root "AutoPost_obfuscated"
                if (Test-Path $destPosterObf) {
                    Copy-Item -Path "$srcPoster\*" -Destination $destPosterObf -Recurse -Force
                }
            }

            if ($srcSumary) {
                $destSumary = Join-Path $root "Sumary"
                if (-not (Test-Path $destSumary)) { New-Item -ItemType Directory -Path $destSumary -Force | Out-Null }
                Copy-Item -Path "$srcSumary\*" -Destination $destSumary -Recurse -Force

                $destSumaryObf = Join-Path $root "Sumary_obfuscated"
                if (Test-Path $destSumaryObf) {
                    Copy-Item -Path "$srcSumary\*" -Destination $destSumaryObf -Recurse -Force
                }
            }

            if ($srcPostVideo) {
                $destPostVideo = Join-Path $root "PostVideo"
                if (-not (Test-Path $destPostVideo)) { New-Item -ItemType Directory -Path $destPostVideo -Force | Out-Null }
                Copy-Item -Path "$srcPostVideo\*" -Destination $destPostVideo -Recurse -Force

                $destPostVideoObf = Join-Path $root "PostVideo_obfuscated"
                if (Test-Path $destPostVideoObf) {
                    Copy-Item -Path "$srcPostVideo\*" -Destination $destPostVideoObf -Recurse -Force
                }
            }

            if ($srcGenImage) {
                $destGenImage = Join-Path $root "GenImage"
                if (-not (Test-Path $destGenImage)) { New-Item -ItemType Directory -Path $destGenImage -Force | Out-Null }
                Copy-Item -Path "$srcGenImage\*" -Destination $destGenImage -Recurse -Force

                $destGenImageObf = Join-Path $root "GenImage_obfuscated"
                if (Test-Path $destGenImageObf) {
                    Copy-Item -Path "$srcGenImage\*" -Destination $destGenImageObf -Recurse -Force
                }
            }

            foreach ($updFile in @("Update.bat", "Update.ps1")) {
                $srcUpd = Join-Path $extractedRoot.FullName $updFile
                if (Test-Path $srcUpd) {
                    Copy-Item -Path $srcUpd -Destination (Join-Path $root $updFile) -Force -ErrorAction SilentlyContinue
                }
            }

            # Tu dong quet them bat ky thu muc Tool moi nao co chua manifest.json trong ban phat hanh
            Get-ChildItem -Path $extractedRoot.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $dirName = $_.Name
                $hasManifest = Test-Path (Join-Path $_.FullName "manifest.json")
                if ($hasManifest -and ($dirName -notlike "*_obfuscated")) {
                    $destTool = Join-Path $root $dirName
                    if (-not (Test-Path $destTool)) { New-Item -ItemType Directory -Path $destTool -Force | Out-Null }
                    Copy-Item -Path "$($_.FullName)\*" -Destination $destTool -Recurse -Force
                }
            }

            $updateSuccess = $true
            Write-Host "   [V] Da tai va giai nen bo 4 Tool (AutoPost, Sumary, PostVideo, GenImage) thanh cong!" -ForegroundColor Green
        }
    } catch {
        Write-Host "   [!] Loi khi tai truc tiep: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        if (Test-Path $tempZip) { Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# -------------------------------------------------------------------------
# BUOC 3: DONG BO DINH DANH MAY VAO CAC EXTENSION DE CHROME TU NHAN DIEN
# -------------------------------------------------------------------------
$restoreFolders = @(
    (Join-Path $root "AutoPost"),
    (Join-Path $root "Sumary"),
    (Join-Path $root "PostVideo"),
    (Join-Path $root "GenImage"),
    (Join-Path $root "AutoPost_obfuscated"),
    (Join-Path $root "Sumary_obfuscated"),
    (Join-Path $root "PostVideo_obfuscated"),
    (Join-Path $root "GenImage_obfuscated"),
    (Join-Path $root "extension_auto_poster"),
    (Join-Path $root "extension_auto_poster_obfuscated")
)

$syncedList = @()
Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ((Test-Path (Join-Path $_.FullName "manifest.json")) -or ($restoreFolders -contains $_.FullName)) {
        $targetFile = Join-Path $_.FullName "device_identity.json"
        [System.IO.File]::WriteAllText($targetFile, $jsonString, $utf8NoBom)
        if ($syncedList -notcontains $_.Name) {
            $syncedList += $_.Name
        }
    }
}

# -------------------------------------------------------------------------
# BUOC 4: DANG KY NATIVE MESSAGING HOST CHO GENIMAGE (MO FILE EXPLORER)
# -------------------------------------------------------------------------
function Get-ChromeUnpackedExtensionId([string]$folderPath) {
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($folderPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash($bytes)
    $chars = New-Object char[] 32
    for ($i = 0; $i -lt 16; $i++) {
        $b = $hash[$i]
        $hi = ($b -shr 4) -band 0x0F
        $lo = $b -band 0x0F
        $chars[$i * 2] = [char]([int][char]'a' + $hi)
        $chars[$i * 2 + 1] = [char]([int][char]'a' + $lo)
    }
    return -join $chars
}

try {
    $genImageDir = Join-Path $root "GenImage"
    if (Test-Path $genImageDir) {
        $batPath = Join-Path $genImageDir "native_host.bat"
        if (Test-Path $batPath) {
            $allowedOrigins = New-Object System.Collections.Generic.List[string]
            $candFolders = New-Object System.Collections.Generic.List[string]
            $candFolders.Add((Join-Path $root "GenImage"))
            $candFolders.Add((Join-Path $root "GenImage_obfuscated"))

            try {
                $browserRoots = @(
                    (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"),
                    (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"),
                    (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data"),
                    (Join-Path $env:LOCALAPPDATA "CocCoc\Browser\User Data")
                )
                foreach ($br in $browserRoots) {
                    if (Test-Path $br) {
                        $prefFiles = Get-ChildItem -Path $br -Include "Preferences","Secure Preferences" -Recurse -ErrorAction SilentlyContinue
                        foreach ($pf in $prefFiles) {
                            $txt = Get-Content $pf.FullName -Raw -ErrorAction SilentlyContinue
                            if ($txt -and ($txt -match "GenImage")) {
                                $pathMatches = [regex]::Matches($txt, '"path"\s*:\s*"([^"]*GenImage[^"]*)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                                foreach ($pm in $pathMatches) {
                                    $rawPath = $pm.Groups[1].Value -replace '\\\\', '\'
                                    if ($rawPath -and (-not $candFolders.Contains($rawPath))) {
                                        $candFolders.Add($rawPath)
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {}

            foreach ($cf in $candFolders) {
                $cleanCf = $cf.TrimEnd('\')
                if ($cleanCf.Length -ge 2) {
                    $upperDrive = $cleanCf.Substring(0, 1).ToUpper() + $cleanCf.Substring(1)
                    $lowerDrive = $cleanCf.Substring(0, 1).ToLower() + $cleanCf.Substring(1)
                    foreach ($variant in @($upperDrive, $lowerDrive)) {
                        $extId = Get-ChromeUnpackedExtensionId $variant
                        $originUrl = "chrome-extension://$extId/"
                        if (-not $allowedOrigins.Contains($originUrl)) {
                            $allowedOrigins.Add($originUrl)
                        }
                    }
                }
            }

            $nmManifest = @{
                name = "com.toolfb.genimage"
                description = "GenImage Windows Explorer Native Host"
                path = $batPath
                type = "stdio"
                allowed_origins = $allowedOrigins.ToArray()
            }
            $nmJson = $nmManifest | ConvertTo-Json -Depth 5
            $nmManifestPath = Join-Path $genImageDir "com.toolfb.genimage.json"
            [System.IO.File]::WriteAllText($nmManifestPath, $nmJson, $utf8NoBom)

            $regKeys = @(
                "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.toolfb.genimage",
                "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.toolfb.genimage",
                "HKCU:\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.toolfb.genimage",
                "HKCU:\Software\CocCoc\Browser\NativeMessagingHosts\com.toolfb.genimage"
            )
            foreach ($rk in $regKeys) {
                try {
                    if (-not (Test-Path $rk)) {
                        New-Item -Path $rk -Force | Out-Null
                    }
                    Set-ItemProperty -Path $rk -Name "(Default)" -Value $nmManifestPath -Force -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }
} catch {}

Write-Host ""
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host "                   KET QUA CAP NHAT TOOLFB                             " -ForegroundColor Green
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host ""
if ($updateSuccess) {
    Write-Host "   [V] TRANG THAI: TAI & CAP NHAT BO 4 TOOL THANH CONG!" -ForegroundColor Green
} else {
    Write-Host "   [!] TRANG THAI: CHUA TAI DUOC BAN MOI TU GITHUB (KIEM TRA KET NOI)" -ForegroundColor Yellow
}
Write-Host "   [V] DA DONG BO MA MAY VAO: $($syncedList -join ', ')" -ForegroundColor Cyan
Write-Host "   [V] MA MAY HIEN TAI : " -NoNewline -ForegroundColor White
Write-Host "$savedMachineId (DA LUU VA CO SAN TRONG CLIPBOARD)" -ForegroundColor Yellow
Write-Host ""
Write-Host "   -> HUONG DAN DUNG TOOL TREN TRINH DUYET CHROME:" -ForegroundColor Cyan
Write-Host "      1. Mo trinh duyet Chrome, vao dia chi: chrome://extensions" -ForegroundColor White
Write-Host "      2. Bat cong tac 'Che do danh cho nha phat trien' (Developer mode)" -ForegroundColor White
Write-Host "      3. Bam 'Tai tien ich da giai nen' (Load unpacked)" -ForegroundColor Yellow
Write-Host "         -> Chon lan luot cac thu muc: 'AutoPost', 'Sumary', 'PostVideo', 'GenImage'" -ForegroundColor White
Write-Host "      4. Neu da cai truoc do, chi can bam nut 'Tai lai' (Reload) tren tung extension!" -ForegroundColor Green
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host ""
