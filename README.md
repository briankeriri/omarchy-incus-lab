# Incus Lab for Omarchy

Bar widget for an **isolated Incus VM** sandbox. Status on the bar, a panel to
restore the golden snapshot, install packages **from the host** (guest stays
offline), and save a new golden. Fail-closed: it will not install Incus, create
VMs, or edit packaged Omarchy (`/usr/share/omarchy/`).

Plugins run unsandboxed inside `omarchy-shell`. Only add this repo if you are
willing to run the QML and scripts.

## Easy part: the plugin (v0.1)

```sh
omarchy plugin add https://github.com/briankeriri/omarchy-incus-lab.git --enable
```

That clones into `~/.config/omarchy/plugins/keri.incus-lab/`, validates the
manifest, and enables the bar widget. Update later with:

```sh
omarchy plugin update keri.incus-lab
```

Move it on the bar if you want:

```sh
omarchy bar move keri.incus-lab --section right
```

### Optional keybind

Add to `~/.config/hypr/bindings.lua` (replace `YOU` with your home):

```lua
o.bind("SUPER + CTRL + ALT + A", "Lab agent", "/home/YOU/.config/omarchy/plugins/keri.incus-lab/scripts/lab-agent.sh")
```

Reload Hyprland (`hyprctl reload`) and check `hyprctl configerrors`.

Left click the bar icon for the panel. Right click restores golden and opens
the host agent. Middle click refreshes status.

**Install packages from this PC** downloads with `sudo pacman` in a terminal on
the host, then `incus file push` + `pacman -U` in the guest. The guest does not
get internet. **Save isolated snapshot as golden** refuses unless the nic is
`labnet` or `isolated`.

## Required host: Incus VM (not installed by the plugin)

The widget looks for an instance named `omarchy-lab` and a snapshot named
`golden`. If those are missing, the panel says so and does nothing.

This is the part that is **not** one command in v0.1. You need Incus, membership
in `incus-admin`, a VM, an isolated network, and a snapshot taken **after**
isolation. A provisioner that does this without extra polkit is v0.2.

Checklist others have used on Arch/Omarchy:

1. Install Incus and OVMF (`edk2-ovmf`). Enable `incus.socket`.
2. `sudo usermod -aG incus-admin "$USER"` then **re-login** so `incus` works
   without root.
3. If Incus is uninitialized: `sudo incus admin init --auto --storage-backend=btrfs`
   (or your pool). Do not re-init if you already have a daemon.
4. Launch a VM (names and caps the plugin expects):

```sh
incus launch images:archlinux/current omarchy-lab --vm \
  -c limits.cpu=4 -c limits.memory=4GiB -c security.secureboot=false
incus config device set omarchy-lab root size=20GiB
```

5. Isolate **before** golden. Do not snapshot while the nic is on `incusbr0`.

```sh
incus network create labnet \
  ipv4.address=10.89.0.1/24 ipv4.nat=false ipv4.routing=false \
  ipv4.dhcp=true ipv4.dhcp.gateway=none ipv6.address=none
incus stop omarchy-lab
incus config device override omarchy-lab eth0 network=labnet
incus start omarchy-lab
incus wait omarchy-lab agent --timeout=180
incus snapshot create omarchy-lab golden
```

6. If you use UFW with `DEFAULT_FORWARD_POLICY=DROP`, do **not** set forward
   to ACCEPT. After the VM is off `incusbr0`, you do not need extra forward
   allows for the lab. The guest should not ping the internet.

The widget talks to Incus as your user (`incus-admin`). It never `pkexec`s
client commands. If your graphical session started before the group was added,
the scripts re-exec with `newgrp` as `sg`.

Never bind-mount `$HOME`, `~/.ssh`, or sockets into the guest. Never push
Cursor/MCP/token paths.

## Local development

```sh
./scripts/validate.sh
```

## License

MIT. See [LICENSE](LICENSE).
