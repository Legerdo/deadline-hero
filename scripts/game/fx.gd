class_name PixelFX
extends Node2D
## World-space juice: crisp square particles, damage numbers, rings, beams,
## danger telegraphs and afterimages. One instance lives in every stage.

var parts: Array = []


func emit(pos: Vector2, count: int, colors: Array, speed := 80.0, life := 0.5, size := 2.0,
		grav := 0.0, dir := Vector2.ZERO, spread := TAU, drag := 3.0) -> void:
	for i in count:
		var ang := randf() * TAU
		if dir != Vector2.ZERO:
			ang = dir.angle() + randf_range(-spread * 0.5, spread * 0.5)
		var sp := speed * randf_range(0.35, 1.0)
		parts.append({"p": pos, "v": Vector2.RIGHT.rotated(ang) * sp, "l": life * randf_range(0.55, 1.0),
			"m": life, "c": colors[randi() % colors.size()], "s": size, "g": grav, "d": drag})


func _process(delta: float) -> void:
	if parts.is_empty():
		return
	var keep: Array = []
	for p in parts:
		p.v += Vector2(0, p.g) * delta
		p.v *= max(0.0, 1.0 - p.d * delta)
		p.p += p.v * delta
		p.l -= delta
		if p.l > 0:
			keep.append(p)
	parts = keep
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var s: float = p.s if p.l > p.m * 0.4 else max(1.0, p.s - 1.0)
		var c: Color = p.c
		draw_rect(Rect2((p.p - Vector2(s, s) * 0.5).round(), Vector2(s, s)), c)


# ------------------------------------------------------------------ text popups
func popup(pos: Vector2, text: String, color := Color.WHITE, big := false, rise := 18.0, dur := 0.7) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Game.font("big" if big else "bold"))
	l.add_theme_font_size_override("font_size", 15 if big else 12)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("2e222f"))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(80, 20)
	l.position = pos - Vector2(40, 14)
	l.pivot_offset = Vector2(40, 10)
	l.z_index = 50
	add_child(l)
	l.scale = Vector2(1.6, 1.6) if big else Vector2(1.25, 1.25)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y - rise, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)
	return l


# ------------------------------------------------------------------ shapes
class Ring:
	extends Node2D
	var radius := 4.0
	var target := 30.0
	var color := Color.WHITE
	var width := 2.0
	var t := 0.0
	var dur := 0.3

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := t / dur
		var r: float = lerp(radius, target, 1.0 - pow(1.0 - k, 3.0))
		var c := color
		c.a *= 1.0 - k
		draw_arc(Vector2.ZERO, r, 0, TAU, 28, c, width)


class Slash:
	extends Node2D
	## crescent swipe drawn along the hit direction (reads as a sword stroke)
	var dir := Vector2.RIGHT
	var color := Color.WHITE
	var big := false
	var t := 0.0
	var dur := 0.14

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := t / dur
		var r := (13.0 if big else 10.0) + 4.0 * k
		var a0 := dir.angle() - 1.25
		var sweep := 2.5 * clampf(k * 1.8, 0.0, 1.0)
		var c := color
		c.a = 1.0 - k
		var w := (4.0 if big else 3.0) * (1.0 - k * 0.6)
		var ink := Color(0.18, 0.13, 0.18, c.a * 0.9)
		draw_arc(Vector2.ZERO, r, a0, a0 + sweep, 10, ink, w + 2.0)
		draw_arc(Vector2.ZERO, r, a0, a0 + sweep, 10, c, w)
		draw_arc(Vector2.ZERO, r - w * 0.5, a0 + sweep * 0.3, a0 + sweep, 8, Color(1, 1, 1, c.a), 1.0)


func slash(pos: Vector2, dir: Vector2, color := Color.WHITE, big := false) -> void:
	var s := Slash.new()
	s.position = pos
	s.dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	s.color = color
	s.big = big
	s.z_index = 45
	add_child(s)


func ring(pos: Vector2, target := 30.0, color := Color.WHITE, dur := 0.3, width := 2.0) -> void:
	var r := Ring.new()
	r.position = pos
	r.target = target
	r.color = color
	r.dur = dur
	r.width = width
	r.z_index = 40
	add_child(r)


