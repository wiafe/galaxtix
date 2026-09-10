# Roguelite prototype

To edit terrain and enemy placement, use the **Maps** tab in Godot. See the [Roguelite map editor guide](map-editor.md) for painting, enemy markers, saving, and direct playtests.

Choose **Roguelite** from the main menu. Surveyor is free; Lancer and Bulwark each cost 10 salvage in Ships. All three share permanent upgrades and reuse Jump's controls, movement, capture mechanics, enemy simulation, icons, and ship art. Jump and Battle Royale remain separate modes.

## Expedition

A run has **three acts of eight encounters**: seven regular sectors, then a boss. Each act has its own eight-sector chart, route shape, palette and backdrop. Defeating its boss reveals the next act. The void keeps the same color throughout. Hull and installed systems carry forward; ability cooldowns refresh.

| Act | Layouts and roster | Boss |
| --- | --- | --- |
| Foundry | Machinery islands and channels; Sparx, Turret, Rotor, Gunner Orb | The Foreman: capture weapons to stop its volleys. |
| Infestation | Rounded chambers, roots and pockets; Spawner, Brood Carrier, Chain Worm | Brood Queen: capture hatcheries to stop mites. |
| Reactor | Bridges, rings, shield pockets and hazards; Sniper, Ray Orb, Siege | Reactor Heart: disable beam, land-breaking and volley relays. |

Anomalies remain shared. Every boss requires capturing three installations, then enclosing its exposed core. Boss victories grant 5/7/10 salvage and one hull, capped at the normal hull limit. The final boss completes the expedition. Each act has an exclusive boss pool, currently with one boss; more bosses can be added without changing route generation.

Territory goals for the seven regular sectors are **60/60/65/65/70/70/75%**, **65/65/70/70/75/75/80%**, and **70/70/75/75/80/80/85%** by act. Objective encounters retain their own win conditions. One Race and one Rival appear somewhere in each full route, on either branch or a shared junction. Chart selection stays within the current act.

See [act content and boss editing](roguelite-acts.md). Maps 09–32 provide the new act arenas. The original eight maps remain available in the editor and Arcade.

## Encounter kinds

The kind table lives in `scripts/roguelite_sectors.gd` and drives the chart symbol, the threat strip, the reward line, arena placement, and the clear rule. Enemy difficulty always follows encounter depth.

For now, every new full expedition chart guarantees one Race and one Rival at different random depths from 3–7. Either can occupy the upper branch, lower branch, or shared fourth node. These are guaranteed chart choices; the player can still choose another branch.

| Kind | Offered from depth | Arena additions | Clear rule | Reward |
| --- | --- | --- | --- | --- |
| Survey | 1 (either branch) | None | Depth territory goal | Normal |
| Salvage | 2 | Two extra pickups, a second turret | Depth territory goal | Two extra pickups |
| Repair | 2 | None | Depth territory goal | One hull restored on clear, capped at the ship's starting maximum |
| Beacon | 2 | Two beacon discs (three from depth 5), radius 5 cells | Every beacon fully enclosed; no territory goal | +1 salvage per beacon |
| Cargo | 3 | One cargo pod at a time, two runs (three from depth 5) | Every pod delivered; no territory goal | +2 salvage per delivery |
| Breach | 5 | One breach disc, radius 4 cells, seeding corruption | Breach sealed **and** the depth territory goal | +3 salvage on seal |
| Rival | 3 | One AI cutter with a protected home, radius 3 cells | Most territory after 45 seconds | +3 salvage on a win; lose one hull and retry on a loss |
| Race | 3 | Two independent copies of the arena, shown side by side | First to capture 60% | +3 salvage on a win; lose one hull and retry on a loss |

**Race.** Matching geometry, pickups, enemies and map hazards start on separate boards. First to 60% wins immediately; there is no countdown. Starting rails, rocks and unfinished trails do not score. The player keeps their ship and build; the AI uses normal loop capturing, suffers enemy hits and loses time respawning. Later depths increase its movement speed and loop size. Race can appear at depths 3–7 on either branch or the shared fourth node.

