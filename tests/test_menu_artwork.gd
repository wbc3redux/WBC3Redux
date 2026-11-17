extends SceneTree
## Geometry/input regression plus optional real-renderer captures of shared backgrounds.
const Screen = preload("res://core/ui_screen.gd")
const Display = preload("res://core/display.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _initialize():
	call_deferred("run")

func run():
	var host := Screen.new()
	root.add_child(host)
	host.setup_screen()
	var capture := "--render-capture" in OS.get_cmdline_user_args()
	var panels := ["PNL_MAINMENU", "PNL_SH", "PNL_CREATEHERO", "PNL_GAMEOPTIONS", "PNL_PROGRESSHT",
		"PNL_SS", "PNL_RESULTS_MAIN", "PNL_RETINUE"]
	Display.ensure_loaded()
	for mode in [0, 1]:
		Display.overrides.MenuScaling = mode
		for size in [Vector2i(800, 600), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1280, 800)]:
			root.size = size
			await process_frame
			host.place_view()
			check(host.viewport.size_2d_override == Vector2i(800, 600) and
				host.viewport.size == Vector2i(host.view.size.round()), "Menu render resolution does not match display")
			check(is_equal_approx(host.view.size.x / host.view.size.y, 800.0 / 600.0), "Centre aspect changed")
			for panel in panels:
				host.canvas.placements.clear()
				host.place(panel)
				host.canvas.queue_redraw()
				check(not host.backdrop.background().is_empty(), "Missing matching background: " + panel)
				if panel == "PNL_MAINMENU":
					var key := "PNL_MAINMENU/BUTT_MM_SINGLEPLAYER#0"
					var button: Dictionary = host.item(key)
					var native := Rect2(button.rect).get_center()
					var window := host.view.position + native * host.view.size / Vector2(800, 600)
					check(host.hit(host.to_native(window)).get("key", "") == key, "Click mapping changed")
					check(host.hit(host.to_native(Vector2(0, size.y / 2.0))).is_empty(), "Side wing accepts button hit")
				if capture and mode == 0:
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var with_wings := root.get_texture().get_image()
					host.backdrop.hide()
					await RenderingServer.frame_post_draw
					var without_wings := root.get_texture().get_image()
					var centre := Rect2i(host.view.position, host.view.size)
					check(with_wings.get_region(centre).get_data() == without_wings.get_region(centre).get_data(),
						"Centre pixels changed: " + panel)
					if size == Vector2i(800, 600):
						check(with_wings.get_data() == without_wings.get_data(), "4:3 rendering changed")
					host.backdrop.show()
					var path := "res://.local/menu_artwork_%dx%d_%s.png" % [size.x, size.y, panel]
					check(with_wings.save_png(path) == OK, "Capture failed")
	# Unsupported/modal-only panels must not receive a decorative background.
	host.canvas.placements.clear()
	host.place("PNL_DROPDOWNLIST")
	check(host.backdrop.background().is_empty(), "Unsupported screen decorated")
	Display.overrides.erase("MenuScaling")
	host.queue_free()
	await process_frame
	print("Menu artwork checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)
