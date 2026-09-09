# Roguelite prototype

To edit terrain and enemy placement, use the **Maps** tab in Godot. See the [Roguelite map editor guide](map-editor.md) for painting, enemy markers, saving, and direct playtests.

Choose **Roguelite** from the main menu. Surveyor is free; Lancer and Sapper each cost 10 salvage in Ships. All three share permanent upgrades and reuse Jump's controls, movement, capture mechanics, enemy simulation, icons, and ship art. Jump and Battle Royale remain separate modes.

## Expedition

A run has eight encounters, selected one jump at a time on a branching star chart. Launch from the hangar opens the chart; meet the arena's territory goal, then choose Star Chart after the sector-clear fanfare. Goals rise by encounter depth: **60%, 65%, 70%, 75%, 80%, 85%, 90%, 90%**, capped at 90%. Alternate routes at the same depth share the goal. The map preview, HUD, and progress bar display that destination's target. Hull and the three installed systems carry forward; ability cooldowns refresh. The last sector completes the expedition.

The survey route retains the original progression below. Alternate destinations use a different arena shape while enemy difficulty follows encounter depth.

| Sector | Arena outline | Introduction |
| --- | --- | --- |
| 1 | Square, 52 × 52 cells | Small opening; one Anomaly, no turret or blockers. |
| 2 | Square, 60 × 60 cells | Two interior pylons with walkable rails. |
| 3 | Notched square, 68 × 68 cells | Opposing edge notches, two pylons, two Anomalies covering opposite sides. |
| 4 | Square, 68 × 68 cells | Four interior pillars. |
| 5 | Square, 68 × 68 cells | Two deep slices entering from the top edge. |
| 6 | Notches, 80 × 68 cells | Two pylons inside a notched outline; three Anomalies. |
| 7 | Bridge, 80 × 68 cells | Two lobes, one pylon each, connected through a narrow crossing. |
| 8 | Island, 80 × 68 cells | A 24 × 24 rock core with a walkable rail; corruption begins. |

The chart has shared opening, fourth, and final encounters, with two destinations at every other depth. Routes stay in their lane between forks and merges, without diagonal cross-links. Routes are generated once per expedition and stay fixed while selecting. The alternate destination at each fork is one of the encounter kinds below, never repeating the previous fork's kind. The selected destination previews its actual arena coast, threats, and reward. Hull, carried salvage, installed systems, and the traveled route remain visible. Nodes use symbols for each kind and the finale; only the focused destination gets a label. The expanded map has a compact status row above and an arena/threat/bonus strip below. Empty system slots and baseline reward copy are omitted. The focused reachable incoming route lights up, while completed nodes show checkmarks. Click any node to inspect its arena, threats, and reward, including locked or past destinations. Left/Right browses columns and Up/Down switches nodes. Only a connected destination in the next column can launch with Jump or Enter; other previews show Locked or Cleared. Escape banks and exits from the chart.

### Encounter kinds

The kind table lives in `scripts/roguelite_sectors.gd` and drives the chart symbol, the threat strip, the reward line, arena placement, and the clear rule. Enemy difficulty always follows encounter depth.

| Kind | Offered from depth | Arena additions | Clear rule | Reward |
| --- | --- | --- | --- | --- |
| Survey | 1 (fixed lane) | None | Depth territory goal | Normal |
| Salvage | 2 | Two extra pickups, a second turret | Depth territory goal | Two extra pickups |
| Repair | 2 | None | Depth territory goal | One hull restored on clear, capped at the ship's starting maximum |
| Beacon | 2 | Two beacon discs (three from depth 5), radius 5 cells | Every beacon fully enclosed; no territory goal | +1 salvage per beacon |
| Cargo | 3 | One cargo pod at a time, two runs (three from depth 5) | Every pod delivered; no territory goal | +2 salvage per delivery |
| Breach | 5 | One breach disc, radius 4 cells, seeding corruption | Breach sealed **and** the depth territory goal | +3 salvage on seal |
| Rival | 3 | One AI cutter on a seed disc, radius 3 cells | Depth territory goal | +3 salvage if the rival is driven off |

