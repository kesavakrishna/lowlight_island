# Lowlight Island | Claude project handoff

Updated 18 November 2026. Work in this folder to change the playable game. The owner wants a first-person island escape game that friends can eventually beat together in about six hours. The working build today is a complete **solo, six-minute escape prototype**. Preserve that playable loop when developing a requested feature. Read the current scripts before changing behavior. This handoff records decisions and context; it does not authorize implementing the whole roadmap at once.

## Open and run

- The active project is `outputs/LowlightIsland`. It uses **Godot 4.5.1, GDScript, and the Compatibility renderer** on Windows. Unreal and a Claude-driven Unreal workflow were discussed. The playable island in this folder is Godot.
- Double-click `Play.cmd` to launch fullscreen. It finds the portable engine under `../../work/godot/` or uses the `GODOT_EXE` environment variable. The project also opens through `project.godot`. Game code and assets can be edited from VS Code or Claude Desktop’s Code tab.
- Open the workspace two levels above this file when a task needs the game, original model generator, and test scripts together. Paths below are relative to this file unless specified otherwise.
- `../ForestStudy/` is the standalone model gallery. Its launcher is `View Models.cmd`. It has orbit, zoom, daylight/moonlight, and a first-person canopy walk. Gameplay edits belong here in LowlightIsland. When working alongside Codex, read the latest on-disk files before editing.

## Playable loop and controls

| Elapsed time | What players experience |
|---|---|
| 0–32 s | Click to begin at the crash in darkness. A creature patrols the clearing. Face the hanging roots for the rainforest; the open ground leads toward the objective. |
| 32–145 s | First dawn, daylight, then dusk. Collect wood, scout shelters, and move the battery. |
| 145–245 s | The second night. Continue the rescue objective or hide, relocate, and use a decoy. |
| 245–365 s | The pickup window opens at the second dawn. A powered radio and boarding at the dock complete the run. The deadline or a creature catching the player ends it. |

The battery starts in the clearing. Carry it to the radio mast, power the radio, then reach the dock. Carrying it prevents sprinting and climbing. It can be set down and recovered. A new run generates a fresh island.

| Input | Action |
|---|---|
| Mouse / WASD / Shift | Look, move, sprint using stamina |
| C / F / G | Toggle crouch, toggle flashlight, throw a night decoy (v2: decoy moved from Q to G) |
| Space | v2: jump (`JUMP`, a smaller `JUMP_CARRYING` hop with the battery) |
| E | Context action: gather, carry, install, drop, climb, descend, use a door, place a screen, or board |
| Q / V | v2: Q climbs to the higher fork (near the trunk; was Space); V builds a small platform where you stand for two planks |
| B / T / E | Preview a one-plank lookout screen, rotate, then place it at a valid aimed location on dry ground or a platform |
| Esc / F11 / R | Pause and release mouse, toggle fullscreen, generate a new island after the results screen |

## Stealth, climbing, and shelter

- **Hiding drives the game.** The creature is a threatening humanoid. It checks distance, facing, stance, light, and line of sight. The flashlight helps navigation and increases exposure. Sprinting and moving through the swamp can draw investigation. A decoy can draw a searching patrol away.
- Crouch in a bush, tall grass, reeds, or on a leafy perch. An exposed treehouse balcony is dangerous. The player can watch through a gap or behind a screen; height alone offers no guarantee. A creature that witnesses a climb can pursue the player to a lower deck or the upper canopy.
- Substantial trees use climb anchors and perches. Trees under **5 m** are too small to climb. The landmark tree has a ladder and deck. The cave has a usable interior and a buildable door that can be breached. Solid rocks, walls, and screens should block movement or sight according to their role.
- **Creature howls are the only audible game sound.** Hearing is also a gameplay system. Maintain visual cues and stealth behavior when game audio is muted.
- Future stealth ideas include true prone crawling, evidence accumulating near repeatedly occupied shelters, a short rest under watch, traps and temporary distractions, repairable defenses, player-built ladders, trunk entrances on selected trees, and alternate exits. Let a patrol discover evidence locally and give the crew a chance to react. These ideas go beyond the current crouch, cover, door, and pursuit systems.

