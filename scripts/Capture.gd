extends Node
## Development helper. Run the game with
##   godot --path . -- --capture=user://shot.png --after=40 [--scene=battle]
## to render a few frames headlessly-ish and save a screenshot. Used to review
## the art without a desktop. Does nothing during normal play.

var _target := ""
var _after := 40
var _frames := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_target = a.substr(10)
		elif a.begins_with("--after="):
			_after = int(a.substr(8))
	set_process(_target != "")

func _process(_delta: float) -> void:
	_frames += 1
	if _frames < _after:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_target)
	print("[capture] wrote ", _target)
	get_tree().quit()
