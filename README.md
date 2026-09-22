# Omarchy Incus Lab

An [Omarchy](https://omarchy.org/) **bar widget** for a lab you already built with [Incus](https://linuxcontainers.org/incus/).

It shows whether that VM is running and isolated, lets you restore a snapshot named `golden`, install packages **from this PC** into an offline guest, and open your **host** coding agent with a few desktop config trees locked read-only.

It does **not** install Incus, create a VM, install Omarchy inside a VM, or put the agent *inside* the guest.

Plugin id: `keri.incus-lab`  
Version: 0.1.1

---

## Is this useful for you?

**Use it if all of these are true:**

- You run Omarchy (or another desktop that already has `omarchy-shell` and this plugin API).
- You already have — or are willing to build by hand — an Incus **virtual machine** named `omarchy-lab`, a snapshot named `golden`, and an isolated Incus network named `labnet` or `isolated`.
- You want a bar status light and one-click **restore snapshot**.
- You want a coding agent on **this computer** that can `incus exec` into the guest, while `~/.config/hypr`, `~/.config/omarchy`, and `/usr/share/omarchy` stay read-only in that agent window.
- You are fine with the guest having **no internet**. Packages are downloaded on the host and copied in.

**Do not use it if you wanted any of these:**

| You wanted | What this plugin actually does |
|---|---|
| A one-command Omarchy desktop in a window | You must create the Incus VM yourself. The README example launches a **headless Arch cloud image**, not the Omarchy ISO. There is no Spice/GTK desktop. |
| An agent that can only touch the VM | The agent is `omarchy-agent` **on the host**. Bubblewrap makes a short list of paths read-only. The rest of your home directory, `/tmp`, network, and `sudo` are still the host. |
| The guest on the internet | Isolation is the point. The nic must be `labnet` / `isolated` (no NAT). The plugin will not attach `incusbr0` for you. |
| The plugin to provision Incus | Fail-closed. Missing Incus, missing VM, or missing snapshot → the panel explains it and **does nothing**. |
| GPU passthrough, Hyprland-in-the-guest, or “my OS clone” | Out of scope. |

If you need a graphical Omarchy VM with the agent **inside** the guest, this repository is the wrong tool.

---

## What you get when you add the plugin

A clone at `~/.config/omarchy/plugins/keri.incus-lab/`:

| Piece | Role |
|---|---|
| Bar icon | Status every 15s (configurable). Color = running+isolated / running-but-on-NAT / idle or missing. |
| Panel (left click) | Human-readable state and three actions. |
| `scripts/status.sh` | `incus` → one JSON object. Never creates anything. |
| `scripts/lab-agent.sh` | Stop VM if needed → restore `golden` → start → wait for Incus guest agent → open **host** agent. |
| `scripts/lab-pkg.sh` | `sudo pacman -Syw` on the host → `incus file push` → `pacman -U` in the guest. |
| `scripts/lab-save-golden.sh` | Replace snapshot `golden` only if the nic is `labnet` or `isolated`. Types `yes` to confirm. |
| `scripts/desktop-lock.sh` | `bwrap`: bind `/` on `/`, then remount a few trees read-only. |
| `scripts/lab-agent-inner.sh` | Re-enter `incus-admin` if the session dropped the group, then `exec` your agent wrapper. |

Nothing under `/usr/share/omarchy` is edited. Nothing is installed with `pkexec`.

---

## What the plugin will never do

- Install or enable the Incus daemon, OVMF, or `incus-admin`.
- Run `incus launch`, create `labnet`, or create the first `golden` snapshot.
- Enable NAT, change UFW, or give the guest a default route.
- Bind-mount your `$HOME`, `~/.ssh`, or sockets into the guest (and you should not do that yourself).
- Run the coding agent *inside* the VM.
- Tear down Incus when you remove the plugin (see [Uninstall](#uninstall)).

---

## How the parts fit

```text
  [ Omarchy bar on YOUR desktop ]
              |
              |  polls status.sh (incus info / nic / snapshot)
              v
  [ Incus VM "omarchy-lab" ] ---- nic must be labnet/isolated (no internet)
              ^
              |  incus exec / incus file push
              |
  [ omarchy-agent on YOUR desktop ]
              |
              +-- bubblewrap: hypr, omarchy config, /usr/share/omarchy,
                  alacritty, foot, kitty, ghostty  = read-only
              +-- everything else on this PC        = still writable
              +-- internet                            = this PC's network
```

The VM is a resettable box the host agent can `incus exec` into.  
The sandbox is **not** the VM. The sandbox is “those config dirs are read-only in this one window.”

---

## Install the plugin

Requires Omarchy’s plugin CLI and a desktop session already running `omarchy-shell`.

```sh
omarchy plugin add https://github.com/briankeriri/omarchy-incus-lab.git --enable
```

That clones the repo, validates `manifest.json`, and enables the widget. Plugins run **unsandboxed inside `omarchy-shell`** (bar, lock, notifications share that process). Only add this if you accept that.

```sh
omarchy plugin update keri.incus-lab
omarchy bar move keri.incus-lab --section right
```

Until Incus and `omarchy-lab` exist, the icon stays muted / the panel says what is missing. That is expected.

### Optional keybind

In `~/.config/hypr/bindings.lua` (your home path, not `YOU`):

```lua
o.bind("SUPER + CTRL + ALT + A", "Lab agent", "/home/YOU/.config/omarchy/plugins/keri.incus-lab/scripts/lab-agent.sh")
```

Then `hyprctl reload` and `hyprctl configerrors`.

The chord is the same as **right-click** on the icon: restore `golden`, then open the locked host agent.

---

## Required: build the VM yourself (v0.1)

The widget looks for:

| Name | Default | Meaning |
|---|---|---|
| Instance | `omarchy-lab` | Incus VM (not a container). |
| Snapshot | `golden` | Restored before every agent launch. |
| Isolated nic | `labnet` or `isolated` | `eth0`’s network. Anything else (including `incusbr0`) is treated as **not isolated**. Running-but-NAT shows as urgent on the bar. Saving golden is refused. |

Isolation is **the network name**, not a ping test.

Typical Arch/Omarchy host checklist (the plugin does not run this):

1. Install Incus and OVMF. Enable the socket.

   ```sh
   sudo pacman -S incus edk2-ovmf
   sudo systemctl enable --now incus.socket
   sudo usermod -aG incus-admin "$USER"
   ```

   Log out and back in so `incus` works without root.

2. If Incus was never initialized:

   ```sh
   sudo incus admin init --auto --storage-backend=btrfs
   ```

   Do not re-init an existing daemon.

3. Launch a VM (names and sizes the widget examples use):

   ```sh
   incus launch images:archlinux/current omarchy-lab --vm \
     -c limits.cpu=4 -c limits.memory=4GiB -c security.secureboot=false
   incus config device set omarchy-lab root size=20GiB
   ```

   This image is a **minimal Arch VM**. It is not Omarchy and has no Hyprland session.

4. Isolate **before** you take `golden`. Do not snapshot while `eth0` is still on `incusbr0`.

   ```sh
   incus network create labnet \
     ipv4.address=10.89.0.1/24 ipv4.nat=false ipv4.routing=false \
     ipv4.dhcp=true ipv4.dhcp.gateway=none ipv6.address=none
   incus stop omarchy-lab
   incus config device override omarchy-lab eth0 network=labnet
   incus start omarchy-lab
   incus wait omarchy-lab --timeout=180
   incus snapshot create omarchy-lab golden
   ```

5. If UFW’s default forward policy is `DROP`, do **not** flip it to `ACCEPT` for this lab. After the VM is off `incusbr0`, you should not need extra forward allows. The guest should not reach the internet.

6. You need an `omarchy-agent` on the host. `lab-agent.sh` runs `$HOME/.local/bin/omarchy-agent` if that file is executable, otherwise `omarchy-agent` on `PATH`. The lock is applied only if that wrapper ends up calling `scripts/desktop-lock.sh` (or you point `OMARCHY_AGENT_WRAPPER` at a script that does). **This repo does not install that wrapper.** Without it, restore still works (`OMARCHY_LAB_SKIP_AGENT=1`) but “open agent” will fail.

Never bind-mount `$HOME`, `~/.ssh`, or agent/MCP sockets into the guest.

A provisioner that does the above without extra polkit is listed in the original notes as v0.2 and is **not shipped**.

---

## Using it

### Bar icon

| Input | Action |
|---|---|
| Left click | Open / close the panel |
| Right click | Restore `golden` and open the host agent |
| Middle click | Refresh status now |
| Hover | `state · isolated\|not isolated · snapshot ready\|missing` |

Status is polled on a timer (`refreshIntervalSec`, default 15, range 5–120).

| Color | Meaning |
|---|---|
| Accent (or full foreground if accent equals foreground) | Running **and** nic is `labnet` / `isolated` |
| Urgent | Running on some other network (e.g. NAT), or no permission on the Incus socket |
| Muted | Stopped, missing pieces, or unknown |

### Panel actions

| Button | When it is enabled | What it runs |
|---|---|---|
| Restore golden + agent | Instance exists and `golden` exists | `lab-agent.sh` |
| Install packages from this PC | Instance exists (will start it if stopped) | `lab-pkg.sh` in a TUI |
| Save isolated snapshot as golden | Instance exists **and** nic is isolated | `lab-save-golden.sh` in a TUI; you must type `yes` |

`lab-agent.sh` will force-stop a stuck VM after `OMARCHY_LAB_STOP_TIMEOUT` seconds (default 60), restore, start, then wait up to `OMARCHY_LAB_AGENT_TIMEOUT` (default 120) for `incus exec … true` before opening the agent.

Package install: names must look like Arch packages (`[A-Za-z0-9][A-Za-z0-9@._+-]*`). Host needs `sudo` for `pacman`. The guest stays on the isolated nic.

### Widget settings

In the bar widget settings (or `shell.json`):

| Key | Default | What it changes |
|---|---|---|
| `instance` | `omarchy-lab` | Incus instance name |
| `snapshot` | `golden` | Snapshot restored / saved |
| `refreshIntervalSec` | `15` | How often `status.sh` runs |

### Optional IPC

If `omarchy-shell` can reach target `keri.incus-lab`:

```sh
omarchy-shell keri.incus-lab status
omarchy-shell keri.incus-lab refresh
omarchy-shell keri.incus-lab launch          # same as restore + agent
omarchy-shell keri.incus-lab installPkgs
omarchy-shell keri.incus-lab saveGolden
omarchy-shell keri.incus-lab toggle          # panel on the focused monitor
```

### Agent window behavior

The launched agent is told, in the prompt, to diagnose **on the host** and to reproduce with `incus exec <instance> -- …`.

In that window, bubblewrap remounts these paths read-only (if they exist):

- `/usr/share/omarchy`
- `~/.config/hypr`
- `~/.config/omarchy`
- `~/.config/alacritty`, `foot`, `kitty`, `ghostty`

Switching the agent from Ask to Agent mode does **not** unlock those paths. The comment in the original setup was: apply live-desktop edits from a **different** chord (Super+Shift+Ctrl+A) after you agree — that chord is **not defined in this repo**.

`desktop-lock.sh --self-test` checks that `~/.config/hypr` is not writable in the sandbox and that `bindings.lua` is still readable. `./scripts/validate.sh` runs Omarchy’s manifest validator, checks a subset of scripts are executable, then runs that self-test (needs `bwrap` and a normal Omarchy `~/.config/hypr`).

---

## Security model (read before enabling)

Three different trust boundaries. They are easy to mix up.

1. **The plugin QML** runs inside `omarchy-shell` with your user privileges. A bug there is a bug in your bar/lock process. The scripts the widget launches are the same user (plus `sudo` only for host `pacman` in `lab-pkg.sh`).

2. **The guest** should be offline and should not see your home directory. That protects the host from *guest* code — if you do not mount secrets in.

3. **The coding agent** is not in the guest. `desktop-lock.sh` is `bwrap --bind / /` plus those read-only binds. The agent can still write the rest of `$HOME`, use the host network, and call `incus`. Treat it as “cannot casually rewrite Hyprland/Omarchy config in this window,” not as “cannot wreck this PC.”

If your graphical session started before you were added to `incus-admin`, scripts re-exec via `newgrp` (`sg`). They never `pkexec` Incus client commands.

---

## Uninstall

Two layers. Removing the plugin does **not** stop Incus or delete the VM.

### 1. Plugin

```sh
omarchy plugin remove keri.incus-lab
```

Remove the optional keybind from `bindings.lua` if you added it, then `hyprctl reload`.

If you added host wrappers (`~/.local/bin/omarchy-agent`, `omarchy-lab-agent`, `omarchy-desktop-lock`) that `exec` scripts from this plugin, retarget or delete them. Crash-toast `--prompt` that requires `desktop-lock.sh` will break once the clone is gone.

### 2. Lab VM

```sh
incus stop omarchy-lab
incus delete omarchy-lab
incus network delete labnet    # only if nothing else uses it
```

`incusd` restores last instance state at **boot**, not at Hyprland login. `boot.autostart=false` plus `incus stop` keeps the disk but stops the RAM use.

### 3. Incus daemon (only if you do not want it at boot)

```sh
sudo systemctl disable --now incus.service
sudo systemctl disable --now incus.socket
```

Disable **both**. Socket-only still starts the daemon on the widget’s 15s `incus info` poll.

If you added UFW forward allows for `incusbr0` during first setup, delete those by rule text (`sudo ufw status`, then `sudo ufw delete …`). Moving the VM to `labnet` does not remove those rules.

### 4. Packages and group (only if Incus is otherwise unused)

```sh
sudo gpasswd -d "$USER" incus-admin
sudo pacman -Rns incus edk2-ovmf
```

Removing the package does not wipe `/var/lib/incus`.

---

## Local check

```sh
./scripts/validate.sh
```

Needs `omarchy plugin validate`, executable scripts listed in `validate.sh`, `bwrap`, and the desktop-lock self-test.

---

## Environment variables

Scripts honor these (widget settings override instance/snapshot when launched from the bar).

| Variable | Default | Used by |
|---|---|---|
| `OMARCHY_LAB_INSTANCE` | `omarchy-lab` | All lab scripts |
| `OMARCHY_LAB_SNAPSHOT` | `golden` | Agent, save, status |
| `OMARCHY_AGENT_WRAPPER` | `~/.local/bin/omarchy-agent` | Agent launch |
| `OMARCHY_NOTIFICATION_SEND` | `omarchy-notification-send` | Desktop notifications |
| `OMARCHY_LAB_STOP_TIMEOUT` | `60` | How long to wait for a clean stop |
| `OMARCHY_LAB_AGENT_TIMEOUT` | `120` (`180` in pkg script) | Wait for `incus exec` |
| `OMARCHY_LAB_SKIP_AGENT` | unset | If `1`, restore/start only; do not open the agent |

---

## License

MIT. See [LICENSE](LICENSE).
