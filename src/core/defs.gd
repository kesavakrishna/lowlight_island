extends RefCounted
## Shared enums and constants. Preload as `const D = preload("res://src/core/defs.gd")`.

enum Stance { STAND, CROUCH, PRONE }
enum Mode { NORMAL, CLIMBING, PERCHED, DOWNED, ESCAPED }
enum Phase { DAY, DUSK, NIGHT, DAWN }
enum CState { DORMANT, PATROL, INVESTIGATE, SEARCH, CHASE, CLIMB, TREE_ATTACK, CLIMB_DOWN, BREACH, LINGER, RETURN }

const PHASE_NAMES := ["Day", "Dusk", "Night", "Dawn"]
const CSTATE_NAMES := ["dormant", "patrol", "investigate", "search", "chase", "climb", "tree_attack", "climb_down", "breach", "linger", "return"]

# Physics layers (bit values). Visibility is kept separate from collision:
# anything that blocks creature sight must also be on L_SIGHT.
const L_WORLD := 1
const L_PLAYER := 2
const L_CREATURE := 4
const L_SIGHT := 8

# Input button bits sent every tick from client to host.
const BTN_SPRINT := 1
const BTN_JUMP := 2
const BTN_INTERACT := 4

const PROTOCOL_VERSION := 1
