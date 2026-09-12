# Trailer rough cut v5 — ship mechanics and cutting directions

The 80-second edit adds two ship demonstrations after ship selection and replaces the Reactor act shot with a bottom-up loop.

- **23.2–26.6:** Lancer fires from the top edge, rides down the full tether, and captures the resulting territory.
- **26.6–39.4:** Bulwark launches from the right, leaves three seals pending, then all three harden and capture territory. A single jump cut skips part of the first crossing; the sequence from the first detached seal through the final payoff runs continuously at normal speed.
- **50.8–55.6:** the Reactor act shot starts with a cut rising from the bottom and follows it through closure.

Ship selection, permanent upgrades, the mid-run draft and Dash demonstration, the other acts, Race, Rival, both bosses, and the filled-letter end card remain in the edit. The score is the existing original temporary synth arrangement extended to the new duration.

## Capture provenance

These are actual Godot simulation captures at 30 fps. The new ship scene is `tools/trailer_ship_capture.tscn`, with `--trailer-ship=lancer` or `--trailer-ship=bulwark`. Save and Steam integration are disabled using `--nosave --no-steam`; setup, ship loadouts, starting cells and the Anomaly's initial separation are staged before recording. Enemies retain normal movement and collision during the takes. No gameplay speeds or hardening rates were changed.

Both ship shots use the authored Act 3 Shield Entry map. Lancer uses its native lance and the Hardlight card. Bulwark uses the Afterburner card on its second cut. Its rehearsed random seed is 23, with seals appearing at 7.70, 10.50 and 13.33 seconds of the source recording. They finish at 16.17, 16.27 and 17.00 seconds, capturing 1,012 cells with zero pending seals and no hull loss. Lancer lands at 2.27 seconds, capturing 2,600 cells without losing hull. The replacement Reactor loop closes at 4.40 seconds without losing hull.

The Bulwark source ranges are 0.30–2.30 and 6.80–17.60 seconds; neither range is sped up. The Reactor take uses `tools/trailer_extended_capture.tscn --trailer-shot=reactor`. Source movies and simulation manifests are under `.godot/trailer-work`; the export builder is `tools/build_trailer_rough_cut.py`.

Output: `galaxtix-roguelite-trailer-rough-v5.mp4`, 1280×720 at 30 fps, with the exact edit recorded in `rough-v5-timeline.json`. Earlier revisions remain available.

Validation: all 2,400 video frames and the audio decoded successfully. Audio peak is -5.6 dBFS. The recorded manifests match the rehearsed events; frames from the final export were checked for the top launch, three pending seals and bottom-origin cut. The MP4 is 40,161,221 bytes.
