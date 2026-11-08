# CrystalDiskInfo for SanDisk

A community build of CrystalDiskInfo 9.9.4 that adds a diagnostic table for the SanDisk Extreme Portable SSD 55DD. It uses CrystalDiskInfo's existing detection and SMART readers for other supported disks.

## Download and install

1. Open the [latest release](https://github.com/adi0900/crystaldiskinfo-sandisk/releases/latest) on a Windows 10 or 11 x64 PC.
2. Download the `Setup-x64.exe` asset and run it. It installs for your Windows account.
3. Open **CrystalDiskInfo for SanDisk** from Start. Windows asks for administrator access when the app opens because CrystalDiskInfo reads physical disk diagnostics.

For portable use, download the ZIP, extract the entire folder, and open `DiskInfo64.exe` from it. The setup and patched executable are unsigned. The release includes SHA-256 checksums.

## What it reads

The added reader was verified on a **1 TB SanDisk Extreme 55DD**, USB ID `0781:55DD`, USB firmware `0010`, connected over UASP on Windows 11 x64. The app selects a supported SanDisk automatically when it opens.

| Source | Readings |
| --- | --- |
| SanDisk diagnostic logs | Lifetime host reads, controller and NAND temperatures, board sensors, recorded minimum and maximum temperature, internal firmware ID |
| Windows and SCSI device queries | Sector sizes, TRIM, read cache, write-back cache |
| Standard SMART | Health, power-on hours, power cycles, lifetime writes, wear, errors, and self-test history are shown as unavailable when the drive provides no verified reading |

The lifetime read counter uses a community-verified field map for this firmware. It gives a total without timestamps. See [diagnostic sources and limits](docs/diagnostics.md) for the page and field map.

## Project structure

| Path | Contents |
| --- | --- |
| [src/](src/) | The SanDisk SCSI diagnostic reader |
| [patches/](patches/) | CrystalDiskInfo integration against a pinned upstream commit |
| [installer/](installer/) | Per-user Windows setup |
| [scripts/](scripts/) | Build, packaging, and a release smoke check |
| [docs/](docs/) | Build instructions and diagnostic references |

See [Building from source](docs/build.md) to reproduce the release. The [license](LICENSE.txt) and [third-party notices](NOTICE.md) credit the upstream project and its bundled components.
