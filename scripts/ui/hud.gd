class_name HUD
extends Control
## In-stage HUD: countdown, stats, minimap, objective arrow, boss bar,
## toasts, tutorial hints, banners and cinematic letterbox.

var stage
var time_label: Label
var time_bar_bg: ColorRect
var time_bar: ColorRect
var loop_label: Label
var lv_label: Label
var hp_bg: ColorRect
var hp_fill: ColorRect
var hp_ghost: ColorRect
var hp_text: Label
var exp_fill: ColorRect
var stat_label: Label
var gold_label: Label
var herb_label: Label
var herb_icon: TextureRect
var obj_label: Label
var obj_panel: NinePatchRect
var boss_box: Control
var boss_fill: ColorRect
var boss_ghost: ColorRect
var boss_name: Label
var mini: Control
var mini_tex: ImageTexture
var mini_scale := 1
var mini_px := Vector2.ZERO
var mini_frame: NinePatchRect
var arrow: TextureRect
var arrow_label: Label
var hint_panel: NinePatchRect
var hint_label: Label
var toasts: Array = []
var bar_top: ColorRect
var bar_bot: ColorRect
var hurry := false
var _t := 0.0
var _last_sec := -1
var _shown_hp := 1.0
var _shown_boss := 1.0
var gold_shown := 0.0
var left_panel: NinePatchRect


