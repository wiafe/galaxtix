# Trailer rough cut v6 — tracking and faster pacing

The edit is 51 seconds, down from v5's 80 seconds. This addresses the supplied v3 feedback about identifying the player, the slow opening, and long screen holds.

The first shot starts in motion, close on the player and its growing trail. The camera follows the first corner, then eases out to show the loop closing and territory filling. The first capture lands before five seconds. By 10.8 seconds the viewer has also seen the three-card draft, Dash activation and the subsequent capture.

## Editorial changes

- Player tracking and a gradual pullback replace the opening's static wide shot.
- Lancer starts close at the top edge; the camera follows downward and widens for the full capture.
- Bulwark gets a close right-edge launch, a separate stacking excerpt and a brief payoff showing all three seals close. The long crossing and idle wait have been trimmed with jump cuts.
- The bottom-origin Reactor loop gets a short upward camera move, followed by the closure.
- Prism gets a restrained push-in. Thorn Maw starts closer to the cut, tracks toward the right and pulls back for the carved body reveal.
- The sector chart moves earlier, immediately after the draft-to-Dash sequence. Draft, chart, ship selection and upgrade purchase all remain visible. Menu holds and the end card are shorter.
- Race and Rival retain full framing so both boards and the contest UI stay visible.
- The original temporary synth score starts its pulse immediately and adds percussion earlier to support the quicker edit.

## Timing

| Time | Shot |
| --- | --- |
| 0.0–5.4 | Player introduction and complete loop capture |
| 5.4–10.8 | Draft, Dash, capture payoff |
| 10.8–12.8 | Sector chart |
| 12.8–15.8 | Ship selection |
| 15.8–18.6 | Lancer crossing from the top |
| 18.6–26.6 | Bulwark right launch, three pending seals and closure |
| 26.6–29.3 | Permanent upgrade purchase |
| 29.3–31.9 | Infestation act |
| 31.9–34.8 | Reactor bottom-origin loop |
| 34.8–38.2 | Race |
| 38.2–41.2 | Rival |
| 41.2–43.8 | Prism boss |
| 43.8–47.4 | Thorn Maw boss and carving payoff |
| 47.4–51.0 | Filled wordmark and empire tagline |

## Provenance and validation

All footage comes from the existing Godot recordings. Camera moves are editorial crops with eased position and zoom keyframes, not changes to the game's camera. The encoder produces one output frame per source frame; gameplay and native audio stay at normal speed. Jump cuts shorten long sequences without accelerating the ship or seal mechanics. No game logic, maps or player saves were changed for this revision.

The builder, `tools/build_trailer_rough_cut.py`, records every source range and camera filter in `rough-v6-timeline.json`. Camera keyframes are checked against the source image boundaries, selected ranges are checked against take duration, and takes with hull loss inside the selected range are rejected. Camera motion uses a larger intermediate image to reduce pixel stepping.

All 1,530 output video frames and the audio decoded successfully. Camera framing was inspected at multiple points across the opening, Dash, Lancer, Bulwark, bottom loop and Thorn Maw. Measured audio peak: -5.6 dBFS; mean: -24.0 dBFS. Output is 1280×720, 30 fps, H.264/AAC. Previous cuts remain available.

Deliverable: `galaxtix-roguelite-trailer-rough-v6.mp4`.