Beacon and cargo sectors keep their area milestones, so cards still come from territory while the clear comes from the objective; territory alone never clears them and the bar scales to 100%. The goal label reads Beacons n/N or Cargo n/N, with the separate percentage explicitly labeled Territory. After transit and the arena intro finish, a briefing modal shows the selected sector, encounter, goal, instructions, and reward over the dimmed loaded arena. Enemies, infection, and gameplay timers wait until Begin Sector is confirmed with Enter, the controller confirm button, or a click. Held launch/skip input must be released first. The star chart previews the goal; the pause screen keeps the instructions available during play. Cargo reminders switch to returning to safe land while carrying; a sealed breach switches to its remaining territory target. Pickup, delivery, drop, enclosure relocation, beacon capture, and breach seal feedback remain visible for four seconds of active gameplay, preserving the notice through card rewards and pauses. Objective discs are placed after pickups and turrets, entirely in the void and clear of rails, so survey, salvage, and repair keep their existing placements.

**Beacon.** A beacon is captured when every cell of its disc is claimed land; a trail crossing it does not count. Each Anomaly guards one open beacon: beyond three radii it is pulled back toward the disc, inside that range it wanders, so windows open and close. A disc holding an Anomaly cannot be enclosed because the claim flood reaches it. Rings spin faster while an Anomaly sits inside; an inner arc shows how much of the disc is claimed.

**Cargo.** The pod is picked up by contact: the trail head steps onto it, a ridden lance reaches it (casting the tether over it is not contact), or an exposed Sapper walks onto it. A pod on an exposed tether stays in place until the rider reaches it. While carrying, every Anomaly hunts the ship. The pod is delivered when the ship is safe again: a completed cut, or a Sapper stepping back onto land. Losing a hull or an Anchor recovery drops the pod back at its cell; if that cell has become land, or the pod is enclosed without contact, it relocates to open void far from the ship. The HUD explains that enclosure alone is not delivery and reports the relocation. Each delivery moves the next pod.

**Breach.** Corruption is active at any depth in a breach sector, seeded only from the breach disc, and the open disc re-infects itself every spread tick so it cannot be cleansed, only sealed by enclosure. The label shows the infected share of the arena in magenta once it passes 15%; at 25% the ship takes a hit and the infection collapses back to the disc, then grows again. Sealing pays, stops the spread for good, and restores the depth goal; remaining infection still cleanses under captures. Corruption cards join that sector's draft pool. Reaching the breach does not unlock the Containment upgrade track; that still needs sector 8. The guard range, hunt rate, and breach limit are playtest values.

**Rival.** A second cutter, drawn in orange, competes for the void using Battle Royale's planner (`scripts/rival_cutter.gd`): it walks its own land, cuts three-leg loops into open void, and claims whatever its loop walls off from every Anomaly, judged the same way as your captures. It never takes your land; your coast, hardened walls, and rock are solid to it. Its land stays void to you: cut through it and enclose it to take it back, and stolen cells count toward the goal like any first capture. Contact follows Battle Royale: if its line crosses your exposed trail, your line is lost and you return to your anchor with a short shield and no hull lost, unless Hardlight, Phase, Ion, or a hardened Leap wall protects you. Stepping on its line, casting a lance across it, or an Anomaly beam crossing it sends the rival back to its land. Land closing over its line does the same, and land taken from under it displaces it to its nearest cell. Taking its last cell drives it off for 3 salvage. Stasis and Ion freeze it. The rival never appears at depth 8, so it never shares a sector with corruption. Its speeds and loop sizes are playtest values.

The act uses angular, mostly square Jump silhouettes instead of an oval or stretched cross. On the survey route, the first three fields grow in capturable area; later fields vary topology. Interior pylons and the island use Jump's rock cutouts with one-cell walkable rails. Anomaly counts rise from one at depths 1–2, to two at 3–5, to three at 6–8. Notched, sliced, and bridge destinations always have at least two, including when offered early. The first two spawn on opposite sides with legal, non-overlapping full beams; the third starts toward the upper region. Enemies remain free to move after spawning. The chart reports the selected destination's actual count.

Every sector keeps at most two starting Sparx; survey and repair encounters at depths 2–8 have one turret and no spawners. Existing Anomaly speed/size progression remains. Clear screens retain the celebration and Star Chart button without shape announcements or tactical hints. The gameplay HUD also omits shape names.

**Surge.** Every sector has a stall clock. Twenty seconds without a land change, a death, or an objective event surfaces a surge: an orange disc of radius 3 in live void, clear of every objective disc, the cargo pod, and any Anomaly's reach. It telegraphs for 2 seconds, then counts down 15 seconds on an outer arc with the seconds shown beside it. Enclosing the whole disc pays 2 salvage and resets the clock. Letting it lapse costs the sector: the first two misses each add a Sparx to the coast patrol, later misses speed the Anomaly by 10% each, up to 50%. Authored maps that override enemies skip the Sparx and go straight to speed. The clock and the countdown freeze in pause, reward, draft, and briefing phases; Stasis and Ion freezes do not stop them. If no open pocket exists the surge retries five seconds later. All values are playtest values.