func setup(s) -> void:
	stage = s
	UIKit.full(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# --- timer (top centre)
	var tp := UIKit.panel("panel", Rect2(262, 2, 116, 40))
	add_child(tp)
	var clock := UIKit.icon("clock", Vector2(8, 9), 2.0)
	tp.add_child(clock)
	time_label = UIKit.big_label("60.0", 30, UIKit.WHITE, 6)
	time_label.position = Vector2(28, -1)
	time_label.size = Vector2(84, 34)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.pivot_offset = Vector2(42, 18)
	tp.add_child(time_label)
	time_bar_bg = UIKit.rect(Color("2e222f"), Rect2(266, 42, 108, 4))
	add_child(time_bar_bg)
	time_bar = UIKit.rect(Color("f9c22b"), Rect2(267, 43, 106, 2))
	add_child(time_bar)
	loop_label = UIKit.label("LOOP 1", "small", UIKit.ECHO, 3)
	loop_label.position = Vector2(262, 47)
	loop_label.size = Vector2(116, 12)
	loop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(loop_label)
	# --- stats (top left)
	left_panel = UIKit.panel("panel", Rect2(2, 2, 150, 50))
	add_child(left_panel)
	lv_label = UIKit.label("Lv 1", "bold", UIKit.GOLD)
	lv_label.position = Vector2(7, 4)
	left_panel.add_child(lv_label)
	var hi := UIKit.icon("heart", Vector2(48, 7))
	left_panel.add_child(hi)
	hp_bg = UIKit.rect(Color("2e222f"), Rect2(58, 7, 86, 8))
	left_panel.add_child(hp_bg)
	hp_ghost = UIKit.rect(Color("fca790"), Rect2(59, 8, 84, 6))
	left_panel.add_child(hp_ghost)
	hp_fill = UIKit.rect(Color("e83b3b"), Rect2(59, 8, 84, 6))
	left_panel.add_child(hp_fill)
	hp_text = UIKit.label("30/30", "tiny", UIKit.WHITE, 3, false)
	hp_text.position = Vector2(60, 4)
	hp_text.size = Vector2(82, 10)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_panel.add_child(hp_text)
	var eb := UIKit.rect(Color("2e222f"), Rect2(7, 19, 137, 4))
	left_panel.add_child(eb)
	exp_fill = UIKit.rect(Color("30e1b9"), Rect2(8, 20, 0, 2))
	left_panel.add_child(exp_fill)
	stat_label = UIKit.label("ATK 7  DEF 2", "small", UIKit.PALE)
	stat_label.position = Vector2(7, 25)
	left_panel.add_child(stat_label)
	var ci := UIKit.icon("coin", Vector2(7, 38))
	left_panel.add_child(ci)
	gold_label = UIKit.label("0", "small", UIKit.GOLD)
	gold_label.position = Vector2(16, 35)
	left_panel.add_child(gold_label)
	herb_icon = UIKit.icon("herb", Vector2(66, 32), 0.75)
	left_panel.add_child(herb_icon)
	herb_label = UIKit.label("x0", "small", Color("91db69"))
	herb_label.position = Vector2(80, 35)
	left_panel.add_child(herb_label)
	# --- objective (bottom left)
	obj_panel = UIKit.panel("panel", Rect2(2, 338, 300, 20))
	add_child(obj_panel)
	var oi := UIKit.icon("boss", Vector2(5, 7))
	obj_panel.add_child(oi)
	obj_label = UIKit.label("", "small", UIKit.WHITE)
	obj_label.position = Vector2(16, 4)
	obj_panel.add_child(obj_label)
	# --- minimap (top right)
	mini = Control.new()
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.draw.connect(_draw_minimap)
	add_child(mini)
	# --- objective arrow
	arrow = UIKit.icon("arrow", Vector2.ZERO)
	arrow.pivot_offset = Vector2(4.5, 4)
	arrow.visible = false
	add_child(arrow)
	arrow_label = UIKit.label("", "tiny", UIKit.GOLD, 3, false)
	arrow_label.visible = false
	add_child(arrow_label)
	# --- boss bar
	boss_box = Control.new()
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.position = Vector2(170, 62)
	boss_box.visible = false
	add_child(boss_box)
	var bb := UIKit.rect(Color("2e222f"), Rect2(0, 12, 300, 8))
	boss_box.add_child(bb)
	boss_ghost = UIKit.rect(Color("fbff86"), Rect2(1, 13, 298, 6))
	boss_box.add_child(boss_ghost)
	boss_fill = UIKit.rect(Color("fb6b1d"), Rect2(1, 13, 298, 6))
	boss_box.add_child(boss_fill)
	boss_name = UIKit.label("", "bold", Color("fca790"), 3)
	boss_name.position = Vector2(0, -3)
	boss_name.size = Vector2(300, 14)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	# --- tutorial hint
	hint_panel = UIKit.panel("panel_echo", Rect2(170, 306, 300, 22))
	hint_panel.visible = false
	add_child(hint_panel)
	hint_label = UIKit.label("", "small", UIKit.WHITE)
	hint_label.position = Vector2(8, 5)
	hint_label.size = Vector2(284, 12)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_panel.add_child(hint_label)
	# --- letterbox
	bar_top = UIKit.rect(Color("2e222f"), Rect2(0, -40, 640, 40))
	add_child(bar_top)
	bar_bot = UIKit.rect(Color("2e222f"), Rect2(0, 360, 640, 40))
	add_child(bar_bot)


func setup_minimap(img: Image) -> void:
	mini_tex = ImageTexture.create_from_image(img)
	mini_px = Vector2(img.get_width(), img.get_height())
	mini_frame = UIKit.panel("panel", Rect2(0, 0, 8, 8))
	add_child(mini_frame)
	move_child(mini_frame, mini.get_index())
	apply_minimap_mode()


## settings.minimap: 0 = hidden, 1 = normal, 2 = large (M cycles it in play)
func apply_minimap_mode() -> void:
	if mini_frame == null:
		return
	var mode := int(Game.settings().get("minimap", 1))
	var auto := 2 if mini_px.x <= 48 and mini_px.y <= 36 else 1
	mini_scale = auto
	if mode == 2:
		# as large as fits in a 150x110 corner
		mini_scale = maxi(auto + 1, mini_scale)
		while mini_scale > 1 and (mini_px.x * mini_scale > 150 or mini_px.y * mini_scale > 110):
			mini_scale -= 1
	var sz := mini_px * mini_scale
	mini.position = Vector2(640 - sz.x - 6, 6)
	mini.size = sz
	mini_frame.position = mini.position - Vector2(4, 4)
	mini_frame.size = sz + Vector2(8, 8)
	mini.visible = mode != 0
	mini_frame.visible = mode != 0
	mini.queue_redraw()


func refresh_minimap(img: Image) -> void:
	if mini_tex:
		mini_tex.update(img)


func _draw_minimap() -> void:
	if mini_tex == null:
		return
	var s := float(mini_scale)
	mini.draw_texture_rect(mini_tex, Rect2(Vector2.ZERO, mini.size), false)
	for m in stage.minimap_marks():
		var p: Vector2 = m.pos / 16.0 * s
		var c: Color = m.color
		var r: float = m.get("size", 2.0)
		if m.get("blink", false) and int(_t * 4.0) % 2 == 0:
			continue
		mini.draw_rect(Rect2(p - Vector2(r, r) * 0.5, Vector2(r, r)), Color("2e222f"))
		mini.draw_rect(Rect2(p - Vector2(r - 1, r - 1) * 0.5, Vector2(r - 1, r - 1)).grow(0.5), c)


# ------------------------------------------------------------------ updates
func update_stats(run: Dictionary) -> void:
	lv_label.text = "Lv %d" % run.lv
	var k := float(run.hp) / float(run.max_hp)
	hp_fill.size.x = 84.0 * k
	hp_text.text = "%d/%d" % [run.hp, run.max_hp]
	exp_fill.size.x = 135.0 * float(run.exp) / float(max(1, run.next))
	stat_label.text = "ATK %d  DEF %d" % [stage.hero_atk(), stage.hero_def()]
	herb_label.text = "x%d" % int(run.items.get("herb", 0))
	if k < 0.3:
		hp_fill.color = Color("e83b3b") if int(_t * 6.0) % 2 == 0 else Color("fca790")
	else:
		hp_fill.color = Color("e83b3b")


func set_loop(n: int) -> void:
	loop_label.text = "LOOP %d" % n


func set_objective(t: String) -> void:
	obj_label.text = t
	obj_panel.size.x = max(120, 26 + t.length() * 10)


func set_time(t: float, total: float) -> void:
	var tt: float = max(t, 0.0)
	time_label.text = "%.1f" % tt if tt < 10.0 else "%d" % int(ceil(tt))
	time_bar.size.x = 106.0 * clamp(tt / total, 0.0, 1.0)
	var col := UIKit.WHITE
	if tt <= 10.0:
		col = UIKit.RED if int(_t * 8.0) % 2 == 0 else Color("fca790")
		time_bar.color = UIKit.RED
	elif tt <= 20.0:
		col = UIKit.GOLD
		time_bar.color = Color("f79617")
	else:
		time_bar.color = Color("f9c22b")
	time_label.add_theme_color_override("font_color", col)
	var sec := int(ceil(tt))
	if sec != _last_sec:
		if tt <= 10.0 and _last_sec != -1 and sec < _last_sec:
			time_label.scale = Vector2(1.45, 1.45)
			var tw := create_tween()
			tw.tween_property(time_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_last_sec = sec


func bump_time() -> void:
	time_label.scale = Vector2(1.6, 1.6)
	time_label.add_theme_color_override("font_color", UIKit.ECHO)
	var tw := create_tween()
	tw.tween_property(time_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func show_boss(boss_name_text: String) -> void:
	boss_box.visible = true
	boss_name.text = boss_name_text
	boss_box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(boss_box, "modulate:a", 1.0, 0.3)


func hide_boss() -> void:
	boss_box.visible = false


func update_boss(hp: int, max_hp: int) -> void:
	var k := clampf(float(hp) / float(max(1, max_hp)), 0.0, 1.0)
	boss_fill.size.x = 298.0 * k


func _process(delta: float) -> void:
	_t += delta
	if stage == null:
		return
	# health ghost bar trails behind real value
	var target := hp_fill.size.x
	hp_ghost.size.x = move_toward(hp_ghost.size.x, target, 60.0 * delta) if hp_ghost.size.x > target else target
	if boss_box.visible:
		var bt := boss_fill.size.x
		boss_ghost.size.x = move_toward(boss_ghost.size.x, bt, 120.0 * delta) if boss_ghost.size.x > bt else bt
	# gold ticks up
	var g := float(stage.run.gold)
	gold_shown = g if abs(g - gold_shown) < 1.0 else lerp(gold_shown, g, 0.25)
	gold_label.text = "%dG" % int(round(gold_shown))
	if Engine.get_process_frames() % 6 == 0:
		mini.queue_redraw()
	_layout_toasts(delta)
	_update_arrow()
	var k := float(stage.run.hp) / float(stage.run.max_hp)
	if k < 0.3:
		hp_fill.color = Color("e83b3b") if int(_t * 6.0) % 2 == 0 else Color("fca790")


func _update_arrow() -> void:
	var tgt = stage.objective_target()
	if tgt == null:
		arrow.visible = false
		arrow_label.visible = false
		return
	var sp: Vector2 = stage.world_to_screen(tgt)
	var margin := Rect2(24, 64, 592, 262)
	if margin.has_point(sp):
		arrow.visible = false
		arrow_label.visible = false
		return
	var c := Vector2(320, 190)
	var d := (sp - c)
	var k: float = min(abs(margin.size.x * 0.5 / max(0.001, abs(d.x))), abs(margin.size.y * 0.5 / max(0.001, abs(d.y))))
	var p := c + d * k
	arrow.visible = true
	arrow.position = p - Vector2(4.5, 4) + d.normalized() * (sin(_t * 8.0) * 2.0)
	arrow.rotation = d.angle() + PI * 0.5
	arrow_label.visible = true
	var dist: float = stage.hero.global_position.distance_to(tgt) / 16.0
	# a "level up first" goal still shows where to head later, but greyed out
	var later: bool = bool(stage.ev.current_goal().get("grind", false))
	arrow.modulate = Color(0.7, 0.7, 0.8, 0.6) if later else Color.WHITE
	arrow_label.modulate = arrow.modulate
	arrow_label.text = ("%dm (나중에)" % int(dist)) if later else ("%dm" % int(dist))
	arrow_label.position = p - d.normalized() * 14.0 - Vector2(10, 5)


func hint(text: String, dur := 5.0) -> void:
	hint_label.text = text
	hint_panel.visible = true
	hint_panel.size.x = max(200, text.length() * 10 + 30)
	hint_panel.position.x = 320 - hint_panel.size.x * 0.5
	hint_label.size.x = hint_panel.size.x - 16
	hint_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(hint_panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(dur)
	tw.tween_property(hint_panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): hint_panel.visible = false)


func toast(text: String, icon_name := "", color := UIKit.WHITE, kind := "panel") -> void:
	var p := UIKit.panel(kind, Rect2(-260, 96, 200, 20))
	var x := 7
	if icon_name != "":
		var ic := UIKit.icon(icon_name, Vector2(5, 3), 0.9 if icon_name.length() > 6 else 1.0)
		p.add_child(ic)
		x = 22
	var l := UIKit.label(text, "small", color)
	l.position = Vector2(x, 4)
	p.add_child(l)
	add_child(p)
	await get_tree().process_frame
	if not is_instance_valid(p):
		return
	p.size.x = x + l.get_minimum_size().x + 8
	toasts.push_front(p)
	var tw := p.create_tween()
	tw.tween_property(p, "position:x", 4.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		toasts.erase(p)
		p.queue_free())
	while toasts.size() > 4:
		var old: NinePatchRect = toasts.pop_back()
		if is_instance_valid(old):
			old.queue_free()


func _layout_toasts(delta: float) -> void:
	# toasts stack downward from y=96; slide smoothly into their slot
	var y := 96.0
	for tp in toasts:
		if not is_instance_valid(tp):
			continue
		tp.position.y = lerp(tp.position.y, y, 1.0 - exp(-16.0 * delta))
		y += tp.size.y + 2.0


func banner(text: String, color := UIKit.WHITE, dur := 1.2, sub := "", px := 45) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full(holder)
	add_child(holder)
	var l := UIKit.big_label(text, px, color, 8)
	l.size = Vector2(640, 60)
	l.position = Vector2(0, 130)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.pivot_offset = Vector2(320, 30)
	holder.add_child(l)
	if sub != "":
		var s := UIKit.label(sub, "bold", UIKit.PALE, 4)
		s.size = Vector2(640, 16)
		s.position = Vector2(0, 188)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(s)
	l.scale = Vector2(2.2, 0.2)
	var tw := holder.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(holder, "modulate:a", 0.0, 0.25)
	tw.tween_callback(holder.queue_free)


var rw_panel: NinePatchRect
var rw_fill: ColorRect


func rewind_progress(k: float) -> void:
	if rw_panel == null:
		rw_panel = UIKit.panel("panel_echo", Rect2(250, 150, 140, 30))
		add_child(rw_panel)
		var l := UIKit.label("R 유지: 되감기", "small", UIKit.WHITE)
		l.position = Vector2(8, 3)
		l.size = Vector2(124, 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rw_panel.add_child(l)
		var bg := UIKit.rect(Color("2e222f"), Rect2(8, 18, 124, 5))
		rw_panel.add_child(bg)
		rw_fill = UIKit.rect(UIKit.ECHO, Rect2(9, 19, 0, 3))
		rw_panel.add_child(rw_fill)
	rw_panel.visible = k > 0.0
	rw_fill.size.x = 122.0 * clampf(k, 0.0, 1.0)


func letterbox(on: bool, t := 0.25) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(bar_top, "position:y", 0.0 if on else -40.0, t)
	tw.tween_property(bar_bot, "position:y", 320.0 if on else 360.0, t)


func set_hud_visible(on: bool, t := 0.2) -> void:
	for c in get_children():
		if c != bar_top and c != bar_bot and c is CanvasItem:
			var tw := (c as CanvasItem).create_tween()
			tw.tween_property(c, "modulate:a", 1.0 if on else 0.0, t)
