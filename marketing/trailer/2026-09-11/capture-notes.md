# Opening proof v1 — capture notes

This is a **9.8-second silent visual proof**, not the complete trailer. The recorded audio track is silent; music and sound are still pending. Both MP4s contain the same take at normal speed.

| File | Format |
|---|---|
| opening-proof-v1.mp4 | 1280×720, 30 fps, H.264; board crop scaled from 960×540 |
| opening-full-frame-v1.mp4 | 1600×900, 30 fps, H.264; complete source framing |

The close version keeps the entire playable arena and removes the peripheral HUD. CRT scanlines, glow, distortion, trails, and the actual territory fill remain in the footage. It is a framing experiment for spectator readability.

## Take

- Act 1, Service Bay (`roguelite_24`), Surveyor, seed 9102050.
- Rehearsed waypoints: (40,32) → (64,32) → (64,48) → (40,48).
- Normal movement and live enemies. No frozen hazards, invulnerability, fabricated fill, or speed change during the recorded action.
- Completed capture: 408 cells, displayed as +10%; no hull loss.
- Draft interruptions disabled within the capture session; existing capture setup stages the encounter before recording its action.
- Native source: 1600×900 MJPEG/PCM AVI, approximately 10.03 seconds. The encoder trims 0.1 seconds of startup margin and retains 9.8 seconds.
- Verified the successful capture in the Godot log; inspected frames during the cut and after the fill; decoded all 294 frames of the close MP4 without an error.

## Reproduce

From the repository root, create `.godot/trailer-work` and run Godot 4.7 with these arguments:

```text
--path . --write-movie .godot/trailer-work/opening.avi --fixed-fps 30 --log-file .godot/trailer-work/capture.log res://tools/trailer_opening_capture.tscn -- --nosave --no-steam
```

The source records the project's 1600×900 viewport. Window size does not change that movie resolution. Let the capture scene quit by itself so Godot closes the AVI correctly.

Then run `tools/encode_trailer_opening.py` with Python. It accepts `FFMPEG_EXE` or the `imageio-ffmpeg` package installed in `.godot/trailer-python`. Source movies and the encoder dependency stay under ignored `.godot/`; deliverables live beside this file. The capture scene uses the existing Steam capture setup and does not write player profiles or maps.
