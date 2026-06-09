# Flying-Wing Quadplane — ArduPilot SITL + Gazebo (Ubuntu)

A **proper, physics-grounded** Gazebo Harmonic model of your flying-wing quadplane, wired to ArduPilot SITL. Mass, inertia, geometry, aero, and thrust are all derived from **your** XFLR5 file `iteration3current2realnewwinglet` — not generic defaults.

It's built by composing the two official `ardupilot_gazebo` reference models — **iris** (rotor thrust) and **Zephyr** (wing + elevons) — re-parameterized to your airframe, so it inherits the proven LiftDrag/channel conventions.

```
flying_wing_quadplane_sim/
├── models/flying_wing_quadplane/
│   ├── model.sdf        # the vehicle: body + 4 lift rotors + pusher + 2 elevons + aero + ArduPilot bridge
│   └── model.config
├── worlds/
│   └── quadplane_runway.sdf
├── config/
│   └── flying_wing_quadplane.parm   # ArduPlane QuadPlane firmware config
└── README.md
```

---

## 1. Design basis (derived from your data)

| Quantity | Value | Source |
|---|---|---|
| All-up weight | **10.8 kg** | 6.3 kg point masses + 4.5 kg wing structure |
| CG | x = 0.383 m from nose datum | XFLR5 mass model |
| Inertia (roll / pitch / yaw) | **Ixx 1.94 / Iyy 0.46 / Izz 2.37** kg·m² | computed; passes Izz≈Ixx+Iyy check |
| Span / area / MAC / AR | 2.375 m / 0.859 m² / 0.447 m / 6.57 | wing sections |
| CL0 / CLα | 0.192 / 4.265 rad⁻¹ | T1 polar @22 m/s |
| CD0 / induced k | 0.0124 / 0.0465 | T1 polar |
| Cm0 / static margin | +0.009 / **+3.1 % MAC (stable)** | T1 polar |
| Cruise | CL 0.42 @ **α ≈ 3°**, drag 5.2 N | from AUW |
| Hover thrust | 26.5 N/motor (×4) | AUW/4 |
| Sized rotor max | **67 N/motor → T/W 2.54, hover 63 %** | thrust model |

> **Candor — static margin is tight (+3.1 %).** Stable, but pitch will be lively and CG-sensitive. Flyable in sim; on the real aircraft, nudging CG ~10–20 mm forward would give a more comfortable 6–10 % margin. The sim is the safe place to test that.

---

## 2. Channel & motor map (model.sdf ↔ ArduPilot)

| SDF control ch | ArduPilot output | Function | Joint / rotor | Spin |
|:--:|:--:|---|---|:--:|
| 0 | SERVO1 | Elevon Left (77) | `flap_left_joint` | — |
| 1 | SERVO2 | Elevon Right (78) | `flap_right_joint` | — |
| 2 | SERVO3 | Throttle / pusher (70) | `pusher_joint` | — |
| 4 | SERVO5 | VTOL Motor 1 (33) | `rotor_0` front-right | CCW |
| 5 | SERVO6 | VTOL Motor 2 (34) | `rotor_1` rear-left | CCW |
| 6 | SERVO7 | VTOL Motor 3 (35) | `rotor_2` front-left | CW |
| 7 | SERVO8 | VTOL Motor 4 (36) | `rotor_3` rear-right | CW |

---

## 3. One-time setup (Ubuntu)

You already have the stack if you followed the install steps. Otherwise:

1. **Gazebo Harmonic** + **ArduPilot SITL** + **`ardupilot_gazebo` plugin** (see `ardupilot.org/dev/docs/sitl-with-gazebo.html`). Confirm the stock Zephyr flies first.
2. Drop this folder in `$HOME` and put its models/worlds on the Gazebo resource path (append to `~/.bashrc`):

```bash
export GZ_SIM_RESOURCE_PATH=$HOME/flying_wing_quadplane_sim/models:$HOME/flying_wing_quadplane_sim/worlds:${GZ_SIM_RESOURCE_PATH}
# (GZ_SIM_SYSTEM_PLUGIN_PATH should already point at ardupilot_gazebo/build from the plugin install)
source ~/.bashrc
```

