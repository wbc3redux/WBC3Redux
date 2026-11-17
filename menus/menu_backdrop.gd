extends Node2D
## Decorative side wings only. The original viewport, pixels and hit coordinates stay untouched.
const ART = preload("res://artwork/menu-wings.png")
const BACKGROUNDS := ["BM_MAINMENU", "BM_SH_BACKGROUND", "BM_CREATEHEROBG", "BM_OPTIONSBG",
	"BM_PROGRESSHT_BG", "BM_WBC3CREDITS_BG", "BM_VICTORYBACKGROUND", "BM_VICTORYDEFEAT_BG",
	"BM_SS_BACKGROUND", "BM_RESULTS_BG", "BM_RETINUE_BACKGROUND", "BM_GY_BACKGROUND",
	"BM_RANDOMGEN_BG", "BM_RM_GENRANWORLD_BG", "BM_SYNC_BG", "BM_MPF_BG"]
var canvas: Node2D
var view: TextureRect
var window_size := Vector2.ZERO

func bind(source: Node2D, original_view: TextureRect):
	canvas = source
	view = original_view
	canvas.draw.connect(queue_redraw)

func place(window: Vector2):
	window_size = window
	texture_filter = view.texture_filter
	queue_redraw()

func background() -> String:
	var found := ""
	for entry in canvas.items():
		var bitmap := String(canvas.bitmap_override_by_key.get(entry.key,
			canvas.bitmap_override.get(entry.element.bitmap, entry.element.bitmap)))
		if bitmap in BACKGROUNDS and Rect2(entry.rect) == Rect2(0, 0, 800, 600):
			found = bitmap
	return found

func _draw():
	if canvas == null or view == null or view.size.y <= 0: return
	var key := background()
	if key.is_empty(): return
	var edge_texture: Texture2D = canvas.texture(key)
	var scale_y := view.size.y / ART.get_height()
	var quarter := ART.get_width() / 4.0
	var left := view.position.x
	var right := window_size.x - (view.position.x + view.size.x)
	for side in [0, 1]:
		var width: float = left if side == 0 else right
		if width <= 0: continue
		# Reveal from the inner edge at native proportions; only extreme widths stretch the outer wings.
		var source_width := minf(width / scale_y, quarter)
		var x := 0.0 if side == 0 else view.position.x + view.size.x
		var source_x := quarter - source_width if side == 0 else 3.0 * quarter
		draw_texture_rect_region(ART, Rect2(x, view.position.y, width, view.size.y),
			Rect2(source_x, 0, source_width, ART.get_height()))
		# Blend a narrow strip of the exact source edge into the generated wing. Never cover the centre.
		var blend := minf(width, 12.0 * view.size.y / 600.0)
		var near_x := left if side == 0 else x
		var far_x := near_x - blend if side == 0 else near_x + blend
		var u := 0.5 / 800.0 if side == 0 else 799.5 / 800.0
		draw_polygon(PackedVector2Array([Vector2(near_x, view.position.y), Vector2(far_x, view.position.y),
			Vector2(far_x, view.position.y + view.size.y), Vector2(near_x, view.position.y + view.size.y)]),
			PackedColorArray([Color.WHITE, Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color.WHITE]),
			PackedVector2Array([Vector2(u, 0), Vector2(u, 0), Vector2(u, 1), Vector2(u, 1)]), edge_texture)
