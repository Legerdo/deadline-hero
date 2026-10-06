class_name MenuList
extends Control
## Generic cursor menu. Entries: {text, value?, icon?, disabled?, desc?, adjust?}.
## usage: var i = await MenuList.open(parent, title, entries, rect)
## `adjust` is a Callable(dir: int, wrap: bool) -> String that changes a setting
## in place (←/→ or click) and returns the new value text; such rows never close
## the menu. Mouse: hover selects, left click picks, right click / wheel = back / scroll.

signal chosen(index: int)

var entries: Array = []
var title := ""
var sel := 0
var rows: Array = []
var vals: Array = []
var cursor: TextureRect
var desc_label: Label
var box: NinePatchRect
var can_cancel := true
var _t := 0.0
var _hold := 0.0
var _hold_x := 0.0
var _mouse := Vector2(-1, -1)
var row_h := 16


static func open(parent: Node, t: String, e: Array, r: Rect2, cancel := true, start := 0) -> int:
	var m := MenuList.new()
	m.title = t
	m.entries = e
	m.can_cancel = cancel
	m.sel = clampi(start, 0, max(0, e.size() - 1))
	parent.add_child(m)
	m.build(r)
	var res: int = await m.chosen
	m.queue_free()
	return res


func build(r: Rect2) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIKit.full(self)
	var extra := _extra()
	var has_desc := false
	for e in entries:
		if e.has("desc"):
			has_desc = true
	var hh := 10 + extra + entries.size() * row_h + (26 if has_desc else 0)
	box = UIKit.panel("panel", Rect2(r.position, Vector2(r.size.x, max(r.size.y, hh))))
	add_child(box)
	if title != "":
		var tl := UIKit.label(title, "bold", UIKit.GOLD)
		tl.position = Vector2(10, 5)
		box.add_child(tl)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var y := 6 + extra + i * row_h
		var x := 20
		if e.has("icon") and str(e.icon) != "":
			var ic := UIKit.icon(str(e.icon), Vector2(18, y))
			box.add_child(ic)
			x = 38
		var l := UIKit.label(str(e.get("text", "")), "main", UIKit.DIM if e.get("disabled", false) else UIKit.WHITE)
		l.position = Vector2(x, y)
		box.add_child(l)
		var v: Label = null
		if e.has("value"):
			v = UIKit.label(str(e.value), "main", UIKit.GOLD if not e.get("disabled", false) else UIKit.DIM)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			v.size = Vector2(90, 14)
			v.position = Vector2(box.size.x - 100, y)
			box.add_child(v)
		rows.append(l)
		vals.append(v)
	if has_desc:
		desc_label = UIKit.label("", "small", UIKit.PALE)
		desc_label.position = Vector2(12, box.size.y - 22)
		desc_label.size = Vector2(box.size.x - 24, 14)
		box.add_child(desc_label)
	cursor = UIKit.icon("cursor", Vector2(8, 0))
	box.add_child(cursor)
	box.scale = Vector2(1, 0.2)
	box.pivot_offset = box.size * 0.5
	var tw := create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# a mouse that is merely resting on the menu must not steal the cursor
	_mouse = get_viewport().get_mouse_position()
	_update()


func _extra() -> int:
	return 16 if title != "" else 0


func _update() -> void:
	if entries.is_empty():
		return
	cursor.position = Vector2(8, 9 + _extra() + sel * row_h)
	for i in rows.size():
		var e: Dictionary = entries[i]
		var c := UIKit.WHITE if i == sel else UIKit.PALE
		if e.get("disabled", false):
			c = UIKit.DIM
		rows[i].add_theme_color_override("font_color", c)
		if vals[i] != null:
			var txt := str(e.get("value", ""))
			# ◀ ▶ hint on the adjustable row under the cursor
			vals[i].text = ("< %s >" % txt) if (i == sel and e.has("adjust")) else txt
	if desc_label:
		desc_label.text = str(entries[sel].get("desc", ""))


