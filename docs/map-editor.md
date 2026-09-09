# Roguelite map editor

Open **Maps** at the top of Godot, beside 2D, 3D, and Script. If the tab has not appeared after pulling these changes, reload the project or enable **Roguelite Maps** in Project → Project Settings → Plugins.

1. Choose one of the eight arena shapes on the left.
2. Use **Open space** and **Rock** to paint. Safe rails are rebuilt around the outside and around rock islands when you release the brush. Dark bands above and below the editing area are reserved for the gameplay HUD.
3. Use **Player** to place the starting point on a cyan rail.
4. Choose an enemy type on the right, then use **Enemy** to place it. **Select / move** lets you drag markers or enter exact X/Y cell coordinates. The turret direction selector sets vertical or horizontal fire. Gunner Orb, Ray Orb, and Rotor are optional [Fillit-inspired enemies](enemy-references.md); their descriptions explain the attack pattern before you place them.
5. **Save map**, then choose the playtest depth, encounter, and ship and press **Playtest**. The selected map loads directly into its briefing. Use the Restart map button or Backspace to reload it; stop the run to return to editing.

Mouse wheel zooms. Middle drag pans. Right click deletes an enemy, or reverses the terrain brush. Delete removes the selected enemy. Undo/Redo also work with Ctrl+Z/Ctrl+Shift+Z; Ctrl+S saves the current map. Switching maps preserves unsaved drafts, marked with an asterisk. Restore built-in map is undoable until you save it.

**Automatic versus authored enemies:** untouched maps keep the existing enemy counts and placement rules, which depend on encounter depth and kind. The automatic markers in the editor are examples from the original shape's survey encounter. Moving, adding, or deleting an enemy enables **Use authored enemies**. That option replaces the automatic enemy list with the exact markers shown, at every depth and in every encounter that uses this shape. Uncheck it to restore automatic spawning. Authored Sparx appear at sector start and replace the delayed Sparx wave. Anomalies move normally after spawning; their initial beam shrinks if needed to fit around their chosen centre. Spawners create mites during play.

The arena number is a **shape**, not a fixed expedition depth. For example, editing Bridge changes every route node that uses Bridge. The chart's shape preview and enemy counts reflect authored maps. Cargo, beacons, breaches, and salvage pickups continue to use automatic placement within the edited arena; this editor does not yet provide draggable objective or pickup markers.

Save and Playtest are disabled for invalid setups, such as a player off the rail, an enemy in rock, overlapping enemy markers, too little open space, or a map with no void enemy (Anomaly, Gunner Orb, Ray Orb, or Rotor). This checks basic placement, not difficulty or whether a design is fun: use the encounter and ship selectors to try all relevant combinations.

Saved overrides live in `maps/roguelite_01.tres` through `maps/roguelite_08.tres`. They are game content and should be committed with the project. Built-in snapshots in `maps/defaults/` are the source for the initial editor view and Restore. The current terrain remains procedural until you paint; enemy placement remains procedural until you enable authored enemies. Playtest uses temporary in-memory progression and does not save campaign or Roguelite progress. Its last launch selection is kept in the ignored `.godot/map_playtest.cfg` file.

For maintainers, `tools/bake_map_defaults.tscn -- --nosave --no-steam` creates missing editor snapshots from the game's procedural layouts. It does not overwrite existing snapshots. The plugin follows Godot's [main-screen EditorPlugin API](https://docs.godotengine.org/en/stable/classes/class_editorplugin.html).
