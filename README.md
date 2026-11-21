# 50 Hertz — Sukamaju Control

A complete ten-stage Godot source demo about **SEBAB AKIBAT — cause and effect**. Build an electricity controller while watching its consequences in Desa Sukamaju. Original geometric placeholder art; no downloaded assets, addons or external libraries.

## Run

Open `E:\Apps\Godot\Project\50Hertz\project.godot` with **Godot 4.7.2 Standard**, then press **F5**. The entry scene is `scenes/gameplay.tscn`; `main.tscn` references that scene for compatibility. Launch starts in borderless fullscreen at the monitor resolution unless a saved display preference says otherwise. Choose Start / Continue or Stage Select.

From PowerShell:

```powershell
& 'E:\Apps\Godot\Godot_v4.7.2-stable_win64_console.exe' --path 'E:\Apps\Godot\Project\50Hertz'
```

The layout uses a 1920×1080 canvas with an equal-width container below the shared toolbar. Village art and the GraphEdit workspace clip independently. Tested at 1280×720, 1920×1080 and 2560×1080. Menus scroll. Fullscreen/windowed and reduced motion are in Settings; F11 toggles display mode. UI scale options are 85%, 100%, 110%, 120% (use 85–100% at 720p).

## Controls

- Click a palette button to place a gate. Drag its title bar to move it.
- **Drag** a right output port to a left input port. One source may feed many inputs. Inputs accept one wire; replacing a wire requires explicitly disconnecting the old wire first.
- Drag an existing input wire away to disconnect, or select the component and choose **Inspect → Disconnect input**. Inspect also edits comparator thresholds/operators and timer delay.
- Select gates and press **Delete**. Mission terminals stay. **Undo / Redo** covers placement, movement, connections, deletion, settings, clear, starter restoration and program application.
- **Middle mouse:** pan. Graph toolbar or **Ctrl+wheel:** zoom. **Fit:** frame circuit. At wide circuits, zoom in to inspect labels and pan between terminals.
- **Space:** Run/Pause. **R:** reset test, preserving circuit. **Step:** one 0.05-second simulation tick while paused. Speed cycles 1× / 2× / 4×.
- **Esc:** cancel an active wire, otherwise close the temporary panel, otherwise pause menu. **H:** help. **F11:** fullscreen/windowed.
- **Board…:** save/load a design for this stage, snap, clear (confirmation), restore starter, reveal reference solution (confirmation). Design changes are undoable.
- **Program:** available from Stage 9. Apply validates the small language; it never executes GDScript.
- Menus support Tab/Shift+Tab and Enter; lists support arrows. Signals display 0/1 in addition to colors.

Editing is disabled during a run and enabled while paused. Editing then resuming continues the current grid state. Reset for a full controlled experiment. Reset clears latch/timer state and replays identical events. Opening menus freezes the simulation and preserves whether it was already paused. Load, equipment purchases and board restoration restart the test.

## Ten-stage progression

| Stage | Concept | Scenario and pass condition |
|---|---|---|
| 1 First Connection | Ports, wires, controls | Connect/toggle a safe lamp, disconnect/reconnect, Run/Pause/Step/Reset; no blackout risk. Clears immediately after the demonstrated checklist and final Run. |
| 2 After Sunset | NOT | Invert DAY to maintain supply at sunset. Predict the signal before running. 40s. |
| 3 Two Reasons to Act | OR | Respond to clouds and sunset; previous NOT branch is provided. 50s. |
| 4 Use the Battery Wisely | AND | Working backup starter; battery requires PEAK and CHARGED. No discharge outside peak. 65s. |
| 5 Stop the Chatter | SR memory / hysteresis | LOW_FREQ sets, HIGH_FREQ resets; at most four starts. Tutorial menu includes unstable direct-controller demonstration. 75s. |
| 6 Ready Before Reconnecting | On-delay / readiness | Start backup (3s physical startup), then wait 1s after readiness before reconnecting the district. 65s. |
| 7 Keep the Clinic On | Priority shedding | Respond to hydro fault while protecting clinic/homes; optional factory+mill interruptions combined ≤70s. 105s. |
| 8 Save the Surplus | Numeric comparisons / storage | Store solar surplus, discharge after sunset. No charge/discharge conflict; finite energy and losses. 100s. |
| 9 From Wires to Code | Safe programming | Translate the shown NOT/OR and AND rules into two program assignments. 90s. |
| 10 The Long Night | Independent engineering | Forecast warning, storm, festival, hydro fault and sunset; avoid blackout, preserve essential service and industry budget ≤170s. 125s. Completion opens the demo summary. |

