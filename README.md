# Kali on QEMU/KVM: fix for the misaligned mouse pointer (spice-vdagent 0.23)

[Español](README.es.md)

In Kali Linux running under QEMU/KVM with SPICE (virt-manager, GNOME Boxes), the
mouse pointer can become misaligned **after the VM resolution changes**: the
arrow is drawn in one place and the click lands somewhere else. This repository
contains a small user-level workaround that keeps it aligned automatically,
plus a write-up of how the cause was found.

> **Status (October 2026): fixed in Debian and Kali `spice-vdagent 0.23.0-4`.**
> If your distribution offers it, upgrade and **reboot the VM**; you do not
> need this workaround:
>
> ```bash
> sudo apt update && sudo apt install spice-vdagent && sudo reboot
> ```
>
> The workaround is still useful where the fixed package is not available yet,
> for example Ubuntu 26.04 LTS (`0.23.0-1ubuntu0.1`) or a Kali system that
> cannot be updated (`0.23.0-3`).

## Symptoms

- Selecting text or clicking menus and buttons misses the target.
- At small resolutions that fit inside the viewer window (1024x768, 1280x800)
  the pointer works.
- The offset starts after maximizing, going fullscreen, resizing the window or
  setting a resolution such as 1920x1080.
- Changing the viewer to X11 or the video model from Virtio to QXL does not help.

Check your version inside the VM:

```bash
dpkg-query -W spice-vdagent
```

