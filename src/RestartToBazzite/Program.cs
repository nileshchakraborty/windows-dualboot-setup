using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace RestartToBazzite
{
    public class BootEntry
    {
        public string Guid { get; set; }
        public string Description { get; set; }
        public string Path { get; set; }
        public string OsName { get; set; }
    }

    public static class BootFinder
    {
        public static readonly Regex GuidRegex = new Regex(
            @"^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$",
            RegexOptions.Compiled);

        public static BootEntry ParseBazziteBootEntry(string output)
        {
            if (string.IsNullOrEmpty(output))
            {
                return null;
            }

            string currentGuid = null;
            string currentDesc = null;
            string currentPath = null;
            string currentOsName = null;
            bool isTargetCandidate = false;

            string[] lines = output.Split(new string[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            foreach (string line in lines)
            {
                string trimmed = line.Trim();

                // Detect entry identifier
                if (trimmed.StartsWith("identifier", StringComparison.OrdinalIgnoreCase))
                {
                    // If previous entry was a match and a valid UUID, return it
                    if (isTargetCandidate && !string.IsNullOrEmpty(currentGuid) && GuidRegex.IsMatch(currentGuid))
                    {
                        return new BootEntry
                        {
                            Guid = currentGuid,
                            Description = currentDesc,
                            Path = currentPath,
                            OsName = currentOsName ?? "Linux"
                        };
                    }

                    // Start new entry
                    string[] parts = Regex.Split(trimmed, @"\s+");
                    currentGuid = parts.Length >= 2 ? parts[1].Trim() : null;
                    currentDesc = null;
                    currentPath = null;
                    currentOsName = null;
                    isTargetCandidate = false;
                    continue;
                }

                if (trimmed.StartsWith("description", StringComparison.OrdinalIgnoreCase))
                {
                    currentDesc = trimmed.Length >= 11 ? trimmed.Substring(11).Trim() : "";
                }
                else if (trimmed.StartsWith("path", StringComparison.OrdinalIgnoreCase))
                {
                    currentPath = trimmed.Length >= 4 ? trimmed.Substring(4).Trim() : "";
                }

                // Check for SteamOS markers
                if (line.IndexOf("steamos", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    line.IndexOf("steamcl.efi", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    isTargetCandidate = true;
                    if (string.IsNullOrEmpty(currentOsName))
                    {
                        currentOsName = "SteamOS";
                    }
                }

                // Check for Bazzite / Fedora / shim bootloader markers
                if (line.IndexOf("bazzite", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    line.IndexOf("fedora", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    line.IndexOf("shimx64.efi", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    isTargetCandidate = true;
                    if (string.IsNullOrEmpty(currentOsName))
                    {
                        currentOsName = "Bazzite";
                    }
                }

                // Generic Linux grub loader marker
                if (line.IndexOf("grubx64.efi", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    isTargetCandidate = true;
                    if (string.IsNullOrEmpty(currentOsName))
                    {
                        currentOsName = "Linux";
                    }
                }
            }

            // Check last entry in output
            if (isTargetCandidate && !string.IsNullOrEmpty(currentGuid) && GuidRegex.IsMatch(currentGuid))
            {
                return new BootEntry
                {
                    Guid = currentGuid,
                    Description = currentDesc,
                    Path = currentPath,
                    OsName = currentOsName ?? "Linux"
                };
            }

            return null;
        }

        public static string BuildBcdEditArguments(string guid)
        {
            return string.Format("/set {{fwbootmgr}} bootsequence {0}", guid);
        }
    }

    public static class Program
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AttachConsole(int dwProcessId);
        private const int ATTACH_PARENT_PROCESS = -1;
        private static bool _hasConsole = false;

        [STAThread]
        public static int Main(string[] args)
        {
            _hasConsole = AttachConsole(ATTACH_PARENT_PROCESS);

            string exeName = Path.GetFileNameWithoutExtension(GetExecutablePath()).ToLowerInvariant();
            string defaultTitle = exeName.Contains("steamos") ? "Restart to SteamOS" : "Restart to Bazzite";

            // Parse optional command-line flags
            bool checkOnly = false;
            bool askConfirm = false;

            foreach (string arg in args)
            {
                string lower = arg.Trim().ToLowerInvariant();
                if (lower == "--check" || lower == "-c" || lower == "/check")
                {
                    checkOnly = true;
                }
                else if (lower == "--confirm" || lower == "/confirm")
                {
                    askConfirm = true;
                }
                else if (lower == "--help" || lower == "-h" || lower == "/?" || lower == "-?")
                {
                    string helpText =
                        string.Format("Usage: {0}.exe [options]\n\n", exeName) +
                        "Options:\n" +
                        "  (no args)    One-click restart directly into Bazzite or SteamOS (default)\n" +
                        "  --check      Check UEFI firmware for Bazzite/SteamOS entry without rebooting\n" +
                        "  --confirm    Prompt with confirmation dialog before restarting\n" +
                        "  --help       Show this help message\n\n" +
                        "Ideal for pinning to ASUS Armoury Crate SE, Xbox App, or Winhance on ROG Ally, Legion Go, or Steam Deck.";

                    ShowMessage(helpText, defaultTitle, MessageBoxIcon.Information);
                    return 0;
                }
            }

            // 1. Verify / Request Administrator Privileges
            if (!IsAdministrator())
            {
                try
                {
                    string exePath = GetExecutablePath();
                    ProcessStartInfo proc = new ProcessStartInfo
                    {
                        FileName = exePath,
                        Arguments = string.Join(" ", args),
                        UseShellExecute = true,
                        Verb = "runas"
                    };
                    Process.Start(proc);
                    return 0;
                }
                catch (Exception)
                {
                    // User canceled UAC prompt
                    return 1223; // ERROR_CANCELLED
                }
            }

            // 2. Discover Bazzite or SteamOS UEFI Boot Entry
            BootEntry targetOs = FindBazziteOrSteamOsBootEntry();
            string appTitle = targetOs != null && !string.IsNullOrEmpty(targetOs.OsName)
                ? string.Format("Restart to {0}", targetOs.OsName)
                : defaultTitle;

            if (targetOs == null || string.IsNullOrEmpty(targetOs.Guid))
            {
                string errorMsg =
                    "Neither Bazzite nor SteamOS boot entry was found in UEFI firmware.\n\n" +
                    "Please verify that Bazzite or SteamOS is installed on the device.\n\n" +
                    "Run 'bcdedit /enum firmware' in an elevated terminal to inspect entries.";

                ShowMessage(errorMsg, appTitle, MessageBoxIcon.Error);
                return 1;
            }

            // 3. Handle check-only mode
            if (checkOnly)
            {
                string infoMsg = string.Format(
                    "{0} UEFI Boot Entry Detected:\n\nGUID: {1}\nDescription: {2}\nPath: {3}",
                    targetOs.OsName,
                    targetOs.Guid,
                    string.IsNullOrEmpty(targetOs.Description) ? targetOs.OsName : targetOs.Description,
                    string.IsNullOrEmpty(targetOs.Path) ? "(firmware default)" : targetOs.Path);

                ShowMessage(infoMsg, appTitle, MessageBoxIcon.Information);
                return 0;
            }

            // 4. Optional user confirmation
            if (askConfirm)
            {
                DialogResult dr = MessageBox.Show(
                    string.Format("Restart system into {0} now?\n\nTarget GUID: {1}", targetOs.OsName, targetOs.Guid),
                    appTitle,
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);

                if (dr != DialogResult.Yes)
                {
                    return 0;
                }
            }

            // 5. Arm Bazzite / SteamOS as one-time boot target (bootsequence)
            try
            {
                string bcdeditPath = Path.Combine(Environment.SystemDirectory, "bcdedit.exe");
                ProcessStartInfo bcd = new ProcessStartInfo
                {
                    FileName = bcdeditPath,
                    Arguments = BootFinder.BuildBcdEditArguments(targetOs.Guid),
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using (Process p = Process.Start(bcd))
                {
                    string stdout = p.StandardOutput.ReadToEnd();
                    string stderr = p.StandardError.ReadToEnd();
                    p.WaitForExit(5000);

                    if (p.ExitCode != 0)
                    {
                        string err = !string.IsNullOrWhiteSpace(stderr) ? stderr.Trim() : stdout.Trim();
                        string failMsg = string.Format("Failed to set UEFI bootsequence (Exit code {0}):\n\n{1}", p.ExitCode, err);
                        ShowMessage(failMsg, appTitle, MessageBoxIcon.Error);
                        return p.ExitCode;
                    }
                }

                // 6. Trigger Immediate Restart
                string shutdownPath = Path.Combine(Environment.SystemDirectory, "shutdown.exe");
                ProcessStartInfo shutdown = new ProcessStartInfo
                {
                    FileName = shutdownPath,
                    Arguments = "/r /t 0",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(shutdown);
                return 0;
            }
            catch (Exception ex)
            {
                string exMsg = string.Format("Error executing restart to {0}:\n\n{1}", targetOs.OsName, ex.Message);
                ShowMessage(exMsg, appTitle, MessageBoxIcon.Error);
                return 1;
            }
        }

        private static void ShowMessage(string message, string title, MessageBoxIcon icon)
        {
            if (_hasConsole)
            {
                Console.WriteLine(message);
            }
            else
            {
                MessageBox.Show(message, title, MessageBoxButtons.OK, icon);
            }
        }

        private static string GetExecutablePath()
        {
            try
            {
                string path = Environment.GetCommandLineArgs()[0];
                if (File.Exists(path))
                {
                    return Path.GetFullPath(path);
                }
            }
            catch { }
            return Application.ExecutablePath;
        }

        private static bool IsAdministrator()
        {
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                WindowsPrincipal principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        private static BootEntry FindBazziteOrSteamOsBootEntry()
        {
            try
            {
                string bcdeditPath = Path.Combine(Environment.SystemDirectory, "bcdedit.exe");
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = bcdeditPath,
                    Arguments = "/enum firmware",
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                string output;
                using (Process p = Process.Start(psi))
                {
                    output = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(5000);
                }

                return BootFinder.ParseBazziteBootEntry(output);
            }
            catch (Exception)
            {
                // Fallback / ignore
            }

            return null;
        }
    }
}
