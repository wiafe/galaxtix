# Roguelite prototype

Choose **Roguelite** from the main menu. Surveyor is free; Lancer and Sapper each cost 40 salvage in Ships. All three share permanent upgrades and reuse Jump's controls, movement, capture mechanics, enemy simulation, icons, and ship art. Jump and Battle Royale remain separate modes.

## Expedition

A run has eight sectors. Claim 75% in each, then Continue after the sector-clear fanfare. Hull and the three installed systems carry forward; ability cooldowns refresh. The last sector completes the expedition.

| Sector | Arena outline | Introduction |
| --- | --- | --- |
| 1 | Square, 52 × 52 cells / 416 × 416 pixels | Matches Jump's small opening; no turret, spawner, or corruption. |
| 2 | Rectangle, 68 × 48 cells | Matches Jump's second sector. |
| 3 | Square, 68 × 68 cells | Matches Jump's larger third sector. |
| 4 | Oval, 120 × 64 cells | Jump's circle fitted into a wider field; one turret. |
| 5 | Cross, 160 × 68 cells | Opposing arms create shorter cuts across the field. |
| 6 | Notches, 160 × 68 cells | Inward coast creates new starting points. |
| 7 | Bridge, 160 × 68 cells | Two lobes connected through a narrow crossing. |
| 8 | Island, 160 × 68 cells | A 40 × 18 rock core with a walkable rail; corruption begins. |

The first three fields grow in capturable area. Later sectors change topology within the 1280 × 544 maximum footprint: a bridge need not have more area to offer a different challenge. Every sector keeps one Anomaly and at most two starting Sparx; sectors 2–8 have one turret and no spawners. Existing Anomaly speed/size progression remains. Clear screens retain the celebration and Continue button without shape announcements or tactical hints. The gameplay HUD also omits shape names.

The island is an inner coast: first cut to its rail, walk around it, then cut outward. Bridging without enclosing a region claims only the trail. Initial safe rails and rock do not advance territory or card milestones; the shared victory threshold uses the same capturable-area denominator.

Cells remain square. A 160 × 104 backing grid permits wider arenas without changing movement speed. The territory bar stays above the field and installed systems below. Entry traces the playable coast without an extra square frame. Jump's own arena sizing remains unchanged.

First-time captures fill the bar and earn choices at 20%, 40%, and 60% in every sector. Captured-cell particles travel to the bar before cards appear. Large captures queue every earned choice, including those on the winning cut. The simulation pauses during reward delivery, drafting, replacement, and installation. Repeated territory never earns progress twice.

Each sector gives three choices, for twenty-four across a completed expedition. The first three fill empty system slots. Later offers can upgrade an installed system to rank III or replace one with a new system. Replacement previews the current systems and permits cancellation before changing the build. With three systems installed, Keep Build (Escape or click) passes an offer without replacing anything; it consumes that choice and resolves queued captures normally. Card ranks reset on a new expedition. Rank II increases the principal effect by 25%; rank III by 50%. Anchor instead reduces recharge time by the corresponding factor. Cards and pause show resulting values.

Drafts, installation, and clears retain synth cues, radial pulses, and beam effects. Continue appears after 2.2 seconds. Intermediate clears keep the focus on the completed sector. Salvage banks exactly once when the expedition ends by completion, defeat, or early exit. Continuing between sectors does not settle the run.

## Controls and hangar

- WASD / arrows: move or face. Surveyor holds Space to draw, Shift for slow draw. Lancer presses Space to fire and ride a line. Sapper holds Space to charge and releases to detonate.
- Q: Afterburner, if installed. E / Ctrl: Hardlight, if installed.
- Escape during play pauses. Resume preserves the cut; End Expedition banks salvage. Escape at an intermediate clear banks and exits.
- Arrows and Enter, or mouse: navigate and choose. R during drafting spends a Scanner rescan, when available.
- Back, Upgrades, and Ships sit at top left; Launch stands alone at top right. The salvage balance is in the footer.
- Upgrades shows all six linear tracks in one continuous scrolling list. Use the mouse wheel or drag the scrollbar; keyboard focus automatically scrolls its track into view. The detail inspector stays fixed on the right. Up/Down changes focus; Left/Right browses ranks. Click a node to inspect, then Upgrade to buy. Only the next rank can be purchased. Rank 5 and 10 diamonds mark milestones.
- Ships supports previewing without buying; Unlock/Select performs the action. Purchases also select the ship. Unaffordable action text and borders are red; the currency glyph stays consistent with pickups.

## Permanent systems

Every track has ten ranks, costing 8 salvage initially and 4 more for each following rank. The inspector displays concrete before/after values. Reactor text adapts to the selected ship.

