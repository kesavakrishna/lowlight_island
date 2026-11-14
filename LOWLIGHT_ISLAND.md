# Lowlight Island — Game Design and Build Brief

This is the design reference for building **Lowlight Island** with Claude Code. Implement it in playable milestones. The complete v1 scope is below. Treat example timings and balancing suggestions as starting points to playtest, and keep deferred ideas out of the first release.

## 1. The game

Lowlight Island is a **first-person 3D online co-op survival horror game for 2–4 friends**. Aim for grounded, modest-detail environments and flashlight-driven horror inspired by Phasmophobia. The crew crashes on an unfamiliar island and must get off it. By day, players scout terrain, read clues, gather wood, build shelter, rescue captured friends, and recover the battery needed to call for rescue. At dusk, creatures emerge from underground. Different types hunt by different senses — sight, sound, ground vibration — and they come back stronger and smarter every night. They investigate noises, follow traces to places the crew has occupied, climb trees, and break into shelters. Each creature has its own personality, carries scars from earlier encounters, and learns from how the crew escaped it. Darkness wears down each player's Nerve, and light restores it — the same light that draws the creatures. The crew escapes by powering the radio, surviving a loud and bright broadcast, and reaching the rescue boat at dawn.

The signature moment comes just before sunset. One friend thinks the team can still reach the radio, another wants to barricade the cave, and the player carrying the battery knows they can't climb to the canopy with it. Make all three positions reasonable. During the night, reward players for reading the danger, preparing an exit, and helping each other improvise when a plan goes wrong.

**v1:** One complete run spanning as many day–night cycles as the crew needs — **there is no run timer**. The pressure is escalation: each night the creatures return stronger and smarter, so every extra day on the island raises the cost of stalling. Aim for a typical escape of **three to six days, roughly 30–60 minutes**, after tuning. Each new run generates a new island. Start testing with two players and a small area, then support up to four for the complete release. Target a native Windows build with keyboard and mouse first. Use first person so players can peek from a cave, crawl at grass height, and look down from a treehouse. Give camera shake a setting and let players adjust mouse sensitivity and field of view.

## 2. Story and delivery

A storm forces the crew's charter plane down on a remote island. An abandoned lighthouse flashes three times as the survivors leave the wreck. At the keeper's cottage, a logbook warns: “If you see the lamp flash after dark, get below the windows.” The keeper learned that the creatures emerge at dusk and track steady light. After losing the main dock, she moved the rescue transmitter to a tidal cave and wired it to signal ships. Her last entries warn that the transmitter is a beacon in both directions: the broadcast glows and hums, and the creatures converge on it. Her log ends partway through the repairs.

For v1, use the **radio shed** as the playable transmitter site and an **old dock** as the pickup point. The lighthouse, cottage, and tidal transmitter can appear in notes or scenery as scope allows. A later version can turn the keeper's full route into a longer story. Keep her fate unresolved in v1.

Tell the story through things players can use. A keeper's note can explain why covering a window matters. A broken floodlight and gouges in the wood can hint at what light attracts. A sketch at the wreck points to the live battery location on that seed. Show the active objective clearly even if the crew skips optional notes. Keep the opening short enough to rematch without friction.

## 3. Match flow and escape

| Phase | What happens | Decision to preserve |
|---|---|---|
| Lobby | A host opens a private session, friends join by address in v1, and the host starts with 2–4 players. | Get into a run quickly. |
| Day | Spawn at the crash on day one with a rough map, a battery clue, and access to a limited supply of wood. Scout, salvage, build, carry the battery toward the radio, and raid burrows to rescue captured teammates. | Push the objective, or spend the day on wood, safer routes, a rescue, and a stronger shelter for tonight. |
| Dusk | The sun and shared clock warn the crew. Creatures emerge as night starts. | Push on or commit to a hiding place while there is time to prepare. |
| Night | Hide, listen for patrols, rest, relocate, and help stranded teammates. Each night the creatures return stronger and smarter, and a new type can surface. If the radio is powered, the crew can choose to run the broadcast tonight. | Trust the current shelter, relocate, or commit to the loud broadcast while the crew is still strong. |
| Dawn and repeat | After a completed broadcast, the boat arrives at the next dawn and holds for a limited boarding window. Until then, the day–night loop repeats with rising danger. | Get everyone aboard or leave while at least one player can still escape. |

The required objective chain is **crash → battery → radio shed → broadcast → dock**. Installing the battery powers the radio. The call is not instant: **the broadcast runs for several minutes, lights up the shed, and hums loudly enough to carry** — every creature in range converges on it. The crew decides which night to broadcast and how to survive it: defend the shed, rotate decoys, split the creatures' attention while one player keeps the transmitter running. An interrupted broadcast keeps its progress, so a crew can finish it in stages across nights. After a completed broadcast, the boat arrives at the next dawn and holds for a limited boarding window. Creatures linger in the shaded stretches of the route to the dock at dawn, so the final leg is a run, not a victory lap. Boarding with at least one player counts as a crew win. The results screen shows who escaped and how many nights it took, and offers a rematch with a fresh seed. There is no run deadline — escalation is the clock. If every player is down or captured at the same time, the run ends in a loss.

