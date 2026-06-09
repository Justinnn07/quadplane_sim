#!/usr/bin/env bash
# ============================================================================
#  run_sim.sh  —  FOOLPROOF launcher: flying-wing quadplane on ArduPilot SITL + Gazebo
#
#  Runs ANYWHERE:
#    * any OS            — macOS (server+GUI split) or Linux (single process)
#    * any Gazebo        — Garden / Harmonic / Ionic / Jetty (auto-detected)
#    * any location      — self-locates; cwd doesn't matter
#    * GUI or headless   — auto (headless if no display), or force with --headless
#  It wires GZ_SIM_RESOURCE_PATH (fixes "uri model:// not found" / error 14),
#  finds the ArduPilotPlugin + sim_vehicle.py, raises the open-file limit,
#  launches Gazebo + SITL together, and stops Gazebo on exit.
#
#  Usage:
#    ./run_sim.sh                  # auto GUI/headless, launch Gazebo + SITL
#    ./run_sim.sh --headless       # force no GUI (VM / WSL / CI / macOS render bug)
#    ./run_sim.sh --no-sitl        # just load the world (model/world sanity check)
#    ./run_sim.sh -- --speedup 5   # everything after -- is passed to sim_vehicle.py
#    ./run_sim.sh --help
#
#  Env overrides: WORLD_FILE, PARM_FILE, VEHICLE, FRAME, GZ_VERB, GZ_VERSION
# ============================================================================
set -uo pipefail

