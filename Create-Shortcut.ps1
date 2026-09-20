$wscript = New-Object -ComObject WScript.Shell
$desktopPaths = @(
    [Environment]::GetFolderPath("Desktop"),
    "C:\Users\Public\Desktop"
)
foreach ($dt in $desktopPaths) {
    if (Test-Path $dt) {
        $shortcut = $wscript.CreateShortcut((Join-Path $dt "Restart to Bazzite.lnk"))
        $shortcut.TargetPath = "C:\DualBoot\Restart-To-Bazzite.cmd"
        $shortcut.WorkingDirectory = "C:\DualBoot"
        $shortcut.Description = "Restart into Bazzite"
        $shortcut.IconLocation = "shell32.dll,220"
        $shortcut.Save()
        Write-Host "Created shortcut at: $(Join-Path $dt 'Restart to Bazzite.lnk')"
    }
}