The terrain, not an unrelated hunger or crafting timer, should make players feel pressed for time. Give them enough daylight to make meaningful progress and reach cover on a direct route. Extra salvage and safer approaches can cost time. Night should still contain decisions, even after a good shelter is built.

## 4. Procedurally generated island

**Generate the actual land and biome layout anew for every normal start and rematch.** Earlier ideas about rotating several authored maps or rearranging fixed areas were superseded. A seed can be replayed intentionally for debugging and playtests. Reuse hand-drawn assets and landmark structures while generating the coastline, terrain regions, routes, shelters, and landmark positions around them.

### Generation pipeline

1. **Build the land.** Use a seeded random generator and low-frequency elevation variation with a falloff toward the edges. Form a main island surrounded by water. Use connected ridges, valleys, and broad flats so the result reads as geography rather than scattered terrain tiles. Make open land wide enough to feel exposed and forests deep enough to change navigation.
2. **Assign biomes.** Use elevation and moisture to create large, mostly contiguous regions. Include open grassland, dense forest, mountains, and swamp in normal v1 worlds, with coast around the island. Vary their size, shape, and positions. Leave walkable corridors through dense vegetation.
3. **Add routes and cover.** Use passes through mountain ridges, dry banks and crossings through swamps, climbable trees, patches of tall grass and bushes, rocks, fallen trunks, and caves along cliff edges. Optional blocked or flooded shortcuts must be visible before players commit and must leave viable routes around them. Designate valid build slots and safe rope landings as part of shelter placement.
4. **Place readable landmarks.** Put the crash and old dock on usable coastline. Place a radio shed on a ridge or another suitable plot with enough room for approaches. Choose a battery site from viable generated spots, such as a beached skiff or salvage near a distinctive tree. Put supplies and a matching battery clue at the wreck. Generate landmarks people can describe to each other.
5. **Validate before spawning.** Check a walkable route from the crash to the battery, from the battery to the radio, and from the radio to the dock. Use carrying restrictions and terrain speeds for the leg that requires the battery. Check that a reasonable direct route allows meaningful progress and access to shelter before dusk. Keep two materially different approaches to the radio viable. Make sure caves have reachable entrances, the rope lands on traversable ground, and objective sites and drops never depend on climbing or crossing impassable terrain. Reject bad seeds before the crew spawns. Use a bounded number of attempts and surface a retry if generation fails.

| Biome | Gameplay |
|---|---|
| **Open grassland** | Fast ground with long sightlines and gaps between cover. Tall grass and fallen logs are valuable during a crossing. |
| **Dense forest** | Short sightlines, many climbable trees, bushes, and breaks in line of sight. Players can lose a creature quickly or get surprised at close range. |
| **Mountains** | Ridges help players orient themselves. Cliffs block movement and sight. Caves, ledges, and narrow passes create strong shelters and risky bottlenecks. |
| **Swamp** | Shallow water makes travel slower and louder. Dry banks and reed beds give a longer but quieter route. Deep water blocks travel. |
| **Coast** | Open beaches offer fast travel, while dunes, wreckage, and grass provide occasional concealment. The coast anchors the crash and escape. |

The server generates one complete world for each room and sends the accepted world data to all clients. Keep the world size small enough for the match length and expand visual scale through broad regions. Start with a seed preview that shows colored terrain, objectives, shelter locations, route checks, and estimated travel times. Inspect a range of seeds, including ones with terrain that could cut a route in two. Show a rough starting sketch in play, with known objectives and landmarks revealed as the group finds them. Support silent map pings for **hold**, **move**, and **danger here**.

Generate a finite height grid and convert it into continuous 3D terrain meshes in sections. Shape slopes, ridges, and cliffs with believable silhouettes and use terrain material changes to make biomes legible. Use separate cave scenes at cliff edges with actual interior space. The height grid is the source for generation and route checks, but the traversability check must also account for height differences, collision, and blocked paths in the placed 3D scenes. Keep terrain fixed during play and allow construction at shelter slots. Mining, deformable voxels, and infinite streaming are outside v1.

## 5. Movement, carry limits, and supplies

