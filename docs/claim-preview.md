# Roguelite claim preview

While cutting toward a closing coast within 16 cells, a dashed guide and pulsing ring show the possible connection. Faint diagonal hatching marks the area that would be claimed if the player continued straight. The ship label reads `CLAIM` or `SPLIT`. Enemy motion can change this forecast before closure.

The preview labels (including Bulwark's `ON SEAL`) stay fully visible in Act 1 sectors 1–3, then fade to 80%, 60%, 40%, 20% and 0% opacity across sectors 4–8. They remain hidden in later acts. Hatching, the dashed guide and the closing pulse stay visible throughout the run. Guidance follows run depth, so retries keep their current strength and starting a new run restores the early labels. Post-capture result messages are unchanged.

The preview reads a copy of the board through the same flood calculation used by an actual capture. This includes persistent enemies, the capturable-only map fallback and Thorn Maw's protected heart. It does not change cells, enemies, rewards or movement. Area prediction refreshes as the path changes and at most every 80 ms while stationary; the hatch brightness and endpoint pulse animate every frame.

Lancer previews its existing tether endpoint. Bulwark displays `ON SEAL`, since its capture is delayed. Forecasts are suppressed while other detached seals are pending, or while a two-ended leap wall or Charge disc is active, because a normal straight-line closure would misrepresent those mechanics. Rock and unfinished walls stop projection. Modals, death and the end of a cut hide the overlay. The feature is drawn only by Roguelite, preserving Arcade's hidden territory mechanic.

A completed split still claims its boundary and keeps the normal rewards for those cells. Its message is `SPLIT / NEW COAST`, with a short quiet tone and a small pulse instead of the normal capture shake and burst. Area captures retain their existing feedback.

Implementation: `scripts/claim_preview.gd`, with shared board-aware flood calculation in `scripts/game.gd` and seed rules in `scripts/roguelite_game.gd` / `scripts/thorn_maw.gd`.

Validation: `tests/claim_preview_smoke.tscn` checks exact capture parity, split rewards/feedback, non-mutating prediction, moving enemies, blocked paths, seedless maps, Bulwark timing, Lancer and modal cleanup. Run with `--nosave --no-steam`; add `--preview-shots` in a graphical run to write both visual states under `.godot`. Existing ship, movement, objective, optimization, Race, Arcade and Thorn Maw suites also pass.
