extends Control
## Overworld stage select. Nodes sit on the illustrated map; the hero token
## hops between them. Shows best time, rank, star and loop count per stage.

var nodes: Array = []
var sel := 0
var token: Sprite2D
var info: NinePatchRect
var info_title: Label
var info_sub: Label
var info_stats: Label
var info_desc: Label
var t := 0.0
var moving := false
var path_layer: Control
var intro_busy := false


func _ready() -> void:
	UIKit.full(self)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/worldmap_bg.png")
	bg.size = Game.VIEW
	add_child(bg)
	path_layer = Control.new()
	UIKit.full(path_layer)
	path_layer.draw.connect(_draw_paths)
	add_child(path_layer)
	var ids: Array = DB.stage_ids()
	var pos: Dictionary = DB.campaign.get("map_pos", {})
	for i in ids.size():
		var sid: String = ids[i]
		var p: Array = pos.get(sid, [100 + i * 60, 200])
		nodes.append({"id": sid, "pos": Vector2(p[0], p[1]), "idx": i + 1})
	var hdr := UIKit.panel("panel", Rect2(4, 4, 220, 22))
	add_child(hdr)
	var hl := UIKit.label("월드맵 — 크로노베일 대륙", "bold", UIKit.GOLD)
	hl.position = Vector2(8, 4)
	hdr.add_child(hl)
	var total := UIKit.label(_totals(), "small", UIKit.PALE, 3)
	total.position = Vector2(232, 8)
	add_child(total)
	token = Sprite2D.new()
	token.texture = load("res://assets/sprites/chars/hero.png")
	token.hframes = 3
	token.vframes = 4
	token.frame = 1
	token.offset = Vector2(0, -13)
	add_child(token)
	info = UIKit.panel("panel", Rect2(4, 276, 632, 80))
	add_child(info)
	info_title = UIKit.label("", "bold", UIKit.GOLD)
	info_title.position = Vector2(10, 6)
	info.add_child(info_title)
	info_sub = UIKit.label("", "small", UIKit.PALE)
	info_sub.position = Vector2(10, 22)
	info.add_child(info_sub)
	info_desc = UIKit.label("", "small", UIKit.WHITE)
	info_desc.position = Vector2(10, 38)
	info_desc.size = Vector2(420, 36)
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(info_desc)
	info_stats = UIKit.label("", "small", UIKit.WHITE)
	info_stats.position = Vector2(440, 8)
	info_stats.size = Vector2(186, 64)
	info.add_child(info_stats)
	var from := str(Game.params.get("from", Game.save.get("last_stage", "s1")))
	sel = max(0, ids.find(from))
	if Game.params.get("cleared", false):
		var nxt := sel + 1
		if nxt < nodes.size() and Game.is_unlocked(nxt + 1):
			token.position = nodes[sel].pos
			_update_info()
			intro_busy = true
			await get_tree().create_timer(0.5).timeout
			Audio.sfx("unlock", 0.0)
			await _move_to(nxt)
			intro_busy = false
	token.position = nodes[sel].pos
	_update_info()
	Audio.play_music("worldmap", 0.6)
	if not Game.params.get("cleared", false) and Game.save.cleared.size() == 0 and int(Game.save.total_loops) == 0:
		_hint_first()