func _row_at(local: Vector2) -> int:
	if local.x < 2 or local.x > box.size.x - 2:
		return -1
	var y := local.y - (6 + _extra())
	if y < 0:
		return -1
	var i := int(y / row_h)
	return i if i < entries.size() else -1


func _adjust(dir: int, wrap: bool) -> void:
	var e: Dictionary = entries[sel]
	if e.get("disabled", false):
		Audio.sfx("buzz", -4.0)
		return
	e.value = str((e.adjust as Callable).call(dir, wrap))
	Audio.sfx("menu_move", -4.0, 1.15 if dir > 0 else 0.9)
	_update()


func _pick() -> void:
	if entries.size() > 0 and entries[sel].get("disabled", false):
		Audio.sfx("buzz", -4.0)
		box.position.x += 3
		var tw := create_tween()
		tw.tween_property(box, "position:x", box.position.x - 3, 0.1)
		return
	if entries.size() > 0 and entries[sel].has("adjust"):
		_adjust(1, true)
		return
	Audio.sfx("menu_ok", -3.0)
	set_process(false)
	chosen.emit(sel)


func _cancel() -> void:
	Audio.sfx("menu_back", -4.0)
	set_process(false)
	chosen.emit(-1)


func _process(delta: float) -> void:
	_t += delta
	if cursor:
		cursor.position.x = 7 + (1 if int(_t * 4.0) % 2 == 0 else 0)
	if _t < 0.08:
		return
	if Game.dbg.bot and _t > (1.4 if Game.dbg.scenario == "ui" else 0.4):
		set_process(false)
		chosen.emit(-1 if can_cancel else _first_pickable())
		return
	var v := 0
	if Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("wheel_down"):
		v = 1
	elif Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("wheel_up"):
		v = -1
	if Input.is_action_pressed("move_down") or Input.is_action_pressed("move_up"):
		_hold += delta
		if _hold > 0.35:
			_hold = 0.27
			v = 1 if Input.is_action_pressed("move_down") else -1
	else:
		_hold = 0.0
	if v != 0 and entries.size() > 0:
		sel = (sel + v + entries.size()) % entries.size()
		Audio.sfx("menu_move", -6.0)
		_update()
	# ←/→ on adjustable rows (with key repeat)
	if entries.size() > 0 and entries[sel].has("adjust"):
		var h := 0
		if Input.is_action_just_pressed("move_right"):
			h = 1
		elif Input.is_action_just_pressed("move_left"):
			h = -1
		if Input.is_action_pressed("move_right") or Input.is_action_pressed("move_left"):
			_hold_x += delta
			if _hold_x > 0.4:
				_hold_x = 0.3
				h = 1 if Input.is_action_pressed("move_right") else -1
		else:
			_hold_x = 0.0
		if h != 0:
			_adjust(h, false)
	# mouse: hover follows actual movement only
	var local := box.get_local_mouse_position()
	var mp := get_viewport().get_mouse_position()
	if mp.distance_squared_to(_mouse) > 0.5:
		_mouse = mp
		var r := _row_at(local)
		if r >= 0 and r != sel:
			sel = r
			Audio.sfx("menu_move", -8.0)
			_update()
	if Input.is_action_just_pressed("click"):
		var r := _row_at(local)
		if r >= 0:
			sel = r
			_update()
			if entries[sel].has("adjust") and vals[sel] != null and local.x >= box.size.x - 100:
				# click the left / right half of the value to step down / up
				_adjust(-1 if local.x < box.size.x - 55 else 1, false)
			else:
				_pick()
			return
		if can_cancel and not Rect2(Vector2.ZERO, box.size).has_point(local):
			_cancel()
			return
	if Input.is_action_just_pressed("confirm"):
		_pick()
	elif can_cancel and (Input.is_action_just_pressed("cancel") or Input.is_action_just_pressed("rclick")):
		_cancel()


func _first_pickable() -> int:
	## bots in non-cancelable menus take the first plain (non-setting) entry
	for i in entries.size():
		if not entries[i].has("adjust") and not entries[i].get("disabled", false):
			return i
	return 0
