# Roguelite enemy references

## Space Xonix additions

Choose **Sniper** or **Siege** in **Maps → New Enemy**. Both are optional authored enemies; no existing maps gain them automatically.

| Type | Behavior in Galaxtix |
| --- | --- |
| Sniper | Fixed, capturable turret. Locks a yellow dashed aim line for 1.25 seconds, fires a red/white beam for 0.3 seconds, then recharges for 3.5 seconds. The beam crosses claimed land but stops at rock. Dodge the locked line, use protection, or enclose the turret. Capture pays the normal turret reward once, including Void Harvest. |
| Siege | Slow void enemy that preserves its region during captures. Approaches captured coasts, marks a two-cell-radius patch for 1.5 seconds, then erodes up to 13 cells. Recharges for 3 seconds. Original rails, hardened walls, shield zones, completed objectives, and the player's current foothold/trail endpoints resist erosion. Capture progress falls; reclaiming restores it without paying duplicate draft credit. |

Bulwark's hardened walls retain their reinforcement after capture. Snipers and Siege attacks freeze with Stasis and during pause, briefing, and rewards. Restart clears attack state, erosion, and reinforcement.

Capturing a Sniper removes its body and beam completely. Rotor is also capturable: enclose its fixed center to destroy the rotating bar and earn the standard hazard reward once. Rotors do not protect a region from the capture flood. If only capturable hazards remain, the largest open region stays unclaimed so one small cut cannot claim the whole map.

Uncapturable enemy bodies share the Anomaly's cycling rainbow palette and beam shimmer: Gunner Orb, Ray Orb, Chain Worm (including links), Brood Carrier, and Siege. Their silhouettes stay distinct, and attack warnings retain their dedicated colors. Capturable enemies, including Sparx, Rotor, Sniper, and Brood eggs, keep solid colors.

Sparx use red/orange beams. Claim the void beside their current rail so it no longer borders exposed space to destroy them and earn the normal hazard reward once. Sparx on a surviving coast keep patrolling; trapped Sparx cannot jump across captured land to another coast.

**Maps → Shield zone / Hazard zone** paints cell overlays with the current brush size. Green plus signs mark protection; red crosses mark a hazard that cycles through 3 seconds safe, 1 second yellow warning, and 2 seconds active. Zones persist after capture. Shield pockets protect the ship while inside and protect trail segments inside them. Active hazard cells hit the ship, including on claimed land. Right-click or **Erase zone** removes paint; Undo, Redo, Save, and Playtest include zones. Environmental cycles also freeze with Stasis and game pauses.

Reference: Space Xonix's aimed lasers, land-breaking hazards, and protective/lethal zones, described in the [community manual](https://steamcommunity.com/sharedfiles/filedetails/?id=1521260124). Timings, code, visuals, and integration are original Galaxtix adaptations.

## Mokoko X additions

In **Maps → New Enemy**, choose **Chain Worm** or **Brood Carrier**. Both are optional void enemies and can replace an Anomaly; existing maps are unchanged.

| Editor type | Behavior in Galaxtix | Reference idea |
| --- | --- | --- |
| Chain Worm | A roaming head followed by six links over an 84-pixel path. The whole body preserves territory and threatens exposed trails/ships. Links follow the head's turns; the body unfolds from its spawn marker. | Mokoko X's segmented snake/train enemies. |
| Brood Carrier | Roams slowly, warns for 0.9 seconds, then drops an egg. Eggs hatch after six seconds into chasing mites. Capture an egg for 0.25 base salvage before it hatches. Each carrier allows at most four eggs plus living mites; subsequent drops are four seconds of roaming apart. | Mokoko X's egg-spawning enemies, adapted into capturable targets. |

Egg countdown rings turn yellow in their last two seconds. Eggs do not preserve unclaimed territory and cannot hurt the player before hatching. Carrier bodies do preserve territory. Stasis freezes movement, attacks, eggs and mites. Briefings, pauses and drafts suspend them; sector restart clears the eggs. Existing Hardlight, trail protection and ship contact rules apply.

Reference: `C:/Users/wiafe/Projects/Decompiled/mokoko/analysis/FINDINGS.md` and `level_enemies.json`, cross-checked against type/field names in the installed Mokoko X metadata. Behavior code, art, timings and rewards are original Galaxtix implementations.

## Fillit additions

Three editor-only additions adapt enemy ideas from the locally installed Fillit. Open Godot's **Maps** tab, pick the type under **New Enemy**, select the **Enemy** tool, and click an open cell. They are not added to any built-in map or procedural spawn pool.

| Editor type | Behavior in Galaxtix | Fillit reference |
| --- | --- | --- |
| Gunner Orb | Bounces through the void, stops with an orange warning for 0.85 seconds, then fires five projectiles in a fan toward its locked aim. Recharges for 3.2 seconds. Safe land and rock absorb the shots. | ShootingBall: moving ball with stop/fire timing, shot count and bullet speed. |
| Ray Orb | Roams, stops and locks a dashed aiming line for 1.15 seconds, then extends and retracts a beam over 1.1 seconds. The beam reaches in both directions and clips at land or rock. Recharges for 3.6 seconds. | RayBall: moving ball with stop delay, reaction time, extension time and ray length. |
| Rotor | A fixed-centre rotating bar. Starts horizontally, reverses rotation at solid geometry, and fits its length into the available space. Enclose its center to destroy it. | RollingStick: rotating bar with size, angle, speed and turn direction. |

Gunner Orb and Ray Orb preserve their region of void like the Anomaly. Rotor is a capturable hazard and does not preserve territory. All three can be placed in void through the editor, threaten trails and exposed ships, use existing ship protections, and freeze with Stasis. Attack clocks pause during briefings, pauses, and rewards; entry and death animations cannot fire their attacks. The editor descriptions, letters and colors distinguish them from existing enemies.

The reference was the local Fillit installation at `C:/Program Files (x86)/Steam/steamapps/common/Fillit/` and its existing local teardown at `C:/Users/wiafe/Projects/Decompiled/fillit/`. The behavior names and parameters were checked in `analysis/FINDINGS.md` and `src/ShootingBallEnemyData.cs`, `src/RayBallEnemyData.cs`, and `src/RollingStickEnemyData.cs`. These files were read as reference material. Galaxtix's behavior code, timings, visuals and integration are authored here; no Fillit code or art assets are bundled.
