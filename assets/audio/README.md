# Recorded sounds

Every sound in the game is synthesized at startup as a placeholder (`src/autoload/sfx.gd`). To replace one, put a
recording here named after its cue, as `.ogg` (preferred), `.wav` or `.mp3`, and reopen the project so Godot imports
it. Nothing else needs to change. Keep files short, mono, and trimmed tight; loops (`wind`, `drone`, `breath`) should
loop cleanly.

Record with a phone and trim in [Audacity](https://www.audacityteam.org/), or use CC0 / properly licensed sounds from
[Freesound](https://freesound.org/) — **check each sound's licence** and list it in `CREDITS.md`.

| Cue | What it is | Notes |
|---|---|---|
| `step` | Player footstep, normal walk | dry leaves / soil, a few variations help |
| `step_soft` | Crouched footstep | quieter, slower |
| `rustle` | Moving through grass / bushes, prone crawl | leaves brushing |
| `branch` | Branches shaking (climbing, someone moving up a tree) | snapping twigs, leaf shake |
| `rope` | Sliding down a rope | rope whir + friction |
| `door_creak` | Cave door opening / closing | old wooden door |
| `door_hit` | Something slamming into a door (also hammering / building, pitched) | **critical cue** — heavy, unmistakable |
| `breach_warn` | A door about to give way; also the Digger's call (pitched down) | **critical cue** — splintering, a growl |
| `scrape` | Claws scraping bark: a creature climbing | **critical cue** |
| `call` | Creature call at nightfall (pitched per type) | long, eerie, carries far |
| `screech` | Creature starting a chase | short, sharp |
| `chitter` | Creature searching; also the Listener's call (pitched down) | clicks |
| `creature_step` | Creature footstep (pitched per type); Digger tunnelling | heavy, padded |
| `rattle` | Noisemaker going off | tin can with stones |
| `down` | A player going down | thud + groan |
| `breath` | Low-nerve breathing (loop) | ragged in / out |
| `wind` | Ambient wind (loop) | |
| `drone` | Night drone (loop); the radio hum and skiff engine are pitched versions | low, even |

Critical cues must stay readable and distinct: they are also always shown on screen with a direction arrow, so the
game still works with the sound muted.
