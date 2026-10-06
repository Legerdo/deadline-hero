class_name SettingsMenu
extends RefCounted
## Shared settings screen (title + pause). Every row changes in place:
## ←/→ step, Z / click cycles. Values are saved when the menu closes.

const MINIMAP_MODES := ["끄기", "보통", "크게"]

var st: Dictionary
var on_change := Callable()


static func open(parent: Node, in_stage := false, changed := Callable()) -> void:
	var sm := SettingsMenu.new()
	sm.st = Game.settings()
	sm.on_change = changed
	await sm._run(parent, in_stage)


func _run(parent: Node, in_stage: bool) -> void:
	var entries := [
		{"text": "음악 볼륨", "value": _pct(st.music), "desc": "←→ 10%씩 · Z 순환", "adjust": _adj_vol.bind("music")},
		{"text": "효과음 볼륨", "value": _pct(st.sfx), "desc": "←→ 10%씩 · Z 순환", "adjust": _adj_vol.bind("sfx")},
		{"text": "음성", "value": _voice_text(), "desc": "0%로 내리면 음성 대신 글자음", "adjust": _adj_voice},
		{"text": "글자 속도", "value": Game.TEXT_SPEEDS[int(st.text_speed)][0], "desc": "대화창 글자가 나오는 속도", "adjust": _adj_text},
		{"text": "미니맵", "value": MINIMAP_MODES[int(st.minimap)], "desc": "플레이 중 M 키로도 바꿀 수 있다", "adjust": _adj_minimap},
		{"text": "화면 흔들림", "value": _onoff(st.shake), "desc": "타격·폭발 시 카메라 흔들림", "adjust": _adj_toggle.bind("shake")},
		{"text": "번쩍임 줄이기", "value": _onoff(st.calm_fx), "desc": "화면 섬광·붉은 테두리를 약하게", "adjust": _adj_toggle.bind("calm_fx")},
		{"text": "여유 모드", "value": _onoff(st.assist), "adjust": _adj_toggle.bind("assist"),
			"desc": "제한 시간 +50% · 다음 루프부터 적용" if in_stage else "제한 시간 +50% · 랭크 기록은 따로 남는다"},
		{"text": "전체 화면", "value": _onoff(st.fullscreen), "desc": "F11", "adjust": _adj_toggle.bind("fullscreen")},
		{"text": "돌아가기"},
	]
	await MenuList.open(parent, "설정", entries, Rect2(190, 44, 260, 0), true)
	Game.apply_settings()
	Game.save_game()
	_changed()


func _changed() -> void:
	if on_change.is_valid():
		on_change.call()


# ------------------------------------------------------------------ row handlers (dir, wrap, ...)
func _adj_vol(d: int, wrap: bool, key: String) -> String:
	var steps := _step(int(round(float(st[key]) * 10.0)), d, 11, wrap)
	st[key] = steps / 10.0
	Game.apply_settings()
	if key == "sfx":
		Audio.sfx("coin", -4.0)
	return _pct(st[key])


func _adj_voice(d: int, wrap: bool) -> String:
	_adj_vol(d, wrap, "voice")
	st.voice_on = float(st.voice) > 0.001
	Game.apply_settings()
	return _voice_text()


func _adj_text(d: int, wrap: bool) -> String:
	st.text_speed = _step(int(st.text_speed), d, Game.TEXT_SPEEDS.size(), wrap)
	return Game.TEXT_SPEEDS[int(st.text_speed)][0]


func _adj_minimap(d: int, wrap: bool) -> String:
	st.minimap = _step(int(st.minimap), d, MINIMAP_MODES.size(), wrap)
	_changed()
	return MINIMAP_MODES[int(st.minimap)]


func _adj_toggle(_d: int, _wrap: bool, key: String) -> String:
	st[key] = not bool(st[key])
	if key == "fullscreen":
		Game.apply_settings()
	_changed()
	return _onoff(st[key])


# ------------------------------------------------------------------ helpers
func _voice_text() -> String:
	return "꺼짐" if float(st.voice) <= 0.001 else _pct(st.voice)


static func _pct(v) -> String:
	return "%d%%" % int(round(float(v) * 100.0))


static func _onoff(v) -> String:
	return "켜짐" if bool(v) else "꺼짐"


static func _step(cur: int, d: int, n: int, wrap: bool) -> int:
	if wrap:
		return (cur + d + n) % n
	return clampi(cur + d, 0, n - 1)
