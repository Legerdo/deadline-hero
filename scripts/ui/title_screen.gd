extends Control
## Title: key art, logo, menu, prologue.

var logo: Label
var sub: Label
var press: Label
var menu_open := false
var menu_sel := 0
var t := 0.0
var sparkles: Array = []
var sand: Node2D


func _ready() -> void:
	UIKit.full(self)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/title_bg.png")
	bg.size = Game.VIEW
	add_child(bg)
	var shade := UIKit.rect(Color(0.18, 0.13, 0.18, 0.25), Rect2(0, 0, 640, 360))
	add_child(shade)
	sand = Node2D.new()
	sand.draw.connect(_draw_sand)
	add_child(sand)
	for i in 60:
		sparkles.append({"p": Vector2(randf() * 640, randf() * 360), "v": randf_range(8, 24), "c": [Color("fbff86"), Color("f9c22b"), Color("ffffff")][i % 3]})
	logo = UIKit.big_label("데드라인 히어로", 42, UIKit.GOLD, 10)
	logo.size = Vector2(640, 60)
	logo.position = Vector2(0, 26)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.pivot_offset = Vector2(320, 30)
	add_child(logo)
	sub = UIKit.label("DEADLINE HERO · 60초 안에 세계를 구하라", "bold", UIKit.WHITE, 4)
	sub.size = Vector2(640, 16)
	sub.position = Vector2(0, 84)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	press = UIKit.label("Z / Enter / 클릭으로 시작", "bold", UIKit.WHITE, 4)
	press.size = Vector2(640, 16)
	press.position = Vector2(0, 318)
	press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(press)
	var ver := UIKit.label("v1.1  ·  Godot 4.7", "tiny", UIKit.PALE, 3)
	ver.position = Vector2(6, 346)
	add_child(ver)
	logo.scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(logo, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Audio.play_music("title", 0.8)
	if Game.dbg.scenario == "prologue":
		menu_open = true
		await get_tree().create_timer(0.5).timeout
		Game.moment("title")
		await _prologue()
		return
	await get_tree().create_timer(0.35).timeout
	Audio.voice("title_call")


func _draw_sand() -> void:
	for s in sparkles:
		var a := 0.5 + 0.5 * sin(t * 3.0 + s.p.x)
		var c: Color = s.c
		c.a = a
		sand.draw_rect(Rect2(s.p.round(), Vector2(1, 1) * (2 if a > 0.8 else 1)), c)


func _process(delta: float) -> void:
	t += delta
	for s in sparkles:
		s.p.y += s.v * delta
		s.p.x += sin(t + s.p.y * 0.05) * 6.0 * delta
		if s.p.y > 362:
			s.p = Vector2(randf() * 640, -2)
	sand.queue_redraw()
	logo.position.y = 26 + sin(t * 1.6) * 2.0
	press.visible = not menu_open and int(t * 2.0) % 2 == 0
	if not menu_open and t > 0.4 and Game.ok_pressed():
		Audio.sfx("menu_ok", 0.0)
		_open_menu()


func _open_menu() -> void:
	menu_open = true
	var entries: Array = []
	var cont := Game.has_progress()
	if cont:
		entries.append({"text": "이어하기", "desc": "월드맵에서 계속"})
	entries.append({"text": "새로 시작" if cont else "모험 시작", "desc": "프롤로그부터"})
	entries.append({"text": "조작법", "desc": "이동·대시·대화"})
	entries.append({"text": "설정", "desc": "볼륨·글자 속도·여유 모드"})
	entries.append({"text": "크레딧", "desc": "만든 사람·라이선스"})
	entries.append({"text": "종료"})
	var i: int = await MenuList.open(self, "", entries, Rect2(250, 190, 140, 0), true, menu_sel)
	menu_sel = maxi(i, 0)
	var pick := "" if i < 0 else str(entries[i].text)
	match pick:
		"이어하기":
			Game.goto("worldmap", {})
			return
		"새로 시작", "모험 시작":
			if cont:
				var c: int = await MenuList.open(self, "기록을 지우고 새로 시작할까?", [{"text": "아니오"}, {"text": "예, 지운다"}], Rect2(210, 200, 220, 0))
				if c != 1:
					menu_open = false
					return
				Game.reset_progress()
			await _prologue()
			return
		"조작법":
			await _controls()
		"설정":
			await SettingsMenu.open(self)
		"크레딧":
			await Credits.open(self)
		"종료":
			get_tree().quit()
	menu_open = false
	# reopen right away instead of dropping back to "press start"
	if i >= 0 and pick != "종료":
		_open_menu()


func _controls() -> void:
	var root := Control.new()
	UIKit.full(root)
	add_child(root)
	var p := UIKit.panel("panel", Rect2(140, 40, 360, 286))
	root.add_child(p)
	var lines := [
		["이동", "방향키 / WASD / 패드"],
		["공격", "적에게 몸통 박치기"],
		["대시", "X 또는 Shift — 대시 박치기는 반격 없음"],
		["반격형 적", "빛날 때(빈틈)만 정면으로 들이받기"],
		["대화·조사", "부딪히기 또는 Z"],
		["메아리 수첩", "C / Tab"],
		["미니맵", "M (끄기·보통·크게)"],
		["일시정지", "Esc / P"],
		["루프 되감기", "R 길게 누르기 (지식·지름길은 남는다)"],
		["마우스", "메뉴 선택·대화 넘기기·월드맵 이동"],
		["전체 화면", "F11"],
	]
	var tl := UIKit.label("조작법", "bold", UIKit.GOLD)
	tl.position = Vector2(14, 10)
	p.add_child(tl)
	for i in lines.size():
		var a := UIKit.label(lines[i][0], "main", UIKit.GOLD)
		a.position = Vector2(18, 34 + i * 22)
		p.add_child(a)
		var b := UIKit.label(lines[i][1], "small", UIKit.WHITE)
		b.position = Vector2(118, 36 + i * 22)
		p.add_child(b)
	await get_tree().create_timer(0.2).timeout
	while true:
		await get_tree().process_frame
		if Game.ok_pressed() or Game.back_pressed():
			break
	Audio.sfx("menu_back", -4.0)
	root.queue_free()


func _prologue() -> void:
	Audio.stop_music(0.5)
	var root := Control.new()
	UIKit.full(root)
	add_child(root)
	var bg := UIKit.rect(Color("2e222f"), Rect2(0, 0, 640, 360))
	root.add_child(bg)
	bg.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(bg, "modulate:a", 1.0, 0.5)
	await tw.finished
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/concept_bg.png")
	art.size = Game.VIEW
	art.modulate = Color(1, 1, 1, 0)
	root.add_child(art)
	var tw2 := create_tween()
	tw2.tween_property(art, "modulate", Color(0.8, 0.75, 0.9, 1), 1.0)
	Audio.play_music("prologue", 0.5)
	var dlg := DialogBox.new()
	root.add_child(dlg)
	var ev := StageEvents.new(null)
	var lines := [
		{"voice": "pro_1"},
		{"voice": "pro_2"},
		{"voice": "zero_intro"},
		{"voice": "chocho_intro"},
		{"voice": "hero_intro"},
		{"voice": "chocho_intro2"},
	]
	var out: Array = []
	for l in lines:
		out.append(ev.make_line(l))
	Game.moment("prologue", 2.0)
	await dlg.play(out)
	Game.save.seen_prologue = true
	Game.save_game()
	Game.goto("stage", {"id": "s1"})
