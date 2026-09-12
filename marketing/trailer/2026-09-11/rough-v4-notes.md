# Trailer rough cut v4 — ships and permanent upgrades

The trailer is now 63.8 seconds. After the opening capture and draft-to-Dash sequence, two new shots show the hangar:

- **18.4–23.2 seconds:** Surveyor, Lancer and Bulwark, with actual ship selections ending on Bulwark.
- **23.2–28.0 seconds:** the permanent upgrade screen, purchasing Engines rank IV. Salvage drops from 45 to 40, the owned-node count advances, and the next milestone appears.

Both shots use the real UI in an isolated `--nosave` capture session. The profile is staged for demonstration; no player saves are changed. These complement the existing mid-run card draft. The remaining act, encounter and boss sequence follows, with the filled-letter end card and original temporary music.

Files: `galaxtix-roguelite-trailer-rough-v4.mp4`, `rough-v4-timeline.json`, `ships-preview.png`, `upgrades-preview.png`, and `title_menu-preview.png`. The still previews are native 1600×900 frames; the trailer is 1280×720 at 30 fps. All 1,914 output frames and the audio decoded successfully; the measured audio peak was -5.6 dBFS.

## Main-menu branding

The capsule-style lettering is a custom GALAXTIX wordmark, not a complete typeface. Its shared geometry now lives in `scripts/galaxtix_wordmark.gd` and is used by both the trailer and the main-menu logo. The menu keeps its power-on fade and sparks on exit. Menu entry, exit into Roguelite, return, and logo reuse were checked with `tools/wordmark_menu_check.tscn`.

To record the new takes, use the existing capture scene with `--trailer-shot=ships` or `--trailer-shot=upgrades`, saving to the matching `.godot/trailer-work/NAME.avi`. The trailer builder reads their manifests and writes v4. Earlier rough cuts remain available.
