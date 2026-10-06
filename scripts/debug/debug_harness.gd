class_name DebugHarness
extends Node
## Automated-run helpers, kept out of the game code. Created by Game only when a
## debug argument is passed after "--":
##   --shots=t1,t2   screenshots at session times      --quit-at=T  quit after T s
##   --scenario=ui        open every stage menu once and screenshot it
##   --scenario=moments   screenshot key beats (loop banner, boss intro, result…)
##   --scenario=prologue  auto-start the prologue from the title and screenshot it
##   --scenario=rewindkey verify that holding R restarts the loop
##   --scenario=selftest  check every referenced asset resolves (exported builds)
##   --scenario=tests     run TestRunner (data validation, formulas, save migration)
##   --scenario=stage4-tests  run the real stage's plate / boss-room regressions
##   --scenario=licenses [--out=PATH]  write THIRD_PARTY_NOTICES.txt
##   --scenario=credits   screenshot the credits / license panel
##   --scenario=mouse     (windowed) synthetic hover / wheel / click checks on a MenuList

const UI_STEPS := [[2.0, "pause"], [5.0, "journal"], [8.0, "shop"], [11.0, "timeshop"], [14.0, "settings"]]

var dbg: Dictionary
var _ui_step := 0
var _stage4_tests_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	dbg = Game.dbg
	match str(dbg.scenario):
		"selftest":
			_selftest.call_deferred()
		"tests":
			_run_tests.call_deferred()
		"licenses":
			_write_licenses.call_deferred()
		"credits":
			_credits_shot.call_deferred()
		"mouse":
			_mouse_test.call_deferred()


func _process(_delta: float) -> void:
	var t: float = Game.session_time
	if dbg.scenario == "stage4-tests" and t > 20.0:
		print("[test] FAIL stage4 runtime: scenario timed out")
		get_tree().quit(1)
	if dbg.shots.size() > 0 and t >= float(dbg.shots[0]):
		var st: float = dbg.shots.pop_front()
		shot("shot_%05.1f" % st)
	if dbg.quit_at > 0 and t >= dbg.quit_at:
		get_tree().quit()


# ------------------------------------------------------------------ screenshots
func shot(tag: String) -> void:
	var dir: String = dbg.shotdir if dbg.shotdir != "" else ProjectSettings.globalize_path("res://tools/_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return  # headless runs have no framebuffer
	img.save_png(dir.path_join(tag + ".png"))
	print("[shot] ", dir.path_join(tag + ".png"))


func moment(tag: String, delay := 0.0) -> void:
	if not str(dbg.scenario) in ["moments", "prologue"]:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay, true, false, true).timeout
	shot("m_" + tag)


# ------------------------------------------------------------------ stage scenarios
func stage_tick(s: Node) -> void:
	match str(dbg.scenario):
		"stage4-tests":
			if s.state == "play" and not s.busy and not _stage4_tests_started:
				_stage4_tests_started = true
				_run_stage4_tests(s)
		"ui":
			if s.state == "play" and not s.busy:
				_ui_showcase(s)
		"rewindkey":
			if s.state == "play" and s.loop_idx == 1 and s.play_time > 4.0:
				Input.action_press("rewind")
			elif s.loop_idx == 2 and Input.is_action_pressed("rewind"):
				Input.action_release("rewind")
				print("[dbg] rewind by key OK -> loop 2 started")


func _run_stage4_tests(s: Node) -> void:
	var tests = load("res://scripts/debug/stage4_tests.gd").new()
	var failures: int = await tests.run_stage(s)
	get_tree().quit(1 if failures > 0 else 0)


func _ui_showcase(s: Node) -> void:
	## opens each menu once; the screenshot is taken while it is on screen
	if _ui_step >= UI_STEPS.size() or s.play_time < UI_STEPS[_ui_step][0]:
		return
	var what: String = UI_STEPS[_ui_step][1]
	_ui_step += 1
	get_tree().create_timer(0.8, true, false, true).timeout.connect(func(): shot("ui_" + what))
	match what:
		"pause":
			s.ev.open_pause()
		"journal":
			s.ev.open_journal()
		"shop":
			s.busy = true
			s.pause_world(true)
			await s.ev.open_shop(str(s.sd.get("shops", {}).keys()[0]))
			s.pause_world(false)
			s.busy = false
		"timeshop":
			s.busy = true
			await s.ev.open_timeshop()
			s.busy = false
		"settings":
			s.busy = true
			s.pause_world(true)
			await SettingsMenu.open(s.ui, true, s.apply_visual_settings)
			s.pause_world(false)
			s.busy = false