class Beam:
	extends Node2D
	var color := Color(1, 1, 0.7)
	var t := 0.0
	var dur := 0.6
	var w := 14.0
	var h := 120.0

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := t / dur
		var ww: float = w * (1.0 - k)
		var c := color
		c.a = 0.85 * (1.0 - k)
		draw_rect(Rect2(-ww * 0.5, -h, ww, h), c)
		draw_rect(Rect2(-ww * 0.25, -h, ww * 0.5, h), Color(1, 1, 1, c.a))


func beam(pos: Vector2, color := Color(1, 1, 0.6), dur := 0.6) -> void:
	var b := Beam.new()
	b.position = pos
	b.color = color
	b.dur = dur
	b.z_index = 30
	add_child(b)


class Telegraph:
	extends Node2D
	var shape := "circle"
	var radius := 24.0
	var to := Vector2.ZERO
	var width := 16.0
	var angle := 0.0
	var arc := 0.8
	var dur := 0.7
	var t := 0.0
	var cb: Callable
	var color := Color(0.93, 0.23, 0.21)

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			if cb.is_valid():
				cb.call()
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := t / dur
		var blink := 0.35 + 0.25 * (1.0 if int(t * 14.0) % 2 == 0 else 0.0)
		var c := color
		c.a = blink * 0.55
		var edge := color
		edge.a = 0.9
		match shape:
			"circle":
				draw_circle(Vector2.ZERO, radius, c)
				draw_arc(Vector2.ZERO, radius, 0, TAU, 32, edge, 1.0)
				draw_circle(Vector2.ZERO, radius * k, Color(edge.r, edge.g, edge.b, 0.35))
			"line":
				var d := to.normalized()
				var n := Vector2(-d.y, d.x) * width * 0.5
				var pts := PackedVector2Array([n, to + n, to - n, -n])
				draw_colored_polygon(pts, c)
				draw_polyline(PackedVector2Array([n, to + n, to - n, -n, n]), edge, 1.0)
				draw_colored_polygon(PackedVector2Array([n, to * k + n, to * k - n, -n]), Color(edge.r, edge.g, edge.b, 0.3))
			"cone":
				var pts2 := PackedVector2Array([Vector2.ZERO])
				for i in 11:
					var a := angle - arc * 0.5 + arc * i / 10.0
					pts2.append(Vector2.RIGHT.rotated(a) * radius)
				draw_colored_polygon(pts2, c)
				pts2.append(Vector2.ZERO)
				draw_polyline(pts2, edge, 1.0)


func telegraph_circle(pos: Vector2, radius: float, dur: float, cb: Callable) -> Node2D:
	var t := Telegraph.new()
	t.position = pos
	t.radius = radius
	t.dur = dur
	t.cb = cb
	t.z_index = -1
	add_child(t)
	return t


func telegraph_line(from: Vector2, to: Vector2, width: float, dur: float, cb: Callable) -> Node2D:
	var t := Telegraph.new()
	t.shape = "line"
	t.position = from
	t.to = to - from
	t.width = width
	t.dur = dur
	t.cb = cb
	t.z_index = -1
	add_child(t)
	return t


func telegraph_cone(pos: Vector2, angle: float, arc: float, radius: float, dur: float, cb: Callable) -> Node2D:
	var t := Telegraph.new()
	t.shape = "cone"
	t.position = pos
	t.angle = angle
	t.arc = arc
	t.radius = radius
	t.dur = dur
	t.cb = cb
	t.z_index = -1
	add_child(t)
	return t


func afterimage(src: Sprite2D, color := Color(0.55, 0.95, 1.0, 0.6), dur := 0.22) -> void:
	if not is_instance_valid(src):
		return
	var s := Sprite2D.new()
	s.texture = src.texture
	s.hframes = src.hframes
	s.vframes = src.vframes
	s.frame = src.frame
	s.flip_h = src.flip_h
	s.offset = src.offset
	s.centered = src.centered
	s.global_position = src.global_position
	s.scale = src.global_scale
	s.modulate = color
	s.z_index = -1
	add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, dur)
	tw.tween_callback(s.queue_free)
