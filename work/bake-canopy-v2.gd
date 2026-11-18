extends SceneTree
# v2 bake: reads the jungle additions from ForestStudy-v2 and writes game meshes into the
# --path project's flora/ folder (run with --path ../outputs/LowlightIsland-v2).
# Same steps as bake-canopy.gd. Distant versions only for species built from leaf() sprays,
# whose leaves share the six-row, three-vertex layout that the coarse pass expects.

const SPECIES := ["Young Shelfwood","Arch Palm","Elephant Ear","Creeper Mat"]
const WITH_DISTANT := ["Young Shelfwood","Arch Palm"]

func _initialize():
	var selected: Array = SPECIES
	if "--river-only" in OS.get_cmdline_user_args():
		selected = JSON.parse_string(FileAccess.get_file_as_string("res://../ForestStudy-v2/models/river-collection.json"))
	for name in selected:
		var skeleton_file: String = "res://../ForestStudy-v2/models/"+name+".skeleton.json"
		if name not in SPECIES and FileAccess.file_exists(skeleton_file):
			if DirAccess.copy_absolute(skeleton_file,"res://flora/"+name+".skeleton.json") != OK:
				quit(1)
				return
		var doc := GLTFDocument.new()
		var data := GLTFState.new()
		if doc.append_from_file("res://../ForestStudy-v2/models/"+name+".glb",data)!=OK:
			push_error("missing model "+name)
			quit(1)
			return
		var model := doc.generate_scene(data)
		var parts := model.find_children("*","MeshInstance3D",true,false)
		assert(parts.size()==1)
		var mesh: ArrayMesh = parts[0].mesh
		var bake := ImporterMesh.new()
		var far := ArrayMesh.new()
		for i in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(i)
			var mat := mesh.surface_get_material(i)
			bake.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},mat)
			if not name in WITH_DISTANT or mat.resource_name == "Stems":
				continue
			if mat.resource_name in ["Foliage","Petals"]:
				var coarse := SurfaceTool.new()
				coarse.begin(Mesh.PRIMITIVE_TRIANGLES)
				var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var color: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				for j in range(0,pos.size(),36):
					for k in [1,6,16,1,16,8]:
						coarse.set_color(color[j+k])
						coarse.set_normal(arrays[Mesh.ARRAY_NORMAL][j+k])
						var mid: Vector3 = (pos[j+6]+pos[j+8])*0.5
						var offset: Vector3 = (pos[j+k]-mid)*0.33 if k in [6,8] else Vector3.ZERO
						coarse.add_vertex(pos[j+k]+offset)
				coarse.commit(far)
			else:
				far.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			far.surface_set_material(far.get_surface_count()-1,mat)
		bake.generate_lods(35,60,[])
		var result := bake.get_mesh()
		if name in WITH_DISTANT:
			ResourceSaver.save(far,"res://flora/"+name+" distant.res",ResourceSaver.FLAG_COMPRESS|ResourceSaver.FLAG_BUNDLE_RESOURCES)
		var err := ResourceSaver.save(result,"res://flora/"+name+".res",ResourceSaver.FLAG_COMPRESS|ResourceSaver.FLAG_BUNDLE_RESOURCES)
		print(name," surfaces ",result.get_surface_count()," first ",result.surface_get_material(0).resource_name," result ",err)
		model.free()
		if err!=OK:
			quit(1)
			return
	quit()
