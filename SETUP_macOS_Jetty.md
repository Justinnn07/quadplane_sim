# SITL + Gazebo Jetty — macOS Setup & Run

You've installed **Gazebo Jetty** (Gazebo v10 / `gz-sim10`, the Sept 2025 LTS). This wires **ArduPilot SITL** + the **`ardupilot_gazebo` plugin** to it and gives you a one-command launcher to run them together.

**Good news:** your `model.sdf`, `quadplane_runway.sdf`, and `.parm` are **unchanged** — the gz system-plugin names (`gz-sim-lift-drag-system`, etc.) are stable across Gazebo versions, and SDF 1.9 is forward-compatible. Only the plugin *build* (against `gz-sim10`) and the macOS run mechanics differ from Linux.

| Piece | Linux (Harmonic) | macOS (Jetty) |
|---|---|---|
| `GZ_VERSION` | `harmonic` | **`jetty`** |
| gz-sim lib | `libgz-sim8` | **`gz-sim10`** |
| Shell rc | `~/.bashrc` | **`~/.zshrc`** |
| Gazebo run | `gz sim -r` (one process) | **server `-s` + GUI `-g` separately** |
| Open-file default | 1024 | **256 (raise it!)** |

---

## 1. Setup (one time)

```bash
cp -r flying_wing_quadplane_sim ~/      # if not already in $HOME
cd ~/flying_wing_quadplane_sim
chmod +x setup_macos.sh run_sim.sh
./setup_macos.sh
```

This builds the ArduPilot bridge against your Jetty install (`GZ_VERSION=jetty`), installs the brew deps (`rapidjson opencv gstreamer`), and writes the env vars to `~/.zshrc`. It does **not** reinstall Gazebo — it uses the Jetty you already have.

Then open a new terminal (or `source ~/.zshrc`).

---

## 2. Run it — one command

```bash
cd ~/flying_wing_quadplane_sim
./run_sim.sh
```

`run_sim.sh` raises the open-file limit, starts the Gazebo **server** and **GUI** (separate processes, as macOS requires), waits for them, then launches ArduPilot SITL with your quadplane params. **Ctrl-C** stops everything.

Then fly it (first-flight checklist is in `README.md`): `mode QLOITER` → `arm throttle` → raise throttle to hover (~63 %) → `mode FBWA` → build speed → watch the transition.

> If the Gazebo **GUI window doesn't appear** (macOS sometimes dislikes a backgrounded GUI), open a separate Terminal and run `gz sim -v4 -g` by hand — the server from `run_sim.sh` is already up.

---

## 3. The macOS open-files limit (you already hit this on Linux)

macOS defaults to a **tiny 256** open files — Gazebo + SITL blow past it instantly. The scripts raise it per-session. To raise it **system-wide and permanently**:

```bash
# temporary, bigger ceiling (needs sudo):
sudo sysctl -w kern.maxfiles=524288 kern.maxfilesperproc=524288
ulimit -n 65535

# permanent across reboots — create a LaunchDaemon:
sudo tee /Library/LaunchDaemons/limit.maxfiles.plist >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>limit.maxfiles</string>
  <key>ProgramArguments</key><array>
    <string>launchctl</string><string>limit</string><string>maxfiles</string>
    <string>65536</string><string>200000</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>ServiceIPC</key><false/>
</dict></plist>
PLIST
sudo launchctl load -w /Library/LaunchDaemons/limit.maxfiles.plist
# log out / back in, then confirm:  ulimit -n
```

---

## 4. Verify the stack (stock Zephyr)

```bash
# Terminal 1            # Terminal 2          # Terminal 3
gz sim -v4 -s -r zephyr_runway.sdf
                        gz sim -v4 -g
                                               sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON --map --console
```
`mode fbwa` → `arm throttle` → `rc 3 1800` → `mode circle`. If the Zephyr flies, your Jetty + plugin + SITL chain is good.

---

## Troubleshooting (macOS + Jetty)

| Symptom | Fix |
|---|---|
| "maximum number of open files" | `ulimit -n 65535`; for a higher ceiling use the `sysctl`/LaunchDaemon in §3 |
| Plugin build can't find gz-sim | `export GZ_VERSION=jetty` then re-run cmake; confirm `gz sim --version` is 10.x |
| `LiftDrag`/`ArduPilotPlugin` not found at runtime | `GZ_SIM_SYSTEM_PLUGIN_PATH` must include `~/gz_ws/src/ardupilot_gazebo/build`; `source ~/.zshrc` in that terminal |
| Gazebo GUI black / won't render | macOS uses Metal via ogre2; update GPU drivers/OS, or run server headless (`-s`) and view in a fresh `gz sim -g` |
| `sim_vehicle.py: command not found` | macOS **zsh** never reads the bash files the ArduPilot installer edits. Add it to zsh: `echo 'export PATH="$HOME/ardupilot/Tools/autotest:$PATH"' >> ~/.zshrc && source ~/.zshrc` |
| wxPython compiles forever (MAVProxy) | `brew install wxpython`, or run headless and connect QGroundControl to TCP `127.0.0.1:5760` |
| Vehicle frozen / no control | frame must be `gazebo-...` **and** `--model JSON`; SITL should print "Connected to Gazebo" |

---

### Notes
- **Jetty vs Harmonic for ArduPilot:** Jetty is supported by the plugin, but Harmonic is the more battle-tested pairing in the ArduPilot community. If you hit Jetty-specific weirdness, switching is just `GZ_VERSION=harmonic` + a rebuild — your model/params don't change.
- Speed up the sim faster-than-real-time: in MAVProxy, `param set SIM_SPEEDUP 5`.

### Sources
- Gazebo Jetty (v10 / gz-sim10) — https://gazebosim.org/docs/latest/install/
- ardupilot_gazebo (supports Garden/Harmonic/Ionic/Jetty) — https://github.com/ArduPilot/ardupilot_gazebo
- Using SITL with Gazebo — https://ardupilot.org/dev/docs/sitl-with-gazebo.html
