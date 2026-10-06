extends Node
## Global state: save data, settings, input map, fonts, screen flow and debug hooks.

const SAVE_PATH := "user://deadline_hero_save.json"
const SAVE_VERSION := 2
const TILE := 16
const VIEW := Vector2(640, 360)
const BG := Color(0.18, 0.13, 0.18)

var save: Dictionary = {}
var fonts: Dictionary = {}
var ui_theme: Theme
var main: Node
var params: Dictionary = {}
var session_time := 0.0

# debug / automated test hooks (pass after "--" on the command line)
var dbg := {"stage": "", "shots": [], "shotdir": "", "quit_at": -1.0, "bot": false, "loop": 0, "fast": false, "screen": "", "fresh": false, "quit_on_clear": false, "scenario": "", "out": ""}
var save_path := SAVE_PATH
var harness: DebugHarness = null

const FONT_FILES := {"tiny": "Galmuri7", "small": "Galmuri9", "main": "Galmuri11", "bold": "Galmuri11-Bold", "big": "Galmuri14"}
const FONT_SIZES := {"tiny": 8, "small": 10, "main": 12, "bold": 12, "big": 15}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	if dbg.scenario == "stage4-tests":
		dbg.stage = "s4"
		dbg.fresh = true
		dbg.fast = true
		dbg.bot = true  # Use the existing automatic dialogue confirmation.
	if dbg.bot or dbg.fresh or dbg.scenario == "tests":
		save_path = "user://bot_save.json"  # automated tests never touch the player's save
	_setup_inputs()
	_setup_fonts()
	load_game()
	if dbg.fresh:
		reset_progress()
	apply_settings()
	# scenario / screenshot / test code lives in scripts/debug and is only
	# instantiated when a debug argument was passed
	if dbg.scenario != "" or not dbg.shots.is_empty() or dbg.quit_at > 0.0:
		harness = DebugHarness.new()
		harness.name = "DebugHarness"
		add_child(harness)


func _process(delta: float) -> void:
	session_time += delta
	_mouse_idle += delta
	if _mouse_idle > 3.0 and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


## Screenshot hook at a key beat (only does something in --scenario=moments/prologue).
func moment(tag: String, delay := 0.0) -> void:
	if harness:
		harness.moment(tag, delay)


## Per-frame hook for scenario scripts that drive a stage (ui showcase, key tests).
func stage_tick(stage: Node) -> void:
	if harness:
		harness.stage_tick(stage)

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var k := kv[0]
		var v := kv[1] if kv.size() > 1 else "1"
		match k:
			"stage": dbg.stage = v
			"screen": dbg.screen = v
			"shots":
				for s in v.split(","):
					dbg.shots.append(float(s))
			"shotdir": dbg.shotdir = v
			"quit-at": dbg.quit_at = float(v)
			"bot": dbg.bot = true
			"loop": dbg.loop = int(v)
			"fast": dbg.fast = true
			"fresh": dbg.fresh = true
			"quit-on-clear": dbg.quit_on_clear = true
			"scenario": dbg.scenario = v
			"out": dbg.out = v


