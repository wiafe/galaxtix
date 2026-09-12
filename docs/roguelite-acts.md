# Acts and bosses

The roguelite has 24 encounters split across three separate eight-sector charts. Each act has seven regular sectors and ends in a boss; Next Act opens the next chart. The existing void color is unchanged. Captured interiors use Jump's territory treatments: Foundry has blue checkerboard, Infestation green stripes, and Reactor violet dots, with matching coast colors. Rival and Race opponents retain their own territory styles. Act identity also comes from chart backgrounds, route shapes, arena layouts, enemy rosters and boss art.

## Content

| Act | Maps | Arena / boss |
| --- | --- | --- |
| Foundry | 09, 24, 25, 10, 11, 12, 26, 13 or 33 | Loading Bay, Service Bay, Transfer Platform, Press Works, Assembly, Coolant Channels, Final Assembly, Foreman's Floor / Grinding Floor |
| Infestation | 27, 14, 28, 15, 16, 17, 29, 18 or 34 | Spore Edge, Nest Pockets, Split Nest, Rootways, Brood Chambers, The Coil, Hive Approach, Queen's Nest / Thorn Garden |
| Reactor | 30, 19, 31, 20, 21, 22, 32, 23 or 35 | Shield Entry, Reactor Bridge, Beam Channels, Containment Rings, Shield Array, Fractured Core, Core Approach, Reactor Heart / Prism Vault |

Five bosses use shielded cores: enclose all three yellow installations to disable their attacks and expose the core, then capture it with a subsequent cut. Thorn Maw instead has a large body that you carve apart. Foreman installations fire aimed volleys; Queen hatcheries spawn mites; Reactor relays fire a beam, break land, and fire volleys. Grinder cutters sweep a limited arc; Thorn Maw thorns fire radial spores with rotating gaps; Prism Warden lenses fire three locked beams. Rock blocks beams, and claimed land blocks spores. Warning markers precede attacks. Captured installations stay disabled. Stasis and menus pause attack timers. Bulwark seals finish normally before awarding captures.

Thorn Maw opens for six seconds after its spore burst. Close loops through the exposed body to remove chunks; those cells become player territory and the silhouette shrinks. Severed thorns stop firing. Carve 60% to expose its heart, then enclose it on a subsequent cut. Cuts and detached Bulwark seals begun during the opening may finish after the timer expires. Pause and Stasis freeze the cycle. Armor never regrows captured chunks.

Boss salvage is 5 / 7 / 10 by act, plus one hull up to the run's normal limit. Rewards pay once, followed by a short capture effect. The final core completes the expedition. Territory percentage alone cannot bypass a boss.

Locked cores share the Anomaly's cycling colors and shimmering halo to signal that they cannot be captured. Once exposed, the halo and lock disappear and the core turns steady yellow.

## Edit in Godot

Open Maps, select the act arena, paint terrain and move enemies as usual. Boss maps are 13/33 (Foundry), 18/34 (Infestation), and 23/35 (Reactor). Both alternatives appear as sector 08 in the editor; a run selects one per act. Keep **one Boss Core**, **three Boss Relays**, and at least one void enemy. Leave a radius of four open cells around the core and two around each relay. Save and Playtest validate these constraints; Playtest automatically selects Boss for boss arenas.

For Thorn Maw (map 34), the Core marker positions its heart and the Relay markers position its three spore thorns. The editor shows the generated body in purple; moving these markers reshapes it. Terrain clips the body footprint.

The resource Inspector exposes `act_theme` and `boss_id`. Existing IDs are `foreman`, `grinder`, `brood_queen`, `thorn_maw`, `reactor_heart`, and `prism_warden`; ordinary maps leave `boss_id` empty. Core and relay markers do not replace the void enemy needed by the capture simulation. Test all three ships after editing terrain.

`scripts/roguelite_acts.gd` holds each act's map, enemy and boss pools. Each exclusive pool has two bosses. Route generation randomly picks one per act; the run still has 24 encounters. A new boss needs an authored arena, an entry in `BOSSES`, its ID in the appropriate act pool, and behavior/art in `scripts/roguelite_boss.gd`. Adding a name alone does not implement a boss.

Maps live in `maps/roguelite_09.tres` through `roguelite_35.tres`; `maps/defaults/` supplies Restore snapshots. `tools/build_act_maps.gd` only creates missing act resources. It never replaces saved maps. Original maps 01–08 remain intact and serve Arcade and legacy test fixtures.

Run `tests/roguelite_acts_smoke.tscn -- --nosave --no-steam` for route and pool coverage, map and chart bounds, unchanged void, beam warning/range/cover/damage, boss attack/pause, all-ship captures for the five installation bosses, rewards and progression checks. Run `tests/thorn_maw_smoke.tscn` with the same flags for body carving, vulnerability grace, all-ship seals/captures, lost thorns, heart exposure, rewards, reset and editor footprint. Balance is a first pass pending hands-on playtesting.

Map IDs remain stable so existing edits keep working. The Act picker lists maps in progression order, rather than numeric filename order. Branches share the scheduled shape so later enemies and layouts cannot appear early; encounter kinds and upper/lower placement still vary. `map_depth()` supplies each arena's playtest depth.
