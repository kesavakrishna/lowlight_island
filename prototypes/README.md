# Prototypes (reference only)

`v2/` is the solo prototype built separately (Godot **4.5.1**, Compatibility renderer), archived here
unchanged except for its location. It is **not** the main game: the main project at the repo root follows
`LOWLIGHT_ISLAND.md` (online co-op, escalation instead of a run timer). We keep v2 as a playable reference
and as the source of art and world-generation ideas being ported into the main project.

- Play it: open `v2/outputs/LowlightIsland-v2/project.godot` in Godot 4.5.1 and press F5
  (or set `GODOT_EXE` and run `Play.cmd`). Its controls and handoff notes are in that folder.
- Model gallery: `v2/outputs/ForestStudy-v2/project.godot`.
- Tests: from `v2/outputs/LowlightIsland-v2`, run
  `godot --headless --fixed-fps 60 --path . --script ../../work/<test>.gd`
  (`smoke_island`, `check-tree-ground`, `test-island-bridge`, `test-branch-climb-v2`,
  `test-branch-pursuit-v2`, `test-canopy-stealth-v2`, `test-jump-lod-v2`, `test-jungle-v2`,
  `test-landscapes-v2`). All passed on 2026-11-18 after the move.
- `prototypes/.gdignore` stops the root project from importing these files.

Referenced by v2's notes but never committed (not recoverable from this repo): the original
`outputs/LowlightIsland` and `outputs/ForestStudy` folders, `work/forest-models.cjs`, `work/bake-canopy.gd`,
`work/river-check.gd`, `work/playable-canopy-check.gd`, `work/profile_island.gd`, and the portable engine in
`work/godot/`. The v2 generator (`work/forest-models-v2.cjs`, run with Node) and bake script
(`work/bake-canopy-v2.gd`) cover every model in the v2 collection.

v2's `CLAUDE.md` says its decisions override the brief; for the main game, `LOWLIGHT_ISLAND.md` at the repo
root is the source of truth.
