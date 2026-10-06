class_name Credits
extends RefCounted
## Credits + license notices. The same text is shown in-game (title → 크레딧·라이선스)
## and written next to the exe as THIRD_PARTY_NOTICES.txt (--scenario=licenses).

const CREDITS := [
	"데드라인 히어로 (Deadline Hero)",
	"",
	"기획·프로그래밍·레벨 디자인·음악/효과음 합성: Kiro",
	"원화: Codex CLI image_gen 생성 후 픽셀 가공",
	"음성: Fish Audio TTS (라이브러리 목소리 + 후처리)",
	"폰트: Galmuri — Lee Minseo (quiple), SIL Open Font License 1.1",
	"팔레트: Resurrect 64 — Kerrie Lake",
	"엔진: Godot Engine (MIT License)",
]


static func short_text() -> String:
	## what the in-game screen shows: credits + the Godot notice required by its MIT license
	var out := "\n".join(CREDITS) + "\n\n"
	out += "This game uses Godot Engine, available under the following license:\n\n"
	out += Engine.get_license_text()
	out += "\n\nGodot 내장 서드파티 라이브러리 목록과 Galmuri 라이선스 전문은\n게임 폴더의 THIRD_PARTY_NOTICES.txt에 있습니다."
	return out


static func full_notices() -> String:
	var out := "\n".join(CREDITS) + "\n"
	out += "\n==================================================================\n"
	out += "Galmuri fonts (assets/fonts)\n"
	out += "==================================================================\n"
	out += FileAccess.get_file_as_string("res://assets/fonts/LICENSE.txt")
	out += "\n==================================================================\n"
	out += "This game uses Godot Engine, available under the following license:\n"
	out += "==================================================================\n"
	out += Engine.get_license_text()
	out += "\n==================================================================\n"
	out += "Third-party components bundled with Godot Engine\n"
	out += "==================================================================\n"
	for comp in Engine.get_copyright_info():
		out += "\n- %s\n" % comp.get("name", "")
		for part in comp.get("parts", []):
			for c in part.get("copyright", []):
				out += "    © %s\n" % c
			out += "    License: %s\n" % part.get("license", "")
	var lic: Dictionary = Engine.get_license_info()
	for name in lic:
		out += "\n------------------------------------------------------------------\n%s\n------------------------------------------------------------------\n" % name
		out += str(lic[name]) + "\n"
	return out


static func open(parent: Node) -> void:
	## scrollable text panel; ↑↓ / wheel scroll, Z / X / click closes
	var root := Control.new()
	UIKit.full(root)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(root)
	root.add_child(UIKit.rect(Color(0.1, 0.07, 0.12, 0.75), Rect2(Vector2.ZERO, Game.VIEW)))
	var p := UIKit.panel("panel", Rect2(90, 24, 460, 312))
	root.add_child(p)
	var tl := UIKit.label("크레딧 · 라이선스", "bold", UIKit.GOLD)
	tl.position = Vector2(12, 8)
	p.add_child(tl)
	var hint := UIKit.label("↑↓ 스크롤 · Z/X 닫기", "tiny", UIKit.PALE)
	hint.position = Vector2(330, 10)
	p.add_child(hint)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2(12, 28)
	clip.size = Vector2(436, 274)
	p.add_child(clip)
	var body := UIKit.label(short_text(), "small", UIKit.WHITE, 0, false)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size = Vector2(430, 10)
	clip.add_child(body)
	await parent.get_tree().process_frame
	var max_scroll: float = maxf(0.0, body.get_minimum_size().y - clip.size.y)
	var y := 0.0
	var t := 0.0
	while true:
		await parent.get_tree().process_frame
		var dt := parent.get_process_delta_time()
		t += dt
		var v := 0.0
		if Input.is_action_pressed("move_down"):
			v += 160.0 * dt
		if Input.is_action_pressed("move_up"):
			v -= 160.0 * dt
		if Input.is_action_just_pressed("wheel_down"):
			v += 36.0
		if Input.is_action_just_pressed("wheel_up"):
			v -= 36.0
		y = clampf(y + v, 0.0, max_scroll)
		body.position.y = -round(y)
		if t > 0.2 and (Game.ok_pressed() or Game.back_pressed()):
			break
		if Game.dbg.bot and t > 1.0:
			break
	Audio.sfx("menu_back", -4.0)
	root.queue_free()
