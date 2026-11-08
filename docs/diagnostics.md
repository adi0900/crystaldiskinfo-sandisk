# SanDisk 55DD diagnostics

The reader identifies the SanDisk Extreme 55DD and checks its USB firmware revision before interpreting its vendor pages. The verified profile is the 1 TB model, USB ID `0781:55DD` and firmware `0010`. Other revisions may expose a different layout.

| Read-only source | Values |
| --- | --- |
| SCSI INQUIRY and unit serial page | Model, USB firmware revision, serial number |
| SanDisk LOG SENSE page `0x30` | Lifetime host reads at page offset `0x81`, a little-endian 32-bit GiB counter |
| SanDisk LOG SENSE page `0x31` | Internal firmware identifier at offset `0x41` |
| SanDisk LOG SENSE page `0x32` | Controller temperature at offset 7, NAND channels at 8–11, maximum at 12, minimum at 13, board sensors at 16 and 21 |
| SCSI MODE SENSE cache page `0x08` | Read-cache and write-back settings |
| Windows storage queries | Logical and physical sector sizes and TRIM status |

The vendor page layout comes from the [1 TB 55DD device investigation](https://github.com/smartmontools/smartmontools/issues/526). The reader checks page identifiers and lengths before decoding. CrystalDiskInfo's **Edit → Copy** includes the same diagnostic rows.

On the verified device, both USB logical units advertised the same vendor pages. Standard SATA, NVMe, and SCSI SMART queries did not produce lifetime hours, cycles, writes, wear, error history, or self-test results. Undocumented bytes are left undecoded. A lifetime read total cannot establish whether reads happened before purchase.
