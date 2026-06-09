#!/usr/bin/env bash
# ============================================================================
#  setup_macos.sh
#  Wire up:  ArduPilot SITL  +  ardupilot_gazebo plugin  → your EXISTING Gazebo Jetty
#  Target :  macOS (Apple Silicon or Intel), Gazebo Jetty (gz-sim10) already installed
#
#  You said you've installed gz-jetty already, so this does NOT install Gazebo.
#  It builds the ArduPilot bridge against Jetty and sets everything up to run together.
#  Run as your normal user.  Time: ~15-30 min (ArduPilot prereqs + plugin compile).
# ============================================================================
set -euo pipefail

ARDUPILOT_DIR="$HOME/ardupilot"
GZ_WS="$HOME/gz_ws"
PLUGIN_DIR="$GZ_WS/src/ardupilot_gazebo"
SIM_DIR="$HOME/flying_wing_quadplane_sim"
GZ_VER="jetty"                 # Gazebo Jetty == gz-sim10
RC="$HOME/.zshrc"              # macOS default shell is zsh

log()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

# ---- 0. checks -------------------------------------------------------------
[ "$(uname)" = "Darwin" ] || { echo "macOS script. On Linux use setup_ubuntu.sh."; exit 1; }
command -v brew >/dev/null 2>&1 || { echo "Homebrew required: https://brew.sh"; exit 1; }
if command -v gz >/dev/null 2>&1; then
  log "Gazebo found: $(gz sim --version 2>/dev/null | head -n1)"
else
  warn "'gz' not on PATH. Make sure Gazebo Jetty is installed and try a new shell first."
fi
# raise open-file limit (macOS default is a tiny 256 -> Gazebo will exhaust it)
ulimit -n 65535 2>/dev/null || ulimit -n 10240 2>/dev/null || \
  warn "Could not raise open-file limit; see SETUP_macOS_Jetty.md (sysctl/launchd)."
log "open-file limit (this session): $(ulimit -n)"

# ---- 1. ArduPilot SITL + macOS dev env -------------------------------------
if [ ! -d "$ARDUPILOT_DIR/.git" ]; then
  log "Cloning ArduPilot…"
  git clone --recurse-submodules https://github.com/ArduPilot/ardupilot.git "$ARDUPILOT_DIR"
else
  log "ArduPilot present — syncing submodules…"
  git -C "$ARDUPILOT_DIR" submodule update --init --recursive
fi
log "Installing ArduPilot macOS prerequisites (MAVProxy, pymavlink, toolchain)…"
( cd "$ARDUPILOT_DIR" && Tools/environment_install/install-prereqs-mac.sh -y )
# shellcheck disable=SC1091
. "$HOME/.profile" 2>/dev/null || true

# ---- 2. plugin build deps (gz headers come from your Jetty install) --------
log "Installing plugin dependencies via Homebrew…"
brew install rapidjson opencv gstreamer || warn "brew reported an issue; continuing."

# ---- 3. build ardupilot_gazebo against Jetty (gz-sim10) ---------------------
mkdir -p "$GZ_WS/src"
[ -d "$PLUGIN_DIR/.git" ] || git clone https://github.com/ArduPilot/ardupilot_gazebo "$PLUGIN_DIR"
log "Building ardupilot_gazebo (GZ_VERSION=$GZ_VER)…"
export GZ_VERSION="$GZ_VER"
mkdir -p "$PLUGIN_DIR/build"
( cd "$PLUGIN_DIR/build" \
    && cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    && make -j"$(sysctl -n hw.ncpu)" )

# ---- 4. environment variables (idempotent append to ~/.zshrc) --------------
log "Writing Gazebo env vars to ~/.zshrc…"
add_line(){ grep -qF -- "$1" "$RC" 2>/dev/null || echo "$1" >> "$RC"; }
add_line "# --- ArduPilot + Gazebo Jetty (added by setup_macos.sh) ---"
# install-prereqs-mac.sh adds sim_vehicle.py to PATH via bash files, which zsh ignores -> add it here.
add_line "export PATH=\"$ARDUPILOT_DIR/Tools/autotest:\$PATH\""
add_line "export GZ_VERSION=$GZ_VER"
add_line "export GZ_SIM_SYSTEM_PLUGIN_PATH=$PLUGIN_DIR/build:\${GZ_SIM_SYSTEM_PLUGIN_PATH}"
add_line "export GZ_SIM_RESOURCE_PATH=$PLUGIN_DIR/models:$PLUGIN_DIR/worlds:$SIM_DIR/models:$SIM_DIR/worlds:\${GZ_SIM_RESOURCE_PATH}"
add_line "ulimit -n 65535 2>/dev/null || ulimit -n 10240 2>/dev/null || true"

log "SETUP COMPLETE."
cat <<EOF

Open a NEW terminal (or: source ~/.zshrc), then launch everything together:

    cd $SIM_DIR && ./run_sim.sh

Or smoke-test the stock Zephyr first (macOS needs server + GUI in SEPARATE terminals):
    Terminal 1:  gz sim -v4 -s -r zephyr_runway.sdf
    Terminal 2:  gz sim -v4 -g
    Terminal 3:  sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON --map --console
EOF
