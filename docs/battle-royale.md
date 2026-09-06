# Battle Royale

Open **Battle Royale** below **Jump** on the main menu. This is a local match against 11 AI cutters. Everyone uses the Surveyor hull and the same base movement speeds and drawing rules, regardless of the campaign ship selection. There are no campaign upgrade bonuses or currency rewards.

| Stage | Cutters | Board | Time | Advance |
| --- | --- | --- | --- | --- |
| Q1 | 12 | 68 × 42 | 90 seconds | Top 6 |
| Q2 | 6 | 56 × 34 | 75 seconds | Top 4 |
| Final | 4 | 46 × 28 | 60 seconds | First place wins |

Every stage starts on a fresh board with reassigned perimeter home rails. Cell size stays fixed, so later boards occupy less of the outer square. Timings and AI aggression are initial playtest values.

## Controls

- Enter: start the round, continue after qualifying, or play again after the match.
- Arrows/WASD: move. Hold Space to leave your territory and draw; reconnect to capture.
- Q: Harden, usable while safe. Your territory becomes a wall, and you cannot leave it.
- E: Overdrive, double movement speed.
- Escape: main menu.

Harden and Overdrive each have one charge for the entire match. Each lasts 4/3/2 seconds in Q1/Q2/Final. Unused charges carry forward. The standings show charges and active abilities.

## Rules

Rails cannot be captured or crossed by opponents and do not count toward territory percentage. Completed lines claim enclosed neutral/enemy territory; disconnected territory stays owned and continues to count toward the standings. Excursions can reconnect to any owned territory, including an island separated from the home rail. Only territory directly captured by an opponent changes hands. Hitting an exposed trail destroys it and returns its cutter to the excursion anchor, or the closest remaining safe cell if the anchor was lost. One small roaming anomaly also threatens trails.

There are no eliminations during a round. The side panel lists every cutter in a fixed order with their charges and active abilities; it never ranks anyone while the clock runs, and only your own territory percentage is shown. Standings at the buzzer determine qualifiers. After the buzzer, names slide one at a time into their ranked slot while their territory lights up on the board: eliminated cutters from the bottom up, then qualifiers from the top, with the last qualifying slot held back for the end. A tie on that slot is called out with the deciding numbers. Enter skips the reveal, then continues. Ties use largest single capture, fewest failed excursions, then a random order assigned at the start of the round. Harden stops movement at its border; activating it around an intruder displaces the cutter without destroying the excursion or its anchor.

AI uses the same movement, trail and capture rules. It plans rectangular excursions, values enemy territory more than neutral territory, walks to attack points through its connected territory, and replans around blocked routes. This is the first AI strategy; human playtests should guide tuning.

## Implementation and checks

`scripts/battle_royale.gd` owns simulation and rendering. Campaign state remains in `Game`; it only routes menu/input/drawing to this mode. Territory fills and merged borders are rebuilt after ownership changes; texture uploads happen once per rendered frame.

Run Godot 4.7 with:

```
godot --headless --path . res://tests/battle_royale_smoke.tscn -- --nosave
```

`godot --path . -- --autotest=royale --nosave --shots=<dir>` captures the roster mid-round and the buzzer reveal.

The smoke scene checks captures, rail protection, surviving disconnected islands, anchor recovery, Harden displacement, persistent charges, qualification/replay, nine AI rounds, human movement, menu entry/exit, and campaign-save isolation.
