# Playtesting Lowlight Island

Milestone 6 is about finding out how it plays with real people. Automated tests cover the rules; only people can
tell us whether it's tense, fair and readable.

## Before a session

- Build: `powershell -ExecutionPolicy Bypass -File tools\export_windows.ps1 -Godot <godot_console.exe>` and share
  `build/LowlightIsland-windows.zip`. Everyone must run the same build (the lobby rejects version mismatches).
- Remote friends: set up Tailscale first (`docs/REMOTE_PLAY.md`). Test the connection with a short run.
- Run `GODOT=... tools/run_tests.sh` and `tools/soak_test.sh` on the build you're sharing.

## During a session

- Don't coach. Note where people get stuck, what they misunderstand, and what they say out loud ("it's a
  Listener night!" is exactly what we want to hear).
- Anyone can press **F8** to save a quick note (time, seed, position are recorded with it).
- Watch for: getting lost on the way to an objective, nights that feel unfair, creatures that feel like they cheat,
  shelters that feel either useless or invincible, Nerve effects that annoy rather than unsettle.

## After each run

- The results screen asks **"What would you do differently next time?"** - concrete answers ("take the dry bank",
  "ladder early", "leave the battery under cover") mean the island gave real choices. "Nothing" or "I don't know"
  means it didn't.
- Reports: `%APPDATA%\Godot\app_userdata\Lowlight Island\runs\*.json` (one per player per run) and `feedback.log`.
  Each report has the seed (replay it with `--seed=N`), a timeline of key moments, downs / captures / revives,
  structures built, notes read, and every creature's traits, scars and lessons.

## The brief's acceptance checks (LOWLIGHT_ISLAND.md §12) to confirm by hand

- [ ] Two to four friends can open the build, connect, learn the controls and the objective, see the shared time,
      call the boat, understand who escaped, and rematch without a developer explaining it.
- [ ] LAN play works; the chosen remote method (Tailscale) works.
- [ ] Night three is noticeably more dangerous than night one; each night past the fourth is clearly worse.
- [ ] Players can tell patrol, search and imminent breach apart - and tell the creature types apart by evidence.
- [ ] A returning creature is recognised by its scars; one visibly adapts to a trick used on it before.
- [ ] Critical cues still work with the sound muted.
- [ ] Recoveries feel credible: a witnessed climb, a breached door, a dropped battery, a captured teammate, a
      brief disconnect.

## What to tune (all in `src/autoload/tuning.gd`)

| Feels... | Try |
|---|---|
| Runs too long / too short | `day_length`, `night_length`, `escalation_threshold_night`, `escalation_growth` |
| Night one too harsh | creature `sight_range_dark`, `awareness_rate`, `patrol_count` ramp |
| Hiding too easy / too hard | `grass_reveal_*`, `bush_reveal`, creature `fov_deg`, `noise_*` radii |
| Battery leg trivial / punishing | `carry_speed`, `route_budget_frac`, `biome_cost` |
| Broadcast too safe / too deadly | `broadcast_time`, `broadcast_noise`, `broadcast_light_mult` |
| Nerve irrelevant / oppressive | `nerve_*` rates, `nerve_hallucinate_below` |
| Building too cheap / useless | wood amounts, `build_time`, piece HP in `src/match/building.gd` |
| Captures too punishing | `drag_speed`, `linger_before_drag`, `raid_time`, `raid_wake_chance_*` |
