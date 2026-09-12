# Galaxtix — roguelite trailer treatment

**Reclaim your empire. One cut at a time.**

A roughly 60-second gameplay trailer: make a risky cut, claim territory, build a stronger ship, then use that same skill against a boss. Scope is entirely the roguelite. The empire line expresses the player's goal; the footage should sell the actual territory game.

## What Derek Lieu's guidance means for us

- **Show the game before the feature list.** Lieu orders a trailer around genre, hook, then content. Our order is loop capturing → dangerous, consequential cuts → builds and encounters. A draft screen means more after viewers understand what the ship does. [Genre, Hook, Content](https://www.derek-lieu.com/blog/2021/4/12/game-trailer-structure-genre-hook-content)
- **Let the first action finish.** His opening-shot examples include an uninterrupted gameplay loop. Ours should show the ship leaving the coast, turning, reconnecting, and the enclosed area filling. Keep the payoff on screen. [The First Shot](https://www.derek-lieu.com/blog/2022/8/1/the-first-shot-of-the-game-trailer)
- **Earn attention immediately.** His indie-specific advice warns against unknown studio logos, slow introductions, repetition, and unfocused capture. Rehearse a particular moment for each shot. Use the title at the end; give each subsequent shot a new consequence. [10 Common Indie Game Trailer Mistakes](https://www.derek-lieu.com/blog/2020/9/14/10-common-indie-game-trailer-mistakes-and-how-to-fix-them)
- **Keep only useful UI.** Retain the draft choice, Race progress, Rival countdown, or boss vulnerability when those explain the shot. Remove spectator-irrelevant controls. [How Much HUD/UI to Show](https://www.derek-lieu.com/blog/2021/5/10/how-much-hudui-to-show-in-a-game-trailer)
- **Clarity comes before percussion.** Lieu notes that sound-driven shooter montages depend on viewers already understanding the gameplay. Introduce our unusual capture mechanic clearly before tightening the cuts to music. [Sound Design Driven Game Trailers](https://www.derek-lieu.com/blog/2021/2/1/sound-design-driven-game-trailers)

**60 seconds is our editorial target, not a proven optimum.** Lieu says length should serve the material and generally aims around 90 seconds for games. We can stay shorter if every idea reads. [Length and Labeling](https://www.derek-lieu.com/blog/2018/12/20/ideal-game-trailer-length-and-labeling)

## Proposed edit

| Time | Picture / action to capture | What the viewer learns |
|---|---|---|
| 0–9s | Foundry: one continuous coast → cut → turn → close → blue territory fill. Enemies remain active. | You draw boundaries to reclaim space. |
| 9–14s | A closer call: an enemy approaches the exposed trail; the player reconnects just in time. | Bigger cuts mean greater risk. |
| 14–17s | Three-card draft. Clearly select one movement ability. | You choose how your run develops. |
| 17–24s | Immediately demonstrate that exact ability saving or extending a cut. | The choice changes play. |
| 24–27s | A brief sector selection and launch. | The battles belong to a continuing run. |
| 27–33s | Infestation capture, then Reactor capture. Different geometry and enemy behavior; green stripes and violet dots inside claimed territory. | The acts bring new challenges. |
| 33–37s | Race: both boards moving, player closes the winning cut. Keep both progress bars. | Sometimes you race another pilot. |
| 37–41s | Rival: contested space, timer close to zero, visible final result. | Sometimes you fight over the same territory. |
| 41–46s | Prism Warden: a readable beam warning, firing, then a successful evasive cut. | Bosses change how you navigate. |
| 46–54s | Thorn Maw exposes its body; a started cut reconnects and removes a visible chunk. Hold the removal. | You can carve the boss itself. |
| 54–60s | GALAXTIX. “Reclaim your empire. One cut at a time.” Steam call to action once the page is live. | Remember the game and where to find it. |

These are shot budgets, not permission to rush an unreadable action. If both contest encounters crowd the edit, extend to 65 seconds or keep the clearer one in the main trailer and use the other in a separate clip. Avoid showing all boss endings.

## Look and sound

Keep the curved CRT, luminous trails, and dark void. Frame the board large enough to follow the ship on a phone; preserve the coast and reconnection point. Match ship position across adjacent shots where practical. Use very little additional text and no voiceover for this first treatment.

Build a synth arrangement with a sparse opening, a lift after the draft, and a final boss peak. Preserve audible game events and give the big capture room to land. Music and the final sound mix still need production. The opening proof is a visual timing study, not a release soundtrack.

## First material made

- `opening-proof-v1.mp4`: the board-focused opening, with an editorial crop that retains the entire arena.
- `opening-full-frame-v1.mp4`: the same take with the original full UI for comparison.
- A repeatable Godot capture scene in `tools/trailer_opening_capture.tscn`.

This is real moving gameplay from the current build, not animated screenshots. The take uses a rehearsed route and seed, normal movement and active hazards. It closes a 408-cell capture without losing hull. Run drafts are disabled in this isolated capture session so the shot can hold on its result. Player saves and authored maps are untouched.

## Next production pass

Capture the draft and its matching ability payoff first, then the boss sequence, then the remaining connective shots. Assemble the 60-second rough cut before polishing typography or effects. Review once muted at phone size: can someone explain the capture loop after the first shot, and recognize the build choice and boss carving by the end? Then finish music, sound, and the live Steam end card.

Research read from Derek Lieu's original articles on 11 September 2026. The treatment and timings above are our application of that guidance, not his review or endorsement of Galaxtix.
