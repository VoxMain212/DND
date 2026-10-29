extends SceneTree
## Bake source illustrations to small RGBA PNG files using Godot's SVG loader.
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/tokens")
	for key in ["warrior", "mage", "rogue", "cleric", "skeleton"]:
		var source := FileAccess.get_file_as_string("res://assets/token_sources/%s.svg" % key)
		var image := Image.new()
		if image.load_svg_from_string(source) != OK or image.save_png("res://assets/tokens/%s.png" % key) != OK:
			printerr("Could not bake " + key)
			quit(1)
			return
	print("Baked five transparent PNG standees.")
	quit()