Stages unlock sequentially. First three stages award three stars for learning/completion without hint/time penalties. Skip/Replay Tutorial is available. Early tutorials highlight relevant controls and inspect actual connections/actions; early commissioning probes verify input/output behavior, not node positions or one required topology. Later stages validate the resulting services and resource use.

Later scoring is displayed before testing: mandatory completion; fuel **and** emission target; compactness/start limit/minimal shedding target. First completions of Stages 4–10 award two credits once. Upgrades cost two credits: battery capacity +600 EU, generator fuel/emissions −30%, or battery efficiency 90%→95% each direction. All stages and efficiency stars have verified baseline reference solutions. Gates unlock through learning, not purchase.

## Cause and effect

The village and live ports show **cause → logic → action → consequence**. Example: cloud event → CLOUD=1 → OR=1 → backup readiness → supply recovers and clinic stays supplied. Port digits and wire brightness show signal state. Selecting a card highlights its connected path. Equipment state, shed industry (amber), failed services (red), day/night, battery energy and frequency history are visible.

Open **Cause / effect log** for timestamped causes, sensor transitions, gate transitions, commands, readiness and recovery. Results are built from this run's recorded events. Failure identifies the event, controller commands, supply/demand/frequency and affected services; Retry retains the circuit. **Compare** shows previous vs current final frequency, fuel, critical outages, generator starts and shedding, with run durations and separate circuit/equipment-change labels. Compare equal-duration or complete runs; the same deterministic event timeline is used every time.

## Game rules / simplified model

These values are teaching rules, **not an engineering-grade grid model**:

- Hydro 45 kW; hydro fault 15. Solar 30 in clear daylight, 7 in cloud, zero at night. Stage 8 uses 50 kW solar.
- Backup produces 30 kW when ready. Stages 6/10 have 3s/2s startup; timers cannot accelerate this.
- Demand 75 kW; peak +20. Shedding factory removes 18; mill removes 12. Critical loads cannot be voluntarily shed. Stage 1 uses a safe 45 kW training load. Stage 5 demand alternates 70/45; Stage 6 demand is 45 until its 30 kW district reconnects.
- Battery baseline 1800 EU, initially 1200 except Stage 8 (empty). One EU is one game kW·second. Discharge up to 24 kW (Stage 8:30), charge up to 20 from actual available surplus only. Charge adds `power × dt × efficiency`; discharge costs `power × dt / efficiency`. Energy is clamped to capacity. Simultaneous charge/discharge is rejected and fails the test.
- Numeric SUPPLY is generation **before battery flow**, avoiding self-triggered comparator oscillation; DEMAND includes actual connected loads. BATTERY_LEVEL is stored EU.
- Frequency approaches `50 + (supply − demand) × 0.025`, damping `dt × 1.8`. Safe band 49.5–50.5 Hz. Unsafe frequency accumulates stress; five seconds trips the grid. Safe operation recovers 0.6 stress-seconds per second. Both over- and undersupply matter.
- Clinic, homes and water share the protected aggregate bus. A grid trip records critical outages. Factory/mill intentional shedding is separately accumulated in building-seconds. Water has no voluntary shedding command; its final-stage allowance is therefore stricter in practice because any blackout fails.
- Fuel = diesel kW·seconds (×0.7 with efficiency); emission game units = diesel kW·seconds ×0.65 (×0.7 upgraded).

