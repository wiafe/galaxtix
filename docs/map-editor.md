# Roguelite map editor

**Act 4 planet test:** in **Maps**, click **Launch Planet Prototype** at the bottom of the left column. It launches the whole-globe scene with a following camera and temporary progression. The prototype generates its own eight surface sectors; the selected 2D map and encounter settings do not change it. See [planet controls and scope](planet-act-prototype.md).

**New tools:** Select **Shield zone** or **Hazard zone** and paint with the brush. Green zones protect the ship; hazard zones cycle through safe, warning, and active states. Use **Erase zone** or right-click to erase. Zones survive captures and are included in Undo, Redo, Save, and Playtest.

Under **New Enemy**, **Sniper** adds a turret that warns before firing an aimed beam; **Siege** adds a slow enemy that warns before breaking captured territory. Siege can serve as the required void enemy; Sniper cannot. See [enemy behavior details](enemy-references.md).

Open **Maps** at the top of Godot, beside 2D, 3D, and Script. If the tab has not appeared after pulling these changes, reload the project or enable **Roguelite Maps** in Project → Project Settings → Plugins.

Use the **Act** dropdown to choose Foundry, Infestation, or Reactor. Each shows its seven regular maps and two **[Boss]** alternatives for sector 08. A run uses one of those bosses. Select **Original / Arcade** for the original eight maps. Switching acts remembers the last selected map and preserves unsaved edits and undo history; an asterisk marks acts with unsaved maps.

1. Choose an act, then a map. Each act lists seven regular arenas followed by both boss alternatives in progression order. Original / Arcade holds the original eight arenas.
2. Use **Open space** and **Rock** to paint. Safe rails are rebuilt around the outside and around rock islands when you release the brush. Dark bands above and below the editing area are reserved for the gameplay HUD.
3. Use **Player** to place the starting point on a cyan rail.
4. Choose an enemy type on the right, then use **Enemy** to place it. **Select / move** lets you drag markers or enter exact X/Y cell coordinates. The turret direction selector sets vertical or horizontal fire. Gunner Orb, Ray Orb, Rotor, Chain Worm, and Brood Carrier are optional [reference-inspired enemies](enemy-references.md); their descriptions explain the attack pattern before you place them.
5. **Save map**, then choose the playtest depth, encounter, and ship and press **Playtest**. The selected map loads directly into its briefing. Use the Restart map button or Backspace to reload it; stop the run to return to editing.

Mouse wheel zooms. Middle drag pans. Right click deletes an enemy, or reverses the terrain brush. Delete removes the selected enemy. Undo/Redo also work with Ctrl+Z/Ctrl+Shift+Z; Ctrl+S saves the current map. Switching maps preserves unsaved drafts, marked with an asterisk. Restore built-in map is undoable until you save it.

**Automatic versus authored enemies:** untouched maps keep the existing enemy counts and placement rules, which depend on encounter depth and kind. The automatic markers in the editor are examples from the original shape's survey encounter. Moving, adding, or deleting an enemy enables **Use authored enemies**. That option replaces the automatic enemy list with the exact markers shown, at every depth and in every encounter that uses this shape. Uncheck it to restore automatic spawning. Authored Sparx appear at sector start and replace the delayed Sparx wave. Anomalies move normally after spawning; their initial beam shrinks if needed to fit around their chosen centre. Spawners create mites during play.

The arena number is a **shape**, not a fixed expedition depth. For example, editing Bridge changes every route node that uses Bridge. The chart's shape preview and enemy counts reflect authored maps. Pickups and objectives appear in the canvas for the selected Encounter Preview. Their automatic positions use the same placement code as the game, with base upgrades.

Save and Playtest are disabled for invalid setups, such as a player off the rail, an enemy in rock, overlapping enemy markers, too little open space, or a map with no void enemy (Anomaly, Gunner Orb, Ray Orb, Rotor, Chain Worm, or Brood Carrier). This checks basic placement, not difficulty or whether a design is fun: use the encounter and ship selectors to try all relevant combinations.

Saved overrides live in `maps/roguelite_01.tres` through `maps/roguelite_32.tres`. They are game content and should be committed with the project. Built-in snapshots in `maps/defaults/` are the source for the initial editor view and Restore. The current terrain remains procedural until you paint; enemy placement remains procedural until you enable authored enemies. Playtest uses temporary in-memory progression and does not save campaign or Roguelite progress. Its last launch selection is kept in the ignored `.godot/map_playtest.cfg` file.

For maintainers, `tools/bake_map_defaults.tscn -- --nosave --no-steam` creates missing editor snapshots from the game's procedural layouts. It does not overwrite existing snapshots. The plugin follows Godot's [main-screen EditorPlugin API](https://docs.godotengine.org/en/stable/classes/class_editorplugin.html).

Boss maps 13/33, 18/34 and 23/35 use **Boss Core** and **Boss Relay** markers. Keep one core and three relays on open space. Thorn Maw (34) uses these as its heart and thorns, with a purple preview of its carvable body. Move them with the same editor tools as enemies; Playtest automatically runs their boss encounter. See [act and boss editing](roguelite-acts.md).

## Salvage and encounter editing

- **Salvage** places a currency pickup. Yellow **$** markers show all starting pickups, including automatic ones. Select / move, X/Y, right-click delete and Undo work on them. Moving, adding or deleting a pickup enables **Use authored salvage**; this exact list replaces automatic starting pickups, including Salvage encounter and Extractor count bonuses. Each still awards the normal salvage value and upgrade bonuses. Uncheck the option to return to automatic placement.
- **Encounter Preview** changes the canvas and the encounter launched by Playtest. It does not force that kind onto the run's route. Saved overrides apply whenever this map is used for that kind. Changing Depth previews the default rules and positions for that depth.
- **Encounter Rules** edits capture percentage for Survey/Salvage/Repair/Breach, the Race target, Rival seconds, or cargo delivery count. Other kinds keep separate settings. **Reset encounter overrides** clears only the selected kind's rules and objective positions.
- **Objective** places beacons, the initial cargo spawn, a breach, or the Rival home. Beacons can be added or removed; the other kinds need exactly one marker. Select a disc to change its Radius. Cargo relocates normally after deliveries or if its starting cell is captured. Bosses use their Core and Relay enemy markers.
- **Save map -> Playtest** checks the edited encounter in the actual game. Invalid placements, missing required objectives, and discs crossing rock or rails block Save and Playtest. Undo/Redo and map/act switching preserve pickup and encounter edits.

The map resource stores `override_pickups`, `pickups`, and an `encounters` dictionary keyed by encounter kind. The shared placement implementation is `scripts/map_encounters.gd`. Resources without overrides keep the existing generated behavior.
