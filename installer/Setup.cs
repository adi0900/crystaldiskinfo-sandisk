using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("CrystalDiskInfo for SanDisk Setup")]
[assembly: AssemblyDescription("Per-user setup for CrystalDiskInfo for SanDisk")]

namespace CrystalDiskInfoSanDisk
{
    public static class PackageInstaller
    {
        public const string ShortcutName = "CrystalDiskInfo for SanDisk.lnk";
        private const string Payload = "CrystalDiskInfo.Payload.zip";
        private const string Executable = "DiskInfo64.exe";

        public static string Install(string root, string shortcutPath)
        {
            root = Path.GetFullPath(root);
            shortcutPath = Path.GetFullPath(shortcutPath);
            using (var mutex = new Mutex(false, @"Local\CrystalDiskInfo-SanDisk-Setup"))
            {
                try
                {
                    if (!mutex.WaitOne(0))
                    {
                        throw new InvalidOperationException("Another setup is already running.");
                    }
                }
                catch (AbandonedMutexException)
                {
                    // The previous setup stopped. A completed version can be reused.
                }

                try
                {
                    return InstallPackage(root, shortcutPath);
                }
                finally
                {
                    mutex.ReleaseMutex();
                }
            }
        }

        private static string InstallPackage(string root, string shortcutPath)
        {
            using (Stream resource = typeof(PackageInstaller).Assembly.GetManifestResourceStream(Payload))
            {
                if (resource == null)
                {
                    throw new InvalidDataException("The setup package is incomplete.");
                }

                using (var archive = new ZipArchive(resource, ZipArchiveMode.Read))
                {
                    ZipArchiveEntry versionEntry = archive.GetEntry("VERSION.txt");
                    if (versionEntry == null || versionEntry.Length > 64)
                    {
                        throw new InvalidDataException("The package version is missing or invalid.");
                    }

                    string version;
                    using (var reader = new StreamReader(versionEntry.Open()))
                    {
                        version = reader.ReadToEnd().Trim();
                    }
                    if (!Regex.IsMatch(version, @"\A\d+\.\d+\.\d+\z"))
                    {
                        throw new InvalidDataException("The package version is invalid.");
                    }

                    Directory.CreateDirectory(root);
                    string destination = Path.Combine(root, version);
                    if (!Directory.Exists(destination))
                    {
                        string staged = Path.Combine(root, ".stage-" + Guid.NewGuid().ToString("N"));
                        Directory.CreateDirectory(staged);
                        Extract(archive, staged);
                        VerifyFiles(staged, version);
                        Directory.Move(staged, destination);
                    }
                    VerifyFiles(destination, version);

                    string exe = Path.Combine(destination, Executable);
                    WriteShortcut(shortcutPath, exe, destination, root);
                    return exe;
                }
            }
        }

        private static void Extract(ZipArchive archive, string directory)
        {
            string prefix = directory + Path.DirectorySeparatorChar;
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                string target = Path.GetFullPath(Path.Combine(directory, entry.FullName));
                if (entry.FullName.Contains(":") || !target.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException("The archive contains an invalid path.");
                }

                if (entry.Name.Length == 0)
                {
                    Directory.CreateDirectory(target);
                    continue;
                }

                Directory.CreateDirectory(Path.GetDirectoryName(target));
                using (Stream source = entry.Open())
                using (var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    source.CopyTo(output);
                }
            }
        }

        private static void VerifyFiles(string directory, string version)
        {
            string versionFile = Path.Combine(directory, "VERSION.txt");
            if (!File.Exists(Path.Combine(directory, Executable))
                || !File.Exists(Path.Combine(directory, @"CdiResource\dialog\Graph.html"))
                || !File.Exists(Path.Combine(directory, @"CdiResource\language\English.lang"))
                || !File.Exists(versionFile)
                || File.ReadAllText(versionFile).Trim() != version)
            {
                throw new InvalidDataException("The version folder is incomplete. Setup could not create a shortcut.");
            }
        }

        private static void WriteShortcut(string path, string exe, string workingDirectory, string root)
        {
            string folder = Path.GetDirectoryName(path);
            Directory.CreateDirectory(folder);
            string staged = Path.Combine(folder, Guid.NewGuid().ToString("N") + ".lnk");
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null)
            {
                throw new InvalidOperationException("Windows could not create a Start menu shortcut.");
            }

            dynamic shell = Activator.CreateInstance(shellType);
            try
            {
                if (File.Exists(path))
                {
                    dynamic existing = shell.CreateShortcut(path);
                    try
                    {
                        string target = existing.TargetPath;
                        if (String.IsNullOrWhiteSpace(target)
                            || !Path.GetFullPath(target).StartsWith(root + Path.DirectorySeparatorChar,
                                StringComparison.OrdinalIgnoreCase))
                        {
                            throw new InvalidOperationException("The Start menu shortcut already points to another app.");
                        }
                    }
                    finally
                    {
                        Marshal.FinalReleaseComObject(existing);
                    }
                }

                dynamic shortcut = shell.CreateShortcut(staged);
                try
                {
                    shortcut.TargetPath = exe;
                    shortcut.WorkingDirectory = workingDirectory;
                    shortcut.IconLocation = exe + ",0";
                    shortcut.Description = "CrystalDiskInfo with SanDisk Extreme 55DD diagnostics";
                    shortcut.Save();
                }
                finally
                {
                    Marshal.FinalReleaseComObject(shortcut);
                }
            }
            finally
            {
                Marshal.FinalReleaseComObject(shell);
            }

            if (File.Exists(path))
            {
                File.Replace(staged, path, null);
            }
            else
            {
                File.Move(staged, path);
            }
        }
    }

    internal static class Setup
    {
        private const string Title = "CrystalDiskInfo for SanDisk Setup";

        [STAThread]
        private static int Main()
        {
            if (MessageBox.Show("Install CrystalDiskInfo for SanDisk for your Windows account?",
                Title, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
            {
                return 0;
            }

            try
            {
                string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    @"Programs\CrystalDiskInfo-SanDisk");
                string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                PackageInstaller.Install(root, Path.Combine(programs, PackageInstaller.ShortcutName));
                MessageBox.Show("Installed. Open CrystalDiskInfo for SanDisk from the Start menu.",
                    Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 0;
            }
            catch (Exception error)
            {
                MessageBox.Show(error.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