- **Movement:** Walk, sprint, crouch, go prone, and climb. Sprint spends stamina and is louder than walking. Crouching or going prone makes sense near cover. Allow a player to sprint behind an obstacle, drop prone, and crawl into grass without a clumsy interaction sequence.
- **Inventory:** Start with two small tool slots and a separate carry state for the radio battery. Store wood as a simple tracked resource so construction doesn't compete with both tool slots. Make small item and wood availability tunable. Put enough wood near the wreck for an early build choice and spare supplies farther out.
- **Heavy battery:** The carrier cannot sprint or climb. They can put the battery down quickly or hand it off by dropping it for a teammate. A valid drop lands on reachable ground and remains findable. If the carrier goes down, drop the battery where the crew can get it back. Keep one authoritative battery state from spawn to pickup, drop, and installation.
- **Rest:** Let players take a short rest in a dark shelter to recover stamina while someone else keeps watch. An emergency branch perch is for concealment and gives no special rest benefit. Avoid forcing everyone to sleep through the night.

## 6. Hiding and creature behavior

Ship a **pool of creature types with distinct traits**, all built on one shared behavior core. Each run draws from the pool, so crews must read tracks, sounds, and silhouettes to work out what they're up against. For development, still start with a single Stalker in the first test scene and add types one at a time.

### Creature types (v1 pool)

| Type | Senses and traits | What it punishes | How to beat it |
|---|---|---|---|
| **Stalker** | Hunts by sight. Drawn to light and movement, fast in pursuit, weak hearing. | Lanterns, crossing open ground, standing silhouettes. | Light discipline, breaking line of sight, staying low. |
| **Listener** | Blind. Acute hearing and ground-feel; ignores light entirely. | Sprinting, building at night, splashing, loud shelters. | Moving slowly, timing noise to wind and rain, decoys. |
| **Digger** | Senses vibration through soft ground and surfaces from below. Cannot climb. | Ground shelters on soil, camping in one spot. | Rock ledges, tree platforms, caves with stone floors. |
| **Climber** | Slower on the ground but climbs trunks fast and shakes platforms. | Treating the canopy as automatically safe. | Rope exits, screens, perching only with a watch kept. |

Give each type a distinct silhouette, call, footstep sound, and track so a crew can identify it from evidence before the first encounter, and tell each other "it's a Listener night" in their own words.

### Nightly escalation

Creatures return **stronger and smarter every night**. Drive escalation from the night index through one tunable table:

- **Stronger:** more individuals on patrol, faster movement, wider sight and hearing ranges, quicker breaches.
- **Smarter:** later nights unlock behaviors — checking known hiding spots first, remembering shelters and entrances the crew has used, searching in pairs, cutting off a fleeing player's route instead of chasing directly.
- **Deeper pool:** night one draws one or two types; later nights add individuals and can surface a type the crew hasn't met yet, announced by new tracks found the next morning.

**Escalation curve.** Difficulty rises in two phases, controlled by one tunable threshold night (start at **night 4**):

- **Ramp phase (nights 1 to threshold):** gentle, linear increases. Each night adds a small fixed amount to patrol count, speed, sense range, and breach speed, and unlocks the next "smarter" behavior. This is the learning window: enough time to find the battery, power the radio, rescue a captive, and meet most of the pool.
- **Exponential phase (after the threshold):** each night multiplies the escalation values by a growth factor (start at **×1.5 per night**) instead of adding to them. The island goes from dangerous to unsurvivable within a few nights.

Put the exponential growth where it stays readable: **number of individuals, breach speed, search thoroughness, and time spent checking hiding spots**. Cap the stats that would break the hiding game — creature speed stays below player sprint, and sight and hearing ranges stop at a maximum — so late nights feel like being overwhelmed, not like being cheated. The curve should feel like a soft deadline: no timer ever appears, but by two or three nights past the threshold the crew has to have broadcast already.

