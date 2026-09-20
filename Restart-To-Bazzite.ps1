# Find Bazzite entry dynamically from UEFI firmware
$firmware = cmd /c "bcdedit /enum firmware"
$bazzite = $null
$current = $null

foreach ($line in ($firmware -split "\r?\n")) {
    if ($line.Trim().StartsWith("identifier")) {
        $parts = $line -split "\s+"
        if ($parts.Count -ge 2) {
            $current = $parts[1].Trim()
        }
    }
    if ($line -match "Bazzite|fedora|shimx64\.efi" -and $current) {
        $bazzite = $current
        break
    }
}

if ($bazzite) {
    Write-Host "Arming one-time boot to Bazzite ($bazzite)..." -ForegroundColor Cyan
    cmd /c "bcdedit /set {fwbootmgr} bootsequence $bazzite"
    Write-Host "Restarting into Bazzite..." -ForegroundColor Green
    shutdown /r /t 0
} else {
    Write-Error "Bazzite UEFI boot entry not found!"
    Pause
}
