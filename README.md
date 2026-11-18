# Lowlight Island

First-person online co-op survival horror for 2–4 friends, built with **Godot 4.7 + GDScript**.
The full design brief lives in [LOWLIGHT_ISLAND.md](LOWLIGHT_ISLAND.md).

## Status: milestones 1–2 (test clearing)

| Milestone | State |
|---|---|
| 1. Smallest connected test | Done: first-person clearing, host-authoritative movement with client prediction, Host / Join by Address, shared day–dusk–night–dawn clock, placeholder geometry |
| 2. Prove the night | Done in the fixture: the Stalker (sight + light + weak hearing), line-of-sight and lost-sight search, tall grass and bush hiding, three climbable tree types (low branches, rough trunk, bare trunk + ladder), deck + rope exit, cave door with intact / damaged / broken states and a prone-only crawl exit, witnessed-climb commitment, bark-scrape and breach cues with on-screen direction arrows, noisemaker decoys, down / crawl / revive. **Remote (non-LAN) test still to do — see below.** |
| 3. Procedural islands | Next |

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

Useful dev flags (after `--`): `--host`, `--join=ADDR`, `--port=N`, `--name=S`, `--autostart=N`,
`--seed=N`, `--fast-clock=X`, `--start-phase=night`, `--log-ai`, `--bot`, `--quit-after=S`,
`--screenshot=FILE`, `--view=x,y,z,yaw,pitch[,stance]`, `--lantern`.

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
