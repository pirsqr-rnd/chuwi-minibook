# Installation Guide

Three steps: run the bootstrap script, flip two BIOS settings, install
thermald. Reboot when done.

This page covers the standard setup. For manual per-component installation,
GPU setup, display rotation internals and sleep modes, see
[GUIDE-ADVANCED.md](GUIDE-ADVANCED.md).

## 1. Run the bootstrap script

On Ubuntu or Debian:

```
sudo tools/bootstrap-ubuntu.sh
```

On Arch, CachyOS or Manjaro (with `sudo` from your normal user account, not
from a root shell — it builds a package, which refuses to run as root):

```
sudo tools/bootstrap-arch.sh
```

The script installs build dependencies, the four DKMS kernel modules
(touchscreen fix, EC driver, DPTF enabler, I2C fix), the patched
iio-sensor-proxy for auto-rotation and tablet mode, and the kernel command
line arguments for display rotation, deep sleep and the PSR screen-tearing
fix.

It is idempotent — safe to re-run at any time. If it stops with an error
saying the running kernel is no longer installed, a package upgrade pulled in
a new kernel: reboot and run it again.

## 2. BIOS tweaks

thermald needs two hidden BIOS settings changed to control CPU power limits.

1. Unlock the hidden BIOS menus:
   `echo 1 | sudo tee /sys/devices/platform/minibook_ec/bios_unlock`
1. Reboot into BIOS setup (press DEL during POST).
1. Go to the `Advanced` tab.
1. Navigate to
   `Power & Performance -> CPU - Power Management Control -> CPU Lock Configuration`
1. Change `CFG Lock` to `Disabled`
1. Go back to the top level of the `Advanced` tab.
1. Navigate to `Thermal Configuration -> CPU Thermal Configuration`
1. Change `Tcc Activation Offset` to `10`

