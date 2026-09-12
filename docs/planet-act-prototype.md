# Act 4: planet prototype

In Godot, open **Maps → Launch Planet Prototype** (left column, under **Act 4 / Experiment**). Reload the plugin/project if the new button has not appeared. The launcher uses Godot's normal play window or embedded play view and supplies `--nosave --no-steam`, like the existing map playtest.

The experiment is kept in the Maps addon. It is not exposed in the main game, hangar, or expedition finale. The scene remains independently runnable with F6 for development.

## Playing

- Move with WASD/arrows or the stick/D-pad, relative to the camera.
- Hold Space/controller A to leave safe land and cut. Rejoin land to close the loop. Release the cut button between loops.
- E/controller X or RB dashes; Escape/controller B pauses.
- Anomaly beams preserve their region and damage open cuts. Hunters have a red center marker and pursue the ship's cuts. Close cuts within 25 seconds.
- Claim the target surface area to choose an upgrade and move to the next of eight sectors. Captured gold salvage markers add to the test-run tally.

This is a Surveyor movement and capture experiment with its own hull, dash, upgrades and generated surface maps. It does not yet carry the expedition build into Act 4, use authored planet maps, include a planet boss, or spend salvage. The regular three-act expedition still ends and banks its rewards normally.

## Implementation and checks

The visual treatment follows the main game's Surveyor diamond and direction stroke, white/magenta ship colors, Anomaly spectrum and twelve-beam history, and gold salvage hexagons. The globe has a quiet ungridded void, dim blue square-patterned territory, bright curved coasts, and flat hatched rocks. Cuts are thin surface beams; fresh territory briefly pulses and emits surface ripples. Landing does not trigger a capture flash. Everything passes through the existing CRT display.

Six connected tile faces form a closed sphere with four reciprocal neighbours per tile, including across every seam. Captures flood the remaining surface from enemy positions. Territory percentages use spherical tile area, so tiles near cube corners count correctly. The following orthographic camera transports its up direction around the sphere without a fixed polar up vector.

The read-only `round-world-incremental` reference informed tangent-plane controls and the orthographic camera approach; no reference assets were copied.

Run `tests/planet_smoke.tscn -- --nosave --no-steam` for topology, capture/split, collision, progression, pole-camera, addon signal and Maps-only launch checks. Add `--planet-shots` with a graphical renderer to save chart, landing and captured-territory images under `.godot/planet-*.png`.
