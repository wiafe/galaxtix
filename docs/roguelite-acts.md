# Acts and bosses

The roguelite has 24 encounters split across three separate eight-sector charts. Each act has seven regular sectors and ends in a boss; Next Act opens the next chart. The existing void color is unchanged. Captured interiors use Jump's territory treatments: Foundry has blue checkerboard, Infestation green stripes, and Reactor violet dots, with matching coast colors. Rival and Race opponents retain their own territory styles. Act identity also comes from chart backgrounds, route shapes, arena layouts, enemy rosters and boss art.

## Content

| Act | Maps | Arena / boss |
| --- | --- | --- |
| Foundry | 09, 24, 25, 10, 11, 12, 26, 13 | Loading Bay, Service Bay, Transfer Platform, Press Works, Assembly, Coolant Channels, Final Assembly, Foreman's Floor |
| Infestation | 27, 14, 28, 15, 16, 17, 29, 18 | Spore Edge, Nest Pockets, Split Nest, Rootways, Brood Chambers, The Coil, Hive Approach, Queen's Nest |
| Reactor | 30, 19, 31, 20, 21, 22, 32, 23 | Shield Entry, Reactor Bridge, Beam Channels, Containment Rings, Shield Array, Fractured Core, Core Approach, Reactor Heart |

Each boss starts shielded. Enclose all three yellow installations to disable their attacks and expose the core, then capture the core with a subsequent cut. Foreman installations fire aimed volleys; Queen hatcheries spawn mites; Reactor relays fire a beam, break land, and fire volleys. Warning markers precede attacks. Captured installations stay disabled. Stasis and menus pause attack timers. Bulwark seals finish normally before awarding captures.

Boss salvage is 5 / 7 / 10 by act, plus one hull up to the run's normal limit. Rewards pay once, followed by a short capture effect. The final core completes the expedition. Territory percentage alone cannot bypass a boss.

## Edit in Godot

Open Maps, select the act arena, paint terrain and move enemies as usual. Boss maps are 13, 18 and 23. Keep **one Boss Core**, **three Boss Relays**, and at least one void enemy. Leave a radius of four open cells around the core and two around each relay. Save and Playtest validate these constraints; Playtest automatically selects Boss for boss arenas.

The resource Inspector exposes `act_theme` and `boss_id`. Existing IDs are `foreman`, `brood_queen`, and `reactor_heart`; ordinary maps leave `boss_id` empty. Core and relay markers do not replace the void enemy needed by the capture simulation. Test all three ships after editing terrain.

`scripts/roguelite_acts.gd` holds each act's map, enemy and boss pools. There is currently one boss in each exclusive pool. A new boss needs an authored arena, an entry in `BOSSES`, its ID in the appropriate act pool, and behavior/art in `scripts/roguelite_boss.gd`. Adding a name alone does not implement a boss.

Maps live in `maps/roguelite_09.tres` through `roguelite_32.tres`; `maps/defaults/` supplies Restore snapshots. `tools/build_act_maps.gd` only creates missing act resources. It never replaces saved maps. Original maps 01–08 remain intact and serve Arcade and legacy test fixtures.

Run `tests/roguelite_acts_smoke.tscn -- --nosave --no-steam` for route, map, chart bounds, unchanged void, boss attack/pause, all-ship capture, reward and progression checks. Balance is a first pass pending hands-on playtesting.

Map IDs remain stable so existing edits keep working. The Act picker lists maps in progression order, rather than numeric filename order. Branches share the scheduled shape so later enemies and layouts cannot appear early; encounter kinds and upper/lower placement still vary. `map_depth()` supplies each arena's playtest depth.
