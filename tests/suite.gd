extends RefCounted
## Base for test suites: methods named test_* receive the runner.

func check(cond: bool, msg: String) -> void:
	if not cond and str(get_meta("fail", "")) == "":
		set_meta("fail", msg)
