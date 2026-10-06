class_name DialogBox
extends Control
## Portrait dialogue with typewriter text, optional Fish Audio voice and
## per-speaker text blips. Timer is paused by the caller while it is open.

signal advanced

var panel: NinePatchRect
var pframe: NinePatchRect
var portrait: TextureRect
var name_tab: NinePatchRect
var name_label: Label
var text_label: Label
var arrow: TextureRect
var typing := false
var cps := 50.0
var vis := 0.0
var total := 0
var _t := 0.0
var _age := 0.0
var active := false
var skip_all := false
var voiced := false
var blip_pitch := 1.0
var _last_blip := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIKit.full(self)
	visible = false
	panel = UIKit.panel("panel", Rect2(12, 270, 616, 84))
	add_child(panel)
	pframe = UIKit.panel("panel_gold", Rect2(6, 7, 70, 70))
	panel.add_child(pframe)
	portrait = TextureRect.new()
	portrait.position = Vector2(9, 10)
	portrait.size = Vector2(64, 64)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(portrait)
	name_tab = UIKit.panel("panel_gold", Rect2(18, 253, 120, 19))
	add_child(name_tab)
	name_label = UIKit.label("", "bold", UIKit.GOLD)
	name_label.position = Vector2(8, 3)
	name_tab.add_child(name_label)
	text_label = UIKit.label("", "main", UIKit.WHITE)
	text_label.position = Vector2(86, 9)
	text_label.size = Vector2(518, 66)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_constant_override("line_spacing", 3)
	panel.add_child(text_label)
	arrow = UIKit.icon("cursor", Vector2(596, 66))
	arrow.rotation = PI * 0.5
	panel.add_child(arrow)


func play(lines: Array) -> void:
	if lines.is_empty():
		return
	visible = true
	active = true
	skip_all = false
	cps = Game.text_cps()
	panel.position.y = 300
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "position:y", 270.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.1)
	for line in lines:
		if skip_all:
			break
		await _show(line)
	Audio.stop_voice()
	active = false
	var tw2 := create_tween()
	tw2.tween_property(self, "modulate:a", 0.0, 0.08)
	await tw2.finished
	visible = false


func _show(line: Dictionary) -> void:
	var nm := str(line.get("name", ""))
	name_tab.visible = nm != ""
	name_label.text = nm
	name_tab.size.x = 20 + nm.length() * 12
	var por := str(line.get("portrait", ""))
	var path := "res://assets/portraits/%s.png" % por
	if por != "" and ResourceLoader.exists(path):
		portrait.texture = load(path)
		portrait.visible = true
		pframe.visible = true
		text_label.position.x = 86
		text_label.size.x = 518
		portrait.scale = Vector2(1.08, 0.94)
		var tw := create_tween()
		tw.tween_property(portrait, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK)
	else:
		portrait.visible = false
		pframe.visible = false
		text_label.position.x = 14
		text_label.size.x = 590
	blip_pitch = float(line.get("pitch", 1.0))
	text_label.text = str(line.get("text", ""))
	total = text_label.get_total_character_count()
	vis = 0.0
	_last_blip = 0
	text_label.visible_characters = 0
	typing = true
	_age = 0.0
	voiced = false
	var vid := str(line.get("voice", ""))
	if vid != "":
		voiced = Audio.voice(vid) > 0.0
	await advanced


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	_age += delta
	if typing:
		vis += delta * cps
		var n := int(vis)
		text_label.visible_characters = n
		if not voiced and n - _last_blip >= 2:
			_last_blip = n
			Audio.sfx("blip", -12.0, blip_pitch, 0.06)
		if n >= total:
			typing = false
	arrow.visible = not typing and int(_t * 3.0) % 2 == 0
	if _age < 0.12:
		return
	if Game.dbg.bot and _age > 0.6:
		typing = false
		advanced.emit()
		return
	if Game.ok_pressed():
		if typing:
			vis = total
			text_label.visible_characters = -1
			typing = false
		else:
			Audio.sfx("menu_move", -10.0, 1.3)
			advanced.emit()
	elif Game.back_pressed():
		if typing:
			vis = total
			text_label.visible_characters = -1
			typing = false
		else:
			advanced.emit()
