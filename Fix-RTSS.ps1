# Stop RTSS
Stop-Process -Name RTSS, RTSSHooksLoader64, RTSSHooksLoader32 -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Update Global profile
$globalPath = "C:\Program Files (x86)\RivaTuner Statistics Server\Profiles\Global"
if (Test-Path $globalPath) {
    $content = Get-Content $globalPath -Raw
    $content = $content -replace "UseDetours=0", "UseDetours=1"
    $content = $content -replace "HookDirect3D8=1", "HookDirect3D8=0"
    $content = $content -replace "HookDirectDraw=1", "HookDirectDraw=0"
    $content = $content -replace "EnableFloatingInjectionAddress=0", "EnableFloatingInjectionAddress=1"
    $content = $content -replace "EnableDynamicOffsetDetection=0", "EnableDynamicOffsetDetection=1"
    Set-Content -Path $globalPath -Value $content -Force
    Write-Host "Updated Global profile settings (Enabled Microsoft Detours hooking, disabled D3D8)." -ForegroundColor Green
}

# Clear stale FnOffsetCache in Config
$configPath = "C:\Program Files (x86)\RivaTuner Statistics Server\Profiles\Config"
if (Test-Path $configPath) {
    $lines = Get-Content $configPath
    $newLines = @()
    $skip = $false
    foreach ($line in $lines) {
        if ($line.StartsWith("[FnOffsetCache")) {
            $skip = $true
            continue
        }
        if ($line.StartsWith("[") -and $skip) {
            $skip = $false
        }
        if (-not $skip) {
            $newLines += $line
        }
    }
    Set-Content -Path $configPath -Value $newLines -Force
    Write-Host "Cleared stale FnOffsetCache in Config." -ForegroundColor Green
}

# Relaunch RTSS cleanly
$rtssExe = "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe"
if (Test-Path $rtssExe) {
    Start-Process -FilePath $rtssExe
    Write-Host "Restarted RTSS with clean Detours hook engine." -ForegroundColor Green
}
