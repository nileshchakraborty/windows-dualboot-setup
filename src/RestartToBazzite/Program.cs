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
                        return new BootEntry { Guid = currentGuid, Description = currentDesc, Path = currentPath };
                    }

                    // Start new entry
                    string[] parts = Regex.Split(trimmed, @"\s+");
                    currentGuid = parts.Length >= 2 ? parts[1].Trim() : null;
                    currentDesc = null;
                    currentPath = null;
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

                // Check for Bazzite / Fedora / shim bootloader markers
                if (line.IndexOf("bazzite", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    line.IndexOf("fedora", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    line.IndexOf("shimx64.efi", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    line.IndexOf("grubx64.efi", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    line.IndexOf("steamos", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    isTargetCandidate = true;
                }
            }

            // Check last entry in output
            if (isTargetCandidate && !string.IsNullOrEmpty(currentGuid) && GuidRegex.IsMatch(currentGuid))
            {
                return new BootEntry { Guid = currentGuid, Description = currentDesc, Path = currentPath };
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
        private const string AppTitle = "Restart to Bazzite";

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AttachConsole(int dwProcessId);
        private const int ATTACH_PARENT_PROCESS = -1;
        private static bool _hasConsole = false;

        [STAThread]
        public static int Main(string[] args)
        {
            _hasConsole = AttachConsole(ATTACH_PARENT_PROCESS);

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
                        "Usage: RestartToBazzite.exe [options]\n\n" +
                        "Options:\n" +
                        "  (no args)    One-click restart directly into Bazzite (default)\n" +
                        "  --check      Check UEFI firmware for Bazzite entry without rebooting\n" +
                        "  --confirm    Prompt with confirmation dialog before restarting\n" +
                        "  --help       Show this help message\n\n" +
                        "Ideal for pinning to ASUS Armoury Crate SE, Xbox App, or Winhance.";

                    ShowMessage(helpText, AppTitle, MessageBoxIcon.Information);
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

            // 2. Discover Bazzite UEFI Boot Entry
            BootEntry bazzite = FindBazziteBootEntry();
            if (bazzite == null || string.IsNullOrEmpty(bazzite.Guid))
            {
                string errorMsg =
                    "Bazzite boot entry was not found in UEFI firmware.\n\n" +
                    "Please verify that Bazzite is installed on the device and that its " +
                    "firmware entry contains 'Bazzite', 'fedora', or 'shimx64.efi'.\n\n" +
                    "Run 'bcdedit /enum firmware' in an elevated terminal to inspect entries.";

                ShowMessage(errorMsg, AppTitle, MessageBoxIcon.Error);
                return 1;
            }

            // 3. Handle check-only mode
            if (checkOnly)
            {
                string infoMsg = string.Format(
                    "Bazzite UEFI Boot Entry Detected:\n\nGUID: {0}\nDescription: {1}\nPath: {2}",
                    bazzite.Guid,
                    string.IsNullOrEmpty(bazzite.Description) ? "Bazzite" : bazzite.Description,
                    string.IsNullOrEmpty(bazzite.Path) ? "(firmware default)" : bazzite.Path);

                ShowMessage(infoMsg, AppTitle, MessageBoxIcon.Information);
                return 0;
            }

            // 4. Optional user confirmation
            if (askConfirm)
            {
                DialogResult dr = MessageBox.Show(
                    string.Format("Restart system into Bazzite now?\n\nTarget GUID: {0}", bazzite.Guid),
                    AppTitle,
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);

                if (dr != DialogResult.Yes)
                {
                    return 0;
                }
            }

            // 5. Arm Bazzite as one-time boot target (bootsequence)
            try
            {
                string bcdeditPath = Path.Combine(Environment.SystemDirectory, "bcdedit.exe");
                ProcessStartInfo bcd = new ProcessStartInfo
                {
                    FileName = bcdeditPath,
                    Arguments = BootFinder.BuildBcdEditArguments(bazzite.Guid),
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
                        ShowMessage(failMsg, AppTitle, MessageBoxIcon.Error);
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
                string exMsg = "Error executing restart to Bazzite:\n\n" + ex.Message;
                ShowMessage(exMsg, AppTitle, MessageBoxIcon.Error);
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

        private static BootEntry FindBazziteBootEntry()
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