The island is an inner coast: first cut to its rail, walk around it, then cut outward. Bridging without enclosing a region claims only the trail. Initial safe rails and rock do not advance territory or card milestones; the shared victory threshold uses the same capturable-area denominator.

Cells remain square. A 160 × 104 backing grid permits wider arenas without changing movement speed. The territory bar stays above the field and installed systems below. Entry traces the playable coast without an extra square frame. Jump's own arena sizing remains unchanged.

First-time captures fill the bar. Draft count follows actual capturable area, excluding rock and starting rails: fewer than 3,800 cells gives one choice at 35%; 3,800–4,399 gives two at 25% and 55%; 4,400 or more gives three at 20%, 40%, and 60%. Three is the maximum. The bar and draft screen show only that arena’s earned/remaining choices. Captured-cell particles travel to the bar before cards appear. Large captures queue every earned choice, including those on the winning cut. The simulation pauses during reward delivery, drafting, replacement, and installation. Repeated territory never earns progress twice.

The first three survey sectors give one choice each, gradually filling the three system slots. The full survey route gives thirteen choices; alternate routes vary with arena size. Each draft presents three cards, from which the player chooses one. Once slots are full, every installed system below rank III is guaranteed an upgrade choice, including owned systems whose acquisition conditions no longer apply. Full builds no longer roll random replacements. Rank II increases the principal effect by 25%; rank III by 50%. Anchor instead reduces recharge time by the corresponding factor. Cards and pause show resulting values.

When fewer than three upgrades remain, the unused choices are filled in this order: **Salvage Cache** (+3 salvage), **Thruster Tuning** (+5 percentage points of movement speed), and **Recovery Shield** (+0.5 seconds of respawn protection). With all systems at rank III, all three bonus choices appear. These rewards use no slots. Passive bonuses stack, carry between sectors, appear on the pause screen, and reset with card ranks on a new expedition. Cache salvage counts toward expedition earnings and is banked through normal settlement; Extractor does not multiply this fixed reward. Keep Build (Escape or click) still passes a full-build draft and resolves queued rewards normally.

Drafts, installation, and clears retain synth cues, radial pulses, and beam effects. Star Chart appears after 2.2 seconds. Intermediate clears keep the focus on the completed sector. Salvage banks exactly once when the expedition ends by completion, defeat, or early exit. Continuing between sectors does not settle the run.

## Controls and hangar

- WASD / arrows: move or face. Surveyor holds Space to draw, Shift for slow draw. Lancer presses Space to fire and ride a line. Sapper holds Space to charge and releases to detonate.
- Claimed interiors and coasts use the ship's normal speed. The displayed ship follows grid movement at its travel speed instead of repeatedly easing to a stop at each cell; lance riding and Leap landing keep their distinct travel rates.
- Q: the opening movement module; hold and release to aim Leap. E / Ctrl: Afterburner or Hardlight, if installed. Only one of these secondary active systems can be equipped at a time.
- Escape during play pauses. Resume preserves the cut; End Expedition banks salvage. Escape at an intermediate clear banks and exits.
- In a rival sector, a rival line across your trail destroys the trail and returns you to your anchor without costing a hull; crossing the rival's line does the same to it.
- Arrows and Enter, or mouse: navigate and choose. R during drafting spends a Scanner rescan, when available.
- Back, Upgrades, and Ships sit at top left; Launch stands alone at top right. The salvage balance is in the footer.
- Upgrades shows all six linear tracks in one continuous scrolling list. Use the mouse wheel or drag the scrollbar; keyboard focus automatically scrolls its track into view. The detail inspector stays fixed on the right. Up/Down changes focus; Left/Right browses ranks. Click a node to inspect, then Upgrade to buy. Only the next rank can be purchased. Rank 5 and 10 diamonds mark milestones.
- Ships supports previewing without buying; Unlock/Select performs the action. Purchases also select the ship. Unaffordable action text and borders are red; the currency glyph stays consistent with pickups.

## Permanent systems

Every track has ten ranks, costing 2 salvage initially and 1 more for each following rank. The inspector displays concrete before/after values. Reactor text adapts to the selected ship.

