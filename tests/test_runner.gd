extends Node
## Headless test runner (autoloads available):
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when all tests pass.

var failures := 0
var passes := 0


func _ready() -> void:
	_check_all_scripts()
	for path in _scripts("res://tests"):
		if path.get_file().begins_with("test_") and path != "res://tests/test_runner.gd":
			var script = load(path)
			if script == null or not script.can_instantiate():
				failures += 1
				print("FAIL test suite does not compile: ", path)
				continue
			var suite = script.new()
			for m in suite.get_method_list():
				var n: String = m["name"]
				if n.begins_with("test_"):
					suite.set_meta("fail", "")
					await suite.call(n, self)
					var f: String = suite.get_meta("fail")
					if f == "":
						passes += 1
					else:
						failures += 1
						print("FAIL %s.%s: %s" % [path.get_file(), n, f])
			if suite is Node:
				suite.free()
	print("tests: %d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check_all_scripts() -> void:
	for path in _scripts("res://src"):
		var s = load(path)
		if s == null or not (s is Script) or not s.can_instantiate():
			failures += 1
			print("FAIL script does not compile: ", path)
		else:
			passes += 1


func _scripts(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out += _scripts(dir + "/" + sub)
	return out