# ---------- self-locate (resolve symlinks; works from any cwd) --------------
SOURCE="${BASH_SOURCE[0]:-$0}"
while [ -h "$SOURCE" ]; do
  D="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"; case "$SOURCE" in /*) ;; *) SOURCE="$D/$SOURCE";; esac
done
ROOT="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# ---------- config (override via env) ---------------------------------------
WORLD="$ROOT/worlds/${WORLD_FILE:-quadplane_runway.sdf}"
PARM="$ROOT/config/${PARM_FILE:-flying_wing_quadplane.parm}"
VEHICLE="${VEHICLE:-ArduPlane}"
FRAME="${FRAME:-gazebo-zephyr}"
GZ_VERB="${GZ_VERB:--v4}"
HEADLESS=""; RUN_SITL=1; EXTRA_SITL=""

say(){ printf '\033[1;36m[run_sim]\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31m[run_sim] ERROR:\033[0m %s\n' "$*" >&2; }
die(){ err "$*"; exit 1; }
usage(){ sed -n '2,28p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'; }

# ---------- args ------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -H|--headless) HEADLESS=1 ;;
    --gui)         HEADLESS=0 ;;
    --no-sitl)     RUN_SITL=0 ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; EXTRA_SITL="$*"; break ;;
    *)             die "unknown arg: $1  (try --help)" ;;
  esac
  shift
done

OS="$(uname)"

# ---------- raise open-file limit (macOS 256 / Linux 1024 are too low) -------
ulimit -n 65535 2>/dev/null || ulimit -n 10240 2>/dev/null || ulimit -n 4096 2>/dev/null || true

# ---------- require gz, detect version -> release name ----------------------
command -v gz >/dev/null 2>&1 || die "'gz' not found. Install Gazebo (Harmonic recommended) and open a new shell."
if [ -z "${GZ_VERSION:-}" ]; then
  GZ_MAJOR="$(gz sim --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
  case "$GZ_MAJOR" in
    7) GZ_VERSION=garden;; 8) GZ_VERSION=harmonic;; 9) GZ_VERSION=ionic;; 10) GZ_VERSION=jetty;;
    *) GZ_VERSION=harmonic;;
  esac
  export GZ_VERSION
fi

# ---------- resource path: makes model://flying_wing_quadplane resolve -------
export GZ_SIM_RESOURCE_PATH="$ROOT/models:$ROOT/worlds:${GZ_SIM_RESOURCE_PATH:-}"

# ---------- locate the ArduPilotPlugin build dir ----------------------------
plugin_dir=""
for d in $(printf '%s' "${GZ_SIM_SYSTEM_PLUGIN_PATH:-}" | tr ':' ' ') \
         "$HOME/gz_ws/src/ardupilot_gazebo/build" \
         "$HOME/ardupilot_gazebo/build" \
         "$HOME/ardu_ws/src/ardupilot_gazebo/build" \
         "$HOME/src/ardupilot_gazebo/build"; do
  [ -n "$d" ] || continue
  if ls "$d"/libArduPilotPlugin.* >/dev/null 2>&1; then plugin_dir="$d"; break; fi
done
if [ -n "$plugin_dir" ]; then
  export GZ_SIM_SYSTEM_PLUGIN_PATH="$plugin_dir:${GZ_SIM_SYSTEM_PLUGIN_PATH:-}"
else
  err "ArduPilotPlugin not found on common paths. If Gazebo can't load it, build it:"
  err "    cd ~/gz_ws/src/ardupilot_gazebo && GZ_VERSION=$GZ_VERSION cmake -B build && cmake --build build -j"
  err "  or: export GZ_SIM_SYSTEM_PLUGIN_PATH=/path/to/ardupilot_gazebo/build"
fi

# ---------- locate sim_vehicle.py (only if launching SITL) ------------------
if [ "$RUN_SITL" = "1" ]; then
  if ! command -v sim_vehicle.py >/dev/null 2>&1; then
    . "$HOME/.profile" 2>/dev/null || true
    for d in "$HOME/ardupilot/Tools/autotest" "$HOME/ardupilot/tools/autotest"; do
      [ -x "$d/sim_vehicle.py" ] && { export PATH="$d:$PATH"; break; }
    done
  fi
  command -v sim_vehicle.py >/dev/null 2>&1 || die \
    "sim_vehicle.py not found. Add ArduPilot to PATH (e.g. export PATH=\"\$HOME/ardupilot/Tools/autotest:\$PATH\") and retry."
fi

# ---------- headless auto-detect (Linux without a display) ------------------
if [ -z "$HEADLESS" ]; then
  if [ "$OS" = "Linux" ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    HEADLESS=1; say "no display detected -> headless"
  else
    HEADLESS=0
  fi
fi

# ---------- preflight -------------------------------------------------------
[ -f "$WORLD" ] || die "world not found: $WORLD"
[ -f "$PARM" ]  || die "param file not found: $PARM"
[ -f "$ROOT/models/flying_wing_quadplane/model.config" ] \
  || die "model.config missing: $ROOT/models/flying_wing_quadplane/model.config"

say "project    : $ROOT"
say "OS/Gazebo  : $OS / $GZ_VERSION ($(gz sim --version 2>/dev/null | head -1))"
say "mode       : $([ "$HEADLESS" = 1 ] && echo headless || echo GUI)   ulimit -n: $(ulimit -n)"
say "plugin     : ${plugin_dir:-<NOT FOUND - see warning above>}"

# ---------- launch ----------------------------------------------------------
GZ_PIDS=""
cleanup(){ trap - EXIT INT TERM; echo; say "stopping Gazebo…"; for p in $GZ_PIDS; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

say "starting Gazebo…"
if [ "$HEADLESS" = "1" ]; then
  gz sim $GZ_VERB -s -r "$WORLD" & GZ_PIDS="$GZ_PIDS $!"          # server only
elif [ "$OS" = "Darwin" ]; then
  gz sim $GZ_VERB -s -r "$WORLD" & GZ_PIDS="$GZ_PIDS $!"          # macOS: server +
  gz sim $GZ_VERB -g             & GZ_PIDS="$GZ_PIDS $!"          #        GUI separately
else
  gz sim $GZ_VERB -r "$WORLD"    & GZ_PIDS="$GZ_PIDS $!"          # Linux: one process
fi

if [ "$RUN_SITL" = "0" ]; then
  say "Gazebo up (--no-sitl). Ctrl-C to stop."
  wait; exit 0
fi

say "waiting for Gazebo…"; sleep 4

if [ "$HEADLESS" = "1" ]; then UI=""; else UI="--map --console"; fi
say "starting ArduPilot SITL ($VEHICLE)…"
# shellcheck disable=SC2086
sim_vehicle.py -v "$VEHICLE" -f "$FRAME" --model JSON --add-param-file="$PARM" $UI $EXTRA_SITL

# SITL exited -> EXIT trap stops Gazebo
