# Lowlight Island | Project report

**19 November 2026 · Windows · Godot 4.5.1 · GDScript · Compatibility renderer**

Lowlight Island is a playable solo stealth-survival game. A run starts at a nighttime crash and lasts about six minutes. The player can already escape, get caught, or miss the rescue window. Its distinctive mechanic is hiding in a forest that both the survivor and the creature can climb. The proposed full game extends that experience into a saveable expedition for one to four players, targeting roughly six hours for a first-time crew.

## Which version contains what?

| Version | Contents |
|---|---|
| Published game at commit `2bf81d2` | The v2 game, model gallery, four landscape layouts, 30 additional environment models, climbing routes for four new species, day/night lighting, 52 night motes, and gameplay tests. |
| Latest tested local v2 build | Adds a fig and bamboo to the opening view, distributes the new models more widely, introduces visible low-angle canopy shafts, and raises night motes to 480. The verification and performance figures below describe this build. |
| Full-game design | Co-op, campaign chapters, save/resume, main menu, expanded player actions and additional extraction routes are proposed work. |

This publication adds the report. To reproduce the published playable build, open the game project in Godot 4.5.1 and press F5. The gallery opens as a second Godot project. [Game](project.godot) · [Controls](README.md) · [Model gallery](../ForestStudy-v2/project.godot) · [Project handoff](CLAUDE.md)

## The playable expedition

| Elapsed time | Player experience |
|---|---|
| 0–32 seconds | Wake at the crash in darkness. A creature patrols the clearing. Find supplies, choose cover, or head toward the battery. |
| 32–145 seconds | Dawn reveals trails and landmarks. Gather wood, scout a shelter, and move the battery toward the radio. |
| 145–245 seconds | The second night puts the crew’s route under pressure. Hide, relocate, distract the creature, or continue carrying the battery. In the current solo build, one survivor makes every decision. |
| 245–365 seconds | The second dawn opens the pickup window. Power the radio and board at the dock before the deadline. |

### Player, shelter, and creature mechanics

- **Movement and handling.** First-person walking, sprinting with stamina, crouching, jumping, and shallow-water wading. The heavy battery prevents sprinting and climbing, reduces jump height, and can be set down and recovered.
- **Climbing.** Physical trunks, branch footing, lower and upper forks, small step-ups over twigs, and walkable bridges between crowns. E climbs or descends and Q reaches a higher fork. Large broadleaf trees have routes fitted to their geometry. Climbable palms have a crown landing. Small saplings and thin bamboo serve as vegetation.
- **Building.** Gather planks, spend two to build a small platform at the player’s position on a branch, and spend one to place an aimed, rotatable lookout screen on valid ground or a platform. The landmark treehouse has a deck and ladder. A cave door can be closed and breached.
- **Stealth.** Use bushes, reeds, tall grass, leafy branches, solid cover, or a screen. Exposure depends on stance, facing, sightlines, distance, canopy shade, and flashlight use. Height alone offers little protection on an exposed balcony.
- **Creature behavior.** A humanoid patrols after dark, investigates disturbances, responds to a thrown decoy, and pursues a witnessed climb. It can return to the trunk to reach another branch or descend when the survivor leaves. Sprinting and swamp movement can attract attention. Creature howls are the only audible game sound.
- **Controls and session.** Mouse/WASD, Shift sprint, C crouch, Space jump, F flashlight, G decoy, E interact, Q climb higher, V platform, B preview screen, T rotate. Esc pauses, F11 toggles fullscreen, and R generates another island after a run ends.

### World, art, and assets

The island is about 420 metres across. Each run chooses a lake basin, pond wetlands, a gorge, or open grassland. Basin positions and dimensions vary. Wetlands can contain several ponds, and a gorge’s elevated stream produces a waterfall. The game reserves landmark approaches, jungle trails, canopy crossings, and a route for the battery carrier. The crash, treehouse, cave, radio, and dock still have structured relationships.

**Canopy Realism** uses folded leaves attached to branches, layered crowns, mossy wood, restrained flowers, and matte rock with visible bedding. The earlier collection includes Shelfwood, Veil Banyan, Crown Fern, Tide Fern, Amethyst Rosette, Lantern Shelves, Canopy Crossing, Curtain Vine, Lantern Orchid, Young Shelfwood, Arch Palm, Elephant Ear, and Creeper Mat.

| Additional models | Inventory |
|---|---|
| 6 trees and bamboo | Umbrella Fig, Tiered Copperwood, Leaning River Myrtle, Crest Palm, Giant Reed Bamboo, Brush Bamboo |
| 6 grasses and sedges | Meadow Hairgrass, Rose Plume Grass, Bronze Seed Sedge, Marsh Rush, Silver Bank Grass, Forest Carpet |
| 8 understory plants | River Elephant Ear, Copper Bromeliad, Violet Shieldleaf, Lime Strapleaf, Blue Ripple Lily, Sword Fern, Bank Maidenhair, Tower Fern |
| 10 rock formations | Bedded Cliff Face, Moss Table Ledge, Fractured Twin Block, River Stair Outcrop, Shale Overhang, Waterworn Boulder, Mossback Boulder, Ford Stepping Slab, River Gravel Fan, Broken Talus |

The gallery supports individual inspection, orbit and zoom, daylight and moonlight, and a walkable mixed grove. The game uses baked meshes, batched ground plants, and distant tree detail. The four protected tree species have geometry-dependent climbing or placement data. The river collection has its own generation and baking option. [Asset workflow](CLAUDE.md)

