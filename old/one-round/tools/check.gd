extends Node
## Loads every script so compile errors show up in one run (autoloads included):
##   godot --headless --path . res://tools/check.tscn


func _ready() -> void:
	for dir: String in ["res://autoload", "res://scripts"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var s: Script = load(dir + "/" + f)
				if s == null or not s.can_instantiate():
					print("BROKEN  ", dir + "/" + f)
	print("check done")
	get_tree().quit()
