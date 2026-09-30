# Licenses

This repository contains original code and forks of upstream projects. Each
component retains the license of its upstream source.

## Kernel modules

All kernel modules are licensed under the Linux kernel's license.

| Module                           | License          | Source                                                           |
| -------------------------------- | ---------------- | ---------------------------------------------------------------- |
| `modules/minibook_ec/`           | GPL-2.0-or-later | Original, Linux kernel module                                    |
| `modules/dptf_enabler/`          | GPL-2.0-or-later | Original, Linux kernel module                                    |
| `modules/i2c_designware_spklen/` | GPL-2.0-or-later | Original, Linux kernel module                                    |
| `modules/goodix_ts/`             | GPL-2.0          | Patched from upstream Linux `drivers/input/touchscreen/goodix.*` |

## Forked upstream projects

Each fork retains the license of its upstream project.

| Component           | License | Upstream                                                                   |
| ------------------- | ------- | -------------------------------------------------------------------------- |
| `thermal_daemon/`   | GPL-2.0 | [intel/thermal_daemon](https://github.com/intel/thermal_daemon)            |
| `iio-sensor-proxy/` | GPL-3.0 | [iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) |

## VBT patcher

| Component               | License | Notes                                        |
| ----------------------- | ------- | -------------------------------------------- |
| `vbt_patch/vbt_patch.c` | GPL-2.0 | Includes Linux kernel VBT definition headers |

## Scripts

All original shell scripts in `tools/` are licensed under the **Zero-Clause BSD
License (0BSD)**:

> Permission to use, copy, modify, and/or distribute this software for any
> purpose with or without fee is hereby granted.
>
> THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
> REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
> AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
> INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
> LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
> OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
> PERFORMANCE OF THIS SOFTWARE.

This applies to:

- `tools/check-status.sh`
- `tools/dptf-status.sh`
- `tools/gpu-status.sh`
- `tools/detect-hardware.sh`
- `tools/update-vbt-clock.sh`

## Documentation

All documentation in `docs/` and the top-level `README.md`, `GUIDE.md`,
`GUIDE-ADVANCED.md` and this
file are licensed under
**[Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)**.
