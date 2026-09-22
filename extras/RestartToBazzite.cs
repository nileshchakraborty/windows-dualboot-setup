using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace RestartToBazziteApp
{
    static class Program
    {
        private static readonly Regex GuidRegex = new Regex(
            @"^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$",
            RegexOptions.Compiled);

        [STAThread]
        static void Main()
        {
            // 1. Verify / Request Administrator Privileges
            if (!IsAdministrator())
            {
                try
                {
                    ProcessStartInfo proc = new ProcessStartInfo
                    {
                        FileName = Application.ExecutablePath,
                        UseShellExecute = true,
                        Verb = "runas"
                    };
                    Process.Start(proc);
                }
                catch
                {
                    // User cancelled UAC prompt
                }
                return;
            }

            // 2. Discover Bazzite UEFI Boot Entry
            string bazziteGuid = FindBazziteGuid();
            if (string.IsNullOrEmpty(bazziteGuid))
            {
                MessageBox.Show(
                    "Bazzite boot entry was not found in UEFI firmware.\nPlease verify that Bazzite is installed on the system.",
                    "Restart to Bazzite",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                return;
            }

            // 3. Arm Bazzite as one-time boot target and restart
            try
            {
                string bcdedit = Path.Combine(Environment.SystemDirectory, "bcdedit.exe");
                ProcessStartInfo bcd = new ProcessStartInfo
                {
                    FileName = bcdedit,
                    Arguments = string.Format("/set {{fwbootmgr}} bootsequence {0}", bazziteGuid),
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
                        MessageBox.Show(
                            string.Format("Failed to arm Bazzite boot (Exit code {0}):\n{1}", p.ExitCode, err),
                            "Restart to Bazzite",
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Error
                        );
                        return;
                    }
                }

                // 4. Trigger Restart
                string shutdown = Path.Combine(Environment.SystemDirectory, "shutdown.exe");
                ProcessStartInfo shutdownInfo = new ProcessStartInfo
                {
                    FileName = shutdown,
                    Arguments = "/r /t 0",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(shutdownInfo);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Failed to arm Bazzite boot: " + ex.Message,
                    "Restart to Bazzite",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        }

        static bool IsAdministrator()
        {
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                WindowsPrincipal principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        static string FindBazziteGuid()
        {
            try
            {
                string bcdedit = Path.Combine(Environment.SystemDirectory, "bcdedit.exe");
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = bcdedit,
                    Arguments = "/enum firmware",
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true
                };

                string output;
                using (Process p = Process.Start(psi))
                {
                    output = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(5000);
                }

                string currentGuid = null;
                string[] lines = output.Split(new string[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
                foreach (string line in lines)
                {
                    string trimmed = line.Trim();
                    if (trimmed.StartsWith("identifier"))
                    {
                        string[] parts = Regex.Split(trimmed, @"\s+");
                        if (parts.Length >= 2)
                        {
                            currentGuid = parts[1].Trim();
                        }
                    }

                    if ((line.IndexOf("Bazzite", StringComparison.OrdinalIgnoreCase) >= 0 ||
                         line.IndexOf("fedora", StringComparison.OrdinalIgnoreCase) >= 0 ||
                         line.IndexOf("shimx64.efi", StringComparison.OrdinalIgnoreCase) >= 0 ||
                         line.IndexOf("grubx64.efi", StringComparison.OrdinalIgnoreCase) >= 0 ||
                         line.IndexOf("steamos", StringComparison.OrdinalIgnoreCase) >= 0) &&
                        !string.IsNullOrEmpty(currentGuid) && GuidRegex.IsMatch(currentGuid))
                    {
                        return currentGuid;
                    }
                }
            }
            catch
            {
            }
            return null;
        }
    }
}