| System | Per rank | Rank 5 | Rank 10 |
| --- | --- | --- | --- |
| Engines | +2% movement speed. | Safe movement primes +30% speed for the first 2 seconds of the next cut or charge. | Boost lasts 3 seconds. |
| Hull | +0.5 seconds protection after losing a hull, from a 2.5-second baseline. | One extra hull per run. | Two extra hulls total. |
| Reactor | +3% ability recharge rate; also lance recharge or Sapper charge speed. | Each capture refunds 1 second of cooldowns. | Refund increases to 2 seconds. |
| Scanner | +2 percentage points chance for a new offered system to start at rank II. | One rescan per sector. | Two rescans per sector. |
| Extractor | +2% salvage yield. | One extra pickup per sector. | Two extra pickups per sector. |
| Containment | 3% less corruption exposure accumulated per second. | Captures cleanse 2 cells beyond their border. | Cleansing extends 4 cells. |

Containment becomes purchasable after reaching sector 8. Hull no longer mixes its shield benefit with corruption resistance. At Containment rank 10, overload takes about 5.7 seconds of continuous exposure instead of 4. Engines' milestone and Slipstream share the same boost; the card can improve its strength without stacking a second copy.

Scanner rescans replace the three offers without consuming a capture reward. Installed rank-III systems cannot be offered as upgrades. Corruption cards enter the pool in sector 8; Void Harvest becomes eligible when turrets are present.

Salvage comes from enclosing board pickups using the shared Flux hexagon, collection effects, and enclosure logic. A normal pickup pays 4, or 5 on a Surveyor slow cut, before Extractor. Three baseline pickups give 12 salvage per sector. Territory and victory alone award no currency. Extractor's fractional rewards accumulate and persist between runs so early +2% purchases are not lost to rounding. Hazard enclosure rewards and Void Harvest feed the same award path.

## Temporary systems

These are rank-I effects. Ranked versions retain the trigger and strengthen the principal effect.

| System | Effect |
| --- | --- |
| Afterburner | Q: +80% cut/riding/charge speed for 3 seconds; 14-second recharge. |
| Hardlight | E: protects the trail or charging disc for 2 seconds; 18-second recharge. |
| Anchor | A lethal exposed hit returns to safe ground without losing a hull; 24-second recharge. |
| Ion Thread / Ion Field | Contact repels enemies and freezes them for 1.5 seconds; 10-second recharge. |
| Clean Sweep | Captures cleanse corruption within 6 cells beyond new territory. |
| Containment | A capture of at least 8% halts corruption spread for 8 seconds. |
| Slipstream | Two seconds moving safely primes +30% cut/charge speed for 2 seconds. |
| Reactor Loop | Every third capture removes 6 seconds from cooldowns. |
| Compression | Cuts below 4% add +15% cut/charge speed, up to +45%; a cut of at least 8% resets it. |
| Phase Line / Phase Charge | Protects the first 1.5 seconds of a cut or charge. |
| Void Harvest | Enclosing a nest or turret grants 5 extra salvage. |
| Stasis Wake | Captures freeze enemies for 1 second. |

Protection cards do not prevent corruption overload. Corruption grows in free territory every three seconds; capture cleanses enclosed infection. Sapper accumulates exposure when occupying infection. Other ships accumulate it while their exposed trail crosses infection.

## Saves and verification

Profile version 5 lives in `user://galaxtix_roguelite.json`, separate from Jump's currencies, ownership, upgrades, and records. Version 1/2/3/4 profiles retain original ranks, balance, and ships; new tracks start at zero. The profile stores highest reached sector, fractional salvage, and Containment access. Existing profiles that reached the old corruption sector retain that unlock. Unknown or unowned ship selections fall back to Surveyor.

Failed purchases refund their price and restore ownership/rank; failed selection saves restore the prior ship. End-of-run save failures retain rewards in memory and offer Retry Save. Active runs do not resume after closing the game.

`RogueliteGame` extends `Game` through stat, capture, economy, and presentation hooks. Shared defaults retain Jump's behavior. It never swaps the campaign save dictionary.

Run with Godot 4.7:

```text
godot --headless --path . --quit-after 1200 tests/roguelite_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 1200 tests/roguelite_ships_smoke.tscn -- --nosave --no-steam
godot --headless --path . --quit-after 1200 tests/roguelite_expedition_smoke.tscn -- --nosave --no-steam
```

The expedition suite covers all eight arenas, real inter-sector transit, queued winning-cut rewards, persistent builds and hull, bounded slots/ranks, upgrades/replacement/cancellation, Scanner offers and rescans, six tracks, Containment gating, fractional salvage, and single settlement. Existing suites cover ship controls, captures, card effects, input, transactions, text bounds, and mode isolation. Assertions count as failures even if Godot exits with code zero.

For graphical screenshots, append `--rogue-shots=<absolute directory>`. For disk persistence checks, point APPDATA and LOCALAPPDATA at `.godot/test-user` and append `--rogue-save-test` to the original suite; it validates that directory before enabling writes.

This slice follows the brainstorming document's numerical upgrades, milestones, distinct ships, and changing run builds. Further galaxies, routes, permanent card-family unlocks, and equipment/loadouts remain future work. Values and corruption's introduction in sector 8 need player balance feedback before extending the campaign further.
