extends Control
## Ending: illustration, epilogue dialogue, staff roll with run statistics.

var t := 0.0
var roll: VBoxContainer
var rolling := false
var done := false


func _ready() -> void:
	UIKit.full(self)
	var bg := UIKit.rect(Color("2e222f"), Rect2(0, 0, 640, 360))
	add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/ending_bg.png")
	art.size = Game.VIEW
	art.modulate.a = 0.0
	add_child(art)
	Audio.play_music("ending", 1.0)
	var tw := create_tween()
	tw.tween_property(art, "modulate:a", 1.0, 2.0)
	await tw.finished
	var dlg := DialogBox.new()
	add_child(dlg)
	var ev := StageEvents.new(null)
	var lines := [
		{"voice": "end_zero"},
		{"voice": "end_chocho"},
		{"voice": "end_hero"},
		{"voice": "end_narr"},
	]
	var out: Array = []
	for l in lines:
		out.append(ev.make_line(l))
	await dlg.play(out)
	Game.save.ending_seen = true
	Game.save_game()
	_staff_roll()


func _staff_roll() -> void:
	var shade := UIKit.rect(Color(0.18, 0.13, 0.18, 0.0), Rect2(0, 0, 640, 360))
	add_child(shade)
	var tw := create_tween()
	tw.tween_property(shade, "color:a", 0.72, 1.0)
	roll = VBoxContainer.new()
	roll.position = Vector2(120, 370)
	roll.size = Vector2(400, 10)
	roll.add_theme_constant_override("separation", 6)
	add_child(roll)
	var stars := 0
	var ranks := {}
	for sid in DB.stage_ids():
		var m: Dictionary = Game.save.stages.get(sid, {})
		if m.get("star", false):
			stars += 1
		ranks[sid] = str(m.get("rank", "-"))
	var items := [
		["big", "데드라인 히어로", UIKit.GOLD],
		["main", "THE END", UIKit.WHITE],
		["gap"],
		["bold", "— 모험 기록 —", UIKit.ECHO],
		["main", "총 루프  %d회" % int(Game.save.total_loops), UIKit.WHITE],
		["main", "쓰러진 횟수  %d회" % int(Game.save.total_deaths), UIKit.WHITE],
		["main", "별 조각  %d / %d" % [stars, DB.stage_ids().size()], UIKit.WHITE],
		["gap"],
		["bold", "— 제작 —", UIKit.ECHO],
		["main", "기획 · 프로그래밍 · 레벨 디자인", UIKit.PALE],
		["main", "Kiro (Claude Opus 5.5)", UIKit.WHITE],
		["gap"],
		["main", "일러스트 · 스프라이트 원화", UIKit.PALE],
		["main", "Codex CLI image_gen → 팔레트 가공", UIKit.WHITE],
		["gap"],
		["main", "음성", UIKit.PALE],
		["main", "Fish Audio TTS", UIKit.WHITE],
		["gap"],
		["main", "음악 · 효과음", UIKit.PALE],
		["main", "Python 칩튠 신시사이저 (자체 제작)", UIKit.WHITE],
		["gap"],
		["main", "폰트", UIKit.PALE],
		["main", "Galmuri by Lee Minseo (OFL)", UIKit.WHITE],
		["main", "팔레트: Resurrect 64 by Kerrie Lake", UIKit.WHITE],
		["gap"],
		["main", "엔진", UIKit.PALE],
		["main", "Godot Engine 4.7", UIKit.WHITE],
		["gap"], ["gap"],
		["bold", "플레이해 주셔서 감사합니다!", UIKit.GOLD],
	]
	for it in items:
		if it[0] == "gap":
			var g := Control.new()
			g.custom_minimum_size = Vector2(10, 14)
			roll.add_child(g)
			continue
		var l: Label
		if it[0] == "big":
			l = UIKit.big_label(it[1], 30, it[2], 6)
		else:
			l = UIKit.label(it[1], it[0], it[2], 3)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(400, 0)
		roll.add_child(l)
	rolling = true


func _process(delta: float) -> void:
	t += delta
	if rolling and roll:
		var spd := 22.0 * (3.0 if Input.is_action_pressed("confirm") or Input.is_action_pressed("click") else 1.0)
		roll.position.y -= spd * delta
		if roll.position.y + roll.size.y < 120 and not done:
			done = true
			var l := UIKit.label("[Z] 타이틀로", "small", UIKit.WHITE, 3)
			l.position = Vector2(270, 330)
			add_child(l)
	if done and Game.ok_pressed():
		Game.goto("title", {})
