# Building from source

Build on Windows x64 with Git, Visual Studio 2022 or Build Tools, the v143 x64 C++ compiler and MFC/ATL components, and a Windows 10 or 11 SDK. Setup uses the .NET Framework compiler supplied with Windows.

From the root of a Git checkout, run:

```powershell
powershell.exe -NoProfile -File .\scripts\Build.ps1
```

The script fetches CrystalDiskInfo at its pinned commit, checks and applies the integration patch, builds the x64 Standard Edition, and packages it in `dist\0.1.0`. It verifies the SHA-256 hash of the official 9.9.4 Standard Edition ZIP before using its resources. Pass `-StandardZip <path>` to use a local copy of that exact archive. Intermediate files live in `.build`.

Run the smoke check against the packaged setup and portable ZIP:

```powershell
powershell.exe -NoProfile -File .\scripts\Test-Package.ps1
```

The check verifies asset hashes, tests installation and retry in an isolated folder, confirms the shortcut target, and compares the installed executable with the portable one. To verify the device reader, launch the build on Windows with a supported SanDisk connected and inspect the **SanDisk diagnostic** table.