## World layout and traversal

The island is about **420 m across**. It currently uses a finite polar terrain mesh, a randomized world axis, seeded terrain noise, variable vegetation, and landmark placement rules. Several landmark relationships and biome positions remain structured. The long-term goal is a genuinely different geography and route choice on each new game.

- Open grassland provides long, dangerous sightlines and fast travel. A central corridor keeps the battery route possible on foot. Keep open land broad and readable.
- Rainforest belts near the crash combine giant trees, understory, hanging roots, and ground plants. Preserve room to weave through them. A solid canopy trunk connects two climbable giants as an optional route.
- Two swamps have reeds, shallow water, and heavier fog. Two flowing streams drain toward the coast and can be waded across.
- Three major rock escarpments have a steep fractured face, mineral seams, fallen rock at the foot, and a gentler rear approach the player can walk up. The owner prefers broad lowlands over frequent small hills. Keep caves enterable and solid rock impassable.
- Preserve clear space for the crash, cave mouth, radio, treehouse ladder, river crossings, and dock. Generating more trees must account for their roots and the player's collision capsule as well as trunk spacing.

## Visual direction — Canopy Realism

**Walk the Canopy in ForestStudy is the visual reference for the whole game.** The desired look is natural forms with clean silhouettes, matte materials, restrained surface grain, and soft shading. A folded leaf should read as a three-dimensional leaf at arm’s length, visibly attached to its twig. Overlapping sprays and the layers between foreground, canopy, and mist create depth. Apply the same visual language to rocks, caves, shelters, creatures, and water while preserving the colors and visibility appropriate to each biome.

- Draw on the Avatar-inspired references for buttressed giants, banyans, fern crowns, hanging vines, occasional shelf fungi, and layered vegetation. Keep flowers and pink growth sparse on trunks. Favor moss, algae-green bark streaks, subdued mineral bands, and plants on wet banks.
- Use moving sun and moon, white daylight clouds, warmer low sunlight, lower night visibility, and readable moonlight across open ground. Keep light and shadow movement smooth. The water uses ripples, current, shallow edges, and sky or bank reflections.
- The game has **52** flying light motes concentrated around groves and damp ground. They fade in over roughly 18 seconds after the later night begins, fade out before dawn, and disappear in daylight. The opening night already has visible motes.
- Optimize against the playable scene. Reuse model resources and materials, batch repeated grass and leaves, simplify distant foliage, and profile the crash site, forest, and swamp with the camera at player height. Earlier benchmarks used an RTX 2060 at 1080p on individual generated islands. Measure a new change on comparable views before making a performance claim.

### Models and the latest root fix

| Original model | Role |
|---|---|
| Shelfwood | Tall canopy tree, compact buttresses, occasional shelves |
| Veil Banyan | Broad crown and hanging aerial roots |
| Crown Fern | Multi-stem tree with a fern crown |
| Tide Fern | Dense understory and cover |
| Amethyst Rosette | Broad-leaved accent on the forest floor |
| Lantern Shelves | Small groups of shelf fungi |
| Canopy Crossing | Solid, walkable trunk linking tree canopies |
| Curtain Vine | Drapes along branches and the crossing |
| Lantern Orchid | Occasional flowers along wet banks |
| Young Shelfwood | 4.6 m sapling filling gaps in jungle patches; below the climb threshold |
| Arch Palm | Leaning 8.4 m palm at jungle edges; solid trunk, not climbable |
| Elephant Ear | Waist-to-head-high broad leaves; counts as cover |
| Creeper Mat | Low ground cover; the only plant allowed on jungle trails |

### Dense jungle patches (v2 copy only)

