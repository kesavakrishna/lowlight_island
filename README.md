# Lowlight Island

First-person online co-op survival horror for 2–4 friends, built with **Godot 4.7 + GDScript**.
The full design brief lives in [LOWLIGHT_ISLAND.md](LOWLIGHT_ISLAND.md).

## Status: milestones 1–5

| Milestone | State |
|---|---|
| 1. Smallest connected test | Done: first-person co-op, host-authoritative movement with client prediction, Host / Join by Address, shared day–dusk–night–dawn clock |
| 2. Prove the night | Done (`--world=clearing` keeps the test fixture). **Remote (non-LAN) test still to do.** |
| 3. Seeds make new worlds | Done: every run generates and validates a new island, rebuilt identically on every peer, with the v2 Canopy Realism art. |
| 4. One full escape run | Done: battery → radio → broadcast → dawn boat, nightly escalation, win / loss, rematch. Reconnect to your slot mid-run. |
| 5. Finish the co-op systems | Done: four creature types (Stalker, Listener, Digger, Climber) with personalities, scars, learned counters, grudges and late-night tricks; Nerve and private hallucinations; building at slots with damage states; trails that lead patrols to used shelters; shove; rest; capture and burrow raids; silent pings; peeking and mantling. Plus more to do on each island: the keeper's notes, cottage and lighthouse, and the optional skiff escape. |
| 6. Replace placeholders and playtest | Next: real creature models and recorded sound, teaching the controls, 2–4 player playtests across PCs, tuning, a Windows export |

## Prototype v2 (reference)

`prototypes/v2/` holds a separately built solo prototype (Godot 4.5.1) with much richer art — a 420 m
island, four landscape types, branch climbing and ~43 generated plant and rock models. It is kept playable
as a reference, and its art and world-generation ideas are being ported into this project.
See [prototypes/README.md](prototypes/README.md).

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, not .NET). A copy of the
   editor was downloaded to `../tools/godot/` while setting up this repo.
2. Open `project.godot` in Godot and press **F5**, or run from a terminal:
   ```
   godot --path .
   ```
3. **Host a run** on one PC and **Join by address** on the others (default port `24680`, UDP).
   One player is enough to start for testing.

Two instances on one PC (host + guest side by side):
```
powershell -ExecutionPolicy Bypass -File tools\run_local_pair.ps1 -Godot "C:\path\to\Godot_v4.7.2-stable_win64.exe" [-Night]
```

Remote friends: see [docs/REMOTE_PLAY.md](docs/REMOTE_PLAY.md) (Tailscale / Radmin recommended — plain port
forwarding often fails behind CGNAT).

## How a run goes

Start at the wreck. The objective line at the top always says what's next.
1. Find the battery (the wreck's sketch marks a beached skiff or a salvage crate under a tree; `M` shows the rough area).
2. Carry it to the radio shed on high ground. It's slow and heavy: plan the route, and drop it (`Q`) if you have to.
3. Connect it, then choose a night to run the broadcast. Someone has to stay at the transmitter while it lights up
   the shed and hums; every creature in range comes for it. Interruptions keep their progress.
4. When the call goes out, a boat comes to the old dock at the next dawn and waits for a short boarding window.
   Creatures linger in the shade along the way. Anyone aboard means the crew escaped.

Optional: the keeper's notes are scattered around the island (wreck, cottage, lighthouse, radio shed, a cave,
the dock, a cove). The lighthouse gallery shows the whole island. Her old skiff is a second way off: find its
three parts, fit them, and start the engine after dark - it takes a while, and it is very loud.

Each night may bring a different kind of creature: one hunts by sight and light, one is blind but hears and feels
everything, one comes up through soft ground but can't climb or feel through rock, one climbs faster than you.
They remember how you escaped them, carry scars you can recognise, and hold grudges. Dark wears down your Nerve;
light restores it - and gives you away.

There's no run timer: each night more creatures come up, faster and quicker to break doors, and past the
fourth night they stop hiding.

## Controls

