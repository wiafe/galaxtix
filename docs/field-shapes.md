# Field shapes

Two ideas borrowed from the Fillit teardown (`C:\Users\wiafe\Projects\Decompiled\fillit\analysis\FINDINGS.md`):
carved outlines and inner rails. Both live in `scripts/sector_arena.gd`; `Game.sector_layout` decides which
galaxies use it (`SectorArena.carved`).

## Carved outlines

`SectorArena.contains_cell(galaxy, level, x, y)` is the sector's silhouette. Everything outside it is rock, and
the coast (rim + 1 cells thick, matching the Bulk upgrade) hugs the carve, so the outline can be a plus, a
bridge, a notched slab or a square with bitten corners without any other work. Helix Reach carves sectors 1 to 7
as before (growing squares, a circle, a plus). Turret Belt now carves every sector:

| Sector | Outline | Pylons |
|---|---|---|
| 1 | 80-cell square | 2, railed |
| 2 | wide slab with notches bitten from top and bottom | 2 |
| 3 | plus | up to 3, only where they fit |
| 4 | two halves joined by a 24-cell bridge | up to 3 |
| 5 | moat: full square around a 24-cell core | the core |
| 6 | square with two slices cut in from the top edge | 3 |
| 7 | square with the corners bitten off | 4 |
| 8 | boss: full square | the fixed four |
| 9+ | full square | 4 |

Spawner Deep is untouched.

## Inner rails

Rock that does not touch the outer rock is a hole: a pylon, the moat's core. Every hole gets exactly one cell
of claimed coast around it, whatever the rim upgrade says. That ring is an island of coast: you can cut to it,
walk it, and start cuts from it. A trail that reaches it without enclosing anything simply becomes claimed land,
because the claim flood runs from the Anomaly and an unenclosed trail is just cells it could not reach. So the
first cut to a pylon builds a bridge, and the next cut from the pylon can enclose.

Sparx patrol `border` cells, so a rail is a patrol loop of its own until a bridge joins it to the coast.

Pylon rectangles still come from `Game.sector_shape` (seeded per sector); in a carved galaxy each one must sit
seven cells inside the silhouette so the rail is a real island. They are passed to `SectorArena.build` as holes.

## Checks

```
godot --headless --path . res://tests/arena_smoke.tscn -- --nosave
godot --path . -- --autotest=field:belt:5 --nosave --shots=<dir>
```

The smoke test checks every Belt sector: rock inside each pylon, a one-cell rail around it, nothing else claimed
that is not walkable from the start, and a cut from the coast to the moat's core that claims only the trail and
joins the core rail to the coast. The field autotest drops into any galaxy sector and takes two screenshots.

## Roguelite shape progression and Fillit reference

Roguelite now fits the existing Jump silhouettes to wide footprints through `SectorArena.contains_offset`. Its route is authored in `scripts/roguelite_sectors.gd`: small square, paired pylons, notched square, four pillars, sliced square, notches with pylons, bridge with pylons, and an island. The first act stays mostly square; the opening footprint matches Jump exactly; shape names and coaching text are omitted from the player HUD and clear screen. The island uses the same inner-rail builder as Turret Belt. Jump's masks, area accounting, and progression stay unchanged.

The local Fillit reference was checked against `C:/Users/wiafe/Projects/Decompiled/fillit/analysis/gameData_single.json`, `analysis/FINDINGS.md`, and the hole construction in `src/BoardCubeVisualHelper.cs`:

- `Already Taken` (index 1) combines holes and occupied land with a 50% target and no timer.
- `Moat` (12) uses holes with a 50% target and no timer; `Narrow Bridge` (20) uses holes and walls with a lower 35% target and 60 seconds.
- `Lock And Key` (41) introduces room/gate ordering through blocks and keys. `Use The Portals` (74) uses flags and portals with no percentage goal.
- These suggest teaching spatial mechanics before layering time pressure or objectives, and treating shape, target, and hazard budget as separate tuning knobs.

This pass uses that lesson for walkable island rails, inset coasts, and a narrower bridge. Roguelite territory goals rise from 60% to a maximum of 90% by encounter depth; card milestones remain tied to capturable arena size. Roguelite scales from one to three Anomalies, with at least two on divided layouts and opposite-side starting coverage. Pre-claimed footholds, gate/key rooms, moving walls, portals, and objective sectors remain future candidates. No Fillit code or map assets were imported.