Signal the shift. On the first night past the threshold, give a clear in-world warning (louder calls at dusk, far more burrows opening, a keeper's note found earlier that says "after the fourth night they stop hiding") so the crew knows they've crossed into the exponential phase.

Escalation is the game's clock. A crew that stalls never hits a timer — they face a night they're no longer equipped for. Tune so night one is survivable with improvised cover, the threshold night demands real preparation, and every night after it is noticeably worse than the last. Weight patrol routes toward the objective legs (battery site, radio approach, dock) and the crew's general region so every night produces encounters without feeling scripted.

### Creature memory and personality

Every individual creature **persists for the whole run** and remembers the crew. Memory lasts only within a run — a new seed brings new creatures. Do not build ranks, promotions, a creature hierarchy, or cross-run persistence; the Nemesis System that inspired this is patented, so keep the design to individual memory and personality within one run, and check with an IP lawyer before any commercial release.

- **Scars.** What happens to a creature shows on its body, so players can recognize individuals. A shoved creature limps or carries a visible wound. A creature that captured a player carries that player's dropped lantern, still glowing faintly. Each creature also keeps its type's base silhouette so it stays identifiable.
- **Learned counters.** Each creature records how players escaped it and adapts on its next encounters: a rope escape makes it check rope landings, a decoy that fooled it makes it more likely to ignore noisemakers, a grass hide makes it rake grass patches, a cave door it failed to breach makes it return to that cave sooner. Learning is per individual, so the crew has to keep track of which creature knows what. Cap how many counters one creature holds and let old ones fade, so no single creature becomes unbeatable.
- **Grudges.** A creature fixates on the player who shoved it, escaped it most, or blinded it with light. It prioritizes that player when choosing targets, and that player's Nerve drains faster when it is near.

**Personality.** Roll a small set of traits for each individual at spawn — **bold or cautious, patient or impulsive, curious, territorial** — and use them to weight its choices in a utility-style decision layer on top of the shared state machine (patrol → investigate → search → chase or breach). Two Stalkers with the same senses should behave noticeably differently: one charges every light, another circles and waits. Traits never change what a creature can perceive, only how it acts on what it perceives.

**Learned tricks unlocked by escalation.** Later nights unlock behaviors on top of personality: **feigned retreat** (leaving a hiding spot, then doubling back), **flush and wait** (one creature drives players out while another holds the exit), and **freezing still** near a shelter it suspects. Each trick needs a readable tell — a sound that stops abruptly, a silhouette that doesn't move — so a careful crew can catch it.

Show every creature's current state, active traits, learned counters, grudge target, and the reason for its last decision in a development debug overlay.

All types share the same cue classes, weighted per type — a Listener ignores sight entirely, a Stalker barely hears:

| Cue | Creature response | Player response |
|---|---|---|
| **Sight or bright light** | A visible player triggers pursuit. A visible light draws the creature to its source. If it sees someone enter a cave or climb a tree, remember that entrance or trunk and commit to checking or breaching it. | Shutter the lantern, use terrain to break sight, then change direction before entering a hide. |
| **Sound** | Investigates footsteps, splashes, branches, building, or a noisemaker at the source. A second sound nearby can prolong or focus the search. | Wait quietly, move during an opening, or send it toward a decoy. A creature that still sees a player keeps pursuing. |
| **Traces** | Finds fresh trails when a patrol passes close enough, follows them, and checks likely hiding places. Repeated approaches and multiple occupants build more traces. Quiet occupation builds them slowly, and they fade when the site is vacant. | Avoid reusing the same approach, choose a sheltered spot away from patrols, or leave while it is still checking. |

Use readable states: **patrol → investigate → search → chase or breach**. A creature can go straight to chase or climb on confirmed sight. On lost sight, search from the last known position before resuming patrol. A trace or an empty ladder is reason to investigate, while direct sight of an entry, strong evidence during the search, or a branch shaking above an investigating creature can trigger a committed climb. Keep traces local and tunable. A creature needs to encounter evidence. A well-chosen shelter can last the full night, and lingering increases risk without forcing an automatic breach at a fixed time. Across a multi-day run, traces are what keep one perfect shelter from trivializing every night: staying put builds risk night over night, and relocating resets it.

| Hide | Strength | How it fails |
|---|---|---|
| **Prone in tall grass** | Lets you crawl between patches when a patrol looks away. | Close movement rustles. A creature can check the patch if it saw you enter. |
| **Bush** | Conceals a still player from several directions. | Entry and exit shake the leaves. A nearby searching creature can inspect it. |
| **Rock or fallen trunk** | Quickly breaks line of sight. | Protects from one direction. The creature can circle it. |
| **Tree perch or canopy** | Gets players out of a passing creature's direct path. | Movement shakes branches. A witnessed climb points the creature to the trunk. |
| **Built shelter** | Conceals a group, offers a place to rest, and buys time against a breach. | Evidence can draw the creature to the site. Cover degrades if attacked. |

In first person, terrain and walls naturally block the view. Use server-side 3D sight checks from the creature's eye position to player exposure points, taking stance, authored grass or bush cover, and visible light into account. Use simple, explicit light detection rules so changing a graphics setting doesn't change stealth. Keep nearby terrain and cover readable after dark. Concealment feedback should say whether cover applies without promising safety from a search. Give distinct cues for passing footsteps, changes in the search, bark scraping, a door under pressure, and the final moments before a breach. Pair critical audio cues with a visible directional cue or animation. Let friends use their own voice chat. Only in-game actions affect creature hearing.

## 6a. Nerve (sanity)

Each player has a **Nerve** meter, inspired by Phasmophobia's sanity. Its core purpose is to set up one tradeoff every night: **light keeps you sane, and light gets you found.**

| Drains Nerve | Restores Nerve |
|---|---|
| Standing in darkness, especially outdoors | Light: an unshuttered lantern or a fire in a shelter |
| Being separated from the crew | Staying close to teammates |
| Seeing a creature, hearing calls, a nearby breach | Resting in a shelter while someone keeps watch |
| A teammate being downed or captured | Daylight, and rescuing a captive |
| Later nights (drain rate scales with escalation, faster in the exponential phase) | |

**Effects of low Nerve:**

- **Hallucinations, private to that player.** Phantom footsteps, silhouettes in the tree line, a false flicker at the edge of the beam, a call from the wrong direction. Hallucinations are client-side only and never reach other players, so the crew has a natural co-op check: "do you see that?"
- **Louder breathing.** Below a threshold, the player breathes audibly in the game world, and creatures can hear it like any other sound.
- **Shakier light.** The lantern beam wavers, and fast shuttering takes slightly longer.
- **Targeting.** When creatures pick between possible targets, they favor the player with the lowest Nerve, like Phasmophobia's hunts.

**Fairness rules.** Hallucinations never imitate the critical warnings — a committed climb, a door under pressure, the final moments before a breach, or their visible directional cues. Those signals are always real, including in the muted-audio mode. Nerve never kills or downs a player on its own, and it always recovers with light, company, rest, or daylight. Display Nerve through the player's body and senses (breathing, vignette, beam steadiness) with an optional numeric meter in settings.

The host owns each player's Nerve value. Each client generates only its own hallucinations from that value.

## 7. Trees, shelters, and building

**Every tree is climbable.** Some trees have an obvious hand-climb entrance such as a low branch, forked root, or rough section of trunk. A player can attempt a climb from any accessible side. Tree shape determines how far they can get by hand. A built ladder can reach the top of **any** tree from a usable base position. Only sufficiently sturdy trees support permanent built platforms.

| Tree type | Hand climb | Ladder |
|---|---|---|
| Low branches | Quick scramble to a lower perch. | Opens a route to the canopy. |
| Rough trunk | Reaches the canopy, with more time and stamina than a ladder. | Gives the crew a quicker shared route. |
| Tall bare trunk | Can grab and climb partway, with no lower perch to stay on. | Reaches the canopy for temporary hiding. |

Trees have real 3D height. Keep climbs manageable with authored anchors for **ground, lower perch when present, and canopy**. Move players and creatures along short, authored paths between anchors. Each spawned tree uses a reusable model with handhold positions, ladder placements, a trunk route for the creature, and a deck socket for sturdy variants. Use separate trunk, canopy, and deck pieces. A platform at the canopy adds room for two to rest or watch. A rope exit requires a valid landing away from the trunk. A creature climbs the trunk independently of any ladder, so removing or pulling up a ladder, if added later, can't make a tree safe. From below it can scrape the bark, shake the deck, reach an exposed player, or attack an upgrade. Give the crew time to commit to the rope, a lower branch where available, or another exit after the first clear warning.

**Caves** conceal light and break sight. A shallow cave gives a view of the approach. A deep cave hides lamps better but restricts your view outside. Put a door at a short entrance and allow an inner low wall in valid slots. Some sites have a second crawl exit. Keep that exit usable on foot while restricting the bulky battery if the passage is too narrow. A one-exit cave is a real risk, so give its occupants time to read the breach and options such as moving behind the inner wall, sending a decoy, or slipping by after a shove.

| Build piece | Purpose | Tradeoff |
|---|---|---|
| **Ladder** | Reaches the canopy on any tree. | Costs wood and placement time. A patrol can stop to investigate it. |
| **Tree platform** | Adds a place for two to rest and scout at a sturdy tree. | Exposed from some angles until screened. Can be damaged. |
| **Screen** | Blocks sight and light in one direction. | Other angles can still expose players. A torn screen leaks light. |
| **Rope exit** | Gives occupants a fast way down away from the trunk. | Uses resources and needs a clear landing. |
| **Cave door** | Conceals the entrance when closed and delays a breach. | Opening it makes noise. Damage reduces how long it can hold. |
| **Low wooden wall** | Hides crouched players and catches sight through a breached door. | Creatures can see standing players over it or break it during a breach. |

Build at fixed slots for v1. Preview what a placement covers, require a valid spot and available wood, and make placement take a short, readable amount of time. A structure that delays a creature should show **intact, damaged, and broken** states. Preserve concealment on a cracked closed door if it still covers the opening. Show torn screens and unstable platforms clearly. Keep repairs cheaper than replacing the piece. For the first pass, use simple damage stages and allow blocking or concealment to change only at defined stages.

## 8. Tools, fighting, and recovery

- **Shuttered lantern:** Helps with navigation and scouting, and restores Nerve while open. The visible light can attract creatures. Allow fast shuttering while moving. The lantern flickers when a creature is close — a real, server-driven warning, never a hallucination.
- **Throwable noisemaker:** Pulls a searching creature toward the sound. It can create a short window to reach the grass or move a downed friend. It won't reliably cancel confirmed pursuit or a climb the creature has committed to.
- **Shove:** Your one close-range defense. It makes a creature recoil briefly and costs most of your stamina. Tune the recovery so a player cannot hold a doorway indefinitely by repeatedly shoving. Use it to get past or rescue someone. Creatures have no killable combat loop in v1.
- **Down, crawl, and revive:** A creature that catches a player downs them. A downed player is not a spectator: they can **crawl slowly and quietly**, inching toward cover or teammates, and use silent pings. A teammate can revive them once there's an opening. Leave dropped gear where it fell. Keep player positions and item drops valid even during a climb or breach.
- **Capture and burrow rescue:** If a creature reaches a downed player, it starts **dragging them toward a burrow**. The drag is slow and interruptible — a shove or a well-timed decoy breaks it. A player dragged all the way becomes captive in the burrow and spectates teammates until rescued. Burrows are marked on the map once seen, and a daytime **burrow raid** frees the captive: creatures inside are sluggish in daylight, but the deeper dark is still dangerous, so the raid is a real excursion, not a formality. Rescue gives days a second job beyond the objective and keeps a caught friend in the story. If the entire crew is down or captive at once, the run ends.
- **Reconnect:** Give a disconnected player a short opportunity to rejoin their existing slot using a reconnect token. Preserve the slot's server state and inventory, with the avatar still subject to the match. Validate the token and room membership on the server.

Example: the crew sets up a screened platform above a patch of grass. The battery is stashed below because the carrier can't climb with it. A late teammate is spotted climbing, and the creature goes straight for the trunk. One player takes the rope into the grass, another waits for a clear chance to retrieve the battery, and a third throws a decoy to distract a searching patrol that hasn't seen them. They can abandon the battery for the moment if the route to it is compromised. The breach changes the plan and leaves the crew with choices.

## 9. Technology and multiplayer architecture

Build a native 3D desktop game with **Godot 4 and GDScript**. Prototype lighting in **Forward+** and profile on the weakest available playtest PC before committing to the effects budget. Keep one Godot project that can run as a player client, a host who also plays, or a headless server if remote tests need one. [Godot renderer comparison](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)

| Part | Choice |
|---|---|
| Engine and game code | **Godot 4 + GDScript**. Use Godot's 3D physics, rendering, audio, and UI. Start with `CharacterBody3D` for movement and simple collision shapes for players, props, and shelters. [Godot](https://godotengine.org/) |
| Coding | **VS Code + the official Godot extension**, with Claude Code working in the same project folder. Use VS Code for GDScript, generator code, tests, and project files. Use the Godot editor for visual scene layout, collision previews, lighting, and animation. [External editor setup](https://docs.godotengine.org/en/stable/tutorials/editor/external_editor.html) |
| Multiplayer | **Godot's high-level multiplayer API + ENet**. Begin with direct IP and port. The host runs the authoritative simulation. [Godot multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) |
| World data | A seeded GDScript terrain generator and reusable Godot scenes for trees, caves, and landmarks. Use a top-down grid for generation and path validation, then instantiate 3D geometry and collision. |
| Storage | Run state lives in server memory. A server restart ends active matches. Seed replay recreates the world layout for debugging. |

Keep the project in one repository. Keep world generation independent of rendering so it can run in headless tests. Use typed inputs and a fixed simulation step. Clients send input or action intent. The host validates it and owns player positions, stamina, climb state, timers, detection, structures, inventory, rescue, and results. Interpolate remote movement as needed. Sync the accepted world data and current match state to reconnecting players. For creature movement, start with ground waypoints or the validated walkable grid, and handle climbing and breaching with explicit traversal points. Never let a client award itself an item, place a structure through a wall, act for another player, or advance a match phase.

Keep tuned settings in one obvious place. Use shared terrain classifications for collision, movement cost, and route validation. Keep visibility distinct from collision, and separate authored art layers from gameplay markers for sight blockers, cover, build slots, climb positions, and exits. Use simple debug overlays during development to show what the creature can see, the last known target, and a build slot's coverage.

Run two local game instances first, then test on two computers on the same Wi-Fi, and **do the first remote (non-LAN) test early — by milestone 2, not at the end** — remote connectivity is the most common reason friends can't actually play together. Remote friends need a reachable UDP host, and most home connections sit behind CGNAT where port forwarding fails. Treat a free mesh VPN such as Tailscale or Radmin as the default remote path and ship short setup instructions with v1; use a forwarded game port or a reachable headless server where available. A short join code alone cannot connect peers across the internet. Ship Host and Join by Address for the first build. Add shareable room codes only if you choose infrastructure that can resolve them to a reachable host. Preserve private access separately from reconnect tokens. Hosting may cost money. Avoid accounts, persistent profiles, and public matchmaking in v1. [Godot command line and headless options](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

## 10. Asset production on a zero tooling budget

**Who makes what.** Claude Code can produce most of the environment directly as code: models built from primitives and generated meshes in GDScript (trees, shed, dock, boards, rocks, and intact, damaged, and broken states), Blender Python scripts for more detailed low-poly models exported as `.glb`, shaders (water, wind sway, fog, lantern flicker, and the low-Nerve screen distortion), generated noise textures, UI icons, and simple keyframed animation. Claude can't generate realistic raster textures or recorded audio. For those, use CC0 libraries such as [Poly Haven](https://polyhaven.com/) and [ambientCG](https://ambientcg.com/) for textures, and phone recordings or [Freesound](https://freesound.org/) (check each sound's license) for audio. The **creature** is the hardest and most important asset: start with a stylized low-poly creature Claude builds in code — darkness and silhouette carry most of the horror — and replace it later with a CC0 model (for example from Quaternius) animated with Mixamo, or a custom model, if playtests call for more detail. Scars and carried items attach to sockets on whichever creature model is used.

Start with primitive placeholders in Godot. For finished assets, use modest geometry, believable proportions, and a small set of shared materials for soil, rock, bark, wet ground, and worn wood. Put finer surface detail in textures. Prioritize what a light reveals at arm's length: tree bark, the cave entrance, a damaged door, the player's tool, and the creature's silhouette.

- **Make modular pieces in Godot first.** Build a tree from a trunk and canopy, a platform from boards, and a character from simple limb shapes. Use simple poses and keyframed movement for climbing and crouching. Make intact, damaged, and broken pieces visually distinct.
- **Use Blender only when a custom model needs it.** Blender is free. Export custom meshes as `.glb` and assemble their gameplay collision and attachment points in Godot. Track source and license information for borrowed models and sounds. [Blender](https://www.blender.org/)
- **Assemble reusable Godot scenes.** Create the crash, radio shed, dock, and cave from a small shared set of meshes. Add entrances, collision, interaction points, and clearance markers. Generate terrain in code. Use simple collision and batch repeated scenery when measured performance calls for it.
- **Record inexpensive sound effects.** Use a phone to record leaves rustling, wood scraping, a door rattling, and simple footfalls. Trim and edit in Audacity. Add ambience for the wind, water, and approaching night when the important cues are clear. Pair bark scrapes and breaches with visible feedback. [Audacity](https://www.audacityteam.org/faq/)

For the first art pass, make a ground palette for the five terrain types, a recognizable model for each tool and the battery, three variations of the climbable tree, and clear damage states for structures. Spend time on readability under dusk lighting before working on extra characters or decorative variants.

### Night lighting prototype

- **Portable light:** Give the existing shutterable light a flashlight-like beam using `SpotLight3D`. Let the center reach farther than the edge. Enable shadows so trunks, rocks, and closed doors stop the beam. Teammates should see where the light is pointed. The host checks visibility of the source or exposed spill at openings with gameplay raycasts. Graphics settings never change what creatures detect.
- **Darkness:** Use low ambient light and a dim directional moonlight outdoors. Keep minimum close-range silhouettes readable. Tune the cave interior separately so it feels sheltered and darker. Start with fixed exposure. Later, test a slow, bounded adjustment when a player enters darkness, inspired by Phasmophobia's eye adaptation. Exposure changes are cosmetic. [Godot environment settings](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html)
- **Fog and performance:** Use distance fog first. Try optional local volumetric fog in a swamp pocket or near a cave mouth. Limit shadow distance and the number of shadow-casting lights. Test with four lights turned on in the same clearing. Keep a lower preset that reduces fog and shadow cost while preserving the cues and basic beam occlusion. Generated worlds and player-built shelters rely on runtime lighting. Full-island light baking and real-time indirect lighting are outside the first pass. [Godot volumetric fog](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html)
- **Playtest:** Light one clearing with a tree, a patch of grass, and a cave door. Check that a player can find the rope with the light on, read nearby cover with it off, and tell when light leaks through a damaged shelter. Judge the look and frame rate at player eye level before building assets for the other biomes.

## 11. Implementation order for Claude Code

1. **Create the smallest connected test.** Build a 3D first-person test clearing with a tree, a cave, and grass. Run two Godot game instances locally with host-controlled movement, direct-address join, a shared clock, and placeholder geometry.
2. **Prove the night.** Add line of sight, lost-sight search, tall-grass hiding, a climbable tree, a rope, a cave door, and one creature — the Stalker — that follows a witnessed climb. Add a decoy, a visible climb cue, and a clear breach window. Test whether a player can evade the creature, whether both clients agree on damage, and whether an unseen climb plays out differently from a witnessed one. Do the first remote (non-LAN) connection test during this milestone.
3. **Prove that seeds make new worlds.** Build the colored tile preview and route validator. Generate whole islands with all four core biomes and different coastlines and objectives. Add reusable landmarks and verify lots of seeds before spending time on art. The fixed test clearing can stay as a development fixture.
4. **Connect one full escape run.** Add gathering, battery carry and drop, the timed broadcast that attracts creatures, the repeating day–night loop, nightly escalation driven by one tunable table, dawn boarding after a completed call, and win or loss. Have the host generate and share a fresh world when starting or rematching. Make shortcuts, route costs, and shelter placements matter to a crew carrying the battery.
5. **Finish the co-op systems.** Add the remaining creature types one at a time (Listener, Digger, Climber), creature persistence with scars, learned counters, grudges, and personality traits, then escalation tricks (feigned retreat, flush and wait, freezing still). Add Nerve with its drain and restore sources, then hallucinations last, once the real cues are reliable. Also add all tree types and ladders, the remaining construction and damage states, trace-based investigations, shove, rest, crawl, capture and burrow rescue, rejoin, silent pings, and rematch. Keep asset states aligned with the server's rules.
6. **Replace placeholders and playtest.** Add final core art and sound, teach the controls through the lobby and first run, test 2–4 players across separate devices, and tune travel, exposure, and night pressure. Fix objective and extraction blockers before polishing optional content.

Keep changes small and reuse platform features first. Preserve input validation, accessibility, readable failure states, and the ability to recover dropped objective items. Write focused tests for world generation and hard-to-reproduce multiplayer or objective regressions. Use hands-on playtests for tension and pacing.

## 12. v1 acceptance checks

- **Fresh world:** Starting a new run or rematch changes the layout, not just the positions of loot. Test several seeds and check that they change where players travel and spend the night. A replayed seed reproduces the same world layout.
- **Fair objective:** A crew can reach the battery, carry it to the radio without a climb, survive a broadcast, and reach the boat. A downed carrier, rough terrain, or a narrow entrance never leaves the battery permanently inaccessible. The run has a clear outcome, and escalation — not a timer — makes stalling visibly costly.
- **Fair detection:** An unseen player in cover can let a patrol pass. A creature can follow a witnessed climb, investigate a lantern or a noise, and eventually find a frequently used shelter through nearby evidence. Players can read the difference between patrol, search, and imminent breach. Each creature type is identifiable from its silhouette, sounds, and tracks, and players can recognize a returning individual by its scars. A creature visibly adapts to a counter the crew used on it before, and two creatures of the same type behave differently. Hallucinations never imitate a critical warning, and a player can always recover Nerve. Night three is noticeably more dangerous than night one, and each night past the threshold is clearly worse than the one before, while capped speed and sense ranges still let a hidden player survive a patrol.
- **Useful shelters:** Every tree can be climbed at least partway by hand and all the way with a ladder. Only sturdy trees take a platform. A compromised platform with a rope offers a practical exit. A cave door shows damage and buys time. A missed build still leaves grass, bushes, and opportunistic perches useful.
- **Recoverable mistakes:** Test a witnessed climb, a breached cave door, a dropped battery, a captured teammate, and a player briefly disconnecting. Each has a credible recovery when the rest of the crew acts in time — including a daytime burrow rescue. A fully downed or captured crew can restart from results.
- **Complete session:** Two to four friends can open the desktop build, connect to the host, learn the controls and objective, see the shared time, call the boat, understand who escaped, and rematch without a developer explaining it. Verify LAN play and test the chosen remote connection method before a remote playtest. Critical creature cues also work with audio muted.
- **Reason to replay:** After a run, ask what players would do differently. Look for concrete answers such as taking the dry bank, putting the ladder up early, saving wood for the rope, or leaving the battery under cover before dark.

## 13. Ideas to defer

- More of the keeper's story, ruins of past runs appearing in new seeds, and a longer coastal finale.
- A second escape route with a repairable fishing skiff. Gathering its parts changes the crew's route, and the engine attracts creatures during the launch.
- Creature types beyond the v1 pool, richer tide changes, and more build parts, such as door braces or a timed decoy lamp. Add them when they create decisions the existing tools can't support.
- In-game proximity voice chat that creatures can hear. It's the genre's best moment-generator, but real-time voice in Godot is a project of its own — revisit after v1.
- An optional fixed-length short mode (a hard cap of two or three nights), or difficulty presets that change the threshold night and growth factor, if playtests show the default curve doesn't pace runs well.
- Player traits, permanent classes, weapon trees, hunger, extensive recipes, and free-form construction. v1 roles arise from who carries the battery, watches an entrance, builds, or spends the last decoy. Let player knowledge carry between runs.
