extends SceneTree
## Diagnostic (playtest 2026-11-12): saves frames of the main-menu hover float to the folder given by --out=.
##   Godot --path . --script res://tests/capture_float.gd -- --out=C:/somewhere
var fe
var out := ""
func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	fe = load("res://menus/front_end.tscn").instantiate()
	root.add_child(fe)
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")

func run():
	for i in 30: await process_frame
	await shot("menu")
	fe.clock_ms = 100000
	fe.add_float("Skirmish", 207)
	for t in [0, 250, 750, 1250]:
		fe.clock_ms = 100000 + t
		fe.float_layer.queue_redraw()
		await shot("float_%04d" % t)
	fe.clock_ms = 100000
	for k in 6: fe.add_float("Skirmish", 207)
	fe.float_layer.queue_redraw()
	await shot("float_stack6")
	quit(0)
