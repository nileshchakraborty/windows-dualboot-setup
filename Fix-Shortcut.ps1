$wscript = New-Object -ComObject WScript.Shell
$desktopPaths = @(
    [Environment]::GetFolderPath("Desktop"),
    "C:\Users\Public\Desktop",
    "C:\Users\niles\OneDrive\Desktop"
)

foreach ($dt in $desktopPaths) {
    if (Test-Path $dt) {
        $shortcutPath = Join-Path $dt "Restart to Bazzite.lnk"
        if (Test-Path $shortcutPath) {
            Remove-Item $shortcutPath -Force
        }
        $shortcut = $wscript.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "C:\DualBoot\RestartToBazzite.exe"
        $shortcut.WorkingDirectory = "C:\DualBoot"
        $shortcut.Description = "Restart into Bazzite Gaming Mode"
        $shortcut.IconLocation = "C:\DualBoot\RestartToBazzite.exe,0"
        $shortcut.Save()

        # Set "Run as Administrator" bit on the .lnk file
        try {
            $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
            $bytes[0x15] = $bytes[0x15] -bor 0x20
            [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
            Write-Host "Created GUI shortcut at: $shortcutPath"
        } catch {
            Write-Warning "Could not set admin bit: $_"
        }
    }
}
