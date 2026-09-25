# Third-Party Notices

This project is licensed under the MIT License (see [LICENSE](LICENSE)).

It incorporates material from the project listed below. The original copyright
notice and license terms are provided here as required.

---

## Microsoft IddSampleDriver

The driver framework in the `driver/` directory is derived from Microsoft's
official indirect display driver sample.

- **Project**: Windows Driver Samples — IndirectDisplay / IddSampleDriver
- **Source**: <https://github.com/microsoft/Windows-driver-samples/tree/main/video/IndirectDisplay>
- **Copyright**: Copyright (c) Microsoft Corporation
- **License**: Microsoft Public License (MS-PL)
- **License text**: <https://opensource.org/licenses/MS-PL>

Source files under `driver/` retain Microsoft's original copyright header.

### What was changed

This project modifies the sample as follows:

- Replaced the random `ContainerId` (`CoCreateGuid`) with a fixed GUID derived
  from the EDID identity, preventing orphaned monitor instances from
  accumulating on every driver reload.
- Embedded a custom EDID (vendor code `CVD`, monitor name `CustomVDD`).
- Expanded the monitor mode list to 27 modes
  (1080p / 1440p / 3440x1440 / 4K, each at 60–240 Hz).
- Extended the corresponding target mode list so the OS reports them.
- Made the INF self-contained so the driver can be installed outside of the
  Visual Studio build system.
- Added a custom installer and uninstaller.

### MS-PL summary

The Microsoft Public License is a permissive license. It permits modification
and redistribution, including for commercial purposes, provided that the
original copyright notice is retained. It does not grant any trademark rights
or patent rights.

---

## Summary of licenses

| Component | License |
|---|---|
| CustomVDD (this project) | MIT |
| Driver framework (`driver/`) | MS-PL (Microsoft Corporation) |

This project is an independent derivative work and is not affiliated with,
endorsed by, or sponsored by Microsoft.
