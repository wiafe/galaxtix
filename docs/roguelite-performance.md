Roguelite performance measurements — September 8, 2026

The capture and corruption optimizations reduce CPU work while preserving gameplay rules and visual output. Measurements used Godot 4.7.1 on an Apple M1 Max, Metal Forward+, a 1600 × 900 window, VSync, and the normal CRT/glow/trail effects. Player saves were disabled.

| Measurement | Before | After |
| --- | ---: | ---: |
| Large final-sector capture with Clean Sweep, median | 47.69 ms | 9.07 ms |
| Same capture, worst of 12 trials | 48.07 ms | 9.37 ms |
| Mature final-sector script work per frame, median | 5.86 ms | 2.42 ms |
| Mature final-sector script work per frame, p95 | 6.03 ms | 2.71 ms |
| Mature final-sector frame interval, median | 8.33 ms | 8.32 ms |
| Run/sector preparation, median | 70.17 ms | 18.85 ms |

The frame interval remains about 120 FPS because VSync limits it. Reduced CPU work provides more headroom and makes the large-capture stall substantially shorter. A 60 FPS frame budget is 16.67 ms; a 120 FPS budget is 8.33 ms. A large capture can still miss a 120 Hz frame, especially when combined with effects or rendering work.

Separate headless measurements isolate the changed routines:

| Routine, median | Before | After |
| --- | ---: | ---: |
| Coast rebuild on captured sector | 25.52 ms | 1.10 ms |
| Border rebuild on captured sector | 12.67 ms | 0.84 ms |
| Territory texture refresh | 3.09 ms | 1.18 ms |
| Playfield drawing with mature corruption | 4.64 ms | 0.22 ms |
| Dense corruption spread | 8.45 ms | 1.77 ms |

Coast and border rebuilds use padded occupancy masks and restrict searches to exposed regions. Texture updates write claimed pixels into a byte buffer rather than calling Image.set_pixel for every cell. Corruption strokes are cached until visibility changes; pulsing color remains dynamic. Spread still reads the previous tick's mask and advances exactly one cell, using integer neighbours instead of allocating vectors and arrays for every infected cell. It retains a full source-mask scan, now much cheaper; an incremental spreading frontier remains a possible later optimization if needed.

Nine relevant suites passed: optimization parity, roguelite smoke, expedition, ships, movement modules, movement timing, territory targets, Jump Leaper, and arena smoke. The parity suite compares the optimized border array, border-cell ordering, coast segments, and territory pixels against the original algorithms. It also checks spread and visual invalidation after capture, cleansing, hardening, Anchor recovery, and restarting.

These are bounded development-runtime diagnostics, not exported-build or web guarantees. Graphical samples used 180–300 measured frames after 90 warm-up frames; the mature state was advanced by 120 simulated seconds. The large-capture fixture deliberately leaves a small enemy-held region. The baseline used the main scene; the final graphical run hosted the same Game and ScopeDisplay directly, with normal input bindings, to isolate concurrent options-screen work. GPU timestamp queries returned zero and were treated as unavailable. Headless component timings are separate measurements and should not be added to graphical frame timings.

The temporary profiling harnesses and raw JSON snapshots remain in `/tmp/roguelite-performance*`; the correctness regression is versioned as `tests/roguelite_optimization_smoke.tscn`.
