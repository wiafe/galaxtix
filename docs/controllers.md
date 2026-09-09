# Controller support

Connect a gamepad before launch or while playing. D-pad and left stick work in the title, dock, options, roguelite menus and all three game modes. On-screen hints follow the last keyboard, mouse or controller input. Recognized PlayStation and Nintendo controller names use their corresponding button labels; other pads use Xbox labels.

| Action | Xbox layout | PlayStation layout |
| --- | --- | --- |
| Move / navigate | D-pad or left stick | D-pad or left stick |
| Select / launch / toggle | A | Cross |
| Draw / charge / ship action | Hold A, LT or RT | Hold Cross, L2 or R2 |
| Slow draw | LB | L1 |
| Back / cancel | B | Circle |
| Pause roguelite / abort Jump / leave Royale | Start (or B) | Options (or Circle) |
| Opening ability / Royale harden | Y | Triangle |
| Secondary ability / Royale overdrive | X or RB | Square or R1 |
| Rescan a roguelite draft | Y | Triangle |
| Switch dock tab | LB | L1 |
| Host / join Royale | X / Y | Square / Triangle |
| Steam invite overlay in lobby | View | Share |

Options follow the keyboard flow: navigate categories, press Select to enter their settings, press Select to toggle, and press Left or Back to return to categories. For volume and resolution, Select begins adjustment; Left/Right changes the value; Select or Back finishes adjustment. Save reset confirmations still default to Cancel.

Stick input uses a 0.35 deadzone. Gameplay chooses the stronger axis to keep movement on the grid. Options react once per stick press, so continuing axis events do not race down the list. Controller input uses Godot's default focus policy, allowing input in embedded editor play. Existing keyboard and mouse controls remain available.

## Reference

The local Fillit installation's embedded `InputActions` configuration maps Move/MoveUI to the left stick and D-pad, Action to the south face button and both triggers, Select to the south face button, Back to the east face button, and Menu to Start. Galaxtix follows those physical conventions and adds bindings for its own abilities. No Fillit files or assets are included in this project.

Implementation uses Godot's [controller input actions](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html).

## Verification

Run `godot --headless --path . tests/controller_smoke.tscn -- --nosave --no-steam` and `godot --headless --path . tests/options_smoke.tscn -- --nosave --no-steam`.

The controller smoke test injects joypad events on device 3 through Godot's InputMap. It checks title/dock/options navigation, toggles, confirmation cancellation, stick drift and held motion, both trigger releases, roguelite pause/resume and draft rescan, and prompt switching. It also runs each mode's actual update loop:

- Jump: all five ships' native actions, Leaper/Sapper/Bulwark release behavior, ending a run, and returning from results to upgrades.
- Roguelite: chart launch, Surveyor/Lancer/Sapper native actions, held opening abilities and release, and secondary abilities without triggering the native action.
- Battle Royale: starting a round, moving the player, applying both abilities, skipping standings, continuing/restarting, and leaving the mode.

Hardware-specific mappings and ergonomics still need a physical controller playthrough. Online transport and Steam overlay interaction are not exercised by this local test.