`resources/stages/stage_catalog.gd` centralizes plant/battery parameters, durations, timelines, allowed tools, scoring, hints, starters and reference circuits. Shared frequency/stress/efficiency constants are in `scripts/grid_sim.gd`.

## Logic / program semantics

NOT, AND, OR, XOR, NAND, NOR, reset-dominant SR LATCH, configurable on-delay TIMER and numeric COMPARE are implemented. Unconnected inputs are false/zero. SET is top and RESET bottom. Memory updates simultaneously from a snapshot each fixed tick; pausing and rendering never advance it. Feedback cycles are rejected even around explicit memory components. Use sensors to set/reset memory rather than wiring a feedback loop.

The rule language accepts permitted named sensors, TRUE/FALSE, numeric constants/comparisons, NOT/AND/OR and parentheses. Each line assigns a permitted output. `#` introduces a comment. No loops, calls, files, network, engine/OS access or arbitrary GDScript. Invalid programs block Run/Step with line-numbered errors. Duplicate assignments or a gate plus script driving one output are rejected. Programs are limited to 4096 characters, 256 tokens/expression and 16 nested parentheses. Example:

```
BACKUP = NOT DAY OR CLOUD
BATTERY = PEAK AND CHARGED
```

## Architecture and replaceable assets

- `scenes/gameplay.tscn`: editable persistent gameplay hierarchy and pre-instanced menus; `main.tscn` is a compatibility alias. `scripts/main.gd` binds controls and orchestrates fixed-step simulation.
- `scenes/ui/*.tscn`: authored menus, settings, inspector, program editor, results and completion. `scripts/ui/game_menus.gd` binds existing controls without creating UI nodes.
- `scenes/ui/logic_editor.tscn`, `scenes/ui/components/*.tscn`: editable editor/palette and individual gate-card templates. `scripts/ui/circuit_editor.gd` binds actions, instantiates authored card templates and traces signals.
- `scripts/ui/equal_split.gd`: exact equal halves, independent of content minimums.
- `scenes/ui/village_view.tscn`: editable monitor labels/panels/chart; `scenes/village/building.tscn`: editable equipment labels; `scripts/ui/village_view.gd` binds the map/state and draws art/flow, while `frequency_chart.gd` draws trace lines only.
- `scripts/logic_board.gd`: graph validation, typed numeric sensor propagation, gate/memory evaluation, undo/redo and serialization. Refactored from the original prototype.
- `scripts/logic/rule_program.gd`: bounded lexer/parser/interpreter, no eval.
- `scripts/grid_sim.gd`: deterministic environment, dispatch, energy accounting, service metrics, structured event recording and explanations. Expanded from the original model.
- `scripts/stage_objectives.gd`: behavior-based commissioning checks.
- `scripts/tool_tutorial.gd`: action-driven tutorial progression.
- `scripts/demo_save.gd`: versioned validated persistence and one-time rewards.
- `resources/stages/stage_catalog.gd`: all ten stage definitions, starters and reference solutions.
- `tests/run_tests.gd`, `tests/ui_tests.gd`: simulation and rendered UI verification; screenshots live under `tests/`.

## Saves and recovery

`user://demo_v2.json` stores display/accessibility preferences, progression, best results, tutorial completion, credits/upgrades and stage circuits with component settings/program text. Writes use a temporary file and rename. Missing, incompatible or malformed saves recover to defaults; invalid circuit data is discarded safely. Circuit loading never overwrites progression. Reset Progress requires confirmation. The prototype's old `progress.json`/`circuit_*.json` files are left untouched; this demo uses a new versioned file.

