# Title presentation

The title keeps Galaxtix's filled capsule wordmark and CRT pipeline. A large cropped Surveyor diamond occupies the right side, built from stepped blue coasts and dim territory squares on one shared grid. A slow light sweep, slight drift, shallow offset silhouette and sparse fragments give it motion and depth. The emblem has no heading stroke inside it. Its fixed local raster is reconstructed with bilinear filtering so subpixel drift does not toggle grid edges abruptly. The glow uses continuous geometry.

The menu sits on the left. Exported builds show Roguelite, Log, Options and Quit. Running through Godot also exposes Jump, Tube, Arcade and Battle Royale for development, using the `editor` feature flag (including hiding them in debug exports). The selected row has a yellow marker and cyan underline that eases across the full label on hover or selection; its short description sits below the list. Log opens a dedicated Roguelite record screen over a dim archive backdrop, hiding the title and mode menu.

Selection crossfades between motifs: Roguelite uses the cyan Surveyor emblem; Jump uses teal chevrons; Tube uses violet scope frames; Arcade uses a gold hourglass; Battle Royale uses red interlocked emblems; Log uses blue archive plates; Options uses a steel-blue tuning dial; Quit uses an amber power symbol. A shared clock and exponentially blended weights preserve motion through rapid selection changes. Options retains a subdued version of its dial backdrop and hides the title wordmark. Leaving the title for any game mode hides both art layers; returning reuses them. The planet experiment is still only exposed through Maps.

## Roguelite Log

Records come from `roguelite_progress.gd` and `user://galaxtix_roguelite.json`, using the current in-memory profile when Roguelite has already been loaded. Opening the Log refreshes its snapshot. No Jump currency or records are used, and viewing the Log does not write a save. The screen shows settled expeditions, wins, current spendable salvage, furthest reached sector across three eight-sector acts, ships unlocked, and purchased upgrade ranks. A fresh profile displays an empty expedition track. The Back button accepts mouse click, Enter/Space, Escape, or the controller confirm/back actions. Other menu navigation and clicks are blocked while it is open; closing restores focus to Log.

## Reference

Sektori's installed main menu was inspected directly: a compact left menu, large cropped geometric backdrop, changing illumination, drifting fragments, and a persistent scene behind mode selection. Its Campaign tile is larger than the alternate modes. Galaxtix adopts the composition and restrained text while using its own Surveyor, territory patterns, lettering and colors. No Sektori assets are used.

## Verification

`tools/title_presentation_check.tscn -- --nosave --no-steam` checks mouse targets, mode launches, title-layer cleanup, Options and return. `--title-shots` saves title, lighting, log and Options captures to `.godot`; `--title-small` also checks 1280×720. Add `--title-motifs` with `--title-shots` to hover and capture every item and verify that its background transition settles. The shader supports Forward+ and Compatibility renderers. Existing controller and Battle Royale smoke tests cover input and the moved title launch target.