This folder (`LowlightIsland-v2`) is the owner's working copy; `../LowlightIsland` is the untouched original. `build_jungle()` adds randomly sized and counted dense patches per seed (lushness varies a lot between islands), inspired by the ForestStudy Mixed grove: layered giants, a packed mid canopy, palms at edges, saplings in gaps, vines between crowns, a dense floor batched as MultiMesh per 28 m cell, and natural trails where only creepers grow. Each larger patch gets 1–2 walkable Canopy Crossings via `add_crossing()`, anchored on Shelfwoods turned with `add_tree(..., facing)`. Bridges keep clear of each other and of standing trees along the whole span, and `crossing_clear()` sweeps a player capsule along each planned span against the anchor giants' branches before building it. Patches stay clear of landmarks and the first grove tree. The four new models come from `../../work/forest-models-v2.cjs --new-only` (writes to `../ForestStudy-v2/models`) and `../../work/bake-canopy-v2.gd` (run with `--path` set to this folder). `../../work/test-jungle-v2.gd` reports patch variety and walks every jungle crossing. Under the joined canopy (`canopy_cover()`, eased into `canopy_shade` in `_process`), `update_light` dims sun, moon and ambient light, tints them green and thickens the haze; `update_creature` cuts sight range by 42% there (15% with the flashlight on). Creature patrol and chase are unchanged. `../../work/test-canopy-stealth-v2.gd` checks that a creature 15 m away spots the player in the open but not deep in the jungle. The smoke test's "aim and place a screen" check fails about one run in six in the original game too; that flake predates the jungle.

### Free climbing on real branches (v2, stage A of 3)

The hand-added climbing limbs and their leaf tufts are gone. `forest-models-v2.cjs --skeletons` records each climbable species' trunk axis and 20 main branches into `flora/<kind>.skeleton.json` (the regenerated GLBs were verified byte-identical, so the skeleton matches the shipped meshes). Each Shelfwood/Veil Banyan of 5 m or more gets: an invisible flat footing shape along the trunk-side two thirds of every main branch (`footing_shape`), so big and medium branches are walkable while tips and side twigs keep only round bark collision; two forks (`TreePerch`) whose seats sit on real branches (`branch_perch`) with a hidden footpad; and climbing routes that wrap round the trunk (`trunk_at`, `trunk_arc`). E at the foot climbs to the low fork; from there the player walks freely. Q (near the trunk) climbs to the high fork; E (near the trunk) climbs down; Space jumps. Standing on any wood tagged `climbable` sets `perch` to that tree's nearest fork (`tree_perch_at`). A small step-up (`step_over_twig`) lifts the player over twigs crossing a branch. `refit_blocked_forks()` runs after the island is built and moves any seat that later trees grew into onto another branch. Hiding up a tree uses the crown's own foliage density around the head (`leaf_cover`, `LEAFY_COVER`). Bridge anchors (landmark, first grove tree, jungle `facing` trees) still use a computed high seat with a hidden pad until stage C. `../../work/test-branch-climb-v2.gd` checks settling, branch walking and the up/down cycle. Stage B is done: on ordinary trees `creature_branch_goal()` drives the pursuit (up the climbing side to the player's height, round the bark to their branch, out along it; back to the trunk for a different branch; down and give up when the player leaves the tree). The treehouse tree keeps the original pursuit. V builds a platform wherever the player stands up a tree (`platform_spot`, `branch_platforms`), not within 1.8 m of another; screens fit on any platform or the deck under both feet. `../../work/test-branch-pursuit-v2.gd` covers all of this.

