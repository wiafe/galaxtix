# Roguelite enemy references

Three editor-only additions adapt enemy ideas from the locally installed Fillit. Open Godot's **Maps** tab, pick the type under **New Enemy**, select the **Enemy** tool, and click an open cell. They are not added to any built-in map or procedural spawn pool.

| Editor type | Behavior in Galaxtix | Fillit reference |
| --- | --- | --- |
| Gunner Orb | Bounces through the void, stops with an orange warning for 0.85 seconds, then fires five projectiles in a fan toward its locked aim. Recharges for 3.2 seconds. Safe land and rock absorb the shots. | ShootingBall: moving ball with stop/fire timing, shot count and bullet speed. |
| Ray Orb | Roams, stops and locks a dashed aiming line for 1.15 seconds, then extends and retracts a beam over 1.1 seconds. The beam reaches in both directions and clips at land or rock. Recharges for 3.6 seconds. | RayBall: moving ball with stop delay, reaction time, extension time and ray length. |
| Rotor | A fixed-centre rotating bar. Starts horizontally, reverses rotation at solid geometry, and fits its length into the available space. | RollingStick: rotating bar with size, angle, speed and turn direction. |

All three count as **void enemies**, like the Anomaly: their region remains unclaimed when a cut closes. A map can use them instead of the base Anomaly. Unlike capturable turrets and spawners, they are hazards to route around rather than rewards to enclose. They threaten trails and exposed ships, use the existing ship protection rules, and freeze with Stasis. Attack clocks pause during briefings, pauses, and rewards; entry and death animations cannot fire their attacks. The editor descriptions, letters and colors distinguish them from existing enemies.

The reference was the local Fillit installation at `C:/Program Files (x86)/Steam/steamapps/common/Fillit/` and its existing local teardown at `C:/Users/wiafe/Projects/Decompiled/fillit/`. The behavior names and parameters were checked in `analysis/FINDINGS.md` and `src/ShootingBallEnemyData.cs`, `src/RayBallEnemyData.cs`, and `src/RollingStickEnemyData.cs`. These files were read as reference material. Galaxtix's behavior code, timings, visuals and integration are authored here; no Fillit code or art assets are bundled.
