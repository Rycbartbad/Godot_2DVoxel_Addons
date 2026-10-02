extends SceneTree
const SolveBatch := preload("res://src/physics/solve_batch.gd")

func _initialize() -> void:
	print("script = ", SolveBatch)
	var b = SolveBatch.new()
	print("instance = ", b)
	if b != null:
		print("has sync_params = ", b.has_method("sync_params"))
	quit(0)