Stage C is done: bridge anchors no longer use hidden pads. The crossing log runs into the crown opening right up to the bark (seat at bark + 0.8 m); `align_crossing_tree` now measures the opening from 1 m out, and `crossing_clear` samples every 0.3 m so thin branches can't slip between samples. Arch Palms of 5 m or more are climbable (`palm_perch`, skeleton from `forest-models-v2.cjs --palm-skeleton`, again verified byte-identical): one fork in the crown on a hidden pad, climbed up the side of the leaning trunk; palms have no `higher` fork. Climb and descent routes follow the bending trunk (`trunk_line`). Building an island takes about 5 s at startup (was 3.4 s). Tree LOD (`place_flora`): the coarse distant mesh now takes over at clamp(24×scale, 10, 30) m (was 13×scale, 5–17 m), with a 2 m hysteresis margin, and it casts shadows, so leaves and their shadows no longer pop beside the player up in the canopy. At 1080p on the RTX 2060 it ran at 113 fps in the densest jungle view and 170–200 fps elsewhere.

The last reported gameplay issue was floating trees and huge exposed roots blocking travel. Outer buttresses now taper underground close to the bole. Fewer banyan aerial roots reach the ground. `ground_surface_height()` interpolates the actual rendered and collidable terrain triangles. `rooted_height()` checks basal vertices across each rotated, scaled woody mesh; `add_tree()` uses the resulting transform for both the render mesh and woody collider. Unsuitable sloped sites can be skipped. Keep the climb entrance on the ground and the canopy crossing aligned with its tree perches. The latest grounding check sampled **1,912 trees across three generated islands** and walked a player through each tested giant's outer root zone without jumping.

## Where to make changes

| File or function | Responsibility |
|---|---|
| `project.godot`, `island.tscn`, `island.gd` | Project settings, main scene, runtime-generated game |
| `build_world`, `build_terrain`, `elevation`, `reserved_lowland`, `build_stream` | Island generation, clear routes, terrain and water geometry |
| `build_rainforest`, `place_flora`, `add_tree`, `rooted_height`, `add_tree_perches`, `dress_grove` | Forest placement, distance detail, physical tree placement, climb anchors, canopy crossing |
| `build_cliff_faces`, `add_talus`, `solid_rock` | Cliff appearance, rubble, rock collision |
| `action`, `interact`, `update_screen_preview`, `_physics_process` | Interactions, build placement, movement, phase changes |
| `update_creature`, `pursue_tree`, `creature_ground_step`, `foliage_hidden` | Detection, pursuit, navigation, cover |
| `update_light`, `build_motes`, `update_howl` | Day/night lighting, particle visibility, audio |
| `terrain.gdshader`, `surface.gdshader`, `water.gdshader`, `sky.gdshader`, `grass.gdshader`, `leaves.gdshader`, `motes.gdshader` | Materials for the corresponding environment features |
| `flora/*.res`, `weather_noise.res`, `audio/howl.wav` | Game-ready models, baked weather texture, howl |

**Asset pipeline.** Editable model geometry is generated by `../../work/forest-models.cjs`. Node writes the original GLBs to `../ForestStudy/models/`. Godot runs `../../work/bake-canopy.gd` to convert the GLBs to the game-ready meshes in `flora/`, including distant versions where applicable. A gallery-only change becomes visible in the game after baking and using the asset in the game scene. Review both near and distant models. Verify that a visual change to roots, rocks, perches, or bridge geometry still matches collision.

## Verification from this folder

PowerShell examples use the portable engine that ships alongside this workspace.

~~~powershell
$engine = "../../work/godot/Godot_v4.5.1-stable_win64_console.exe"
& $engine --headless --fixed-fps 60 --path . --script ../../work/smoke_island.gd
& $engine --headless --fixed-fps 60 --path . --script ../../work/check-tree-ground.gd
& $engine --headless --fixed-fps 60 --path . --script ../../work/test-island-bridge.gd
~~~

The smoke script exercises multiple generated islands, including terrain and solid rock, cave access, supplies, climbing, placement, creature pursuit, and escape. The ground and bridge scripts use player physics. Repeat seed-sensitive checks on several runs. Use `../../work/river-check.gd` for wading and the night fade; it also uses the renderer. The rendered checks `../../work/playable-canopy-check.gd` and `../../work/profile_island.gd` measure views in the running game. Read their output and exit status. For art, also inspect the actual scene from a player camera in both daylight and darkness.

