extends Node3D
## Placeholder main scene. Replaced by the game entry point in milestone 1.

func _ready() -> void:
	print("Takedown Racer: main scene loaded (renderer: %s)" % RenderingServer.get_current_rendering_method())
