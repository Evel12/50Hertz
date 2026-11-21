# Editable UI and village scenes

All player-facing UI is authored in `.tscn` files. Code binds actions and updates data/state, without constructing controls, labels, menus, layouts, themes or gate ports. The frequency trace and village art use custom drawing; their labels and monitoring panels are saved controls too.

## Where to edit

| File | What you edit |
|---|---|
| `scenes/gameplay.tscn` | Complete gameplay layout, toolbar, objective/tutorial, village/lab split, editor actions and pre-instanced UIViews |
| `main.tscn` | Compatibility entry referencing gameplay.tscn; open the source gameplay scene to edit its hierarchy |
| `scenes/ui/main_menu.tscn` | Main menu |
| `scenes/ui/pause_menu.tscn` | Pause menu |
| `scenes/ui/stage_select.tscn` | Ten stage buttons |
| `scenes/ui/settings.tscn` | Display/accessibility controls |
| `scenes/ui/logic_editor.tscn` | Circuit palette, GraphEdit and preview cards |
| `scenes/ui/components/*.tscn` | Individual SENSOR, OUTPUT, NOT, AND, OR, XOR, NAND, NOR, LATCH, TIMER and COMPARE cards, labels and ports |
| `scenes/ui/component_inspector.tscn` | Input/output display, disconnect buttons, timer/comparator controls |
| `scenes/ui/script_editor.tscn` | Safe program editor, syntax help, validation label |
| `scenes/ui/board_menu.tscn` | Circuit save/load, starter, clear, snap and reference controls |
| `scenes/ui/result_screen.tscn` | Success/failure explanation, metrics and action buttons |
| `scenes/ui/demo_complete.tscn` | Demo completion summary |
| `scenes/ui/confirmation.tscn` | Confirmation overlay and buttons |
| `scenes/ui/hint.tscn`, `comparison.tscn`, `upgrades.tscn`, `help.tscn`, `tutorial.tscn` | Remaining panels |
| `scenes/ui/village_view.tscn` | Village labels, forecast, frequency chart, monitoring panels |
| `resources/ui/control_room.tres` | Shared theme, fonts/colors and control styles |
| `scenes/stages/stage_01.tscn` through `stage_10.tscn` | Distinct building/road/tree layouts |
| `scenes/village/building.tscn` | Shared building placeholder and editable status/name/control labels |

F5 starts `scenes/gameplay.tscn`. Reopen the source scene from disk if Godot still has an older root-only main.tscn open. Avoid saving that stale tab over the compatibility scene; choose Reload when Godot detects external file changes.

## UI editing workflow

1. Open a scene above in Godot's 2D view; select its root and press F to frame it.
2. In gameplay.tscn, expand `ScreenMargin → GameLayout`. Edit Header, Toolbar, EqualSplit, VillagePanel and LabPanel.
3. To edit an instanced menu or logic editor, open its source `.tscn` (the scene icon next to the instance). All controls exist before running. UIViews contains pre-instanced menus; runtime shows/hides them instead of creating new screens.
4. Container-managed controls move by reordering children and adjusting spacing, margins, minimum sizes and size flags. Containers intentionally control child positions for responsive sizing. Freeform controls use normal anchors/offsets.
5. Change button captions and theme overrides in the Inspector. Keep binding names, `metadata/action`, `metadata/menu_action`, `metadata/value_action` and `metadata/gate_kind`; behavior uses these keys rather than the caption. Runtime updates live metric/result text and visibility, not the structural layout.
6. Gate cards are instantiated only from their authored PackedScene templates as a player places components. Their labels/ports are saved in the template; the controller does not build them. The fixed palette buttons are all saved in logic_editor.tscn and are hidden/shown by stage availability.

Opening an individual menu `.tscn` runs a static preview with F6. Use F5 for the fully bound game. Menus share the theme resource and are editable independently.

## Preview and edit villages

Select VillageView in gameplay.tscn (or open village_view.tscn), then choose **Preview Stage**. **Map Scene Override** accepts a custom map PackedScene. Disable **Show Main Menu On Launch** on the gameplay root to test the selected stage directly.

Open a stage map to freely move its building Node2D instances with transform handles. Each has Role, Display Name, Appearance, Wall Color and Roof Color. Roles retain simulation binding: BACKUP readiness; BATTERY charging/discharging; FACTORY/MILL shedding; DISTRICT reconnection; LAMP switch; protected HOME/CLINIC/WATER grid status. Move native Line2D roads and Polygon2D trees separately. Power wires follow buildings and the GRID node.

Building art occupies roughly x=100–820, y=100–410 on the map's 900×790 reference canvas; lower space is monitoring. Leave room beneath equipment for status labels. Rendering preserves authored transforms.

The state indicators are CONTROL (applied) and NEXT (paused circuit preview). Timers/equipment only advance on Run/Step. Incorrect valid controllers can run: wrong commands can cause visible generation, waste, stress and dark buildings. A gate disconnected from every actuator has no physical effect; the missing command and resulting non-response are visible. Intentional shedding is amber; outages are red with dark windows.

Art is still placeholder geometry in village_building.gd. Its names/status/command/fault UI is now in building.tscn. Adding a decorative house does not automatically change aggregate load: simulation balance remains in stage_catalog.gd and grid_sim.gd.

## Code responsibilities and validation

- `main.gd`: bind existing gameplay controls, fixed-step simulation orchestration.
- `game_menus.gd`: bind existing menu signals and update labels/settings.
- `circuit_editor.gd`: instantiate authored card templates, update values/wires and handle edits.
- `frequency_chart.gd`: trace drawing only; text is in village_view.tscn.

`tests/scene_ui_tests.gd` checks every form/template, verifies no UI constructors or draw_string calls remain in runtime scripts, tests saved control actions and captures menu previews. Core, rendered UI and authoring suites remain available.

## Completion UI

`result_screen.tscn` contains ClearBanner, ProgressionInfo and the primary Next button above the detailed explanation. `stage_select.tscn` contains CompletionSummary, Legend and the ten state-labeled buttons. `gameplay.tscn` contains StageStatus in the header. Their geometry/styles remain editable; scripts update state text and button availability. `DemoSave.is_completed/is_unlocked` are the completion/lock source of truth. Stage-clear records survive replays and reloads.

## Electricity route artwork

Each stage map now contains `PowerFlow` as its first child. The shared source scene is `scenes/village/power_flow.tscn`, with exported generation/delivery/charging/fault colors, line width, arrow spacing and speed. It draws above behind-parent roads and below buildings so power cannot be hidden by road artwork. Actual simulation generation, battery flow and load connection state determine direction/activity. Change the scene-authored FlowLegend in village_view.tscn to edit its explanation. Source and delivery paths use separated lanes around the grid. Selecting an actuator in the logic editor emphasizes its corresponding route.

Replay starts a new local attempt with starter layout and tutorial; persistent completed-stage records and unlocks are not reset. The scene-authored result Retry button changes to Replay Stage for a successful result.
