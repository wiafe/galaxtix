# Arcade

Arcade keeps loop capturing and adds a full-round countdown with a hidden territory tally, inspired by the round structure in the local Paint Chase study notes.

- Start with one life and normal drawing movement.
- Play each map for 90 seconds. Reaching the target, even 100%, never ends a round early.
- During play, show the timer and target only. Current territory percentages, progress bars, and numeric capture popups stay hidden.
- At the buzzer, freeze the board and count up the captured percentage. Close results (within 12 percentage points of the target) slow down near the final number; the outcome and confirmation appear after the count.
- Meeting the target advances to the next map. Falling short costs one life and retries the same map if a life remains. Losing the last life ends the run.
- Each whole percentage point above the target adds one score point. Score is awarded once, after the tally.

The initial progression uses the eight existing authored roguelite maps in order, with targets of **50, 55, 55, 60, 60, 65, 70, and 75 percent**. These are initial tuning values. Geometry and authored enemies come from the existing map assets; Arcade has no route choices, corruption, surge encounters, drafts, permanent upgrades, or profile rewards.

## Pickups and controls

Capture the tile beneath a pickup to collect it. Crossing it with an unfinished line is insufficient.

| Action | Keyboard | Xbox-style controller |
|---|---|---|
| Move | Arrows / WASD | D-pad / left stick |
| Draw | Space | A / trigger |
| Use selected ability | Q | Y |
| Next captured ability | E | X / RB |
| Pause | Escape | B / Start |
| Confirm menu or tally | Enter | A |

Lance, Leap, Charge, Harden, and Dash are map pickups. The first captured ability equips automatically; further captures add to the inventory. Switching preserves each ability's cooldown and waits until an active movement finishes. Hold/release Q (Y) to aim Leap or grow Charge, just as with the portable roguelite versions. Ability inventories reset on each new map or retry.

A health pickup adds one life, up to three total. A collected health pickup stays consumed across retries of that map, preventing repeated attempts from farming lives. Advancing to the next map supplies its own health pickup.

Pauses, briefings, entry animations, and death animations stop the countdown. The tally counts live captured cells only; starting rails, rock, eroded cells, and unfinished trails do not score. A near miss is rounded down for display so it never looks like a passing result.

## Verification

Run `tests/arcade_smoke.tscn` with `--nosave --no-steam`. It exercises real loop captures, all five abilities, collection and life rules, no early clears, frozen tally and one-time scoring, target boundaries, retry resets, all eight maps, controller input, and isolation from Jump and Roguelite saves. Add `--rogue-shots=<absolute folder>` in a graphical run to capture the menu, gameplay, count-up, clear, and miss screens.