Briefings, pauses and player death animations stop both boards. Capture milestones never interrupt Race: all earned drafts and salvage wait until a win. Winning releases the held salvage plus the 3-salvage bonus, then presents the earned draft choices before advancing the chart. Losing or exiting forfeits that attempt's held rewards. Stasis and other abilities affect only your arena; surges are disabled. A loss costs one hull and retries the same destination, restoring the entry build and salvage; the last hull ends the run. A same-simulation-step finish is a free retry. The AI uses teal chevrons; each progress bar and its frame match its map's displayed width. The 60% target and AI pace are initial playtest values.

Beacon and cargo sectors keep their area milestones, so cards still come from territory while the clear comes from the objective; territory alone never clears them and the bar scales to 100%. The goal label reads Beacons n/N or Cargo n/N, with the separate percentage explicitly labeled Territory. After transit and the arena intro finish, a briefing modal shows the selected sector, encounter, goal, instructions, and reward over the dimmed loaded arena. Enemies, infection, and gameplay timers wait until Begin Sector is confirmed with Enter, the controller confirm button, or a click. Held launch/skip input must be released first. The star chart previews the goal; the pause screen keeps the instructions available during play. Cargo reminders switch to returning to safe land while carrying; a sealed breach switches to its remaining territory target. Pickup, delivery, drop, enclosure relocation, beacon capture, and breach seal feedback remain visible for four seconds of active gameplay, preserving the notice through card rewards and pauses. Objective discs are placed after pickups and turrets, entirely in the void and clear of rails, so survey, salvage, and repair keep their existing placements.

**Beacon.** A beacon is captured when every cell of its disc is claimed land; a trail crossing it does not count. Each Anomaly guards one open beacon: beyond three radii it is pulled back toward the disc, inside that range it wanders, so windows open and close. A disc holding an Anomaly cannot be enclosed because the claim flood reaches it. Rings spin faster while an Anomaly sits inside; an inner arc shows how much of the disc is claimed.

**Cargo.** Move within two cells of cargo while exposed to pick it up, then return to safe land to deliver it. Surveyor and Bulwark reach it while drawing; Lancer must ride to it. Casting a tether over cargo or enclosing it alone does not collect it. Pickup cannot reach through rock or land. While carrying, every Anomaly hunts the ship. Losing a hull or an Anchor recovery drops the cargo. Cargo enclosed without pickup relocates to open void, with a HUD notice. Each delivery places the next cargo.

**Breach.** Corruption is active at any depth in a breach sector, seeded only from the breach disc, and the open disc re-infects itself every spread tick so it cannot be cleansed, only sealed by enclosure. The label shows the infected share of the arena in magenta once it passes 15%; at 25% the ship takes a hit and the infection collapses back to the disc, then grows again. Sealing pays, stops the spread for good, and restores the depth goal; remaining infection still cleanses under captures. Corruption cards join that sector's draft pool. Reaching the breach does not unlock the Containment upgrade track; that still needs sector 17. The guard range, hunt rate, and breach limit are playtest values.

**Rival.** Own more territory when the 45-second clock expires. The HUD shows both scores; a frozen-board tally compares live territory, excluding starting rails, the Rival home, rock, and unfinished trails. Winning awards 3 salvage and opens the next chart choice. Losing costs one hull and retries the same destination with a fresh board; the last hull ends the expedition. A tie retries for free. Retrying restores the entry build and salvage, so failed attempts cannot farm drafts or loot. Briefings, pauses, drafts, and death animations pause the clock; Stasis freezes the rival while time continues. Reaching the usual capture goal does not end the contest early.

The orange cutter uses Battle Royale's planner (`scripts/rival_cutter.gd`): it walks its land, cuts three-leg loops, and claims void unreachable by Anomalies. Your land and walls block it; you can enclose its territory to steal it. Crossing an exposed line sends its owner home, with no hull damage; existing trail defenses still apply. Its shield-marked starting disc is a permanent safe zone, like Battle Royale starting rails: you cannot enter, blast, lance through, or capture it. The Rival can walk there and return after losing its trail. Enclosing its expansion leaves the home intact, so the Rival remains in the encounter until the tally. Later encounter depths increase speed (up to 48% faster), shorten planning and recovery delays, enlarge possible loops, and favor cuts crossing the player's trail. These are tuning values for playtesting. Rival is eligible at depths 3–7, on either branch or the shared fourth node.