On Windows user data is normally `%APPDATA%\Godot\app_userdata\50 HERTZ — Sukamaju Control\`. Testing uses a test flag and separate temporary files, without changing player progression.

## Validation and limits

See `TEST_RESULTS.txt` and `SOLUTIONS.md`. Run:

```powershell
& 'E:\Apps\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --quit
& 'E:\Apps\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/run_tests.gd
& 'E:\Apps\Godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/ui_tests.gd -- --test-ui
```

The demo has no audio, production art, localization, exported executable, AC power flow, voltage/line physics or independent per-building electrical networks. Circuit interaction uses drag-to-wire and palette click-to-place; there is no component drag from palette. The model is deliberately aggregate and critical-service outages occur on grid trips. Large circuits may require pan/zoom; Fit can make dense boards small. Visual verification covers the local Windows/NVIDIA environment, not every monitor/DPI/OS combination. Human novice playtesting is still useful for tutorial wording and difficulty tuning.

## All UI is scene-authored

Open `scenes/gameplay.tscn` for the complete UI, `scenes/ui/main_menu.tscn` for the main menu, `scenes/ui/pause_menu.tscn` for pause, and `scenes/ui/logic_editor.tscn` for the editor. All other forms are under `scenes/ui/`; gate cards are under `scenes/ui/components/`. The shared theme is `resources/ui/control_room.tres`.

There are no runtime UI constructors or code-drawn UI text in the game scripts. Menus are pre-instanced in gameplay.tscn and shown/hidden. Placed cards instantiate authored PackedScene templates; they are not built out of controls in code. Scripts still update live values, colors, visibility and signals. The art, signal wires and chart traces use drawing code.

See `AUTHORING.md` for the file map and editing workflow. Containers manage UI positions through child order, spacing and size flags; stage buildings use free Node2D transforms. Reload source scenes from disk if an older root-only main.tscn remains open in Godot. F5 uses the canonical gameplay scene.

Validation after migration: 187 core + 49 rendered UI + 28 authoring + 103 scene-UI checks passed. Scene tests cover every form/template, standalone editor placement, menu callbacks, confirmations, saved circuit loading, component settings, script rejection/application and a static audit forbidding constructed controls and draw_string UI text.

## Clear and unlock indicators

Completing a goal opens a prominent **STAGE CLEARED** result with a **Continue to Stage NN** button near the top and an announcement that the next stage is unlocked. Stage 1 clears on the first simulation tick after its demonstrated tool sequence and final Run; later stages complete their required scenario timeline. Failed or unfinished tests cannot use the Next action.

Stage Select shows **CLEARED**, **NOT CLEARED** (available), or **LOCKED**, plus best stars and a cleared-stage total. The gameplay header also shows the current stage's completion status. Clear records persist in best results. Availability is derived from successful completion of every preceding stage, including after save reload; an old unlocked counter alone cannot bypass locks. Cleared stages remain replayable. All indicators are authored in the editable result, stage-select and gameplay scenes.

## Replay and electricity flow

**Replay Stage** after a clear and **Restart Stage** in the pause menu start a fresh attempt: morning/time zero, initial energy/equipment, empty component memory, starter circuit and tutorial checklist. Saved clears, best stars, rewards, upgrades and all already-unlocked stages remain intact. The header says REPLAY / NEW RUN so the saved clear is not mistaken for this attempt being complete. Toolbar Reset during an unfinished test still preserves the current circuit (including the tutorial's required Reset action); after a completed test it starts fresh. Failed-test Retry keeps the design for correction. Loading/restoring a design or purchasing equipment resets the test while preserving the design just chosen.

The village now has visible, directional power routes above roads and below buildings. Cyan arrows point **generator → GRID**; green arrows point **GRID → connected buildings**. Amber arrows point **GRID → battery** while charging; discharge reverses the battery route into the grid. Moving arrowheads travel the full bent route. Inactive paths are dashed without moving arrows; intentionally disconnected loads have amber break markers and outages red markers. Starting equipment does not display flowing power until it actually produces electricity. An empty battery, shed district or tripped grid cannot show phantom flow. Reduced-motion mode retains fixed directional arrowheads.

The per-stage PowerFlow instance comes from `scenes/village/power_flow.tscn`; its Inspector exports control colors, line width, spacing and visual speed. `FlowLegend` in `scenes/ui/village_view.tscn` is editable UI. Flows illustrate aggregate connectivity and direction, not per-line AC quantities.