### Light and atmosphere

The sun and moon move across the sky. Daylight has white clouds, dusk warms the horizon, swamp fog thickens near water, and the joined canopy filters light. Water carries ripples, current, shallow edges, and reflected sky and banks. The latest local pass frames the crash with bamboo and an Umbrella Fig. Warm shafts appear in canopy openings when the sun is low. Night lights drift along routes, landmarks, wet banks, and groves, then fade before dawn.

## Verification and performance

These are recorded results from the latest local visual pass. All eight required gameplay suites passed. The additional landscape and crash-view checks passed as well.

| Check | What passed |
|---|---|
| Smoke and escape | The rescue sequence, interactions, lighting transitions, and win condition |
| Branch climbing | 48/48 sampled landings and higher-fork cycles, 44/48 outward branch walks, and 16/16 tested palm cycles |
| Branch pursuit and building | Pursuit across branches and into palm crowns, descent after the player leaves, platform placement, and screens |
| Jungle generation | Generated patches and traversal of sampled jungle crossings |
| Canopy stealth | Open-ground detection, deep-canopy concealment, and shaded lighting |
| Jump and distant detail | Ground and branch jumps, landing, tree detail transitions, and shadows |
| Landmark bridge | Player walked the canopy crossing |
| Tree grounding | 277 sampled trees, 7,269 terrain collision probes, and a walk across the outer root zone |
| Landscape and opening visuals | All four landscape types, landings on four new climbable species, opening fig in view, dawn shafts, and day/night mote visibility |

The project handoff records an intermittent smoke-test failure when aiming a screen at a branch platform on earlier builds. A passing suite samples generated islands and does not guarantee every possible placement.

| RTX 2060, 1920 × 1080 | Before latest local visual pass | After |
|---|---:|---:|
| Crash view | 8.0 ms/frame | 7.5 ms/frame |
| Forest view | 7.5 ms/frame | 8.2 ms/frame |
| Swamp view | 6.6 ms/frame | 7.8 ms/frame |

The two runs generated different islands. These measurements describe observed scenes. A release benchmark should repeat fixed seeds and camera routes and measure frame-time spikes as well as averages.

## Full-game scope and remaining work

| Area | Proposed features and decisions |
|---|---|
| **Main menu and sessions** | New Expedition, Continue, Join a Friend, Settings, Quit. Save slots show camp, objective, crew, and last played time. Add a lobby, invitations or codes, late join, reconnect, and a recap for returning players. Solo can pause. Co-op menus should communicate that the world is still running. |
| **Player actions** | Add prone crawling, leaning to peek, low mantles, controlled drops, clear climb destinations, safe heavy-item placement, item handoffs, and rope hauling. Peeking should move both the camera and the body point the creature can see. Define injury, downed, revive, and solo recovery rules. |
| **Stealth and night survival** | Give searches readable stages and local evidence such as flattened grass, repeated light leaks, or damage at a door. Expand hide choices to trunk hollows and emergency reed beds. Add supervised rest, noise alarms, and temporary distractions. |
| **Shelters and expeditions** | Player-built ladders, storage, repairable screens and doors, salvage when moving camp, and shelters with different escape options. Make camp relocation worthwhile through changing destinations and patrol pressure. |
| **Co-op** | Start with two players, then test four. Synchronize world generation, time, inventory, structures, doors, creature decisions, carried items, and extraction. Add pings and shared map notes. Handle disconnections while carrying a critical item. |
| **Campaign** | Proposed arc: survive the crash, read the island, recover rescue equipment, prepare an exit, make the extraction. Use a failed coastal rescue station and keeper’s records to connect light, stealth, and escape. Playtest boat repair and radio pickup as distinct exit choices. |
| **World and navigation** | Place clues and sites by terrain. Give the crew a choice between an exposed shortcut and a sheltered detour. Validate every critical objective with the heavy carrier’s movement limits. Decide any map expansion through measured travel time. |
| **Gear and progression** | A small kit of light, rope, tools, decoys, bandages, and mapping supplies. Unlock practical actions and routes. Combat weapons, permanent traits, and hunger systems remain optional design decisions. |
| **Persistence** | Save the island, campaign progress, time, builds and damage, caches, dropped items, survivors, and extraction state. Exercise save/resume halfway through a carry and reconnect after a host saves. |
| **Accessibility and release** | Rebinding, input sensitivity, brightness calibration, head-bob options, captions or visual howl cues, and readable prompts. Package a standalone Windows build, test on a clean PC, profile dense four-player camps, and finish the campaign solo and with friends. |

### Recommended production order

1. Prove the existing rescue with two players. Add New, Save & Leave, Continue, and reconnect. A dropped battery must survive saving, quitting, and rejoining.
2. Build a 30–45 minute expedition with a clue, two viable carry routes, a shelter choice, and a teammate rescue. Observe first-time players without coaching.
3. Deepen hiding and traversal with peeking, prone movement, mantling, local creature searches, and shelter repair.
4. Produce the campaign, environmental story, equipment sites, and two extraction routes. Tune toward six hours using measured expedition times.
5. Balance one through four players, validate seeds and saves, finish accessibility and menus, and ship a standalone build.

The next milestone is a complete two-player rescue that can be interrupted and resumed with the island, shelter, battery, and crew intact.