The act uses angular, mostly square Jump silhouettes instead of an oval or stretched cross. On the survey route, the first three fields grow in capturable area; later fields vary topology. Interior pylons and the island use Jump's rock cutouts with one-cell walkable rails. Anomaly counts rise from one at depths 1–2, to two at 3–5, to three at 6–8. Notched, sliced, and bridge destinations always have at least two, including when offered early. The first two spawn on opposite sides with legal, non-overlapping full beams; the third starts toward the upper region. Enemies remain free to move after spawning. The chart reports the selected destination's actual count.

Every sector keeps at most two starting Sparx; survey and repair encounters at depths 2–8 have one turret and no spawners. Existing Anomaly speed/size progression remains. Clear screens retain the celebration and Star Chart button without shape announcements or tactical hints. The gameplay HUD also omits shape names.

**Surge.** Every sector has a stall clock. Twenty seconds without a land change, a death, or an objective event surfaces a surge: an orange disc of radius 3 in live void, clear of every objective disc, the cargo pod, and any Anomaly's reach. It telegraphs for 2 seconds, then counts down 15 seconds on an outer arc with the seconds shown beside it. Enclosing the whole disc pays 2 salvage and resets the clock. Letting it lapse costs the sector: the first two misses each add a Sparx to the coast patrol, later misses speed the Anomaly by 10% each, up to 50%. Authored maps that override enemies skip the Sparx and go straight to speed. The clock and the countdown freeze in pause, reward, draft, and briefing phases; Stasis and Ion freezes do not stop them. If no open pocket exists the surge retries five seconds later. All values are playtest values.

The island is an inner coast: first cut to its rail, walk around it, then cut outward. Bridging without enclosing a region claims only the trail. Initial safe rails and rock do not advance territory or card milestones; the shared victory threshold uses the same capturable-area denominator.

Cells remain square. A 160 × 104 backing grid permits wider arenas without changing movement speed. The territory bar stays above the field and installed systems below. Entry traces the playable coast without an extra square frame. Jump's own arena sizing remains unchanged.

Bulwark can begin another crossing while a detached seal hardens. If that seal earns a draft, the live crossing and its hardening progress are preserved through the card choices and resume afterward.

First-time captures fill the bar. Draft count follows actual capturable area, excluding rock and starting rails: fewer than 3,800 cells gives one choice at 35%; 3,800–4,399 gives two at 25% and 55%; 4,400 or more gives three at 20%, 40%, and 60%. Three is the maximum. The bar and draft screen show only that arena’s earned/remaining choices. Captured-cell particles travel to the bar before cards appear. Large captures queue every earned choice, including those on the winning cut. The simulation pauses during reward delivery, drafting, replacement, and installation. Repeated territory never earns progress twice.

The first three survey sectors give one choice each, gradually filling the three system slots. The full survey route gives thirteen choices; alternate routes vary with arena size. Each draft presents three cards, from which the player chooses one. Once slots are full, every installed system below rank III is guaranteed an upgrade choice, including owned systems whose acquisition conditions no longer apply. Full builds no longer roll random replacements. Rank II increases the principal effect by 25%; rank III by 50%. Anchor instead reduces recharge time by the corresponding factor. Cards and pause show resulting values.

When fewer than three upgrades remain, the unused choices are filled in this order: **Salvage Cache** (+3 salvage), **Thruster Tuning** (+5 percentage points of movement speed), and **Recovery Shield** (+0.5 seconds of respawn protection). With all systems at rank III, all three bonus choices appear. These rewards use no slots. Passive bonuses stack, carry between sectors, appear on the pause screen, and reset with card ranks on a new expedition. Cache salvage counts toward expedition earnings and is banked through normal settlement; Extractor does not multiply this fixed reward. Keep Build (Escape or click) still passes a full-build draft and resolves queued rewards normally.

Drafts, installation, and clears retain synth cues, radial pulses, and beam effects. Star Chart appears after 2.2 seconds. Intermediate clears keep the focus on the completed sector. Salvage banks exactly once when the expedition ends by completion, defeat, or early exit. Continuing between sectors does not settle the run.

## Controls and hangar