| System | Per rank | Rank 5 | Rank 10 |
| --- | --- | --- | --- |
| Engines | +2% movement speed. | Safe movement primes +30% speed for the first 2 seconds of the next cut or charge. | Boost lasts 3 seconds. |
| Hull | +0.5 seconds protection after losing a hull, from a 2.5-second baseline. | One extra hull per run. | Two extra hulls total. |
| Reactor | +3% ability recharge rate; also lance recharge or Sapper charge speed. | Each capture refunds 1 second of cooldowns. | Refund increases to 2 seconds. |
| Scanner | +2 percentage points chance for a new offered system to start at rank II. | One rescan per sector. | Two rescans per sector. |
| Extractor | +2% salvage yield. | One extra pickup per sector. | Two extra pickups per sector. |
| Containment | 3% less corruption exposure accumulated per second. | Captures cleanse 2 cells beyond their border. | Cleansing extends 4 cells. |

Containment becomes purchasable after reaching sector 8. Hull no longer mixes its shield benefit with corruption resistance. At Containment rank 10, overload takes about 5.7 seconds of continuous exposure instead of 4. Engines' milestone and Slipstream share the same boost; the card can improve its strength without stacking a second copy.

The first earned draft always presents Hardening, Leap, and Dash at rank I. It cannot be rescanned and does not spend a Scanner charge. Subsequent drafts offer passive systems or one E-bound active system; the installed movement module can appear as a rank upgrade once the three slots are full. Unselected movement modules stay out of later drafts. Space retains the selected ship's native action; a successful Lancer activation no longer displays a redundant center-screen announcement.

Scanner rescans replace offers while slots remain open without consuming a capture reward. Once slots are full, the guaranteed choices cannot be rescanned and no rescan charge is spent. Installed rank-III systems cannot be offered as upgrades. Corruption cards enter the pool in sector 8 and in breach encounters; Void Harvest becomes eligible when turrets are present.

Salvage comes from enclosing board pickups using the shared Flux hexagon, collection effects, and enclosure logic. A normal pickup pays 1, or 1.25 on a Surveyor slow cut, before Extractor. Three baseline pickups give 3 salvage per sector. Captured turrets/nests grant 0.25; Void Harvest adds 1.25 at rank I. Territory and victory alone award no currency. Extractor's fractional rewards accumulate and persist between runs so early +2% purchases are not lost to rounding. Hazard enclosure rewards, objective rewards, surge captures, and Void Harvest feed the same award path.

## Temporary systems

These are rank-I effects. Ranked versions retain the trigger and strengthen the principal effect.

| System | Effect |
| --- | --- |
| Hardening | Q: hardens the trail behind Surveyor or Lancer at 10 cells/second for 3 seconds. Sapper instead braces its charging disc against one hit. 12-second recharge. |
| Leap | Hold Q from a safe coast to aim; release to leap to the target and build an exposed wall in both directions. 16-second recharge after landing. |
| Dash | Q: moves forward at 3× speed for 0.3 seconds; rock still blocks movement. Surveyor draws, Lancer boosts along its coast or tether, and Sapper moves freely. 8-second recharge. |
| Afterburner | E: +80% cut/riding/charge speed for 3 seconds; 14-second recharge. |
| Hardlight | E: protects the trail or charging disc for 2 seconds; 18-second recharge. |
| Anchor | A lethal exposed hit returns to safe ground without losing a hull; 24-second recharge. |
| Ion Thread / Ion Field | Contact repels enemies and freezes them for 1.5 seconds; 10-second recharge. |
| Clean Sweep | Captures cleanse corruption within 6 cells beyond new territory. |
| Containment | A capture of at least 8% halts corruption spread for 8 seconds. |
| Slipstream | Two seconds moving safely primes +30% cut/charge speed for 2 seconds. |
| Reactor Loop | Every third capture removes 6 seconds from cooldowns. |
| Compression | Cuts below 4% add +15% cut/charge speed, up to +45%; a cut of at least 8% resets it. |
| Phase Line / Phase Charge | Protects the first 1.5 seconds of a cut or charge. |
| Void Harvest | Enclosing a nest or turret grants 1.25 extra salvage. |
| Stasis Wake | Captures freeze enemies for 1 second. |

Protection cards do not prevent corruption overload. Corruption grows in free territory every three seconds; capture cleanses enclosed infection. Sapper accumulates exposure when occupying infection. Other ships accumulate it while their exposed trail crosses infection.

Sector briefings show only the objective and a Start button above a dark, softly blurred arena. Detailed instructions remain on pause. The HUD separates **Personal Exposure** (100% causes a hull hit) from breach **Arena** infection (25% causes a hit even without contact). Exposure takes four seconds of continuous contact at base resistance, drains when contact ends, and resets on capture. Pause contact times account for permanent Containment ranks. Sealing a breach stops growth; remaining purple still causes exposure until cleansed by capture. The pause explanation updates after sealing.

