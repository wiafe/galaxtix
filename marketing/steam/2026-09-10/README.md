# Galaxtix · Steam store kit

Prepared 10 September 2026. Local review materials; nothing has been uploaded to Steam.

Open **gallery.html** for a visual overview. Click any image to inspect the full PNG.

Open **capsule-options.html** to compare the original outline title with three new font treatments: **A / Solid phosphor**, **B / Sector stencil**, and **C / Arcade chrome**. All three are saved in the capsule folder; their built-in image generation prompts are in capsule/typography-prompts.txt. These are alternatives, with no final selection made.

The comparison also includes three different backgrounds with the filled title: **D / Boss close-up**, **E / Reclaimed sectors**, and **F / Rival frontier**. These explore composition and subject, not just color. All preserve straight cardinal cuts. Files are capsule/capsule-d-boss-closeup.png, capsule/capsule-e-reclaimed-sectors.png, and capsule/capsule-f-rival-frontier.png; built-in generation prompts are in capsule/background-prompts.txt. E combines act motifs as promotional artwork rather than depicting a literal playable map.

## Eight requested screenshots

All eight are 1920 × 1080 PNG frames captured from the game's roguelite renderer, including its CRT effects. No image generation, retouching, cropping, or promotional overlays were used on the screenshots.

| File | Content |
| --- | --- |
| screenshots/01-act-1-foundry.png | Surveyor cutting around cover; blue checker territory, Coolant Channels |
| screenshots/02-act-2-infestation.png | Lancer cutting with Hardlight active; green striped territory, The Coil |
| screenshots/03-act-3-reactor.png | Bulwark cutting beyond its completed claim; violet territory, Fractured Core |
| screenshots/04-boss-thorn-maw.png | A chunk already removed; a new cut entering the exposed body |
| screenshots/05-boss-prism-warden.png | A lens firing split beams while the player cuts on the opposite side |
| screenshots/06-upgrade-hangar.png | Permanent ship upgrade tracks, next Engine rank selected |
| screenshots/07-encounter-race.png | Separate matching arenas, both pilots cutting, racer territory and progress meters |
| screenshots/08-encounter-rival.png | Shared arena, opposing territory, protected rival home, and 27 seconds remaining |

Suggested carousel order: **01 → 04 → 07 → 03 → 05 → 08 → 02 → 06**. Start with the core loop, then show the distinctive boss interaction and encounter variety.

These are staged in-engine gameplay states, not a recording of a continuous player run. The capture director selects authored maps, seeds encounters, positions the pilot, performs real cuts, and schedules boss attacks. It pauses hazards while claim animations settle and supplies a valid build/profile to illustrate progression. Map layouts, enemy artwork, gameplay rendering, and UI are the current implementation. Game rendering uses its normal 1600 × 900 internal effect buffers, presented and captured at 1920 × 1080.

Recreate from the project root with Godot 4.7:

```powershell
& 'C:\Users\wiafe\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --path . --resolution 1920x1080 res://tools/steam_capture.tscn -- --nosave --no-steam
```

The capture tool never writes the player's profile. Marketing assets are excluded from Godot imports with marketing/.gdignore.

To refresh only Race and Rival, use `res://tools/steam_encounter_capture.tscn` instead. These two captures let the real opposing AI claim territory and start a new cut. The pilot has temporary invulnerability while waiting for this staged moment, removed before capture. The first six screenshots remain unchanged.

## Descriptions

- **short-description.txt**: 228 characters, plain text.
- **long-description.txt**: 204 words, easy to edit.
- **long-description-steam.txt**: the same long description with Steam BBCode formatting.
- **research.md**: current official requirements, reference store pages, and reasoning behind the pitch.

## Capsule concept

**capsule/capsule-concept-v2.png** is a 1658 × 949 mockup generated with the built-in image generation tool, using actual game screenshots as style references. **capsule/prompt-v2.txt** preserves the generation prompt. The concept keeps the name readable and foregrounds loop capturing, reclaimed territory, and an abstract boss.

This is the requested art mockup. Production layout/export work remains for Steam's exact capsule sizes; do not upload this native concept as a finished main capsule. See research.md for the required dimensions.

Revision 2 corrects the flight path to straight horizontal/vertical cuts and right-angle turns, with the ship facing along the final segment. The original capsule-concept.png is retained only as an earlier draft.

Rival frontier revision 2: capsule/capsule-f-rival-frontier-v2.png simplifies the territory pattern, removes CRT curvature, and uses straight horizontal launch paths. The comparison now shows this version. The earlier F remains for reference. This is generated concept art; exact pixel-perfect lattice construction remains a final vector-art production step. Prompt: capsule/rival-grid-revision-prompt.txt.

Rival frontier revision 3: capsule/capsule-f-rival-frontier-v3.png restores bowed screen edges, scanlines, phosphor glow and grain while retaining the revised grid layout and direct launch paths. The comparison now displays revision 3; previous versions remain as references. Built-in image-generation prompt: capsule/rival-crt-revision-prompt.txt.

Rival solid-fill alternative: capsule/capsule-f-rival-solid-fill.png replaces the square pattern with darker continuous cyan and amber fills, keeping bright perimeter lines, straight cuts and curved CRT effects. Both the patterned and solid versions are available in the comparison. Built-in generation prompt: capsule/rival-solid-fill-prompt.txt.

11 September: patterned Rival revision 4 (capsule/capsule-f-rival-frontier-v4.png) removes the unused peninsula above the cyan launch and below the amber launch. Both active tips and straight trails remain. The user prefers the patterned treatment; F2 solid fill remains an alternative. The comparison now shows revision 4. Built-in generation prompt: capsule/rival-launch-tips-prompt.txt.
