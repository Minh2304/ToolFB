[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Read-NativeMessage {
    $stdin = [Console]::OpenStandardInput()
    $lenBytes = New-Object byte[] 4
    $read = $stdin.Read($lenBytes, 0, 4)
    if ($read -lt 4) { return $null }
    $len = [BitConverter]::ToInt32($lenBytes, 0)
    if ($len -le 0 -or $len -gt 1048576) { return $null }

    $buf = New-Object byte[] $len
    $offset = 0
    while ($offset -lt $len) {
        $n = $stdin.Read($buf, $offset, $len - $offset)
        if ($n -le 0) { break }
        $offset += $n
    }
    $json = [System.Text.Encoding]::UTF8.GetString($buf, 0, $offset)
    try {
        return ($json | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-NativeMessage($obj) {
    $json = $obj | ConvertTo-Json -Compress -Depth 5
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $lenBytes = [BitConverter]::GetBytes([int]$bytes.Length)
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($lenBytes, 0, 4)
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

function Find-ExactFolder($msg) {
    $folderPath = [string]$msg.folderPath
    $folderName = [string]$msg.folderName
    $verifyFile = [string]$msg.verifyFileName
    if (-not $verifyFile) { $verifyFile = [string]$msg.markerFileName }

    if ($folderPath -and ($folderPath -like "*:*")) {
        if ($verifyFile) {
            $checkFile = Join-Path $folderPath $verifyFile
            if (Test-Path -LiteralPath $checkFile) {
                return $folderPath
            }
        }
    }

    $userProfile = $env:USERPROFILE
    $priorityRoots = @(
        (Join-Path $userProfile "Downloads"),
        (Join-Path $userProfile "Desktop"),
        (Join-Path $userProfile "Pictures"),
        (Join-Path $userProfile "Documents"),
        $userProfile
    )

    if ($verifyFile) {
        foreach ($root in $priorityRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            $directCheck = Join-Path $root $verifyFile
            if ((Split-Path $root -Leaf) -ieq $folderName -and (Test-Path -LiteralPath $directCheck)) {
                return $root
            }
            $subCheck = Join-Path (Join-Path $root $folderName) $verifyFile
            if (Test-Path -LiteralPath $subCheck) {
                return (Join-Path $root $folderName)
            }
            try {
                $found = Get-ChildItem -LiteralPath $root -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ieq $folderName -and (Test-Path -LiteralPath (Join-Path $_.FullName $verifyFile)) } |
                    Select-Object -First 1
                if ($found) { return $found.FullName }
            } catch {}
        }

        foreach ($drv in @("D:\", "E:\", "F:\", "G:\", "C:\")) {
            if (-not (Test-Path -LiteralPath $drv)) { continue }
            $subCheck = Join-Path (Join-Path $drv $folderName) $verifyFile
            if (Test-Path -LiteralPath $subCheck) {
                return (Join-Path $drv $folderName)
            }
            try {
                $found = Get-ChildItem -LiteralPath $drv -Directory -Depth 2 -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notin @("Windows", "Program Files", "Program Files (x86)", "ProgramData", "Users", '$Recycle.Bin', "node_modules") } |
                    ForEach-Object {
                        if ($_.Name -ieq $folderName -and (Test-Path -LiteralPath (Join-Path $_.FullName $verifyFile))) {
                            return $_.FullName
                        }
                        Get-ChildItem -LiteralPath $_.FullName -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -ieq $folderName -and (Test-Path -LiteralPath (Join-Path $_.FullName $verifyFile)) } |
                            Select-Object -First 1 -ExpandProperty FullName
                    } | Select-Object -First 1
                if ($found) { return $found }
            } catch {}
        }
    }

    if ($folderPath -and ($folderPath -like "*:*") -and (Test-Path -LiteralPath $folderPath)) {
        return $folderPath
    }

    foreach ($root in $priorityRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        if ((Split-Path $root -Leaf) -ieq $folderName) { return $root }
        $cand = Join-Path $root $folderName
        if (Test-Path -LiteralPath $cand) { return $cand }
    }

    return $folderPath
}

try {
    $msg = Read-NativeMessage
    if (-not $msg) {
        Write-NativeMessage @{ ok = $false; error = "Empty message" }
        exit 0
    }

    $action = ([string]$msg.action).ToUpper()
    $resolvedDir = Find-ExactFolder $msg

    if ($action -eq "OPEN_EXPLORER") {
        if ($resolvedDir -and (Test-Path -LiteralPath $resolvedDir)) {
            Start-Process "explorer.exe" -ArgumentList "`"$resolvedDir`""
            Start-Sleep -Milliseconds 500
            Write-NativeMessage @{ ok = $true; opened = $true; fullPath = $resolvedDir }
            exit 0
        }
        Write-NativeMessage @{ ok = $false; error = "Folder not found"; fullPath = $resolvedDir }
        exit 0
    }

    Write-NativeMessage @{ ok = [bool]$resolvedDir; fullPath = $resolvedDir }
} catch {
    Write-NativeMessage @{ ok = $false; error = $_.Exception.Message }
}