| Key | Action |
|---|---|
| WASD / mouse | Move / look |
| Shift | Sprint (stamina, loud) — also stands you up |
| Ctrl or C | Crouch toggle |
| Z | Prone toggle (fits the cave's crawl exit) |
| Space | Jump · stand up · climb down / let go when perched |
| E | Interact: climb, door, rope, pick up · **hold** beside a downed teammate to revive |
| F | Open / shutter the lantern |
| G | Throw a noisemaker |
| R | Rope down from the platform |
| Q | Put the battery down (the carrier can't sprint, jump, climb or go prone) |
| V | Repair a cave door with wood (cheaper than rebuilding a broken one) |
| M | Map: a rough sketch; the dock, caves, burrows and the battery appear as the crew finds them |
| Left click | Shove a creature back (costs most of your stamina; can't be spammed) |
| Hold 1 / 3 | Lean left / right to peek |
| Space into a ledge | Climb over a waist-high obstacle |
| H | Rest in a dark shelter while a teammate keeps watch |
| X / B / N | Silent pings: move here / danger / hold |
| Esc | Pause menu: settings (sensitivity, FOV, camera shake, volume), leave |
| F3 | Creature debug overlay (state, reason for last decision, awareness, target) |
| F6 | Host only, dev: skip to the next phase |

## Tests

```
GODOT=/path/to/godot tools/run_tests.sh
```
Runs headless unit + integration tests (`tests/test_*.gd`: routes, cave door pathing, cover queries,
escalation caps, climbing / rope / bare-trunk drop, grass concealment, witnessed climbs, unseen patrols,
noisemaker lure, door breach, crawl tunnel, crew loss) and a two-instance ENet smoke test
(host + scripted bot client).

### Seed preview

```
godot --headless --path . -- --preview-seeds=1-12 --out=previews
```
Writes one coloured, hill-shaded map per seed plus `contact_sheet.png`, and prints each island's route
times, biome shares and any rejected attempts. Legend: red crash, yellow battery, magenta radio, cyan dock,
black caves, brown burrows; white / orange / pink / cyan lines are the crash→battery walk, the two
battery→radio carry routes and radio→dock.

Useful dev flags (after `--`): `--host`, `--join=ADDR`, `--port=N`, `--name=S`, `--autostart=N`,
`--seed=N`, `--world=clearing`, `--fast-clock=X`, `--start-phase=night`, `--log-ai`, `--bot`,
`--quit-after=S`, `--screenshot=FILE`, `--view=x,y,z,yaw,pitch[,stance]`, `--freeze`, `--lantern`,
`--preview-seeds=A-B`, `--out=DIR`, `--map`, `--dev-state=radio|broadcast|boat`, `--drop-after=S`, `--dev-lineup` (one of each creature type).

## Layout

```
src/autoload/   tuning.gd (every tuned value + escalation table), settings.gd, net.gd (session), sfx.gd (procedural placeholder audio)
src/core/       defs.gd: shared enums and physics layers (sight is a separate layer from collision)
src/match/      match.gd: host-authoritative run — clock, inputs, climbing, doors, items, revive, snapshots, events
src/player/     player.gd: avatar movement shared by host simulation and client prediction
src/creature/   creature.gd: shared behavior core (patrol → investigate → search → chase / climb / breach)
src/world/      test_clearing.gd (milestone fixture), walk_grid.gd (A* grid for creatures + route checks), geo.gd, environment_ctl.gd
src/ui/         main_menu.gd, hud.gd, settings_panel.gd
tests/          headless test runner + suites
```

## Architecture notes

- **The host is authoritative** for positions, stamina, climb state, timers, detection, structures,
  items, revive and results. Clients send input intent every tick (unreliable, ordered) and discrete
  actions as reliable requests; the host validates range and state before acting.
- **Client prediction**: the owning client runs the same `simulate()` and corrects against the host's
  acknowledged input sequence. Remote avatars and creatures are interpolated ~100 ms behind.
- **Detection never depends on graphics**: creatures use server-side raycasts on the `L_SIGHT` layer
  from their eye to stance-based exposure points, plus explicit cover rules (grass, bush, canopy) and a
  separate light-source check. A damaged cave door blocks body sight but leaks light.
- **Critical cues are always real** and always paired with an on-screen direction arrow, so they still
  work with audio muted.