# ------------------------------------------------------------------ input
func _setup_inputs() -> void:
	_bind("move_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("move_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("confirm", [KEY_Z, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A], [])
	_bind("dash", [KEY_X, KEY_SHIFT], [JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER], [])
	_bind("cancel", [KEY_X, KEY_ESCAPE, KEY_BACKSPACE], [JOY_BUTTON_B], [])
	_bind("journal", [KEY_C, KEY_TAB], [JOY_BUTTON_Y], [])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_bind("rewind", [KEY_R], [JOY_BUTTON_BACK], [])
	_bind("fullscreen", [KEY_F11], [], [])
	_bind("minimap", [KEY_M], [], [])
	_bind_mouse("click", MOUSE_BUTTON_LEFT)
	_bind_mouse("rclick", MOUSE_BUTTON_RIGHT)
	_bind_mouse("wheel_up", MOUSE_BUTTON_WHEEL_UP)
	_bind_mouse("wheel_down", MOUSE_BUTTON_WHEEL_DOWN)


func _bind_mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	var m := InputEventMouseButton.new()
	m.button_index = button
	InputMap.action_add_event(action, m)


## "OK" from keyboard/pad or a left click (used by dialogs and result cards).
func ok_pressed() -> bool:
	return Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("click")


func back_pressed() -> bool:
	return Input.is_action_just_pressed("cancel") or Input.is_action_just_pressed("rclick")


const TEXT_SPEEDS := [["느림", 28.0], ["보통", 50.0], ["빠름", 90.0], ["즉시", 5000.0]]


func text_cps() -> float:
	return float(TEXT_SPEEDS[clampi(int(save.settings.get("text_speed", 1)), 0, TEXT_SPEEDS.size() - 1)][1])


func _bind(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.35)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	for ax in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = ax[0]
		m.axis_value = ax[1]
		InputMap.action_add_event(action, m)


var _mouse_idle := 0.0


func _input(event: InputEvent) -> void:
	# the OS cursor hides itself while playing with keys and comes back on mouse use
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_mouse_idle = 0.0
		if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey or event is InputEventJoypadButton:
		_mouse_idle = 99.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		save.settings.fullscreen = not save.settings.fullscreen
		apply_settings()
		save_game()


# ------------------------------------------------------------------ fonts / theme
func _setup_fonts() -> void:
	for key in FONT_FILES:
		var f: FontFile = load("res://assets/fonts/%s.ttf" % FONT_FILES[key])
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		fonts[key] = f
	ui_theme = Theme.new()
	ui_theme.default_font = fonts.main
	ui_theme.default_font_size = 12
	get_tree().root.theme = ui_theme


func font(key: String) -> Font:
	return fonts.get(key, fonts.main)


func font_size(key: String) -> int:
	return FONT_SIZES.get(key, 12)


# ------------------------------------------------------------------ save
func default_save() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": {"music": 0.75, "sfx": 0.9, "voice": 1.0, "voice_on": true, "fullscreen": false, "shake": true,
			"text_speed": 1, "minimap": 1, "calm_fx": false, "assist": false},
		"unlocked": 1,
		"cleared": {},
		"stages": {},
		"total_loops": 0,
		"total_deaths": 0,
		"seen_prologue": false,
		"ending_seen": false,
		"play_time": 0.0,
		"last_stage": "s1",
	}


func load_game() -> void:
	save = default_save()
	if FileAccess.file_exists(save_path):
		var txt := FileAccess.get_file_as_string(save_path)
		var d = JSON.parse_string(txt)
		if d is Dictionary:
			save = migrate_save(d)


## Brings any older (or partial / hand-edited) save up to SAVE_VERSION.
## Pure function so the test runner can feed it old layouts.
func migrate_save(d: Dictionary) -> Dictionary:
	var out := default_save()
	for k in d:
		out[k] = d[k]
	for key in ["settings", "cleared", "stages"]:
		if out[key] is not Dictionary:
			out[key] = default_save()[key]
	var defs: Dictionary = default_save().settings
	for k in defs:
		if not out.settings.has(k):
			out.settings[k] = defs[k]
	var ver := int(d.get("version", 1))
	if ver < 2:
		# v2: the separate voice on/off switch became "voice volume 0% = off"
		if not bool(out.settings.get("voice_on", true)):
			out.settings.voice = 0.0
		out.settings.voice_on = float(out.settings.voice) > 0.001
	# JSON has no ints: counters come back as floats
	out.unlocked = int(out.unlocked)
	out.total_loops = int(out.total_loops)
	out.total_deaths = int(out.total_deaths)
	out.settings.text_speed = int(out.settings.text_speed)
	out.settings.minimap = int(out.settings.minimap)
	for sid in out.stages:
		if out.stages[sid] is not Dictionary:
			out.stages[sid] = {}
	out.version = SAVE_VERSION
	return out


func save_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
		f.close()


func has_progress() -> bool:
	return save.seen_prologue or save.cleared.size() > 0


func reset_progress() -> void:
	var s: Dictionary = save.settings.duplicate()
	save = default_save()
	save.settings = s
	save_game()


func apply_settings() -> void:
	var st: Dictionary = save.settings
	if st.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if is_instance_valid(Audio) and Audio.is_node_ready():
		Audio.apply_volumes(st)


func stage_mem(id: String) -> Dictionary:
	if not save.stages.has(id):
		save.stages[id] = {}
	var m: Dictionary = save.stages[id]
	var defaults := {"loops": 0, "known": {}, "shortcuts": {}, "met": {}, "chests": {}, "explored": {},
		"best": -1.0, "rank": "", "star": false, "record": [], "deaths": [], "clears": 0, "boss_seen": false,
		"attempts": 0}
	for k in defaults:
		if not m.has(k):
			m[k] = defaults[k]
	return m


func star_count() -> int:
	var n := 0
	for sid in save.stages:
		if save.stages[sid].get("star", false):
			n += 1
	return n


func is_unlocked(index: int) -> bool:
	return index <= int(save.unlocked)


# ------------------------------------------------------------------ flow
func goto(screen: String, p: Dictionary = {}) -> void:
	params = p
	if main:
		main.change_screen(screen)


func settings() -> Dictionary:
	return save.settings