func _hint_first() -> void:
	var h := UIKit.panel("panel_echo", Rect2(200, 214, 300, 26))
	add_child(h)
	var l := UIKit.label("Z / 클릭: 모험 시작 · ←→: 스테이지 선택", "small", UIKit.WHITE)
	l.position = Vector2(10, 7)
	l.size = Vector2(280, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(l)


func _totals() -> String:
	var stars := 0
	var s_ranks := 0
	for sid in DB.stage_ids():
		var m: Dictionary = Game.save.stages.get(sid, {})
		if m.get("star", false):
			stars += 1
		if str(m.get("rank", "")) == "S":
			s_ranks += 1
	return "클리어 %d/%d  ★ %d  S랭크 %d  총 루프 %d" % [Game.save.cleared.size(), DB.stage_ids().size(), stars, s_ranks, int(Game.save.total_loops)]


func _draw_paths() -> void:
	for i in range(1, nodes.size()):
		var a: Vector2 = nodes[i - 1].pos
		var b: Vector2 = nodes[i].pos
		var unlocked := Game.is_unlocked(i + 1)
		var n := int(a.distance_to(b) / 6.0)
		for k in n:
			if k % 2 == 1:
				continue
			var p := a.lerp(b, float(k) / n)
			path_layer.draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color("2e222f"))
			path_layer.draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(2, 2)) if false else Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("fbff86") if unlocked else Color("7f708a"))
	for nd in nodes:
		var p: Vector2 = nd.pos
		var idx: int = nd.idx
		var cleared: bool = Game.save.cleared.has(nd.id)
		var unlocked: bool = Game.is_unlocked(idx)
		var r := 7.0
		var col := Color("f9c22b") if cleared else (Color("e83b3b") if unlocked else Color("625565"))
		if nd.id == nodes[sel].id:
			r = 8.0 + sin(t * 6.0)
		path_layer.draw_circle(p, r + 2, Color("2e222f"))
		path_layer.draw_circle(p, r, col)
		path_layer.draw_circle(p + Vector2(-2, -2), r * 0.35, Color(1, 1, 1, 0.6))
		var m: Dictionary = Game.save.stages.get(nd.id, {})
		if m.get("star", false):
			path_layer.draw_texture(load("res://assets/ui/icon_star.png"), p + Vector2(6, -16))
		var f := Game.font("bold")
		var s := str(idx) if unlocked else "?"
		path_layer.draw_string_outline(f, p + Vector2(-4, 5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color("2e222f"))
		path_layer.draw_string(f, p + Vector2(-4, 5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _update_info() -> void:
	var nd: Dictionary = nodes[sel]
	var sd := DB.stage(nd.id)
	var m: Dictionary = Game.save.stages.get(nd.id, {})
	var unlocked := Game.is_unlocked(nd.idx)
	if not unlocked:
		info_title.text = "STAGE %d  ???" % nd.idx
		info_sub.text = "이전 스테이지를 클리어하면 열린다"
		info_desc.text = ""
		info_stats.text = ""
		return
	info_title.text = "STAGE %d  %s" % [nd.idx, sd.get("name", "")]
	info_sub.text = "%s · 제한 %d초 · 권장 Lv%d" % [sd.get("subtitle", ""), int(sd.get("time", 60)), int(sd.get("rec_level", 5))]
	info_desc.text = str(sd.get("blurb", ""))
	var best := float(m.get("best", -1.0))
	var kn: int = m.get("known", {}).size()
	var kt: int = sd.get("knowledge", {}).size()
	var rank := str(m.get("rank", ""))
	if rank == "":
		rank = "-"
	# 여유 모드 records are listed next to (never instead of) the normal ones
	var ar := str(m.get("assist_rank", ""))
	if ar != "":
		rank += "  (여유 %s)" % ar
	var best_txt := ("%.1f초 남김" % best) if best >= 0 else "-"
	if best < 0 and float(m.get("assist_best", -1.0)) >= 0:
		best_txt = "여유 %.1f초" % float(m.assist_best)
	info_stats.text = "최고 기록  %s\n랭크  %s   별 %s\n루프  %d회\n메아리 지식  %d/%d" % [
		best_txt, rank, "★" if m.get("star", false) else "☆", int(m.get("loops", 0)), kn, kt]


func _move_to(i: int) -> void:
	if i < 0 or i >= nodes.size() or i == sel:
		return
	moving = true
	var from: Vector2 = nodes[sel].pos
	var to: Vector2 = nodes[i].pos
	var d := to - from
	if abs(d.x) > abs(d.y):
		token.frame = 3 * (1 if d.x < 0 else 2) + 1
	else:
		token.frame = 3 * (3 if d.y < 0 else 0) + 1
	var tw := create_tween()
	tw.tween_property(token, "position", to, 0.28).set_trans(Tween.TRANS_SINE)
	var tw2 := create_tween()
	tw2.tween_property(token, "offset:y", -19.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw2.tween_property(token, "offset:y", -13.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Audio.sfx("step", -4.0, 1.4)
	await tw.finished
	sel = i
	token.frame = 1
	_update_info()
	moving = false


func _process(delta: float) -> void:
	t += delta
	path_layer.queue_redraw()
	if moving or intro_busy or Game.main.busy:
		return
	var nxt := -1
	if Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("move_down"):
		nxt = sel + 1
	elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_up"):
		nxt = sel - 1
	if nxt >= 0 and nxt < nodes.size():
		if Game.is_unlocked(nodes[nxt].idx):
			_move_to(nxt)
		else:
			Audio.sfx("buzz", -4.0)
	var enter := Input.is_action_just_pressed("confirm")
	if Input.is_action_just_pressed("click"):
		# click a node to walk there, click the current node (or the info panel) to enter
		var hit := _node_at(get_local_mouse_position())
		if hit >= 0 and hit != sel:
			if Game.is_unlocked(nodes[hit].idx):
				_move_to(hit)
			else:
				Audio.sfx("buzz", -4.0)
			return
		if hit == sel or info.get_rect().has_point(get_local_mouse_position()):
			enter = true
	if enter and Game.is_unlocked(nodes[sel].idx):
		Audio.sfx("stage_select", 0.0)
		Game.goto("stage", {"id": nodes[sel].id})
	elif Game.back_pressed():
		Audio.sfx("menu_back", -4.0)
		Game.goto("title", {})


func _node_at(p: Vector2) -> int:
	var best := -1
	var best_d := 14.0 * 14.0
	for i in nodes.size():
		var d: float = p.distance_squared_to(nodes[i].pos)
		if d < best_d:
			best_d = d
			best = i
	return best
