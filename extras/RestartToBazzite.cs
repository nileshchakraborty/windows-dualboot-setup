using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace RestartToBazziteApp
{
    static class Program
    {
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
                ProcessStartInfo bcd = new ProcessStartInfo
                {
                    FileName = "bcdedit.exe",
                    Arguments = string.Format("/set {{fwbootmgr}} bootsequence {0}", bazziteGuid),
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                using (Process p = Process.Start(bcd))
                {
                    p.WaitForExit(5000);
                }

                // 4. Trigger Restart
                ProcessStartInfo shutdown = new ProcessStartInfo
                {
                    FileName = "shutdown.exe",
                    Arguments = "/r /t 0",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(shutdown);
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
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "bcdedit.exe",
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
                         line.IndexOf("shimx64.efi", StringComparison.OrdinalIgnoreCase) >= 0) &&
                        !string.IsNullOrEmpty(currentGuid))
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
