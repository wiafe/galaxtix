# Roguelite trailer — rough cut v2

**54.2 seconds. Gameplay footage with an original temporary synth score.**

This extends the opening study into an assembled trailer. The footage comes from the current roguelite build through its actual renderer and simulation.

| Time | Sequence |
|---|---|
| 0:00–0:09 | Foundry: leave the coast, turn, reconnect, capture |
| 0:09–0:12 | Three-card movement draft; select Dash |
| 0:12–0:18 | Use Dash and complete the cut |
| 0:18–0:21 | Act 2 sector chart |
| 0:21–0:25 | Infestation: shielded capture among chain worms |
| 0:25–0:30 | Reactor: capture with violet territory fill |
| 0:30–0:35 | Race: both boards and progress bars |
| 0:35–0:40 | Rival: shared territory and countdown |
| 0:40–0:43 | Prism Warden: warning and beam fire |
| 0:43–0:49 | Thorn Maw: complete a cut and remove 26% of its body |
| 0:49–0:54 | CRT title: Reclaim your empire. One cut at a time. |

## Editorial decisions

The first cut stays continuous. Later shots begin partway through longer actions, keeping their capture payoffs. Gameplay uses a closer board crop; the draft, chart, Race, and Rival retain the UI needed to read those scenes. The title uses the game's vector lettering and CRT renderer.

The score is an original procedural synth sketch made for this edit, with no third-party music or samples. Native recorded cues are mixed underneath it. This is temporary music and sound, not a final audio pass.

The Race and Rival sections currently establish the encounters; they do not show their final win or tally. A public release pass would benefit from a stronger Race finish and a clearer Rival result. The Steam call to action is also pending the live store page.

## Capture provenance

- Rehearsed paths, encounter states, and loadouts are staged in a separate capture scene. Some later cuts are already in progress at the start of their take.
- Movement and hazards run through the normal simulation at normal speed during recording. The Infestation, Reactor, and Thorn Maw shots use the real Hardlight ability; the Maw take uses rank III.
- Initial Anomaly positions were staged away from the planned cuts in the Reactor and Maw takes. Enemies remain active in the recorded action.
- Preparatory captures and opponent pre-roll happen before the selected footage. Draft interruptions are suppressed in action takes so the shot can hold on a capture; the draft sequence itself uses the real choice and install flow.
- The selected Prism range ends before a later hull loss in its raw take. Rejected captures are retained only in the ignored work directory.
- Saves, authored maps, and gameplay scripts are unchanged by this trailer work.

## Rebuild

Use `tools/trailer_extended_capture.tscn` with Godot Movie Maker, 30 fps, and `-- --nosave --no-steam`. The scene writes the take manifest to `.godot/trailer-work/extended-takes.json`. A single take can be recorded with `--trailer-shot=NAME`, writing its movie to `.godot/trailer-work/NAME.avi`; the editor script uses its matching manifest as a replacement.

Then run `tools/build_trailer_rough_cut.py`. It reads the take manifests, trims and crops the footage, synthesizes the temporary score, mixes audio, and writes the MP4 plus `rough-v2-timeline.json`. Raw footage, intermediate encodes, and the temporary WAV stay in `.godot/trailer-work/`.

The earlier Derek Lieu research and proposed shot order are preserved in `trailer-plan.md`.
