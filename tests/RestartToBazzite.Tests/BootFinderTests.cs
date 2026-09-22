using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using RestartToBazzite;

namespace RestartToBazzite.Tests
{
    [TestClass]
    public class BootFinderTests
    {
        private const string StandardAllyOutput = @"
Firmware Boot Manager
---------------------
identifier              {fwbootmgr}
displayorder            {bootmgr}
                        {7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}
timeout                 0

Windows Boot Manager
--------------------
identifier              {bootmgr}
device                  partition=\Device\HarddiskVolume1
path                    \EFI\Microsoft\Boot\bootmgfw.efi
description             Windows Boot Manager

Firmware Application (101fffff)
-------------------------------
identifier              {7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}
device                  partition=\Device\HarddiskVolume1
path                    \EFI\fedora\shimx64.efi
description             Bazzite
";

        [TestMethod]
        public void StandardAllyOutput_ReturnsCorrectGuidAndMetadata()
        {
            BootEntry entry = BootFinder.ParseBazziteBootEntry(StandardAllyOutput);

            Assert.IsNotNull(entry);
            Assert.AreEqual("{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}", entry.Guid);
            Assert.AreEqual("Bazzite", entry.Description);
            Assert.AreEqual(@"\EFI\fedora\shimx64.efi", entry.Path);
            Assert.AreEqual("Bazzite", entry.OsName);
        }

        [TestMethod]
        public void MatchViaFedoraInPath_ReturnsGuid()
        {
            string bcd = @"
identifier              {aaaa1111-0000-0000-0000-000000000000}
path                    \EFI\fedora\grubx64.efi
description             Linux
";
            BootEntry entry = BootFinder.ParseBazziteBootEntry(bcd);

            Assert.IsNotNull(entry);
            Assert.AreEqual("{aaaa1111-0000-0000-0000-000000000000}", entry.Guid);
            Assert.AreEqual("Bazzite", entry.OsName);
        }

        [TestMethod]
        public void MatchViaShimInPath_ReturnsGuid()
        {
            string bcd = @"
identifier              {bbbb2222-0000-0000-0000-000000000000}
path                    \EFI\BOOT\shimx64.efi
description             UEFI OS
";
            BootEntry entry = BootFinder.ParseBazziteBootEntry(bcd);

            Assert.IsNotNull(entry);
            Assert.AreEqual("{bbbb2222-0000-0000-0000-000000000000}", entry.Guid);
            Assert.AreEqual("Bazzite", entry.OsName);
        }

        [TestMethod]
        public void MatchViaSteamOs_ReturnsGuid()
        {
            string bcd = @"
identifier              {cccc3333-0000-0000-0000-000000000000}
path                    \EFI\steamos\grubx64.efi
description             SteamOS
";
            BootEntry entry = BootFinder.ParseBazziteBootEntry(bcd);

            Assert.IsNotNull(entry);
            Assert.AreEqual("{cccc3333-0000-0000-0000-000000000000}", entry.Guid);
            Assert.AreEqual("SteamOS", entry.Description);
            Assert.AreEqual("SteamOS", entry.OsName);
        }

        [TestMethod]
        public void CaseInsensitiveMatching_WorksForLabelsAndPaths()
        {
            string bcd = @"
identifier              {dddd4444-0000-0000-0000-000000000000}
path                    \EFI\BOOT\SHIMX64.EFI
description             BAZZITE (GAME MODE)
";
            BootEntry entry = BootFinder.ParseBazziteBootEntry(bcd);

            Assert.IsNotNull(entry);
            Assert.AreEqual("{dddd4444-0000-0000-0000-000000000000}", entry.Guid);
            Assert.AreEqual("BAZZITE (GAME MODE)", entry.Description);
        }

        [TestMethod]
        public void WindowsEntryWithBazziteKeyword_IsRejectedBecauseNotUuid()
        {
            // If Windows Boot Manager has a dual-boot note mentioning Bazzite,
            // {bootmgr} must NEVER be returned.
            string bcd = @"
identifier              {bootmgr}
path                    \EFI\Microsoft\Boot\bootmgfw.efi
description             Windows Boot Manager (dual-boot with Bazzite)

identifier              {7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}
path                    \EFI\fedora\shimx64.efi
description             Bazzite
";
            BootEntry entry = BootFinder.ParseBazziteBootEntry(bcd);

            Assert.IsNotNull(entry);
            Assert.AreEqual("{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}", entry.Guid);
        }

        [TestMethod]
        public void FirmwareBootMgr_IsNeverMatched()
        {
            string bcd = @"
identifier              {fwbootmgr}
displayorder            {bootmgr}
description             Firmware Boot Manager
";
            BootEntry entry = BootFinder.ParseBazziteBootEntry(bcd);
            Assert.IsNull(entry);
        }

        [TestMethod]
        public void OnlyWindowsInstalled_ReturnsNull()
        {
            string bcd = @"
identifier              {bootmgr}
path                    \EFI\Microsoft\Boot\bootmgfw.efi
description             Windows Boot Manager
";
            BootEntry entry = BootFinder.ParseBazziteBootEntry(bcd);
            Assert.IsNull(entry);
        }

        [TestMethod]
        public void EmptyOrNullInput_ReturnsNull()
        {
            Assert.IsNull(BootFinder.ParseBazziteBootEntry(null));
            Assert.IsNull(BootFinder.ParseBazziteBootEntry(""));
            Assert.IsNull(BootFinder.ParseBazziteBootEntry("   \r\n  \n  "));
        }

        [TestMethod]
        public void MultipleBazziteEntries_ReturnsFirstEntry()
        {
            string bcd = @"
identifier              {aaaa1111-0000-0000-0000-000000000000}
description             Bazzite Primary

identifier              {bbbb2222-0000-0000-0000-000000000000}
description             Bazzite Fallback
";
            BootEntry entry = BootFinder.ParseBazziteBootEntry(bcd);

            Assert.IsNotNull(entry);
            Assert.AreEqual("{aaaa1111-0000-0000-0000-000000000000}", entry.Guid);
            Assert.AreEqual("Bazzite Primary", entry.Description);
        }

        [TestMethod]
        public void BuildBcdEditArguments_FormatsCommandCorrectly()
        {
            string args = BootFinder.BuildBcdEditArguments("{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}");
            Assert.AreEqual("/set {fwbootmgr} bootsequence {7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}", args);
        }

        [TestMethod]
        public void GuidRegex_ValidatesProperUuids()
        {
            Assert.IsTrue(BootFinder.GuidRegex.IsMatch("{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}"));
            Assert.IsTrue(BootFinder.GuidRegex.IsMatch("{00000000-0000-0000-0000-000000000000}"));
            Assert.IsTrue(BootFinder.GuidRegex.IsMatch("{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}"));

            Assert.IsFalse(BootFinder.GuidRegex.IsMatch("{bootmgr}"));
            Assert.IsFalse(BootFinder.GuidRegex.IsMatch("{fwbootmgr}"));
            Assert.IsFalse(BootFinder.GuidRegex.IsMatch("{default}"));
            Assert.IsFalse(BootFinder.GuidRegex.IsMatch("7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963")); // Missing braces
        }
    }
}