| Package | Status |
|---|---|
| Debian stable 0.22.1 (GTK3 build) | Not affected |
| Debian and Kali GTK4 builds before 0.23.0-4 (e.g. Kali 0.23.0-3) | Affected |
| Ubuntu 26.04 LTS 0.23.0-1ubuntu0.1 | Affected: GTK4 build without the patch ([LP #2168964](https://bugs.launchpad.net/bugs/2168964)) |
| Debian and Kali 0.23.0-4 or later | **Fixed** (verified on Kali 2026.2) |

## Quick fix (one time)

Restarting the session agent realigns the pointer until the next resolution
change. No sudo needed:

```bash
pkill -x spice-vdagent
spice-vdagent
```

## Permanent workaround

`vdagent-watch` listens for X screen-change events (RandR) and restarts the
agent when the resolution actually changes.

- **Event-driven:** it blocks on `xev`, with no polling, so it uses no CPU or
  battery while nothing happens.
- **One restart per change:** the burst of events from a single resize is
  coalesced, and repeated events for the same resolution are ignored. It
  also restarts the agent once at startup, in case it is already out of sync.
- **User-level only:** two files in your home; no system packages are changed.
- **Single instance**, logs to the journal, and **tells you when Kali upgrades
  spice-vdagent** so you know when to remove it.

### Install

Inside the Kali VM, from a terminal in the graphical session, as your normal
user (not root):

```bash
git clone https://github.com/JorgeXern/kali-spice-vdagent-pointer-fix.git
cd kali-spice-vdagent-pointer-fix
./install.sh
```

The installer adds missing packages (`x11-utils`, `x11-xserver-utils`,
`spice-vdagent`), copies the script to `~/.local/bin/vdagent-watch`, creates
`~/.config/autostart/vdagent-watch.desktop` and starts it. If your
spice-vdagent already has the fix, it says so and stops (`--force` overrides
that). On start it
restarts the agent once, so a pointer that is already misaligned lines up
right away, with no need to change the resolution.

### Check that it works

```bash
journalctl -t vdagent-watch -f
```

Change the resolution, for example with
`xrandr --output Virtual-1 --mode 1280x1024`, or resize the viewer window if
*Auto resize VM with window* is enabled. Each change logs a line such as
`resolution 1920x1080: agent restarted`, and the pointer lines up within a
second or two.

### Uninstall

When `spice-vdagent` is upgraded the script logs and shows a notification.
If the pointer then stays aligned without it:

```bash
./uninstall.sh
```

## Why it happens

With the SPICE agent running, the pointer works in *client* mode: the viewer
sends the absolute mouse position, and the agent injects it into Xorg through
a virtual device (`spice vdagent tablet` in `xinput list`). To translate that
position it needs the current screen geometry.

The agent reads the screen size at startup and is supposed to refresh it on
every RandR event. In `src/vdagent/x11-randr.c` that refresh was wrapped in
`#ifndef USE_GTK_FOR_MONITORS`:

```c
void vdagent_x11_randr_handle_root_size_change(...)
{
#ifndef USE_GTK_FOR_MONITORS     /* compiled out in GTK4 builds */
    update_randr_res(x11, 0);
    ...
    x11->width[screen]  = width;
    x11->height[screen] = height;
#endif
```

Since 0.22.1-5, Debian builds the package with `--with-gtk4=yes`, which
defines that macro. GTK's monitor API only answers on Wayland, so on X11 the
agent keeps the startup geometry, the virtual tablet keeps that size and
absolute pointer events drift. Restarting the agent makes it read the
geometry again, which is what this workaround automates.

It is not new code in 0.23.0: `x11-randr.c` is identical in 0.22.1 and 0.23.0;
the GTK4 build exposed it. The upstream fix ([MR !58](https://gitlab.freedesktop.org/spice/linux/vd_agent/-/merge_requests/58),
[issue #47](https://gitlab.freedesktop.org/spice/linux/vd_agent/-/work_items/47)) removes those guards, and Debian ships it in 0.23.0-4
(October 1, 2026).

### How it was diagnosed

| Test | Result | Conclusion |
|---|---|---|
| Small resolution, viewer scaling "Never" | Pointer OK | The offset depends on the resolution |
| virt-manager forced to X11 (`GDK_BACKEND=x11`) | Still offset | Not the viewer on Wayland |
| Video model Virtio → QXL | Still offset | Not the video model |
| `xinput list` | QEMU USB Tablet and spice vdagent tablet present | Absolute pointer configured correctly |
| Restart the session agent at 1920x1080 | **Pointer OK** | **It is the agent** (bug #9653) |
| Compare 0.22.1 and 0.23.0 source | `x11-randr.c` identical; refresh compiled out with GTK4 | Root cause: the GTK4 build |
| Upgrade to 0.23.0-4 and reboot, no workaround | **Pointer OK** | **Official fix verified** |

## Official fix

Upgrading to 0.23.0-4 is the real solution. Reboot afterwards: the running
agent keeps using the old binary until it restarts (until then,
`ls -l /proc/$(pgrep -xo spice-vdagent)/exe` ends in `(deleted)`). To confirm
your package has the patch:

```bash
zcat /usr/share/doc/spice-vdagent/changelog.Debian.gz | head -10   # cites LP: #2168964
```

## Tips

- In virt-manager, set **View → Scale Display → Never**, so the viewer shows
  the guest 1:1 instead of stretching it.
- Install the guest agents: `sudo apt install -y spice-vdagent qemu-guest-agent`.
- Pick one way to handle the resolution. vdagent-watch realigns the pointer
  after every change in both cases.
  - **Follow the window:** enable **View → Scale Display → Auto resize VM with
    window**. The guest resolution matches the viewer window; nothing else
    is needed.
  - **Fixed resolution** (e.g. 1920x1080): disable *Auto resize VM with
    window*, otherwise resizing the window replaces your resolution. If Xfce
    does not restore it after a reboot, add an autostart entry that sets it.
    Replace `Virtual-1` and `1920x1080` with your output name and a mode
    listed by `xrandr`:

    ```bash
    cat > ~/.config/autostart/set-resolution.desktop <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=Set resolution
    Exec=sh -c "sleep 3; xrandr --output Virtual-1 --mode 1920x1080"
    EOF
    ```

## Tested on

| Component | Version |
|---|---|
| Host | Fedora 44 Workstation, GNOME 50 (Wayland) |
| Virtualization | virt-manager 5.1.0, QEMU 10.2.2, libvirt 12.0.0 |
| VM | Q35, UEFI (OVMF), virtio disk and NIC, SPICE, USB tablet, QXL or Virtio video |
| Guest | Kali Linux 2026.2, Xfce on X11, spice-vdagent 0.23.0-3 (bug) and 0.23.0-4 (fix) |

It should apply to any Debian-based guest with spice-vdagent 0.23 on X11.
Reports from other setups are welcome in the issues.

## Documentation

Full guide with diagnosis details, in PDF:
[English](docs/kali-kvm-misaligned-pointer-spice-vdagent.pdf) ·
[Español](docs/kali-kvm-puntero-desalineado-spice-vdagent.pdf)

## References

- Kali Linux Bug Tracker #9653: spice-vdagent, possible regression, mouse
  pointer misaligns with cursor. <https://bugs.kali.org/view.php?id=9653>
- Ubuntu Discourse: Mouse pointer desync/offset on fresh Lubuntu 26.04
  (SPICE + VirtIO) after monitor size change. <https://discourse.ubuntu.com/t/82365>
- spice-vdagent upstream, MR !58: x11-randr: keep cache current on X11+GTK4
  builds. <https://gitlab.freedesktop.org/spice/linux/vd_agent/-/merge_requests/58>
- Launchpad #2168964 (Ubuntu). <https://bugs.launchpad.net/bugs/2168964>
- Debian Package Tracker: spice-vdagent. <https://tracker.debian.org/pkg/spice-vdagent>

## License

[MIT](LICENSE) © 2026 JorgeXern