- WASD / arrows: move or face. Surveyor holds Space to draw, Shift for slow draw. Lancer presses Space to fire and ride a line. Bulwark holds Space to draw and harden its trail; releasing braces in place while hardening continues.
- Claimed interiors and coasts use the ship's normal speed. The displayed ship follows grid movement at its travel speed instead of repeatedly easing to a stop at each cell; lance riding and Leap landing keep their distinct travel rates.
- Q: the opening movement module; hold and release for Charge or Leap. Charge starts from a coast and keeps the ship stationary. E / Ctrl: Afterburner or Hardlight, if installed. Only one of these secondary active systems can be equipped at a time.
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
| Reactor | +3% ability recharge rate; also lance recharge and Charge growth speed. | Each capture refunds 1 second of cooldowns. | Refund increases to 2 seconds. |
| Scanner | +2 percentage points chance for a new offered system to start at rank II. | One rescan per sector. | Two rescans per sector. |
| Extractor | +2% salvage yield. | One extra pickup per sector. | Two extra pickups per sector. |
| Containment | 3% less corruption exposure accumulated per second. | Captures cleanse 2 cells beyond their border. | Cleansing extends 4 cells. |

Containment becomes purchasable after reaching sector 17. Hull no longer mixes its shield benefit with corruption resistance. At Containment rank 10, overload takes about 5.7 seconds of continuous exposure instead of 4. Engines' milestone and Slipstream share the same boost; the card can improve its strength without stacking a second copy.

The first earned draft always presents Charge, Leap, and Dash at rank I. It cannot be rescanned and does not spend a Scanner charge. Subsequent drafts offer passive systems or one E-bound active system; the installed movement module can appear as a rank upgrade once the three slots are full. Unselected movement modules stay out of later drafts. Space retains the selected ship's native action; a successful Lancer activation no longer displays a redundant center-screen announcement.

Scanner rescans replace offers while slots remain open without consuming a capture reward. Once slots are full, the guaranteed choices cannot be rescanned and no rescan charge is spent. Installed rank-III systems cannot be offered as upgrades. Corruption cards enter the pool in sector 17 and in breach encounters; Void Harvest becomes eligible when turrets are present.

Salvage comes from enclosing board pickups using the shared Flux hexagon, collection effects, and enclosure logic. A normal pickup pays 1, or 1.25 on a Surveyor slow cut, before Extractor. Three baseline pickups give 3 salvage per sector. Captured turrets/nests grant 0.25; Void Harvest adds 1.25 at rank I. Territory and victory alone award no currency. Extractor's fractional rewards accumulate and persist between runs so early +2% purchases are not lost to rounding. Hazard enclosure rewards, objective rewards, surge captures, and Void Harvest feed the same award path.

## Temporary systems

Authored maps can add **Sniper** and **Siege** enemies plus painted **Shield** and **Hazard** zones. Siege erosion reduces current territory progress; draft milestones retain first-time capture credit, so recapturing lost land cannot farm upgrades. Completed hardened walls resist erosion. See [enemy and zone details](enemy-references.md).

These are rank-I effects. Ranked versions retain the trigger and strengthen the principal effect.

| System | Effect |
| --- | --- |
| Charge | Hold Q on a coast or mid-cut to grow a capture disc; release to detonate and finish the approach trail. Stationary, 8-cell radius after 3 seconds, 12-second recharge. Ranks II/III increase radius to 10/12 cells. The fuse pauses while charging; enemies still threaten the disc and trail. |
| Leap | Hold Q on a coast or mid-cut to aim; release to leap to the target and build an exposed wall in both directions. The approach trail joins the completed capture. 16-second recharge after landing. |
| Dash | Q: moves forward at 3× speed for 0.3 seconds on land or during a cut/tether ride; rock still blocks movement. Dash alone never starts a cut. 8-second recharge. |
| Afterburner | E: +80% cut/riding/charge speed for 3 seconds; 14-second recharge. |
| Hardlight | E: protects the trail or charging disc for 2 seconds; 18-second recharge. On safe land it shows ARMED and waits for the next cut, charge, or Leap landing before spending protection time or starting its cooldown. |
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

Protection cards do not prevent corruption overload. Corruption grows in free territory every three seconds; capture cleanses enclosed infection. Ships accumulate exposure while their exposed trail crosses infection.

