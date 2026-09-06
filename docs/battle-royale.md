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
- Arrows/WASD: move. Leaving your territory starts a cut; reconnect to capture. No draw key in this mode.
- H: host a friends lobby. J: join with an invite code on the clipboard. I: Steam invite overlay (host, when launched through Steam).
- Q: Harden, usable while safe. Your territory becomes a wall, and you cannot leave it.
- E: Overdrive, double movement speed.
- Escape: main menu.

Harden and Overdrive each have one charge for the entire match. Each lasts 4/3/2 seconds in Q1/Q2/Final. Unused charges carry forward. The standings show charges and active abilities.

## Rules

Rails cannot be captured or crossed by opponents and do not count toward territory percentage. Completed lines claim enclosed neutral/enemy territory; disconnected territory stays owned and continues to count toward the standings. Excursions can reconnect to any owned territory, including an island separated from the home rail. Only territory directly captured by an opponent changes hands. Hitting an exposed trail destroys it and returns its cutter to the excursion anchor, or the closest remaining safe cell if the anchor was lost. One small roaming anomaly also threatens trails.

There are no eliminations during a round. The side panel lists every cutter in a fixed order with their charges and active abilities; it never ranks anyone while the clock runs, and only your own territory percentage is shown. Standings at the buzzer determine qualifiers. After the buzzer, names slide one at a time into their ranked slot while their territory lights up on the board: eliminated cutters from the bottom up, then qualifiers from the top, with the last qualifying slot held back for the end. A tie on that slot is called out with the deciding numbers. Enter skips the reveal, then continues. Ties use largest single capture, fewest failed excursions, then a random order assigned at the start of the round. Harden stops movement at its border; activating it around an intruder displaces the cutter without destroying the excursion or its anchor.

AI uses the same movement, trail and capture rules. It plans rectangular excursions, values enemy territory more than neutral territory, walks to attack points through its connected territory, and replans around blocked routes. This is the first AI strategy; human playtests should guide tuning.

## Friends online

Press H on the start screen to host. With the Steam client running you get a friends-only Steam lobby and the lobby id is copied to your clipboard; otherwise the game hosts over ENet and copies `ip:port` instead. A friend copies that code and presses J on their own start screen. Up to four people play; the remaining slots stay AI. The host presses Enter in the lobby to start.

The host runs the whole simulation. Guests send only their intent (direction and abilities) and render 20 Hz snapshots, about 1 KB each plus a packed 4-bit board whenever ownership changes. Rounds are rebuilt on guests from the match seed, so only live state crosses the wire. Steam peer ids are not 1, so every RPC in `scripts/net.gd` is `any_peer` with an explicit host check. The transport layer is ported from chrono-pulp; the Spacewar app id 480 in `steam_appid.txt` is for development.

## Implementation and checks

`scripts/battle_royale.gd` owns simulation and rendering. Campaign state remains in `Game`; it only routes menu/input/drawing to this mode. Territory fills and merged borders are rebuilt after ownership changes; texture uploads happen once per rendered frame.

Run Godot 4.7 with:

```
godot --headless --path . res://tests/battle_royale_smoke.tscn -- --nosave
```

`godot --path . -- --autotest=royale --nosave --shots=<dir>` captures the roster mid-round and the buzzer reveal.

Wire test over ENet on localhost, two processes (`--no-steam` forces the fallback transport):

```
godot --headless --path . -- --brhost --no-steam --nosave
godot --headless --path . -- --brjoin=127.0.0.1 --no-steam --nosave
```

Each prints `[brtest] RESULT ... PASS`. `godot --headless --path . -- --steamtest --nosave` does a real Steam lobby round-trip and needs the Steam client logged in.

The smoke scene checks captures, rail protection, surviving disconnected islands, anchor recovery, Harden displacement, persistent charges, qualification/replay, nine AI rounds, human movement, menu entry/exit, and campaign-save isolation.