See [thermald.md](docs/thermald.md#bios-settings) for what these do.

## 3. thermald

Patched thermal daemon. Requires steps 1 and 2.

```
cd thermal_daemon
./configure && make
sudo make install
sudo systemctl daemon-reload
sudo systemctl enable --now thermald
```

On Arch and Manjaro, use `make install-arch` instead — it builds via `makepkg`
so pacman tracks the install. Add `IgnorePkg = thermald` to `/etc/pacman.conf`
so upgrades don't replace it with the unpatched repo build.

On Debian and Ubuntu, `sudo apt remove thermald` first; on Fedora,
`sudo dnf remove thermald` — so the distro package doesn't shadow the fork.

Verify: `journalctl -u thermald | grep minibook`. See
[thermald.md](docs/thermald.md) for details.

## 4. Reboot and verify

Reboot, then run:

Requires the `i2c-dev` and `acpi_call` kernel modules. Without `i2c-dev`, the
MXC6655 driver cannot open `/dev/i2c-*` and the service exits immediately with
"No sensors or missing kernel drivers for the sensors". `acpi_call` is needed
for the EC-level keyboard/touchpad toggle in tablet mode (screen rotation
itself works without it). Load both and make them persistent:

```
sudo pacman -S acpi_call-dkms   # or your distro's acpi_call package
sudo modprobe i2c-dev acpi_call
printf 'i2c-dev\nacpi_call\n' | sudo tee /etc/modules-load.d/iio-sensor-proxy.conf
```

```
sudo tools/check-status.sh
```

The warnings section at the end lists anything still missing. Two more status
scripts dig deeper — see
[GUIDE-ADVANCED.md](GUIDE-ADVANCED.md#status-scripts).

## Optional: higher refresh rate

On Fedora, `sudo dnf remove iio-sensor-proxy` first for the same reason.

The proxy exposes orientation on D-Bus (`net.hadess.SensorProxy`). How that
becomes a screen rotation depends on your desktop:

- **GNOME and KDE Plasma (Wayland)**: built-in. Enable auto-rotate in the
  quick-settings panel / System Settings. No extra daemon needed.
- **Niri**: install [`iio-niri`](https://github.com/Zhaith-Izaliel/iio-niri) and
  add to one of your Niri config files (e.g.
  `~/.config/niri/cfg/autostart.kdl`):
  ```
  spawn-at-startup "iio-niri" "listen" "--monitor" "DSI-1"
  ```
- **Sway / wlroots compositors**: use
  [`iio-sway`](https://github.com/okeri/iio-sway) (works on Sway, river,
  Wayfire) or an equivalent bridge for your compositor.
- **Hyprland**: use
  [`iio-hyprland`](https://github.com/JeanSchoeller/iio-hyprland).

The patched proxy reports `right-up` whenever the device is in laptop mode, so
the compositor applies the 270° portrait correction dynamically and switches to
live accelerometer rotation in tablet mode. Do **not** combine this with a
static rotation (kernel cmdline, VBT patch, xrandr script) - they will stack.

Verify: `monitor-sensor` and tilt the device. See
[iio-sensor-proxy.md](docs/iio-sensor-proxy.md) for details.

#### On-screen keyboard (tablet mode)

In tablet mode the physical keyboard is disabled at the EC level (see
[minibook-ec.md](docs/minibook-ec.md#touchpad-and-keyboard)), so text input
needs an on-screen keyboard. There is no built-in popup-on-focus mechanism on
Niri (unlike GNOME/KDE) -- wire one up manually with `switch-events`:

```
yay -S wvkbd-deskintl
```

Add to a Niri config file (e.g. `~/.config/niri/cfg/switch-events.kdl`):

```
switch-events {
    tablet-mode-on {
        spawn "wvkbd-deskintl"
    }
    tablet-mode-off {
        spawn "pkill" "-x" "wvkbd-deskintl"
    }
}
```

`wvkbd-deskintl` has no dedicated Polish layout, but every diacritic (ą ć ę ł
ń ó ś ź ż) is reachable through the "Cmp" (Compose) key: tap `Cmp`, then the
base letter, then pick the accented variant from the popup that appears.

### 8. VBT patcher (display refresh rate)

The stock DSI panel runs at 50 Hz. The VBT patcher changes the pixel clock to
increase the refresh rate. Build the tool first:

```
cd vbt_patch
make
```

Then use `update-vbt-clock.sh` to patch, install into the initramfs, and update
the kernel command line in one step:

```
cd vbt_patch && make && cd ..
sudo tools/update-vbt-clock.sh 90
```

**Treat this as an experiment, not a default.** Panels vary between units, and
a rate can survive a cold boot yet fail on the first suspend/resume. Test a
suspend cycle before relying on it, and revert if the display misbehaves:

```
sudo tools/update-vbt-clock.sh --revert
```

See [vbt-patch.md](docs/vbt-patch.md) for choosing a rate and telling the two
failure modes apart.

## Optional: screen auto-rotation on other desktops

## GPU and Vulkan

The Intel N150 has UHD Graphics (Gen12.2, Alder Lake-N). Run
`tools/gpu-status.sh` (as your normal user, not root) to see what is working. It
checks Vulkan, VA-API, and OpenCL and lists which video codecs are available for
hardware decode and encode.

### Required packages

The exact package names vary by distro. On Arch/CachyOS:

| Package                 | What it provides                                |
| ----------------------- | ----------------------------------------------- |
| `mesa`                  | OpenGL and Vulkan (ANV) drivers for Intel       |
| `vulkan-intel`          | Intel ANV Vulkan ICD (may be bundled with mesa) |
| `intel-media-driver`    | VA-API hardware video acceleration (iHD driver) |
| `intel-compute-runtime` | OpenCL support (NEO runtime)                    |
| `vulkan-tools`          | `vulkaninfo` for `gpu-status.sh`                |
| `libva-utils`           | `vainfo` for `gpu-status.sh`                    |
| `clinfo`                | `clinfo` for `gpu-status.sh`                    |

On CachyOS most of these are installed by default. On other distros the package
names may differ (e.g. `mesa-vulkan-drivers` on Fedora/Ubuntu).

### Enable Vulkan video decode and encode

Intel's ANV driver supports hardware video decode and encode (H.264, H.265, AV1,
VP9) but these are behind a feature flag. Add to your environment (e.g.
`/etc/environment`):

```
ANV_DEBUG=video-decode,video-encode
```

Log out and back in for the change to take effect, then re-run
`tools/gpu-status.sh` to confirm the codecs appear in the vulkan section.

______________________________________________________________________

## DSI panel

The MiniBook X has a portrait-mode 1200x1920 MIPI DSI panel mounted in landscape
orientation. It needs rotation for normal use and has a known issue with DSI
link tearing.

### Display rotation

If your compositor consumes iio-sensor-proxy orientation events (see
[§7](#7-iio-sensor-proxy) for the per-desktop list), you do not need any of the
methods below. The patched proxy reports `right-up` in laptop mode so the
compositor applies the 270° rotation dynamically, and switches to live
accelerometer rotation in tablet mode. There is nothing to configure on the
kernel/firmware side.

Otherwise, pick one of the methods below for a fixed rotation.

**Combining a static rotation with the proxy:** the proxy reads the DRM
`panel orientation` property at startup and subtracts any statically-applied
rotation (VBT patch, kernel cmdline, or i915 quirk) from what it reports, so the
two no longer stack. If a static rotation is present, laptop mode reports
`normal` instead of `right-up` and tablet-mode readings are de-rotated to match.

`tools/check-status.sh` reports the applied rotation (read straight from the DRM
`panel orientation` property) on the `panel rotation` line. With no static
rotation it reads *"normal, no static rotation (laptop mode reports right-up)"*;
after a VBT `--rotation 3` patch (or `panel_orientation=right`) it becomes
*"right-side-up/270° (laptop mode reports normal)"*. The proxy also logs its own
decision at startup (`journalctl -u iio-sensor-proxy | grep 'panel orientation'`).

#### Kernel command line

Add the `video=` parameter to the kernel command line in `/etc/default/limine`:

```
video=DSI-1:panel_orientation=right
```

This tells the i915 DRM driver to apply a hardware rotation, so the console
framebuffer and all desktop environments see the correct orientation from the
start -- including the boot splash, TTY consoles and login screen. After
editing, rebuild the initramfs with `sudo limine-mkinitcpio` and reboot.

#### Bootloader framebuffer

Limine can rotate its own framebuffer (boot menu, boot splash) independently of
the kernel. Add to `/boot/limine.conf`:

```
interface_rotation: 90
```

This only affects the Limine boot screen itself. You still need one of the other
methods for the kernel and desktop. After editing, rebuild with
`sudo limine-mkinitcpio`.

#### VBT patch

The `vbt_patch` tool can set the MIPI panel rotation in the Video BIOS Table.
This makes the i915 driver treat the panel as already rotated at the hardware
level:

```
cd vbt_patch
make
vbt_patch <input> --rotation 1 <output>
```

The rotation values are: 0 = 0 degrees, 1 = 90 degrees, 2 = 180 degrees, 3 = 270
degrees. This is a firmware-level change embedded in the initramfs (see
[VBT patcher](#8-vbt-patcher-display-refresh-rate) above). It can be combined
with a refresh rate patch in a single `vbt_patch` invocation.

#### Xrandr

For X11 sessions, `xrandr` can rotate the display at the compositor level:

```
xrandr --output DSI-1 --rotate right
```

This is a runtime-only change that does not persist across reboots unless added
to a startup script or xprofile. It does not affect the boot splash, TTY
consoles or login screen.

#### Login screen (greetd + noctalia-greeter)

None of the methods above reach the login screen -- it runs as its own,
separate process before your compositor session even starts. SDDM's default
X11 greeter has no rotation of its own, and getting its Wayland mode working
is more trouble than it's worth on this panel (see the aside at the end of
this section). `greetd` + `noctalia-greeter` is the setup that ended up
working reliably.

**Prerequisite: `seatd`.** Without it, switching VTs between the greeter and
an already-running Niri session can wedge Niri's DRM output permanently --
`journalctl` fills with `Page flip commit failed ... Permission denied` and
the session never recovers (hard reset required). This happens with *any*
second compositor grabbing a VT (reproduced with Weston, a second Niri
instance, and noctalia-greeter's own compositor), not just a Niri-vs-Niri
conflict -- the actual cause is `libseat` falling back to `logind` for seat
management, which does not hand DRM master back and forth between VTs
reliably on this hardware. `seatd` is the seat backend Niri prefers and
fixes this:

```
sudo usermod -aG seat "$USER"
sudo usermod -aG seat greeter   # after installing greetd below, so the user exists
sudo systemctl enable --now seatd
sudo reboot
```

Verify both the greeter and your session picked it up (look for backend
`seatd`, not `logind`):

```
journalctl -b --no-pager | grep -i "seat opened"
```

Do this before touching the greeter config below -- it is not
Wayland-greeter-specific, plain SDDM+Xorg can wedge the same way if anything
else on the seat needs a VT switch.

**Install `greetd` and `noctalia-greeter`:**

```
sudo pacman -S greetd noctalia-greeter
sudo systemctl disable sddm   # if migrating from SDDM
sudo systemctl enable greetd
```

`greetd`'s `greeter` system user needs a real home directory -- by default it
is `/`, and GTK/Qt-based greeters abort (`SIGABRT`) trying to create
cache/config directories there:

```
sudo mkdir -p /var/lib/greeter
sudo chown greeter:greeter /var/lib/greeter
sudo usermod -d /var/lib/greeter greeter
```

`/etc/greetd/config.toml`:

```
[terminal]
vt = 1

[default_session]
command = "/usr/bin/noctalia-greeter-session -- --session niri"
user = "greeter"
```

**Rotation and scale** live in `/var/lib/noctalia-greeter/greeter.toml`
(created automatically, root:greeter-owned, mode `0750` -- edit with `sudo`):

```
[output]
transforms = "DSI-1:270"
scale = 1.25
```

Both are meant to sync automatically from the Noctalia shell running on your
desktop session (see `sync.toml` in the same directory) -- set them manually
here if the sync hasn't happened yet or you don't run Noctalia.

`transforms` (plural) takes a `"<connector>:<value>"` string, `;`-separated
for multiple outputs (e.g. `"DP-1:normal; HDMI-A-1:270"`). It must be a
single `[output]` table -- not `[output.DSI-1]` with a singular `transform`
key, which is silently ignored (no error, the greeter just stays unrotated).

`scale` is different: it's a bare number (`1.25`, not `"DSI-1:1.25"`) and
applies uniformly to every output -- there is no per-connector equivalent.
Upstream's own example config also documents a plural `scales` key (per
connector, same `"name:value"` format as `transforms`), but the packaged
version at the time of writing (`noctalia-greeter 1.0.0` internally, `1.1.0-1`
in the CachyOS package) does not recognize it --
`journalctl -u greetd | grep greeter-config` logs
`unrecognized key 'output.scales' (ignored)` and silently keeps the
auto-detected scale (`2` on this panel) instead. Use singular `scale` until
that lands; check the same log line to confirm your key was actually picked
up rather than silently ignored either way.

<details>
<summary>Aside: why not SDDM+Weston, or plain Niri+regreet?</summary>

Both were tried first and worked, technically, but neither was worth keeping:

- **SDDM + Weston**: SDDM's Wayland mode needs a compositor for its
  `CompositorCommand`. `cage` cannot rotate at all (no CLI flag, and wlroots
  only exposes the panel-orientation property to compositors that explicitly
  read it -- cage doesn't). `weston` can, via a `weston.ini` with
  `transform=rotate-270`, but it's a second, unrelated compositor codebase
  to configure and keep in sync by hand, and installing it adds a spurious
  "Weston" entry to session pickers
  (`/usr/share/wayland-sessions/weston.desktop`, safe to `rm`).
- **greetd + Niri + regreet**: Niri itself auto-detects the DRM
  panel-orientation quirk with zero config (same mechanism as the desktop
  session), which looked ideal -- run Niri as the greeter compositor too.
  In practice `regreet` (GTK4) needs its own D-Bus session bus or it aborts
  on startup (wrap it in `dbus-run-session`), and the handoff from the
  greeter's Niri instance to the real one still shows a brief flash of raw
  console text during the VT switch -- an inherent property of running two
  independent compositor processes back to back, not a misconfiguration.

`noctalia-greeter` sidesteps the GTK/D-Bus fragility (it bundles its own
compositor and handles that internally) at the cost of *not* getting Niri's
automatic rotation for free -- its compositor is a separate wlroots build,
so rotation needs the same kind of manual, per-panel config Weston did.

</details>

**The VT-switch flash also happens with `noctalia-greeter`, and it is
actually fixable.** The brief flash of text isn't a generic "two compositors
handing off a VT" artifact after all -- it's one specific deprecation warning
from `/usr/bin/niri-session` (part of the `niri` package, not a custom
config): the line `systemctl --user import-environment` (called with no
variable-name list) prints `calling import-environment without a list of
variable names is deprecated` on stderr. This happens while `niri-session` is
still a plain shell script running directly on the raw VT, before Niri itself
grabs the display, so the warning never reaches `journalctl` -- it goes
straight to the physical console, which is what actually flashes.

Confirmed live that this is the actual cause -- it reproduces identically
with and without the intermittent Niri panic below, so the panic was never
what caused the flash.

Already reported upstream: this is a known, long-standing issue
([niri-wm/niri#254](https://github.com/niri-wm/niri/issues/254), open since
March 2024). The maintainer has explicitly declined to change the default
(`"we're not gonna replace a 1 line command with something complicated just
to hide this warning message"`), so don't re-report it -- patch locally
instead, which the maintainer also explicitly endorses in that thread
("you could also patch niri-session or make your own version, it's not too
complex a script").

Fixed via a **pacman hook** (borrowed from a fix shared in that issue by
`real-or-random`) rather than a one-off edit, so it survives `niri` package
updates automatically instead of needing manual reapplication after every
upgrade:

```
# /etc/pacman.d/hooks/niri-import-environment-patch.hook
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = niri

[Action]
Description = Patch niri-session import-environment deprecation warning
When = PostTransaction
Exec = /usr/bin/env sed -i "s@ systemctl --user import-environment$@ # HACK: The following line has been automatically patched by a pacman hook\n SYSTEMD_COLORS=true systemctl --user import-environment 2>\&1 | grep -v 'Calling import-environment without a list of variable names is deprecated.'@" /usr/bin/niri-session
```

The hook only fires on a package transaction, so it doesn't touch an
already-installed `niri-session` -- apply the same `sed` once by hand after
installing the hook to patch the current install immediately. A pristine
backup of the original script is kept at
`/usr/bin/niri-session.orig-pre-import-env-fix` for reference/diffing.

Note there's a second, more thorough fix discussed in the same issue: pass
an explicit variable list (`systemctl --user import-environment PATH
XDG_SESSION_ID`) instead of suppressing the warning. Several users report the
bare, no-args form also permanently clobbers variables set via
`~/.config/environment.d/*.conf` (systemd puts imported vars in an override
layer that survives later environment.d changes). Not observed on this
machine and not worth the extra complexity unless `environment.d` ends up in
use here.

**Separate, unrelated finding: Niri sometimes panics on session quit.**
Reproduced once (2026-09-20 ~09:50) when returning to the greeter via
`CTRL+ALT+Delete { quit; }`:

```
seatd: [ERROR] Could not revoke evdev on device fd: No such device
niri: thread 'main' panicked at .../smithay/src/backend/session/libseat.rs:215:57:
niri: called `Result::unwrap()` on an `Err` value: Errno { code: 107, description: "Transport endpoint is not connected" }
niri.service: Main process exited, code=exited, status=101/n/a
```

Intermittent -- a later identical quit exited cleanly (`status 0`, plain
`seatd: Client disconnected` INFO line, no panic). Looks like a race in
Smithay's libseat session backend during teardown (`.unwrap()` on a seat
disconnect that should be handled gracefully), not a config issue on this
machine. Not the cause of the console flash above. Worth an upstream report
if it recurs enough to be annoying; functionally harmless so far (the session
still ends either way).

### DSI link tearing

Panel Self Refresh (PSR) can cause DSI link tearing on this panel - the screen
partially fills with green and horizontal lines. Disabling PSR with a kernel
parameter seems to fix it. Add to the kernel command line in
`/etc/default/limine`:

```
i915.enable_psr=0
```

Rebuild the initramfs with `sudo limine-mkinitcpio` and reboot.

______________________________________________________________________

## Sleep mode (S0ix vs S3)

The MiniBook X supports two suspend modes. Check which one is active with
`check-status.sh` or directly:

```
cat /sys/power/mem_sleep
```

The active mode is shown in brackets (e.g. `[s2idle]` or `[deep]`).

### S0ix (s2idle) - software sleep

Similar to how smartphones sleep: the CPU enters a low-power idle state but the
system does not fully power down. The hardware stays partially active, allowing
for faster wake times.

### S3 (deep) - hardware sleep

Traditional suspend-to-RAM. The system powers down everything except memory.

**Recommended.** On the MiniBook X, S0ix does not reach its low-power
residency states reliably and drains the battery noticeably overnight. S3
("deep") suspends to a true low-power state and, in testing on this device,
gives substantially better standby battery life. Switch to `deep` and make it
the default unless you have a specific reason to keep s2idle.

### Switching between modes

To switch to S3 (hardware sleep, recommended):

```
echo deep | sudo tee /sys/power/mem_sleep
```

To switch to S0ix (software sleep):

```
echo s2idle | sudo tee /sys/power/mem_sleep
```

These changes do not persist across reboots. To make `deep` the default
permanently, add `mem_sleep_default=deep` to the kernel command line in
`/etc/default/limine` and rebuild the initramfs with `sudo limine-mkinitcpio`
(use `mem_sleep_default=s2idle` if you ever need to go back).
