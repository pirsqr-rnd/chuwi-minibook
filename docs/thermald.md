# Patched thermald

The `thermal_daemon/` directory contains a fork of Intel's
[thermald](https://github.com/intel/thermal_daemon) (v2.5.11) with
MiniBook-specific patches. Stock thermald does not work on this machine: the
BIOS ships DPTF firmware tables that are incomplete or locked in ways that
prevent the upstream adaptive engine from controlling thermals. This fork fixes
those gaps so that thermald can manage CPU power limits (PL1) based on
temperature readings from multiple sensors.

Without it, the N150 either throttles too early (stock BIOS TCC offset throttles
at 85 C) or runs unmanaged with no software thermal policy at all.

______________________________________________________________________

## Prerequisites

- `dptf_enabler` module loaded (unhides BIOS-gated DPTF devices)
- `minibook_ec` module loaded (see [minibook-ec.md](minibook-ec.md))
- `intel_rapl_common` module loaded
- CFG Lock disabled and TCC offset reduced (see below)

## Install

See [GUIDE.md](../GUIDE.md#3-thermald). The service unit runs
`thermald --systemd --dbus-enable --adaptive`; this build requires `--adaptive`
mode and will refuse to start without it.

## BIOS settings

Two hidden BIOS settings (see [GUIDE.md](../GUIDE.md#2-bios-tweaks) for how to
access them) affect how well thermald can do its job:

**CFG Lock** -- thermald adjusts CPU power limits at runtime, and CFG Lock
blocks those MSR writes entirely. Must be disabled.

**TCC Activation Offset** -- the factory setting of 20 makes the CPU start
hardware throttling at 85 C, which is too early. Reducing it to 10 moves that
point to 95 C, giving thermald more room to manage thermals in software before
the CPU's own emergency throttle kicks in.

## Verify it is working

```
journalctl -u thermald | grep minibook
```

All MiniBook-specific log messages are prefixed with `minibook:`. A healthy
startup looks like:

```
minibook: RAPL PL1 writable, current 15000000 uW (15000 mW)
minibook: TCC offset = 10 C, TjMax = 105 C, throttle at 95 C
minibook: activated Passive 1 UUID
minibook: overriding SEN3 trip from 55000 to 50000
minibook: PBAT[0]: tid=0 name=... part=... code=PL2PowerLimit arg=45000
minibook: PBCT[0]: target=0 conditions=3
minibook: adding minibook_soc passive trip at 80000 mC
minibook: adding minibook_charger passive trip at 60000 mC
```

**`RAPL PL1 write failed`** -- CFG Lock is still enabled. Go back to BIOS setup
and disable it (see above).

**`TCC offset is stock`** -- TCC Activation Offset is still at the factory
value. Go back to BIOS setup and reduce it to 10.

**`DPTF device ... not active`** -- the `dptf_enabler` module is not loaded or
failed. Load it first.

**`minibook_soc` or `minibook_charger` not found** -- the `minibook_ec` module
is not loaded. The EC thermal zones are optional -- thermald will still manage
DPTF zones (SEN3, TCPU) without them. See [minibook-ec.md](minibook-ec.md) for
installation.

______________________________________________________________________

## What the patches do

### Unlock the PPCC power range

The BIOS firmware advertises a PPCC (power control capabilities) table for the
CPU with min and max both set to 15 W. This locks thermald into a single power
level -- it cannot throttle. The patch detects this (max \<= min) and
substitutes a usable range:

| Parameter   | Value           |
| ----------- | --------------- |
| PL1 minimum | 8000 mW (8 W)   |
| PL1 maximum | 17000 mW (17 W) |
| Step size   | 500 mW          |

These come from the ITMT3 (Intelligent Thermal Management) table in the DPTF
firmware. The 8-17 W range gives thermald room to reduce power when hot and
restore it when cool. The step size controls the granularity of adjustments
(mostly cosmetic when PID control is enabled).

### Cap the SEN3 ambient trip point

SEN3 is the only working EC thermistor exposed through DPTF. It reads
ambient/chassis temperature from EC register 0x15 (TSR3). The firmware PSVT
table maps it as the passive cooling trigger for the CPU, but the default trip
temperature from the firmware (55 C) is too high -- by the time a slow-reacting
ambient sensor hits 55 C, the CPU has been running hot for a while.

The patch caps SEN3's passive trip at 50 C so PL1 throttling starts earlier.
This is the single most impactful tuning parameter. See "Tunable parameters"
below.

### Enable PID control on the RAPL cooling device

Stock thermald uses a step-based controller for RAPL: it increments or
decrements PL1 by fixed amounts. The patch enables PID (proportional-
integral-derivative) control instead, which produces smoother, faster
convergence to the target temperature.

The PID gains are:

| Gain | Value | Effect                                                  |
| ---- | ----- | ------------------------------------------------------- |
| Kp   | -1000 | 1 C overshoot reduces PL1 by ~1 W                       |
| Ki   | -100  | Sustained overshoot accumulates correction over time    |
| Kd   | -10   | Dampens rapid temperature swings to prevent oscillation |

The negative signs mean "overtemperature reduces power." The units are
millidegrees (error) to microwatts (output). With Kp = -1000, a 2 C overshoot
produces a proportional correction of -2 W.

The patch also overrides `control_begin()` on the RAPL cooling device to prevent
the PID integral term from being reset every polling cycle. Without this fix,
the integral never accumulates and the I-term is useless.

### Add minibook_ec thermal zones

The [minibook_ec](minibook-ec.md) kernel module exposes two thermal zones
(`minibook_soc` and `minibook_charger`) that are not part of DPTF and therefore
invisible to thermald's firmware table parsing. The patch installs passive trip
points on both zones, bound to the RAPL cooling device. Each zone gets two trips
(at the target temperature and 1 C above) following thermald's consolidation
pattern. See [minibook-ec.md](minibook-ec.md) for details on what these zones
measure.

### Activate the DPTF passive policy UUID

The kernel's `int3400_thermal` driver sometimes fails to activate a DPTF policy
UUID on its own, leaving the adaptive engine in a non-functional state. The
patch writes the Passive 1 UUID to sysfs at startup if no policy is currently
active.

### Parse and evaluate PBAT/PBCT power boss tables

The DPTF firmware contains Power Boss Action Tables (PBAT) and Power Boss
Condition Tables (PBCT) that define power limit overrides (PL2, PL4) conditioned
on AC/DC state and battery level. Stock thermald parses APAT/APCT (adaptive
performance tables) but ignores PBAT/PBCT. The patch adds parsing and periodic
evaluation so these power policies take effect.

On this machine, PBAT sets PL2 = 45 W and PL4 = 65 W regardless of battery
level.

### Evaluate battery percentage conditions

Stock thermald marks `Aggregate_power_percentage` as an unsupported condition
type, causing any PBCT rule that checks battery level to fail. The patch adds
evaluation via UPower, reading the actual battery percentage and comparing it
against the condition's threshold.

### Startup diagnostics

At startup, thermald runs two checks and logs the results:

- **RAPL PL1 write test**: writes the current PL1 value back to sysfs to verify
  the write succeeds. If it fails, CFG Lock is enabled and thermald cannot
  control power limits.
- **TCC offset check**: reads the current TCC (Thermal Control Circuit) offset
  and warns if it is still at the stock value of 20 C, which causes the CPU to
  throttle at 85 C instead of 95 C.

### Require adaptive mode

This build removes the non-adaptive fallback path. If `--adaptive` is not
passed, the binary exits immediately. This simplifies the code and prevents
accidentally running without DPTF table support.

______________________________________________________________________

## Tunable parameters

All tunable values are `#define` constants in
`thermal_daemon/src/thd_minibook_config.h`. Changing them requires rebuilding
thermald.

### Trip temperatures

| Constant                     | Default | Unit | What it controls              |
| ---------------------------- | ------- | ---- | ----------------------------- |
| `MINIBOOK_SEN3_TRIP_TEMP`    | 50000   | mC   | SEN3 ambient passive trip     |
| `MINIBOOK_SOC_TRIP_TEMP`     | 80000   | mC   | minibook_soc passive trip     |
| `MINIBOOK_CHARGER_TRIP_TEMP` | 60000   | mC   | minibook_charger passive trip |

`MINIBOOK_SEN3_TRIP_TEMP` is the most impactful. Lowering it makes throttling
start earlier (cooler chassis, lower sustained performance). Raising it lets the
system run hotter before intervention. The firmware default is 55 C; the patch
uses 50 C. Reasonable range: 45-55 C.

`MINIBOOK_SOC_TRIP_TEMP` controls when the fast-reacting SoC thermistor triggers
PL1 reduction. At 80 C on this external sensor, the CPU die is likely already in
the mid-90s. Lowering to 70 C is more conservative; raising above 85 C risks
approaching the TCC throttle point.

`MINIBOOK_CHARGER_TRIP_TEMP` protects against heat buildup during charging under
load. The charger idles around 55-56 C, so the trip must be above that to avoid
permanently clamping PL1 at the minimum. 60 C gives ~4 C of headroom before PID
intervention; the ACPI firmware's \_PSV for the charger area is 65 C. This only
matters when the charger is plugged in and the system is under sustained load
simultaneously.

### PL1 power range

| Constant                  | Default | Unit | What it controls              |
| ------------------------- | ------- | ---- | ----------------------------- |
| `MINIBOOK_PPCC_PL1_MIN`   | 8000    | mW   | Lowest PL1 thermald will set  |
| `MINIBOOK_PPCC_PL1_MAX`   | 17000   | mW   | Highest PL1 thermald will set |
| `MINIBOOK_PPCC_STEP_SIZE` | 500     | mW   | PL1 adjustment granularity    |

`MINIBOOK_PPCC_PL1_MIN` sets the floor. At 8 W the system is slow but
functional. Lowering to 6 W (the N150's fused TDP) squeezes out more cooling at
the cost of responsiveness. Raising it keeps the system faster under thermal
pressure but limits the cooling range.

`MINIBOOK_PPCC_PL1_MAX` sets the ceiling for sustained power. 17 W is above the
firmware's locked 15 W, giving the PID controller headroom. Raising it further
(e.g., 20 W) allows more sustained performance when thermals permit, but
generates more heat.

### PID gains

| Constant          | Default | What it controls                                         |
| ----------------- | ------- | -------------------------------------------------------- |
| `MINIBOOK_PID_KP` | -1000   | Proportional: how aggressively to react to current error |
| `MINIBOOK_PID_KI` | -100    | Integral: how quickly to correct sustained error         |
| `MINIBOOK_PID_KD` | -10     | Derivative: how much to dampen rapid changes             |

The ratio Kp:Ki:Kd = 100:10:1 is a standard starting point. If the system
oscillates between throttling and full power, increase Kd (more negative). If it
takes too long to recover from a temperature spike, increase Ki. If it
overreacts to brief load spikes, decrease Kp (less negative).

### Non-tunable constants

| Constant                    | Value              | Why it is fixed                                          |
| --------------------------- | ------------------ | -------------------------------------------------------- |
| `MINIBOOK_TJMAX`            | 105 C              | Fused into the N150 silicon                              |
| `MINIBOOK_STOCK_TCC_OFFSET` | 20 C               | Factory BIOS value, used only for the diagnostic warning |
| `MINIBOOK_SOC_ZONE`         | `minibook_soc`     | Must match the `minibook_ec` kernel module               |
| `MINIBOOK_CHARGER_ZONE`     | `minibook_charger` | Must match the `minibook_ec` kernel module               |
| `MINIBOOK_TCC_SYSFS`        | sysfs path         | Hardware-specific PCI address                            |
| `MINIBOOK_RAPL_PL1_SYSFS`   | sysfs path         | Standard powercap path                                   |