## Saves and verification

Profile version 6 lives in `user://galaxtix_roguelite.json`, separate from Jump's currencies, ownership, upgrades, and records. Version 1–5 profiles retain their ranks, ships, and unlocks. Existing salvage balances and fractional remainders convert at 4 old units to 1 new unit, matching the price reduction; conversion remainders are preserved. Version 6 profiles do not convert again. The profile stores highest reached sector, fractional salvage, and Containment access. Existing profiles that reached the old corruption sector retain that unlock. Unknown or unowned ship selections fall back to Surveyor.

Failed purchases refund their price and restore ownership/rank; failed selection saves restore the prior ship. End-of-run save failures retain rewards in memory and offer Retry Save. Active runs do not resume after closing the game.

`RogueliteGame` extends `Game` through stat, capture, economy, and presentation hooks. Shared defaults retain Jump's behavior. It never swaps the campaign save dictionary.

Capture rebuilds sample occupancy into padded byte masks, restrict coast/border searches to exposed regions, and upload territory pixels in one buffer. This preserves the original border ordering, coast segments, and dither pixels. Corruption strokes are cached in field-local coordinates and rebuilt after spreading, cleansing, captures, hardening, or recovery; their color pulse still animates each frame. Corruption spreads from the previous tick's mask using integer neighbour indices, preserving one-cell growth and blocked-cell rules.

Run with Godot 4.7:

```text
godot --headless --path . --quit-after 1200 tests/roguelite_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 1200 tests/roguelite_ships_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 1200 tests/roguelite_expedition_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 4000 tests/roguelite_movement_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 4000 tests/roguelite_timing_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 4000 tests/roguelite_targets_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 4000 tests/roguelite_objectives_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 4000 tests/roguelite_optimization_smoke.tscn -- --nosave --no-steam
```

The expedition suite covers all eight arenas, repeated full-beam spawn validation, opposing-side coverage and real middle cuts, real inter-sector transit, queued winning-cut rewards, persistent builds and hull, bounded slots/ranks, upgrades/replacement/cancellation, Scanner offers and rescans, six tracks, Containment gating, fractional salvage, area-based draft limits, version-6 currency conversion, single settlement, generated routes, mouse preview/jump input, alternate geometry, and salvage/repair encounters. Existing suites cover ship controls, captures, card effects, input, transactions, text bounds, and mode isolation. Assertions count as failures even if Godot exits with code zero.

For graphical screenshots, append `--rogue-shots=<absolute directory>`. For disk persistence checks, point APPDATA and LOCALAPPDATA at `.godot/test-user` and append `--rogue-save-test` to the original suite; it validates that directory before enabling writes.

The movement suite exercises all three opening modules on all three ships through real input, including hardening captures, disc protection, leap aiming and wall completion, dash speed and rock collisions, cooldowns, separate Q/E bindings, fixed opening offers, and the silent Lancer activation.

The timing suite compares coast and interior travel for every roguelite ship, with base and upgraded engines at 30, 60, and 120 FPS. It measures visual speed consistency and verifies that releasing input and hitting rock stop the ship without drift.

The targets suite uses real captures just below and exactly at every sector goal, checks progress-bar scaling and the 90% cap, and verifies Jump retains its existing 75% goal.

The objectives suite covers the kind table and two hundred generated routes, disc placement on every stage, beacon capture, guarding, drift, milestone-plus-clear ordering, cargo pickup and delivery for all three ships, drops on death, Anchor recovery, hardened land and enclosure, Anomaly hunting, breach seeding, re-seeding, pressure hits, shields, sealing, goal-before-seal ordering, and the surge: no surge before the stall limit, live-void placement clear of Anomalies, telegraph then window, capture payout, Sparx then Anomaly-speed escalation, a paused window, and coexistence with beacons; and the rival: seed placement on every stage, autonomous planning and claims, a seedless flood that cannot swallow the arena, trail contact both ways with protections, lance and beam cuts, blasts taking its land, freezes, elimination, and the depth-goal clear. The expedition suite's route check now launches every alternate kind on the built-in arenas.

The optimization suite compares geometry and texture output with frozen reference algorithms across arenas, random cell states, empty/full fields, and all galaxy patterns. It checks corruption growth and visual cache invalidation after captures, cleansing, hardening, Anchor recovery, and restart.

This slice follows the brainstorming document's numerical upgrades, milestones, distinct ships, and changing run builds. Further galaxies, permanent card-family unlocks, and equipment/loadouts remain future work. Values and corruption's introduction in sector 8 need player balance feedback before extending the campaign further.