# ------------------------------------------------------------------ checks
func _selftest() -> void:
	## Verifies that every referenced asset resolves (works inside exported builds too).
	var missing: Array = []
	var voices := 0
	for id in DB.voice_lines:
		if str(id).begins_with("_"):
			continue
		if ResourceLoader.exists("res://assets/audio/voice/%s.ogg" % id):
			voices += 1
		else:
			missing.append("voice:" + str(id))
	var music := 0
	for m in ["title", "worldmap", "prologue", "ending", "field", "river", "cave", "manor", "temple", "volcano", "tower", "boss", "final2", "victory"]:
		if ResourceLoader.exists("res://assets/audio/music/%s.ogg" % m):
			music += 1
		else:
			missing.append("music:" + m)
	var sfx := 0
	for sname in ["hit", "crit", "dash", "levelup", "coin", "bell_toll", "rewind", "boss_appear", "time_add", "heartbeat"]:
		if ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % sname):
			sfx += 1
		else:
			missing.append("sfx:" + sname)
	var stages := 0
	for sid in DB.stage_ids():
		var sd := DB.stage(sid)
		if sd.is_empty() or DB.map_lines(str(sd.map)).is_empty():
			missing.append("stage:" + sid)
		else:
			stages += 1
	print("[selftest] voices=%d/%d music=%d sfx=%d stages=%d missing=%s" % [voices, DB.voice_lines.size() - 1, music, sfx, stages, str(missing)])
	get_tree().quit(0 if missing.is_empty() else 1)


func _mouse_test() -> void:
	## --scenario=mouse (windowed): hover + click + wheel on a MenuList and an
	## adjustable row, using synthetic OS-level mouse input.
	await get_tree().create_timer(0.6).timeout
	var val := [5]
	var bump := func(d: int, _w: bool) -> String:
		val[0] += d
		return str(val[0])
	var entries := [{"text": "A"}, {"text": "B"}, {"text": "C"}, {"text": "D", "value": "5", "adjust": bump}]
	var m := MenuList.new()
	m.entries = entries
	Game.main.add_child(m)
	m.build(Rect2(250, 120, 160, 0))
	var got := [-99]
	m.chosen.connect(func(i: int): got[0] = i)
	await get_tree().create_timer(0.3).timeout
	var row := func(i: int, x := 60.0) -> Vector2:
		return m.box.global_position + Vector2(x, 6 + i * m.row_h + 8)
	# hover row 2
	get_viewport().warp_mouse(row.call(2))
	await _frames(4)
	var hover_ok: bool = m.sel == 2
	# wheel up -> row 1
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, row.call(2))
	var seen_wheel := false
	for i in 3:
		await get_tree().process_frame
		seen_wheel = seen_wheel or Input.is_action_just_pressed("wheel_up")
	var wheel_ok: bool = m.sel == 1
	print("[mouse] wheel action seen=%s sel=%d" % [seen_wheel, m.sel])
	# click the right half of the adjustable value -> +1, menu stays open
	var vpos: Vector2 = row.call(3, m.box.size.x - 30.0)
	get_viewport().warp_mouse(vpos)
	await _frames(3)
	_mouse_button(MOUSE_BUTTON_LEFT, vpos)
	await _frames(3)
	var adjust_ok: bool = val[0] == 6 and got[0] == -99
	# click row 0 -> chosen(0)
	get_viewport().warp_mouse(row.call(0))
	await _frames(3)
	_mouse_button(MOUSE_BUTTON_LEFT, row.call(0))
	await _frames(3)
	var click_ok: bool = got[0] == 0
	print("[mouse] hover=%s wheel=%s adjust=%s click=%s" % [hover_ok, wheel_ok, adjust_ok, click_ok])
	get_tree().quit(0 if hover_ok and wheel_ok and adjust_ok and click_ok else 1)


func _mouse_button(button: MouseButton, at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
		if pressed:
			await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _credits_shot() -> void:
	## --scenario=credits : open the credits panel over the title and screenshot it
	await get_tree().create_timer(1.2).timeout
	Credits.open(Game.main)
	await get_tree().create_timer(0.5).timeout
	shot("ui_credits")
	get_tree().quit()


func _write_licenses() -> void:
	## --scenario=licenses --out=PATH : writes THIRD_PARTY_NOTICES.txt for distribution
	# default: next to the running exe. Relative --out paths are taken from there too
	# (res:// is read-only inside an exported build).
	var path := str(dbg.get("out", ""))
	if path == "":
		path = "THIRD_PARTY_NOTICES.txt"
	if path.is_relative_path():
		path = OS.get_executable_path().get_base_dir().path_join(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[licenses] cannot write ", path)
		get_tree().quit(1)
		return
	f.store_string(Credits.full_notices())
	f.close()
	print("[licenses] wrote ", path)
	get_tree().quit(0)


func _run_tests() -> void:
	var failed := TestRunner.new().run()
	get_tree().quit(0 if failed == 0 else 1)
