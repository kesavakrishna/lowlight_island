extends RefCounted
## One creature's memory and personality for this run only (no ranks, no hierarchy,
## nothing carried between runs). Host-side; scars are replicated for visuals.
##
## Personality weights choices but never changes what the creature can perceive.
## Learned counters record how players escaped this individual; they are capped and
## fade if not reinforced. A grudge makes one player its preferred target.

# ---- personality, rolled once at spawn (-1..1 or 0..1)
var boldness := 0.0       # bold charges lights and pursues sooner; cautious circles and waits
var patience := 0.0       # patient searches longer and doubles back; impulsive gives up and switches
var curiosity := 0.0      # investigates small sounds, checks hiding places on patrol
var territorial := 0.0    # keeps close to its burrow, returns to known shelters

var scars: Array[String] = []          # "wound", "limp", "lantern", "blind"
var counters: Array[Dictionary] = []   # {kind, strength, night, arg}
var grudges: Dictionary = {}           # peer -> score
var grudge_reason := ""


func roll(rng: RandomNumberGenerator) -> void:
	boldness = rng.randf_range(-1.0, 1.0)
	patience = rng.randf_range(-1.0, 1.0)
	curiosity = rng.randf()
	territorial = rng.randf()


func traits_text() -> String:
	var parts: Array[String] = []
	parts.append("bold" if boldness > 0.25 else ("cautious" if boldness < -0.25 else "steady"))
	parts.append("patient" if patience > 0.25 else ("impulsive" if patience < -0.25 else "even"))
	if curiosity > 0.6:
		parts.append("curious")
	if territorial > 0.6:
		parts.append("territorial")
	return ", ".join(parts)


# ------------------------------------------------------------------ decisions

## Awareness needed before it commits to a chase.
func chase_threshold() -> float:
	return 1.0 - 0.2 * boldness


func search_mult() -> float:
	return 1.0 + 0.4 * patience


# ------------------------------------------------------------------ learned counters

func knows(kind: String) -> bool:
	for c in counters:
		if c["kind"] == kind and c["strength"] > 0.0:
			return true
	return false


func counter_arg(kind: String) -> Variant:
	for c in counters:
		if c["kind"] == kind:
			return c.get("arg")
	return null


func learn(kind: String, night: int, arg: Variant = null) -> bool:
	for c in counters:
		if c["kind"] == kind:
			c["strength"] = minf(c["strength"] + 1.0, 3.0)
			c["night"] = night
			if arg != null:
				c["arg"] = arg
			return false
	counters.append({"kind": kind, "strength": 1.5, "night": night, "arg": arg})
	if counters.size() > Tuning.max_counters:
		counters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["strength"] > b["strength"])
		counters.resize(Tuning.max_counters)
	return true


## Called each time it wakes: old lessons fade unless the crew keeps teaching them.
func fade(night: int) -> void:
	var keep: Array[Dictionary] = []
	for c in counters:
		if night - int(c["night"]) >= Tuning.counter_fade_nights:
			c["strength"] -= 1.0
		if c["strength"] > 0.0:
			keep.append(c)
	counters = keep


func counters_text() -> String:
	var parts: Array[String] = []
	for c in counters:
		parts.append("%s(%.1f)" % [c["kind"], c["strength"]])
	return ", ".join(parts) if not parts.is_empty() else "-"


# ------------------------------------------------------------------ scars and grudges

func scar(kind: String) -> bool:
	if scars.has(kind):
		return false
	scars.append(kind)
	return true


func add_grudge(peer: int, amount: float, why: String) -> void:
	grudges[peer] = grudges.get(peer, 0.0) + amount
	if grudges[peer] >= Tuning.grudge_threshold and grudge_peer() == peer:
		grudge_reason = why


func grudge_peer() -> int:
	var best := -1
	var best_v := Tuning.grudge_threshold - 0.001
	for p in grudges:
		if grudges[p] > best_v:
			best_v = grudges[p]
			best = p
	return best


func rekey(old_id: int, new_id: int) -> void:
	if grudges.has(old_id):
		grudges[new_id] = grudges[old_id]
		grudges.erase(old_id)
