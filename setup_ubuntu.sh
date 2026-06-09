#!/usr/bin/env bash
# ============================================================================
#  setup_ubuntu.sh
#  Stand up:  ArduPilot SITL  +  Gazebo Harmonic  +  ardupilot_gazebo plugin
#  Target  :  Ubuntu 22.04 (Jammy) or 24.04 (Noble) LTS   [June 2026 commands]
#
#  Run as your NORMAL user (NOT root). It will call sudo only for apt/curl.
#  Safe to re-run — each stage skips work that's already done.
#  Time: ~20-40 min (mostly the ArduPilot prereqs + plugin compile).
# ============================================================================
set -euo pipefail

# ---- install locations (edit if you like) ----------------------------------
ARDUPILOT_DIR="$HOME/ardupilot"
GZ_WS="$HOME/gz_ws"
PLUGIN_DIR="$GZ_WS/src/ardupilot_gazebo"
SIM_DIR="$HOME/flying_wing_quadplane_sim"     # this project (copy it into $HOME)
GZ_VER="harmonic"

log()  { echo -e "\n\033[1;32m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m!!  $*\033[0m"; }

# ---- 0. sanity -------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || { echo "Do not run as root. Run as your user; sudo is called when needed."; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release 2>/dev/null || true
log "Detected: ${PRETTY_NAME:-unknown}"
case "${VERSION_ID:-}" in
  22.04|24.04) : ;;
  *) warn "Targets Ubuntu 22.04/24.04 LTS. '${VERSION_ID:-?}' may work but is untested." ;;
esac

# Raise the open-file limit for this build session. Gazebo + SITL + a parallel
# compile open many file descriptors; Ubuntu's default soft limit (1024) is too low.
ulimit -n 65535 2>/dev/null \
  || warn "Could not raise open-file limit (hard cap?). See SETUP_Ubuntu_LTS.md if you hit 'too many open files'."
log "open-file limit (this session): soft=$(ulimit -Sn)  hard=$(ulimit -Hn)"

# ---- 1. ArduPilot SITL + dev environment -----------------------------------
if [ ! -d "$ARDUPILOT_DIR/.git" ]; then
  log "Cloning ArduPilot (with submodules)…"
  git clone --recurse-submodules https://github.com/ArduPilot/ardupilot.git "$ARDUPILOT_DIR"
else
  log "ArduPilot present — syncing submodules…"
  git -C "$ARDUPILOT_DIR" submodule update --init --recursive
fi

# Preempt the SLOW wxPython source build (MAVProxy depends on it). The prebuilt
# system package installs in seconds; pip then sees wxPython satisfied and skips
# compiling wxWidgets from source (which can take 30-60 min or segfault on 24.04).
log "Installing prebuilt wxPython (python3-wxgtk4.0) to avoid a long source build…"
sudo apt-get update
sudo apt-get install -y python3-wxgtk4.0 \
  || warn "python3-wxgtk4.0 unavailable — MAVProxy may fall back to building wxPython from source."

log "Installing ArduPilot prerequisites (MAVProxy, toolchain, pymavlink)…"
( cd "$ARDUPILOT_DIR" && Tools/environment_install/install-prereqs-ubuntu.sh -y )
# shellcheck disable=SC1091
. "$HOME/.profile" 2>/dev/null || true   # puts Tools/autotest (sim_vehicle.py) on PATH

# ---- 2. Gazebo Harmonic (OSRF apt repo) ------------------------------------
if ! command -v gz >/dev/null 2>&1; then
  log "Adding OSRF apt repo + installing Gazebo Harmonic…"
  sudo apt-get update
  sudo apt-get install -y curl lsb-release gnupg
  sudo curl https://packages.osrfoundation.org/gazebo.gpg \
       --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
       | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y gz-harmonic
else
  log "Gazebo already installed: $(gz sim --version 2>/dev/null | head -n1)"
fi

# ---- 3. ardupilot_gazebo plugin --------------------------------------------
log "Installing plugin build dependencies…"
sudo apt-get install -y \
  libgz-sim8-dev rapidjson-dev \
  libopencv-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl \
  cmake build-essential

mkdir -p "$GZ_WS/src"
if [ ! -d "$PLUGIN_DIR/.git" ]; then
  log "Cloning ardupilot_gazebo…"
  git clone https://github.com/ArduPilot/ardupilot_gazebo "$PLUGIN_DIR"
fi
log "Building ardupilot_gazebo plugin…"
export GZ_VERSION="$GZ_VER"
mkdir -p "$PLUGIN_DIR/build"
( cd "$PLUGIN_DIR/build" \
    && cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    && make -j"$(nproc)" )

# ---- 4. environment variables (idempotent append to ~/.bashrc) -------------
log "Writing Gazebo env vars to ~/.bashrc…"
RC="$HOME/.bashrc"
add_line(){ grep -qF -- "$1" "$RC" 2>/dev/null || echo "$1" >> "$RC"; }
add_line "# --- ArduPilot + Gazebo (added by setup_ubuntu.sh) ---"
add_line "export GZ_VERSION=$GZ_VER"
add_line "export GZ_SIM_SYSTEM_PLUGIN_PATH=$PLUGIN_DIR/build:\${GZ_SIM_SYSTEM_PLUGIN_PATH}"
add_line "export GZ_SIM_RESOURCE_PATH=$PLUGIN_DIR/models:$PLUGIN_DIR/worlds:$SIM_DIR/models:$SIM_DIR/worlds:\${GZ_SIM_RESOURCE_PATH}"
add_line "ulimit -n 65535 2>/dev/null || true   # raise open-file limit for Gazebo/SITL"

# ---- done ------------------------------------------------------------------
log "SETUP COMPLETE."
cat <<EOF

Open a NEW terminal (or run: source ~/.bashrc), then:

  # 1) Smoke-test the stack with the stock Zephyr (two terminals):
  gz sim -v4 -r zephyr_runway.sdf
  sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON --map --console

  # 2) Fly YOUR quadplane (make sure $SIM_DIR exists in \$HOME):
  gz sim -v4 -r $SIM_DIR/worlds/quadplane_runway.sdf
  sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON \\
     --add-param-file=$SIM_DIR/config/flying_wing_quadplane.parm --map --console

If 'sim_vehicle.py' is not found, run:  . ~/.profile
If you were just added to the 'dialout' group, log out and back in once.
EOF
