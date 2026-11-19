extends SceneTree
## One-off asset bake: copies the v2 prototype models the main game uses into
## res://assets/flora/ with automatic LODs, plus their climb skeletons and the
## sky / water textures. Re-run after changing the list or the source models:
##   godot --headless --path . --script res://tools/bake_flora.gd

const SRC := "res://prototypes/v2/outputs/LowlightIsland-v2/"
const OUT := "res://assets/"
const SPECIES := [
	# climbable trees (see island_world.gd TREE_MODELS)
	"Umbrella Fig", "Tiered Copperwood", "Crest Palm",
	# cover and ground dressing
	"Tide Fern", "Sword Fern", "Elephant Ear", "Meadow Hairgrass", "Rose Plume Grass",
	"Bronze Seed Sedge", "Marsh Rush", "Forest Carpet",
	# rocks
	"Mossback Boulder", "Waterworn Boulder", "Bedded Cliff Face", "Broken Talus", "Shale Overhang", "Moss Table Ledge",
]
const SKELETONS := ["Umbrella Fig", "Tiered Copperwood", "Crest Palm"]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "flora"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "textures"))
	var failed := 0
	for name in SPECIES:
		var src: ArrayMesh = load(SRC + "flora/%s.res" % name)
		if src == null:
			push_error("missing source model " + name)
			failed += 1
			continue
		var im := ImporterMesh.new()
		for i in src.get_surface_count():
			var st := SurfaceTool.new()
			st.create_from(src, i)
			st.index()
			im.add_surface(src.surface_get_primitive_type(i), st.commit_to_arrays(), [], {}, src.surface_get_material(i))
		im.generate_lods(25.0, 60.0, [])
		var mesh := im.get_mesh()
		var err := ResourceSaver.save(mesh, OUT + "flora/%s.res" % name, ResourceSaver.FLAG_COMPRESS)
		var lods := im.get_surface_lod_count(0) if im.get_surface_count() > 0 else 0
		print("baked %-18s surfaces=%d lods=%d -> %s" % [name, mesh.get_surface_count(), lods, error_string(err)])
		if err != OK:
			failed += 1
	for name in SKELETONS:
		var text := FileAccess.get_file_as_string(SRC + "flora/%s.skeleton.json" % name)
		var f := FileAccess.open(OUT + "flora/%s.skeleton.json" % name, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	var noise = load(SRC + "weather_noise.res")
	ResourceSaver.save(noise, OUT + "textures/weather_noise.res", ResourceSaver.FLAG_COMPRESS)
	print("bake done, %d failures" % failed)
	quit(1 if failed > 0 else 0)