Sector briefings show only the objective and a Start button above a dark, softly blurred arena. Detailed instructions remain on pause. The HUD separates **Personal Exposure** (100% causes a hull hit) from breach **Arena** infection (25% causes a hit even without contact). Exposure takes four seconds of continuous contact at base resistance, drains when contact ends, and resets on capture. Pause contact times account for permanent Containment ranks. Sealing a breach stops growth; remaining purple still causes exposure until cleansed by capture. The pause explanation updates after sealing.

## Saves and verification

Profile version 8 lives in `user://galaxtix_roguelite.json`, separate from Jump's currencies, ownership, upgrades, and records. Version 1–5 profiles retain their ranks, ships, and unlocks. Existing salvage balances and fractional remainders convert at 4 old units to 1 new unit, matching the price reduction; conversion remainders are preserved. Version 6 and newer profiles do not convert again. The profile stores highest reached sector, fractional salvage, and Containment access. Existing profiles that reached the old corruption sector retain that unlock. Unknown or unowned ship selections fall back to Surveyor.

Existing Sapper ownership and selection transfer to Bulwark without another purchase. Salvage and permanent ranks are preserved.

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
godot --headless --path . --quit-after 1200 tests/roguelite_race_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 4000 tests/roguelite_optimization_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 1200 tests/roguelite_field_features_smoke.tscn -- --nosave --no-steam
```

The expedition suite covers all eight arenas, repeated full-beam spawn validation, opposing-side coverage and real middle cuts, real inter-sector transit, queued winning-cut rewards, persistent builds and hull, bounded slots/ranks, upgrades/replacement/cancellation, Scanner offers and rescans, six tracks, Containment gating, fractional salvage, area-based draft limits, version-6 currency conversion, single settlement, generated routes, mouse preview/jump input, alternate geometry, and salvage/repair encounters. Existing suites cover ship controls, captures, card effects, input, transactions, text bounds, and mode isolation. Assertions count as failures even if Godot exits with code zero.

For graphical screenshots, append `--rogue-shots=<absolute directory>`. For disk persistence checks, point APPDATA and LOCALAPPDATA at `.godot/test-user` and append `--rogue-save-test` to the original suite; it validates that directory before enabling writes.

The movement suite exercises all three opening modules on all three ships through real input, including Charge capture and protection, native Bulwark hardening and bracing, leap aiming and wall completion, dash speed and rock collisions, cooldowns, separate Q/E bindings, fixed opening offers, and Sapper ownership migration to Bulwark.

The timing suite compares coast and interior travel for every roguelite ship, with base and upgraded engines at 30, 60, and 120 FPS. It measures visual speed consistency and verifies that releasing input and hitting rock stop the ship without drift.

The targets suite uses real captures just below and exactly at every sector goal, checks progress-bar scaling and the 90% cap, and verifies Jump retains its existing 75% goal.

The objectives suite covers the kind table and two hundred generated routes, disc placement on every stage, beacon capture, guarding, drift, milestone-plus-clear ordering, cargo pickup and delivery for all three ships, drops on death, Anchor recovery, hardened land and enclosure, Anomaly hunting, breach seeding, re-seeding, pressure hits, shields, sealing, goal-before-seal ordering, and the surge: no surge before the stall limit, live-void placement clear of Anomalies, telegraph then window, capture payout, Sparx then Anomaly-speed escalation, a paused window, and coexistence with beacons; and the rival: seed placement on every stage, autonomous planning and claims, a seedless flood that cannot swallow the arena, trail contact both ways with protections, lance and beam cuts, blasts taking its land, freezes, permanent-home protection and score exclusion, enclosure without early clearing, the 45-second clock and paused interruptions, live territory scoring, frozen results, one-time win rewards, retry rollback, ties, last-hull settlement, and depth-scaled AI completing claims before time expires. The expedition suite's route check now launches every alternate kind on the built-in arenas.

The optimization suite compares geometry and texture output with frozen reference algorithms across arenas, random cell states, empty/full fields, and all galaxy patterns. It checks corruption growth and visual cache invalidation after captures, cleansing, hardening, Anchor recovery, and restart.

This slice follows the brainstorming document's numerical upgrades, milestones, distinct ships, and changing run builds. Additional bosses for each act pool, permanent card-family unlocks, and equipment/loadouts remain future work. Boss attack timing, rewards and act difficulty need player balance feedback.
