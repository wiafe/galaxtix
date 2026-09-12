# Trailer rough cut v7 — continuous camera motion

The duration and shot order stay at 51 seconds. This revision corrects v6's stop-start camera movement.

V6 eased to zero velocity at every intermediate framing point. The opening, Dash, Lancer and Thorn Maw therefore repeatedly slowed down and accelerated inside a single shot. V7 gives each shot one continuous move with zero velocity and acceleration only at its endpoints. The most aggressive close-ups and quick pans are also reduced.

Camera rendering now uses floating-point affine image sampling, replacing FFmpeg zoompan's integer crop window. The camera is evaluated at 60 Hz. The original gameplay remains at 30 fps and its original speed: each recorded frame lasts 1/30 second, with two camera positions during that interval. No optical-flow frames or extra gameplay states are generated. Static shots are held at the same 60 fps export cadence. All clips use the same video range and color matrix to prevent brightness changes at edits.

The changes are confined to the trailer builder and exports. No game camera, movement, maps or saves were changed. Earlier cuts remain available.

Output: `galaxtix-roguelite-trailer-rough-v7.mp4`, 1280×720 at 60 fps, H.264/AAC. Camera start/end framing and source ranges are recorded in `rough-v7-timeline.json`.

Validation: all 3,060 video frames and the audio decoded successfully, with audio peak -5.6 dBFS. The opening's moving interval from 0.5–2.5 seconds was sampled at 60 Hz: v6 repeated 60 adjacent frame pairs; v7 had zero identical adjacent pairs across the 120 sampled frames. This confirms an actual 60 Hz camera update, rather than only a higher container frame rate. Framing was also inspected through the opening, Lancer, Bulwark, Reactor and Thorn Maw. The cadence measurement does not assess subjective motion quality or imply that the original gameplay was recorded at 60 fps.
