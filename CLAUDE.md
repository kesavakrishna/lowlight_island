# Lowlight Island — notes for Claude Code

- Design brief: `LOWLIGHT_ISLAND.md` (source of truth for scope and milestones; implement in order of §11).
- `prototypes/v2/` is an archived solo prototype (Godot 4.5.1) used as an art / world-gen reference.
  Don't edit it for main-game work; copy what you need into `assets/` (Git LFS) or `src/`.
- Engine: Godot 4.7, GDScript only. No `class_name` — scripts reference each other via `preload` consts
  so headless runs work without an editor import cache. Avoid `:=` when the right side is a Variant
  (dictionary access, untyped calls): GDScript refuses to infer it.
- All tunables go in `src/autoload/tuning.gd`. Shared enums / physics layers in `src/core/defs.gd`.
- The host is authoritative. Clients only send input (`_rpc_input`) and action requests (`request()` →
  `_handle_request`). Never let a client mutate shared state directly.
- Keep world generation and gameplay rules independent of rendering (headless tests must run).
- World generation must stay deterministic per (seed, attempt): use the generator's own `rng` and
  `_shuffle`, never `randf()` / `Array.shuffle()`. The host validates a seed in `Net.start_match`, sends
  seed + attempt + checksum, and every peer rebuilds the island (`island_world.gd`); a checksum mismatch
  is logged.
- Worlds share one interface (`island_world.gd`, `test_clearing.gd`): `grid`, `trees`, `caves`, `cave_at`,
  `ground_y`, `cover_at`, `set_door`, ... Heights are never assumed to be 0.
- Art from the v2 prototype is re-baked with LODs by `tools/bake_flora.gd` into `assets/flora/` (LFS).

## Commands (Godot binary: `$GODOT`, e.g. `../tools/godot/Godot_v4.7.2-stable_win64_console.exe`)

- Tests: `GODOT=... tools/run_tests.sh` (unit + integration + two-instance network smoke test)
- Just the suites: `$GODOT --headless --path . res://tests/test_runner.tscn`
- Screenshot a view: `$GODOT --path . --resolution 1280x720 -- --host --autostart=1 --start-phase=night --view=x,y,z,yaw,pitch --lantern --screenshot=out.png`
- AI trace: add `--log-ai` to a host run.
- Island maps: `$GODOT --headless --path . -- --preview-seeds=1-12 --out=previews`
- Re-bake models: `$GODOT --headless --path . --script res://tools/bake_flora.gd`

New test suites: `tests/test_*.gd` extending `res://tests/suite.gd`; methods `test_*(runner)` may `await`.