## Full game direction and open work

**Campaign and story.** The desired finished experience is a roughly six-hour escape for 2–4 friends. Early discussions used a 15–20 minute slice to prove one loop. The current 365-second clock belongs to the solo prototype. Six-hour pacing, chapter count, progression, persistence, and save/resume design are open. The intent is to earn duration through new places, clues, changing routes, shelter decisions, and cooperative problems. Simply stretching the clock would leave long periods with nothing to decide.

The story proposal opens with a storm bringing down a charter plane. An abandoned lighthouse flashes three times. A keeper’s log warns survivors to stay below the windows after dark; damage near a floodlight teaches what the creatures follow. The keeper moved rescue equipment after losing the dock. Notes, sketches, and landmarks can reveal the route while the crew scavenges its way toward a working transmitter. The keeper’s fate can remain uncertain. The existing game implements the crash, battery, radio, and boat loop. The lighthouse mystery and keeper’s narrative are design material for expansion.

**Replayability.** Generate islands that change where the crew explores, which shelter makes sense, and how it carries an objective home. A fuller generator would vary coastlines, regions, clue and supply placement, and shelter approaches, then validate player and battery routes before accepting a world. Test with repeatable seeds, multiple viable approaches to the radio, and clear landings for any planned alternate exits.

**Co-op proposal.** Godot high-level multiplayer with ENet and a player host is the earlier architecture proposal. Start with two local clients and a private direct-address LAN session; expand to four after the shared loop works. The host should own accepted world data, clock, inventory, battery ownership, structure state, detection, and extraction. Clients send movement and interaction intent. Proposed later features include down/revive, safe battery drops, reconnecting to a slot, map pings, and results showing who escaped. The present build is single-player.

**Player roles and combat.** The interesting choices are who carries the battery, scouts, builds, watches the patrol, or spends a decoy. A short stamina-costing defensive shove was proposed for a future iteration. Weapons, permanent character classes, traits, hunger meters, and large crafting trees remain optional ideas. The established fantasy is surviving through concealment and cooperation.

## Working agreement

Use the owner's Ponytail coding rules. Make the smallest correct change, reuse native Godot features and existing helpers first, preserve validation and error handling, protect accessibility and data, and trace the actual flow before editing. Respect the zero-budget tooling preference. Test through the normal game entry point and keep the current design decisions intact when implementing an unrelated request.

The earlier long-form proposal is in `../LOWLIGHT_ISLAND.md`. Use it for story, co-op, and design exploration. Later owner decisions documented here take precedence on opening at night, the six-hour campaign goal, Canopy Realism, howl-only audio, the small-tree climbing exception, aimed screen placement, and the low, grounded roots.

## River collection and island layouts (v2)

Each new run chooses a lake basin, pond wetland, gorge, or open grassland. Basin positions and sizes drive the terrain, water, reeds and stream outlets. Gorge islands feed one stream from an elevated basin over a drop. The six-minute rescue route and landmark crossing remain in place. Dawn has warm backlight, midday shade has more fill, and open ground receives stronger moonlight than the jungle floor.

The gallery and game include 30 river-forest models. Umbrella Fig, Tiered Copperwood and Leaning River Myrtle use branch routes recorded from their geometry. Crest Palm has a single crown landing. Bamboo is vegetation. Habitat plants share batched meshes. Cliff rubble uses the new stone models. Palm planting reserves crown clearance, and branch ownership checks the supporting collider where crowns overlap.

Regenerate only this collection with `node work/forest-models-v2.cjs --river-only` from the workspace, then run the v2 bake from the game folder with `--script ../../work/bake-canopy-v2.gd -- --river-only`. The older `--new-only` selection includes Arch Palm and Young Shelfwood. The new selection bypasses those models. `work/test-landscapes-v2.gd` checks the four landscape types and new tree landings; pass `-- --pictures` on a graphical run for player-height lighting captures.
