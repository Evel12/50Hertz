# Verified reference circuits

The data-driven generators are `StageCatalog.solution(0)` through `.solution(9)` in `resources/stages/stage_catalog.gd`. The Board menu can reveal these circuits after confirmation. They are examples, not required topologies. Engine tests exercise all ten with baseline equipment at 30/60/144 rendering-frame schedules and 1×/4× speeds.

| Stage | Reference rule | Meaningful failure experiment |
|---|---|---|
| 1 | TEST_SWITCH → LAMP | Disconnect wire, toggle switch: lamp cannot follow. Safe bench, no blackout. |
| 2 | BACKUP = NOT DAY | No connection: sunset removes solar, backup remains off, grid trips. Early commissioning also catches incorrect DAY polarity. |
| 3 | BACKUP = (NOT DAY) OR CLOUD | Keep only NOT DAY: cloud event is ignored. |
| 4 | Preserve backup OR circuit; BATTERY = PEAK AND CHARGED | Constant battery command wastes energy outside peak. PEAK alone fails commissioning when CHARGED=0. |
| 5 | LOW_FREQ → LATCH SET; HIGH_FREQ → RESET; latch → BACKUP | LOW_FREQ directly to BACKUP creates repeated starts and exceeds four. The Tutorial menu can demonstrate it. |
| 6 | START_WARNING → BACKUP; GENERATOR_READY → TIMER (1s) → CONNECT_DISTRICT | Connect on warning: demand arrives before supply. Connect directly on READY: missing stabilization delay. Both fail. |
| 7 | BACKUP = (NOT DAY) OR HYDRO_FAULT; SHED_FACTORY = HYDRO_FAULT | Ignore fault: critical grid supply trips. Shed forever: industry budget exceeded. |
| 8 | SUPPLY >75 → CHARGE; SUPPLY <75 → BATTERY | Do not charge: empty storage cannot support evening. Both commands true: conflict is rejected. |
| 9 | Program: BACKUP = NOT DAY OR CLOUD; BATTERY = PEAK AND CHARGED | Starter FALSE assignments ignore weather/peak. Invalid syntax blocks test; gate + program on same output rejects multiple drivers. |
| 10 | START_WARNING → BACKUP; (PEAK OR HYDRO_FAULT) → SHED_FACTORY; HYDRO_FAULT → SHED_MILL; (PEAK AND HYDRO_FAULT) → BATTERY | Ignore storm/festival/fault: aggregate shortage trips the village. Leaving all actuators on creates a storage conflict or excessive shedding. |

NOT/OR/AND can be replaced by other unlocked circuits with equivalent behavior. Stage 9 must use program assignments. Reset-dominant latch behavior and on-delay timing are important: no feedback cycles and no timer-driven acceleration of physical generator startup.

In Stage 8, SUPPLY is available generation before battery flow. Clear-day generation is 95 kW, demand 75. Charge at 20 kW ×90% efficiency for 65s: 1170 EU. Evening discharge at 30 kW costs 33.33 EU/s, nearly exhausting storage by 100s. Capacity and rate limits are enforced. The final reference has about 3.3 EU remaining because the command samples the environment at fixed tick boundaries.

In Stage 10, backup starts on the 25s warning, before cloud at 30s. Factory shedding covers festival demand at 50s. At the 55s hydro fault, mill shedding and battery support cover the overlapping causes. Fault and peak clear at 85s and the controller releases their actions. Backup remains on through sunset. This is one baseline solution; storage/comparators/program combinations are alternatives.