---

## 4. Run it (Ubuntu — server + GUI together)

```bash
# Terminal 1 — Gazebo
gz sim -v4 -r $HOME/flying_wing_quadplane_sim/worlds/quadplane_runway.sdf

# Terminal 2 — ArduPilot SITL (frame name needs "gazebo-", model JSON)
sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON \
    --add-param-file=$HOME/flying_wing_quadplane_sim/config/flying_wing_quadplane.parm \
    --map --console
```

`gazebo-zephyr` is only the JSON transport frame (ArduPlane on port 9002); the `.parm` turns it into your quadplane. Speed it up with `param set SIM_SPEEDUP 5`.

---

## 5. First-flight checklist (do these in order)

```text
# A. HOVER (validates lift rotors, mixing, hover throttle)
MAV> mode QLOITER
MAV> arm throttle
MAV> rc 3 1600            # raise collective; should lift around mid-high stick (~63%)
   -> hold a stable hover, check it doesn't flip (motor order/spin) or drift hard.

# B. FORWARD FLIGHT (validates wing lift + pusher + elevons)
MAV> mode QHOVER          # climb to ~40 m first
MAV> mode FBWA
MAV> rc 3 1700            # pusher spins up, aircraft accelerates; wing takes the load

# C. TRANSITION (the main thing this sim exists to de-risk)
   -> as airspeed passes Q_ASSIST_SPEED (14 m/s) the lift motors throttle down;
      watch for altitude sag or pitch kick during the hand-off.
```

---

## 6. Calibration — 3 things to verify on the FIRST run

I sized everything from physics, but two of the LiftDrag conventions are sign/scale-sensitive and I can't run Gazebo from where this was built. Expect to touch these once:

- **[C1] Wing lift sign** (`<a0>` on both wing halves, currently `-0.045`). In FBWA at speed the wing must make **upward** lift and hold level. If it pushes the nose under / won't hold altitude, flip the sign to `+0.045` on both `base_link` wing LiftDrag blocks.
- **[C2] Hover throttle** (rotor `<area>`, currently `0.0068`). In QHOVER read `CTUN.ThO` (hover throttle). If it's not ~0.55–0.70, rescale: `area_new = 0.0068 × (observed_hover / 0.63)²`, then update `Q_M_THST_HOVER`.
- **[C3] Rotor spool** (velocity `<cmd_max>`, currently `2.5`). If rotors feel sluggish / can't reach RPM to climb, raise to `5`–`10` on the four motor `<control>` blocks.

Standard symptom→fix: **flips on takeoff** → motor order or spin direction (swap channel↔rotor or `<multiplier>` sign); **slow yaw drift** → CW/CCW assignment.

---

## 7. Tuning workflow (after it flies)

1. **Hover:** `QSTABILIZE` → tune `Q_A_RAT_RLL/PIT_P`, then `Q_AUTOTUNE` (switch to QAUTOTUNE mode, fly gentle).
2. **Forward flight:** `AUTOTUNE` mode in FBWA for roll/pitch; let TECS settle height/speed.
3. **Transition:** sweep `Q_ASSIST_SPEED`, `Q_TRANSITION_MS`; watch logs for altitude/pitch excursions.
4. Then: validate on real hardware (Simulation-on-Hardware), then first flight + in-air AUTOTUNE for final gains.

---

## 8. Open items — confirm these and I'll lock the numbers

1. **Propulsion data (EOLO 16×8 table).** I couldn't read its column units reliably, and a 16×8 implies far more thrust than a 10.8 kg quad needs at hover. Tell me: (a) the column headers/units, and (b) is that prop the **lift rotor** or the **pusher**? With the real static thrust-vs-throttle curve I'll set `Q_M_THST_EXPO` + rotor `<area>` to match your motors exactly.
2. **All-up weight.** Is **10.8 kg** (6.3 point + 4.5 wing) your true flying weight, or is there battery/payload beyond the XFLR5 model? If different, it's a one-line mass + thrust rescale.

Everything else is derived and locked.
