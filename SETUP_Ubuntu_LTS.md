# SITL + Gazebo — Ubuntu LTS Setup Config

Stand up the full stack — **ArduPilot SITL + Gazebo Harmonic + the `ardupilot_gazebo` plugin** — on **Ubuntu 22.04 (Jammy)** or **24.04 (Noble)**. This is the foundation your `flying_wing_quadplane` model runs on. Commands verified June 2026.

| Component | Version | Installs to |
|---|---|---|
| ArduPilot (ArduPlane SITL) | latest `master` | `~/ardupilot` |
| Gazebo | **Harmonic (LTS, → Sep 2028)** | apt (`gz-harmonic`) |
| `ardupilot_gazebo` plugin | `main` (gz-sim8) | `~/gz_ws/src/ardupilot_gazebo` |

**Why Harmonic:** it's the LTS that pairs cleanly with both 22.04 and 24.04 and is the version the ArduPilot plugin targets (`GZ_VERSION=harmonic`, `libgz-sim8-dev`). Don't mix with gazebo-classic (`gazebo11`) on the same machine.

> No ROS required — the ArduPilot plugin talks to SITL directly, keeping the stack lean.

---

## Option A — one-shot script (recommended)

```bash
# from this project folder, with the project copied to your home dir:
cp -r flying_wing_quadplane_sim ~/        # if not already there
cd ~/flying_wing_quadplane_sim
chmod +x setup_ubuntu.sh
./setup_ubuntu.sh                          # run as your normal user; it calls sudo when needed
```

The script is **idempotent** — safe to re-run; each stage skips work already done. When it finishes, open a new terminal (or `source ~/.bashrc`) and jump to **§3 Verify**.

---

## Option B — manual, stage by stage

### 1. ArduPilot SITL + dev environment

```bash
cd ~
git clone --recurse-submodules https://github.com/ArduPilot/ardupilot.git
cd ardupilot
Tools/environment_install/install-prereqs-ubuntu.sh -y     # installs MAVProxy, toolchain, pymavlink
. ~/.profile                                                # puts sim_vehicle.py on PATH
```

Sanity check (no Gazebo yet):

```bash
sim_vehicle.py -v ArduPlane --console --map     # map + console appear -> SITL works. Ctrl-C to stop.
```

> If you were just added to the `dialout` group, log out and back in once.

### 2. Gazebo Harmonic (OSRF apt repo)

```bash
sudo apt-get update
sudo apt-get install curl lsb-release gnupg
sudo curl https://packages.osrfoundation.org/gazebo.gpg \
     --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
     | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
sudo apt-get update
sudo apt-get install gz-harmonic
gz sim --version        # confirm
```

### 3. `ardupilot_gazebo` plugin

```bash
# dependencies (Harmonic = gz-sim8)
sudo apt install libgz-sim8-dev rapidjson-dev \
  libopencv-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl

mkdir -p ~/gz_ws/src && cd ~/gz_ws/src
git clone https://github.com/ArduPilot/ardupilot_gazebo
export GZ_VERSION=harmonic
cd ardupilot_gazebo && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j$(nproc)
```

### 4. Environment variables

Append to `~/.bashrc` (so every terminal finds the plugin, the stock models, **and your quadplane**):

```bash
cat >> ~/.bashrc <<'EOF'
# --- ArduPilot + Gazebo ---
export GZ_VERSION=harmonic
export GZ_SIM_SYSTEM_PLUGIN_PATH=$HOME/gz_ws/src/ardupilot_gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH}
export GZ_SIM_RESOURCE_PATH=$HOME/gz_ws/src/ardupilot_gazebo/models:$HOME/gz_ws/src/ardupilot_gazebo/worlds:$HOME/flying_wing_quadplane_sim/models:$HOME/flying_wing_quadplane_sim/worlds:${GZ_SIM_RESOURCE_PATH}
EOF
source ~/.bashrc
```

---

## 4. Verify — stock Zephyr (two terminals)

On Ubuntu the GUI + server run together with `-r` (unlike macOS):

```bash
# Terminal 1
gz sim -v4 -r zephyr_runway.sdf
# Terminal 2
sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON --map --console
```

In MAVProxy: `mode fbwa` → `arm throttle` → `rc 3 1800` → `mode circle`. If the Zephyr flies, the stack is good.

---

## 5. Launch YOUR quadplane

```bash
# Terminal 1
gz sim -v4 -r $HOME/flying_wing_quadplane_sim/worlds/quadplane_runway.sdf
# Terminal 2
sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON \
    --add-param-file=$HOME/flying_wing_quadplane_sim/config/flying_wing_quadplane.parm \
    --map --console
```

Then follow the first-flight checklist in the project `README.md`. Speed it up with `param set SIM_SPEEDUP 5`.

---

## Troubleshooting (Ubuntu)

| Symptom | Fix |
|---|---|
| `sim_vehicle.py: command not found` | `. ~/.profile` (it adds `ardupilot/Tools/autotest` to PATH) |
| `gz sim` opens but world is empty / model missing | `GZ_SIM_RESOURCE_PATH` not set in that terminal → `source ~/.bashrc` |
| Vehicle loads but won't respond to SITL | frame must be `gazebo-...` **and** `--model JSON`; check SITL prints "Connected to Gazebo" |
| `cmake` can't find `gz-sim8` | `export GZ_VERSION=harmonic` then re-run cmake; confirm `gz-harmonic` installed |
| Black viewport / no 3D (VM or headless) | needs OpenGL; in a VM use ≥ Ubuntu 22.04 with 3D accel, or run headless `gz sim -s` + connect a GUI |
| `gz-harmonic` conflicts with `gazebo11` | remove classic, or use the side-by-side guide; don't run both |
| Plugin not found at runtime | `GZ_SIM_SYSTEM_PLUGIN_PATH` must point at `ardupilot_gazebo/build` |

---

## 22.04 vs 24.04 notes

Both are fully supported by Harmonic and the ArduPilot prereqs script. On **24.04**, the ArduPilot installer handles the newer Python packaging (PEP 668); if you install Python packages by hand, add `--break-system-packages`. Everything else is identical.

---

### Sources
- Gazebo Harmonic — Ubuntu binary install — https://gazebosim.org/docs/harmonic/install_ubuntu/
- Using SITL with Gazebo (ArduPilot) — https://ardupilot.org/dev/docs/sitl-with-gazebo.html
- ardupilot_gazebo plugin — https://github.com/ArduPilot/ardupilot_gazebo
