class_name Stage
extends Node2D
## One ~60 second adventure. Builds the map from data, runs the countdown,
## bump combat, the echo (loop memory) systems and every cinematic beat.

const T := 16
const RANK_S := 0.40
const RANK_A := 0.25
const RANK_B := 0.10

var id := "s1"
var sd: Dictionary = {}
var mem: Dictionary = {}
var loop_idx := 1
var state := "intro"
var time_left := 60.0
var time_total := 60.0
var play_time := 0.0
var flags: Dictionary = {}
var run: Dictionary = {}
var busy := false

var map: MapBuilder
var world: Node2D
var fx: PixelFX
var hero: Hero
var cam: Camera2D
var boss: Boss
var enemies: Array = []
var npcs: Dictionary = {}
var props: Array = []
var props_by_id: Dictionary = {}
var touch_props: Array = []
var respawns: Array = []
var bullets: Array = []
var allies: Array = []
var ghost: Node2D
var ghost_line: Line2D
var record: PackedInt32Array = PackedInt32Array()
var prev_record: Array = []
var rec_acc := 0.0
var start_pos := Vector2.ZERO
var respawn_pos := Vector2.ZERO

var ui: CanvasLayer
var hud: HUD
var dialog: DialogBox
var post: CanvasLayer
var vignette: ColorRect
var flash_rect: ColorRect
var rewind_rect: ColorRect
var dark_rect: ColorRect
var dark_layer: CanvasLayer
var tint: CanvasModulate
var ev: StageEvents
var hands_node: Node2D

var shake_amt := 0.0
var shake_t := 0.0
var hitstop_left := 0.0
var hurry := false
var heart_t := 0.0
var cam_target_override: Variant = null
var cam_look := Vector2.ZERO
var lights: Array = []
var explored: Dictionary = {}
var mini_img: Image
var mini_dirty := false
var lava_events: Array = []
var hint_queue: Array = []
var time_stop_warn := 0.0
var hand_hit_cd := 0.0
var countdown_said := {}
var stage_music := "field"
var _mini_full: Image
var vig := 0.0
var boss_known_before := false
var obj_t := 0.0
var bot: StageBot
var rewind_hold := 0.0
var unpause_ms := 0
var camera_zone := Rect2i()
var zone_mask: Node2D
var star_bonus := 0.0
var assist := false


# ================================================================== setup
func _ready() -> void:
	id = str(Game.params.get("id", "s1"))
	sd = DB.stage(id)
	mem = Game.stage_mem(id)
	loop_idx = int(mem.loops) + 1
	mem.attempts = int(mem.attempts) + 1
	Game.save.last_stage = id
	time_total = float(sd.get("time", 60))
	# 별의 가호: every star shard found anywhere adds 2 s to every stage
	star_bonus = 2.0 * float(Game.star_count())
	time_total += star_bonus
	# 여유 모드 (accessibility): +50% time, marked on the result screen.
	# Fixed for the whole loop so toggling it mid-run can't skew the record.
	assist = bool(Game.settings().get("assist", false))
	if assist:
		time_total = round(time_total * 1.5)
	time_left = time_total
	stage_music = str(sd.get("music", "field"))
	prev_record = mem.get("record", [])
	explored = mem.get("explored", {})
	boss_known_before = bool(mem.boss_seen)
	_init_run()
	ev = StageEvents.new(self)
	_build_world()
	_build_ui()
	_spawn_entities()
	_setup_special()
	hud.update_stats(run)
	hud.set_loop(loop_idx)
	hud.set_time(time_left, time_total)
	hud.set_objective(ev.objective_text())
	_snap_camera()
	_intro()


func _init_run() -> void:
	var st: Dictionary = sd.get("start", {})
	run = {
		"lv": 1, "exp": 0, "next": exp_next(1), "hp": 30, "max_hp": 30, "base_atk": 5, "base_def": 2,
		"gold": int(st.get("gold", 0)), "weapon": str(st.get("weapon", "wood_sword")), "armor": str(st.get("armor", "")),
		"items": {}, "buffs": {}, "time_bought": 0, "kills": 0,
	}
	for k in st.get("items", {}):
		run.items[k] = int(st.items[k])


func exp_next(lv: int) -> int:
	return int(12 + 10 * (lv - 1) + 1.5 * (lv - 1) * (lv - 1))


func exp_bonus() -> float:
	## "the hero remembers how to fight": +10% EXP per failed loop (max +50%)
	return 1.0 + min(0.5, 0.1 * float(loop_idx - 1))


func hero_atk() -> int:
	return int(run.base_atk) + int(DB.item(str(run.weapon)).get("atk", 0)) + (4 if run.buffs.has("rage") else 0)


func hero_def() -> int:
	return int(run.base_def) + int(DB.item(str(run.armor)).get("def", 0))


func _build_world() -> void:
	map = MapBuilder.new()
	map.build(self, DB.map_lines(str(sd.map)), str(sd.get("theme", "village")), sd.get("under", {}))
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child(world)
	fx = PixelFX.new()
	fx.name = "FX"
	fx.z_index = 20
	add_child(fx)
	hands_node = ClockHands.new()
	hands_node.z_index = 15
	add_child(hands_node)
	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = map.w * T
	cam.limit_bottom = map.h * T
	add_child(cam)
	cam.make_current()
	tint = CanvasModulate.new()
	tint.color = Color(str(sd.get("tint", "ffffff")))
	add_child(tint)


func _build_ui() -> void:
	if sd.get("dark", false):
		dark_layer = CanvasLayer.new()
		dark_layer.layer = 1
		add_child(dark_layer)
		dark_rect = ColorRect.new()
		UIKit.full(dark_rect)
		dark_rect.material = Shaders.material("darkness")
		dark_layer.add_child(dark_rect)
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	hud = HUD.new()
	ui.add_child(hud)
	hud.setup(self)
	mini_img = map.minimap_image()
	if sd.get("dark", false):
		_apply_fog_to_minimap()
	hud.setup_minimap(mini_img)
	dialog = DialogBox.new()
	ui.add_child(dialog)
	post = CanvasLayer.new()
	post.layer = 20
	add_child(post)
	vignette = ColorRect.new()
	UIKit.full(vignette)
	vignette.material = Shaders.material("vignette")
	post.add_child(vignette)
	flash_rect = UIKit.rect(Color(1, 1, 1, 0), Rect2(Vector2.ZERO, Game.VIEW))
	post.add_child(flash_rect)
	rewind_rect = ColorRect.new()
	UIKit.full(rewind_rect)
	rewind_rect.material = Shaders.material("rewind")
	rewind_rect.visible = false
	post.add_child(rewind_rect)


func _spawn_entities() -> void:
	var mk: Dictionary = sd.get("markers", {})
	for ch in map.markers:
		var spec: Dictionary = mk.get(ch, {})
		var cells: Array = map.markers[ch]
		for i in cells.size():
			var c: Vector2i = cells[i]
			var pos := Vector2(c.x * T + 8, c.y * T + 14)
			if ch == "@":
				start_pos = pos
				continue
			if ch == "B":
				_spawn_boss(pos)
				continue
			if spec.is_empty():
				continue
			if spec.has("if") and not ev.check(spec["if"]):
				continue
			match str(spec.get("type", "")):
				"enemy":
					spawn_enemy(str(spec.kind), pos, spec.get("stats", {}), true)
				"npc":
					_spawn_npc(str(spec.id), pos)
				"prop":
					var d: Dictionary = spec.duplicate(true)
					if cells.size() > 1:
						if d.has("id"):
							d.id = str(d.id) + str(i)
						if d.has("shortcut"):
							d.shortcut = str(d.shortcut) + str(i)
						if d.has("give_list"):
							d.give = d.give_list[i % d.give_list.size()]
					spawn_prop(str(spec.kind), pos, d)
				"point":
					pass
	respawn_pos = start_pos
	hero = Hero.new()
	hero.stage = self
	hero.position = start_pos
	world.add_child(hero)
	if prev_record.size() >= 6:
		_spawn_ghost()


func _spawn_boss(pos: Vector2) -> void:
	var bd: Dictionary = sd.get("boss", {})
	if bd.is_empty():
		return
	boss = Boss.new()
	boss.stage = self
	boss.setup(str(bd.kind), bd.get("stats", {}))
	boss.position = pos
	world.add_child(boss)
	boss.died.connect(_on_boss_died)
	enemies.append(boss)


func spawn_enemy(kind: String, pos: Vector2, overrides: Dictionary = {}, can_respawn := false) -> Enemy:
	var e := Enemy.new()
	e.stage = self
	e.setup(kind, overrides)
	e.position = pos
	if not can_respawn:
		e.respawn = false
	e.spawn_info = {"kind": kind, "pos": pos, "stats": overrides}
	world.add_child(e)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e


func spawn_minion(kind: String, pos: Vector2) -> void:
	var alive_minions := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive and not e.respawn and not e.is_boss:
			alive_minions += 1
	if alive_minions >= 6:
		return
	if map.solid_at(pos):
		pos = boss.global_position if boss else hero.global_position
	var e := spawn_enemy(kind, pos, {"respawn": false, "exp": 2, "gold": 0}, false)
	e.aggro = 400.0
	fx.emit(pos, 8, [e.color, Color.WHITE], 60.0, 0.4, 2.0)


func _spawn_npc(npc_id: String, pos: Vector2) -> void:
	var d: Dictionary = sd.get("npcs", {}).get(npc_id, {})
	if d.is_empty():
		return
	if d.has("if") and not ev.check(d["if"]):
		return
	var n := NPC.new()
	n.stage = self
	n.setup(npc_id, d)
	n.position = pos
	world.add_child(n)
	npcs[npc_id] = n


func spawn_prop(kind: String, pos: Vector2, d: Dictionary) -> Prop:
	var p := Prop.new()
	p.stage = self
	p.setup(kind, d)
	p.position = pos + Vector2(d.get("offset", [0, 0])[0], d.get("offset", [0, 0])[1])
	world.add_child(p)
	props.append(p)
	if p.pid != "":
		props_by_id[p.pid] = p
	if kind in ["pickup", "warp", "plate"]:
		touch_props.append(p)
		p.set_solid(false)
	ev.init_prop(p)
	return p


func _spawn_ghost() -> void:
	ghost = Sprite2D.new()
	var g := ghost as Sprite2D
	g.texture = load("res://assets/sprites/chars/hero.png")
	g.hframes = 3
	g.vframes = 4
	g.frame = 1
	g.offset = Vector2(0, -13)
	g.material = Shaders.material("ghost")
	g.z_index = 1
	world.add_child(g)
	g.position = Vector2(prev_record[0], prev_record[1])
	ghost_line = Line2D.new()
	ghost_line.width = 1.0
	ghost_line.default_color = Color(0.19, 0.88, 0.73, 0.45)
	ghost_line.z_index = -2
	add_child(ghost_line)


func _setup_special() -> void:
	for le in sd.get("lava", []):
		lava_events.append(le.duplicate())
	for h in sd.get("hints", []):
		hint_queue.append(h.duplicate())


# ================================================================== flow
func world_active() -> bool:
	return state == "play" and hitstop_left <= 0.0


func can_act() -> bool:
	return state == "play"


func hero_hidden() -> bool:
	return map.terrain_at(hero.global_position) == "^"


func hero_speed_mul() -> float:
	return 1.0 + (0.15 if run.buffs.has("boots") else 0.0)


func _intro() -> void:
	state = "intro"
	hero.control = false
	var first: bool = int(mem.attempts) <= 1 and loop_idx == 1
	var rewound: bool = Game.params.get("rewound", false)
	if rewound:
		_rewind_in()
	Audio.stop_music(0.3)
	if first:
		hud.letterbox(true, 0.01)
		hud.set_hud_visible(false, 0.01)
		await wait(0.35)
		Audio.sfx("stage_start", 0.0)
		hud.banner("STAGE %d" % int(sd.get("index", 1)), UIKit.GOLD, 1.9, "%s — %s" % [sd.get("name", ""), sd.get("subtitle", "")], 45)
		Audio.voice("%s_start" % id)
		await wait(2.3)
		var intro: Array = sd.get("intro", [])
		if not intro.is_empty():
			await ev.say(intro)
		hud.letterbox(false)
		hud.set_hud_visible(true)
		await wait(0.2)
	else:
		var sub := ""
		if loop_idx > 1:
			sub = "메아리 보정: 경험치 +%d%%" % int(round((exp_bonus() - 1.0) * 100.0))
		hud.banner("LOOP %d" % loop_idx, UIKit.ECHO, 0.7, sub, 45)
		Game.moment("loop_banner", 0.3)
		Game.moment("loop_ghost", 4.0)
		if loop_idx > 1 and rewound:
			ev.chocho_loop_quip()
		await wait(0.85)
		await _offer_inheritance()
	Audio.sfx("go", 0.0)
	hud.banner("GO!", UIKit.WHITE, 0.45, "", 60)
	Audio.voice("go")
	state = "play"
	hero.control = true
	Audio.play_music(stage_music, 0.2)
	if star_bonus > 0.0:
		hud.toast("별의 가호 +%d초 (별 조각 %d개)" % [int(star_bonus), int(star_bonus / 2.0)], "star", UIKit.GOLD)
	if assist:
		hud.toast("여유 모드: 제한 시간 +50%", "clock", UIKit.PALE)
	ev.on_start()


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


# ------------------------------------------------------------------ echo inheritance
func inherit_offer() -> Dictionary:
	## Skip the early grind: start at ~60% of last loop's level, paying 3 s per level.
	var last := int(mem.get("last_lv", 1))
	if loop_idx < 2 or last < 3:
		return {}
	var lv := maxi(2, int(floor(last * 0.6)))
	return {"lv": lv, "cost": float((lv - 1) * 3)}


func _offer_inheritance() -> void:
	var off := inherit_offer()
	if off.is_empty():
		return
	var entries := [
		{"text": "메아리 계승: Lv%d로 시작" % off.lv, "value": "-%d초" % int(off.cost), "icon": "echo",
			"desc": "지난 루프 최고 Lv%d의 몸놀림을 이어받는다" % int(mem.last_lv)},
		{"text": "처음부터 (Lv1)", "value": "±0초", "desc": "시간을 아끼고 직접 키운다"},
	]
	var start := 0 if mem.get("inherit_pref", true) else 1
	Game.moment("inherit", 0.25)
	var i: int = await MenuList.open(ui, "초초: 지난 루프의 힘을 이어받을래냥?", entries, Rect2(190, 118, 260, 0), false, start)
	mem.inherit_pref = i == 0
	if i != 0:
		return
	apply_inheritance(int(off.lv), float(off.cost))


func apply_inheritance(lv: int, cost: float) -> void:
	while int(run.lv) < lv:
		run.lv = int(run.lv) + 1
		run.next = exp_next(int(run.lv))
		run.max_hp = int(run.max_hp) + 9
		run.base_atk = int(run.base_atk) + 2
		run.base_def = int(run.base_def) + 1
	run.hp = run.max_hp
	time_left = max(5.0, time_left - cost)
	if Game.dbg.bot:
		print("[dbg] inherit Lv%d for -%ds" % [lv, int(cost)])
	hud.update_stats(run)
	hud.set_time(time_left, time_total)
	fx.beam(hero.global_position, Color(0.55, 1.0, 0.9), 0.6)
	fx.emit(hero.global_position + Vector2(0, -12), 20, [Color("30e1b9"), Color("8ff8e2"), Color.WHITE], 80.0, 0.7, 2.0, -40.0)
	fx.popup(hero.global_position + Vector2(0, -34), "메아리 계승 Lv%d" % lv, Color("8ff8e2"), true)
	Audio.sfx("learn", 0.0)
	for e in enemies:
		if is_instance_valid(e):
			e.refresh_label()


func _declutter_labels() -> void:
	## Stack level labels of monsters standing close together so "Lv2"+"Lv3" never read as "Lv23".
	var placed: Array = []
	var list: Array = enemies.filter(func(e): return is_instance_valid(e) and e.alive and not e.is_boss and e.lv_label and e.lv_label.visible)
	list.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
	for e in list:
		var lift := 0.0
		var top: Vector2 = e.global_position + Vector2(0, -e.tex_h - 6)
		var moved := true
		while moved and lift < 30.0:
			moved = false
			for p in placed:
				var q: Vector2 = p
				if abs(q.x - top.x) < 22.0 and abs(q.y - (top.y - lift)) < 8.0:
					lift += 8.0
					moved = true
					break
		placed.append(top - Vector2(0, lift))
		e.set_label_lift(lift)


func _update_camera_zone() -> void:
	## Optional per-stage camera zones (e.g. tower floors): the camera never shows
	## a neighbouring zone, so separate floors read as separate places.
	var zones: Array = sd.get("camera_zones", [])
	if zones.is_empty() or hero == null:
		return
	var c := Vector2i(int(hero.global_position.x / T), int(hero.global_position.y / T))
	for z in zones:
		var r := Rect2i(int(z[0]), int(z[1]), int(z[2]) - int(z[0]) + 1, int(z[3]) - int(z[1]) + 1)
		if r.has_point(c) and r != camera_zone:
			camera_zone = r
			if zone_mask == null:
				zone_mask = Node2D.new()
				zone_mask.z_index = 60
				zone_mask.draw.connect(_draw_zone_mask)
				add_child(zone_mask)
			zone_mask.queue_redraw()
			return


func _draw_zone_mask() -> void:
	var r := Rect2(Vector2(camera_zone.position) * T, Vector2(camera_zone.size) * T)
	var big := Rect2(-2000, -2000, map.w * T + 4000, map.h * T + 4000)
	var col := Color(0.12, 0.09, 0.16, 0.94)
	zone_mask.draw_rect(Rect2(big.position, Vector2(big.size.x, r.position.y - big.position.y)), col)
	zone_mask.draw_rect(Rect2(Vector2(big.position.x, r.end.y), Vector2(big.size.x, big.end.y - r.end.y)), col)
	zone_mask.draw_rect(Rect2(Vector2(big.position.x, r.position.y), Vector2(r.position.x - big.position.x, r.size.y)), col)
	zone_mask.draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(big.end.x - r.end.x, r.size.y)), col)


func pause_world(on: bool) -> void:
	get_tree().paused = on
	Audio.set_muffled(on)
	if not on:
		unpause_ms = Time.get_ticks_msec()


# ================================================================== frame
func _physics_process(delta: float) -> void:
	if hitstop_left > 0.0:
		return
	if state == "play":
		_tick_timer(delta)
		_combat()
		_update_ghost()  # Plates must see the echo's position for this frame.
		_touches()
		_update_respawns(delta)
		_update_bullets(delta)
		_record(delta)
		_update_allies(delta)
		_update_hands(delta)
		_lava(delta)
		_hints()
		check_boss_trigger()
		if Game.dbg.bot:
			if bot == null:
				bot = StageBot.new(self)
			bot.tick(delta)
		if hero_hidden():
			map.secret_l.modulate.a = move_toward(map.secret_l.modulate.a, 0.45, delta * 3.0)
		else:
			map.secret_l.modulate.a = move_toward(map.secret_l.modulate.a, 1.0, delta * 3.0)


func _process(delta: float) -> void:
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	if hitstop_left > 0.0:
		hitstop_left -= real_dt
	_update_camera(delta, real_dt)
	_update_post(real_dt)
	if dark_rect:
		_update_darkness()
	hud.set_time(time_left, time_total)
	if boss and boss.alive and boss.engaged:
		hud.update_boss(boss.hp, boss.max_hp)
	if state == "play":
		if Input.is_action_just_pressed("pause"):
			ev.open_pause()
		elif Input.is_action_just_pressed("journal"):
			ev.open_journal()
		elif Input.is_action_just_pressed("confirm"):
			_interact_near()
		elif Input.is_action_just_pressed("minimap"):
			var st: Dictionary = Game.settings()
			st.minimap = (int(st.get("minimap", 1)) + 1) % SettingsMenu.MINIMAP_MODES.size()
			hud.apply_minimap_mode()
			hud.toast("미니맵: " + SettingsMenu.MINIMAP_MODES[st.minimap], "", UIKit.PALE)
			Audio.sfx("menu_move", -6.0)
			Game.save_game()
		# hold R to start the loop over (knowledge, shortcuts and the echo are kept)
		if Input.is_action_pressed("rewind") and not busy:
			rewind_hold += real_dt
			hud.rewind_progress(rewind_hold / 0.6)
			if rewind_hold >= 0.6:
				rewind_hold = 0.0
				hud.rewind_progress(0.0)
				rewind("manual")
		elif rewind_hold > 0.0:
			rewind_hold = 0.0
			hud.rewind_progress(0.0)
	if mini_dirty and Engine.get_process_frames() % 10 == 0:
		mini_dirty = false
		hud.refresh_minimap(mini_img)
	obj_t += delta
	if obj_t > 0.5 and state == "play":
		obj_t = 0.0
		hud.set_objective(ev.objective_text())
	if Engine.get_process_frames() % 6 == 0:
		_declutter_labels()
	_update_camera_zone()
	Game.stage_tick(self)


func _tick_timer(delta: float) -> void:
	play_time += delta
	time_left -= delta
	if time_stop_warn > 0.0:
		time_stop_warn = max(0.0, time_stop_warn - delta)
	if time_left <= 10.0 and not hurry:
		_set_hurry(true)
	elif time_left > 10.5 and hurry:
		_set_hurry(false)
	if hurry:
		heart_t -= delta
		if heart_t <= 0.0:
			heart_t = 1.0 if time_left > 5.0 else 0.5
			Audio.sfx("heartbeat", -2.0)
			Audio.sfx("tick", -6.0, 1.0 if time_left > 5 else 1.2)
			pulse_vignette(0.75)
		var sec := int(ceil(time_left))
		if sec <= 10 and not countdown_said.has(sec):
			countdown_said[sec] = true
			if sec == 10:
				Audio.voice("count_10")
				hud.toast("10초 남았다!", "clock", UIKit.RED, "panel_red")
			elif sec <= 5 and sec >= 1:
				Audio.voice("count_%d" % sec)
	if time_left <= 0.0:
		time_left = 0.0
		_on_time_up()


func _set_hurry(on: bool) -> void:
	hurry = on
	if on:
		Audio.set_music_pitch(1.2, 0.6)
		var tw := create_tween()
		tw.tween_property(tint, "color", Color(str(sd.get("tint", "ffffff"))) * Color(1.0, 0.82, 0.85), 1.0)
		heart_t = 0.0
		shake(3.0, 0.3)
	else:
		Audio.set_music_pitch(1.0, 0.4)
		var tw2 := create_tween()
		tw2.tween_property(tint, "color", Color(str(sd.get("tint", "ffffff"))), 0.6)
		vig = 0.0


func _update_post(dt: float) -> void:
	var floor_v := 0.28 if hurry else 0.0
	vig = move_toward(vig, floor_v, dt * 1.2)
	var k := 0.45 if Game.settings().get("calm_fx", false) else 1.0
	(vignette.material as ShaderMaterial).set_shader_parameter("intensity", vig * k)


func pulse_vignette(v: float) -> void:
	vig = max(vig, v)


# ================================================================== camera & juice
func _snap_camera() -> void:
	cam.position = _cam_goal()
	cam.reset_smoothing()


func _cam_goal() -> Vector2:
	if cam_target_override != null:
		return cam_target_override
	var look: Vector2 = hero.move_vel * 0.18
	cam_look = cam_look.lerp(look, 0.08)
	return hero.global_position + Vector2(0, -10) + cam_look


func _update_camera(delta: float, real_dt: float) -> void:
	if hero == null:
		return
	var goal := _cam_goal()
	var k := 1.0 - exp(-9.0 * delta)
	var p := cam.position.lerp(goal, k) if state != "rewind" else goal
	cam.position = p
	var off := Vector2.ZERO
	if shake_t > 0.0:
		shake_t -= real_dt
		var s: float = shake_amt * clampf(shake_t / 0.2, 0.2, 1.0)
		if Game.settings().get("shake", true):
			off = Vector2(randf_range(-s, s), randf_range(-s, s))
		if shake_t <= 0.0:
			shake_amt = 0.0
	cam.offset = off.round()


func shake(amount: float, dur := 0.2) -> void:
	if amount >= shake_amt or shake_t <= 0.0:
		shake_amt = amount
		shake_t = dur


func hitstop(t: float) -> void:
	hitstop_left = max(hitstop_left, t)


func apply_visual_settings() -> void:
	## called live from the settings menu
	hud.apply_minimap_mode()


func flash_screen(col := Color(1, 1, 1, 0.8), dur := 0.15) -> void:
	if Game.settings().get("calm_fx", false):
		col.a *= 0.3  # 번쩍임 줄이기
	flash_rect.color = col
	var tw := flash_rect.create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, dur)


func world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


# ================================================================== combat
func _damage(a: int, d: int) -> int:
	return max(1, int(round((float(a) - float(d) * 0.5) * randf_range(0.9, 1.1))))


func _combat() -> void:
	var hp_pos := hero.global_position
	for e in enemies:
		if not is_instance_valid(e) or not e.alive or not e.can_clash():
			continue
		var reach: float = 7.0 + e.radius
		if e.is_boss:
			reach = 8.0 + e.radius
		var ep: Vector2 = e.global_position
		if abs(ep.x - hp_pos.x) > reach + 4 or abs(ep.y - hp_pos.y) > reach + 4:
			continue
		if hp_pos.distance_to(ep) < reach:
			_clash(e)
	enemies = enemies.filter(func(x): return is_instance_valid(x))


func _clash(e: Enemy) -> void:
	var dir: Vector2 = e.global_position - hero.global_position
	if dir.length() < 0.5:
		dir = hero.facing
	dir = dir.normalized()
	var dashing := hero.is_dashing()
	e.clash_cd = 0.22 if e.is_boss else 0.28
	if e.is_boss and ev.on_boss_touch(e):
		return
	var contact := hero.global_position + dir * 6.0 + Vector2(0, -6)
	if e.invulnerable:
		fx.popup(e.world_pos_top(), "무효!", UIKit.DIM)
		Audio.sfx("clink", -2.0)
		fx.emit(contact, 5, [Color("c7dcd0"), Color("9babb2")], 60.0, 0.25, 2.0)
		hero.knock = -dir * 150.0
		hero.dash_t = 0.0
		ev.on_invulnerable_hit(e)
		hitstop(0.03)
		return
	var dmg := _damage(hero_atk(), e.def)
	var crit := randf() < (0.15 if dashing else 0.06)
	if dashing:
		dmg = int(dmg * 1.3)
	if crit:
		dmg = int(dmg * 1.8)
	dmg = int(dmg * e.dmg_mul)
	var spiky: bool = not e.is_boss and e.counter and not e.is_open()
	if spiky:
		dmg = int(dmg * 0.5)
	if e.is_boss:
		e.clash_cd = 0.42
	var blocked := false
	if e.is_boss and (e as Boss).blocks(-dir):
		blocked = true
		dmg = 1
	dmg = max(1, dmg)
	var killed := e.take_hit(dmg, dir, crit)
	if blocked:
		fx.popup(e.world_pos_top(), "막힘!", Color("8ff8e2"))
		Audio.sfx("clink", 0.0)
		fx.emit(contact, 8, [Color("8ff8e2"), Color.WHITE], 90.0, 0.25, 2.0)
		hero.knock = -dir * 180.0
		hero.dash_t = 0.0
		shake(2.0, 0.1)
		hitstop(0.04)
		ev.on_blocked(e)
		return
	var col := Color("fbff86") if crit else Color.WHITE
	fx.popup(e.world_pos_top() + Vector2(randf_range(-4, 4), 0), str(dmg), col, crit or dmg >= 50)
	if crit:
		fx.popup(e.world_pos_top() + Vector2(0, -12), "크리티컬!", Color("fb6b1d"), false, 10.0, 0.5)
	Audio.sfx("crit" if crit else "hit", 0.0 if crit else -2.0, 1.0 + randf_range(-0.08, 0.08) - (0.15 if e.is_boss else 0.0))
	fx.emit(contact, 12 if crit else 6, [Color.WHITE, Color("fbff86"), e.color], 120.0 if crit else 80.0, 0.3, 2.0)
	fx.slash(contact, dir, Color("fbff86") if crit else (Color("8fd3ff") if dashing else Color.WHITE), crit or killed)
	hero.lunge(dir)
	if dashing:
		fx.ring(contact, 14.0, Color("8fd3ff"), 0.18, 2.0)
	shake(3.5 if crit else (2.5 if killed else 1.5), 0.12)
	hitstop(0.075 if crit else (0.06 if killed else 0.035))
	if e.is_boss and not killed and randf() < 0.3:
		Audio.sfx("boss_hurt", -6.0, randf_range(0.9, 1.1))
	# Bosses hit back on contact unless they are in an opening (stun / exposed / core).
	# Dashing only protects against regular monsters, so boss fights have a rhythm:
	# read the telegraph, dodge, punish the opening.
	var boss_open: bool = e.is_boss and (e.state in ["stun", "exposed", "core"] or e.dmg_mul >= 1.5)
	var safe: bool = killed or hero.invuln > 0.0 or (dashing and not spiky and (not e.is_boss or boss_open))
	if safe:
		hero.knock = -dir * ((160.0 if e.is_boss else 60.0) if dashing else 100.0)
		if dashing:
			hero.dash_t = 0.0
			hero.move_vel = -dir * 40.0
		if (e.is_boss and boss_open) or (e.counter and not e.is_boss and e.is_open()):
			fx.popup(e.world_pos_top() + Vector2(0, -14), "약점!", Color("fbff86"), false, 8.0, 0.35)
			if not e.is_boss and not flags.has("_shot_counter_open"):
				flags["_shot_counter_open"] = true
				Game.moment("counter_open", 0.05)
	else:
		if e.is_boss or spiky:
			hero.dash_t = 0.0
			hero.knock = -dir * (220.0 if e.is_boss else 170.0)
		if e.is_boss and not flags.has("boss_counter_hint"):
			flags["boss_counter_hint"] = true
			hud.hint("보스는 몸통 박치기에 반격한다! 기절·빈틈을 노려라", 4.0)
		elif spiky and not flags.has("spiky_hint"):
			flags["spiky_hint"] = true
			fx.popup(e.world_pos_top() + Vector2(0, -14), "반격!", UIKit.RED, false, 10.0, 0.5)
			hud.hint("%s 반격한다! 돌진 전 준비 동작이나 돌진 후 쉴 때(빛날 때) 노려라" % UIKit.josa(str(e.data.get("name", "")), "은", "는"), 5.0)
			Game.moment("counter_block", 0.1)
		hurt_hero(_damage(e.atk, hero_def()), -dir, e.data.get("name", ""))


func hurt_hero(dmg: int, dir: Vector2, _src = "") -> void:
	if hero.invuln > 0.0 or state != "play":
		return
	if hero.dash_t > 0.0:
		fx.popup(hero.global_position + Vector2(0, -28), "회피!", Color("8fd3ff"), false, 12.0, 0.45)
		return
	run.hp = int(run.hp) - dmg
	hero.hurt(dir)
	fx.popup(hero.global_position + Vector2(0, -26), "-%d" % dmg, UIKit.RED, dmg >= int(run.max_hp) / 4)
	Audio.sfx("hurt", -1.0, randf_range(0.95, 1.05))
	fx.emit(hero.global_position + Vector2(0, -10), 8, [Color("e83b3b"), Color("f68181"), Color.WHITE], 90.0, 0.35, 2.0)
	shake(4.0, 0.18)
	hitstop(0.06)
	flash_screen(Color(1, 0.1, 0.1, 0.22), 0.2)
	if int(run.hp) > 0 and int(run.hp) < int(run.max_hp) * 0.3:
		_try_herb()
	if int(run.hp) <= 0:
		run.hp = 0
		_on_hero_down()
	hud.update_stats(run)


func _try_herb() -> void:
	var n := int(run.items.get("herb", 0))
	if n <= 0:
		return
	run.items.herb = n - 1
	var heal := int(run.max_hp * 0.55)
	run.hp = min(int(run.max_hp), int(run.hp) + heal)
	fx.popup(hero.global_position + Vector2(0, -34), "+%d" % heal, Color("91db69"), true)
	fx.emit(hero.global_position + Vector2(0, -10), 14, [Color("91db69"), Color("cddf6c"), Color.WHITE], 50.0, 0.7, 2.0, -40.0)
	Audio.sfx("heal", -2.0)
	hud.toast("약초 자동 사용! (남은 %d)" % (n - 1), "herb", Color("91db69"))


func area_damage(pos: Vector2, r: float, base: int, _kind := "") -> void:
	if state != "play":
		return
	var hp: Vector2 = hero.global_position + Vector2(0, -4)
	if hp.distance_to(pos) <= r + 4.0:
		hurt_hero(_damage(base, hero_def()), (hp - pos).normalized(), _kind)


func cone_damage(pos: Vector2, ang: float, arc: float, r: float, base: int) -> void:
	var d: Vector2 = hero.global_position - pos
	if d.length() <= r and abs(angle_difference(d.angle(), ang)) <= arc * 0.5 + 0.1:
		hurt_hero(_damage(base, hero_def()), d.normalized(), "fire")


func _on_enemy_died(e: Enemy) -> void:
	if state == "clear" or state == "cutscene":
		fx.emit(e.center(), 10, [e.color, Color.WHITE], 90.0, 0.4, 2.0)
		return
	run.kills = int(run.kills) + 1
	var c := e.center()
	fx.emit(c, 16, [e.color, Color.WHITE, e.color.darkened(0.3)], 120.0, 0.55, 2.0, 60.0)
	fx.ring(c, 20.0, Color.WHITE, 0.22, 2.0)
	Audio.sfx("enemy_die", -2.0, randf_range(0.9, 1.15))
	var xp := int(ceil(e.exp_val * exp_bonus()))
	var gd := e.gold
	_spawn_loot(c, xp, gd)
	if e.drop != "":
		var dd := {"item": e.drop, "icon": e.drop}
		spawn_prop("pickup", e.global_position, dd)
	if e.respawn:
		respawns.append({"t": 11.0, "info": e.spawn_info})
	ev.on_kill(e)


func _spawn_loot(pos: Vector2, xp: int, gd: int) -> void:
	var n_orbs: int = clampi(xp / 4, 2, 8)
	var n_coins: int = clampi(gd / 3, 0, 6) if gd > 0 else 0
	var total: int = n_orbs + n_coins
	var state_box := {"left": total}
	for i in total:
		var o := Orb.new()
		o.is_coin = i >= n_orbs
		o.position = pos
		o.vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60, 120) + Vector2(0, -40)
		o.target = hero
		o.delay = 0.18 + i * 0.03
		o.done.connect(func(coin: bool):
			if coin:
				Audio.sfx("coin", -8.0, randf_range(1.0, 1.25))
			else:
				Audio.sfx("orb", -10.0, randf_range(1.1, 1.5))
			state_box.left -= 1
			if state_box.left == 0:
				gain(xp, gd))
		fx.add_child(o)
	if total == 0:
		gain(xp, gd)


func gain(xp: int, gd: int) -> void:
	run.gold = int(run.gold) + gd
	run.exp = int(run.exp) + xp
	var ups := 0
	while int(run.exp) >= int(run.next):
		run.exp = int(run.exp) - int(run.next)
		_level_up()
		ups += 1
	hud.update_stats(run)
	if ups > 0:
		for e in enemies:
			if is_instance_valid(e):
				e.refresh_label()


func _level_up() -> void:
	run.lv = int(run.lv) + 1
	if Game.dbg.bot:
		print("[dbg] LV %d at t=%.1f" % [int(run.lv), play_time])
	run.next = exp_next(int(run.lv))
	run.max_hp = int(run.max_hp) + 9
	run.base_atk = int(run.base_atk) + 2
	run.base_def = int(run.base_def) + 1
	run.hp = run.max_hp
	var p := hero.global_position
	fx.beam(p, Color(1, 0.95, 0.5), 0.55)
	fx.ring(p + Vector2(0, -8), 26.0, Color("fbff86"), 0.35, 2.0)
	fx.emit(p + Vector2(0, -10), 18, [Color("fbff86"), Color("f9c22b"), Color.WHITE], 90.0, 0.7, 2.0, -30.0)
	fx.popup(p + Vector2(0, -34), "LEVEL UP!", Color("fbff86"), true, 22.0, 0.9)
	fx.popup(p + Vector2(0, -20), "Lv%d  ATK+2" % run.lv, Color("8ff8e2"), false, 12.0, 0.9)
	Audio.sfx("levelup", 0.0)
	hero.flash(Color(1, 0.95, 0.5), 0.3)
	hitstop(0.05)
	ev.on_level_up()


func _update_respawns(delta: float) -> void:
	for r in respawns:
		r.t -= delta
	var keep: Array = []
	for r in respawns:
		if r.t <= 0.0:
			var pos: Vector2 = r.info.pos
			var sp := world_to_screen(pos)
			if Rect2(-32, -32, 704, 424).has_point(sp):
				r.t = 2.0
				keep.append(r)
				continue
			spawn_enemy(str(r.info.kind), pos, r.info.stats, true)
		else:
			keep.append(r)
	respawns = keep


# ================================================================== bullets / orbs / hands
class Bullet:
	extends Node2D
	var vel := Vector2.ZERO
	var dmg := 5
	var col := Color.WHITE
	var life := 4.0

	func _draw() -> void:
		draw_rect(Rect2(-3, -3, 6, 6), Color("2e222f"))
		draw_rect(Rect2(-2, -2, 4, 4), col)
		draw_rect(Rect2(-1, -1, 2, 2), Color.WHITE)


func spawn_bullet(pos: Vector2, vel: Vector2, dmg: int, color_hex) -> void:
	var b := Bullet.new()
	b.position = pos
	b.vel = vel
	b.dmg = dmg
	b.col = Color(str(color_hex))
	b.z_index = 12
	add_child(b)
	bullets.append(b)


func _update_bullets(delta: float) -> void:
	var keep: Array = []
	var hp: Vector2 = hero.global_position + Vector2(0, -8)
	for b in bullets:
		if not is_instance_valid(b):
			continue
		b.position += b.vel * delta
		b.life -= delta
		var dead: bool = b.life <= 0.0 or map.solid_at(b.position + Vector2(0, 6))
		if not dead and b.position.distance_to(hp) < 7.0:
			hurt_hero(_damage(b.dmg, hero_def()), b.vel.normalized())
			dead = true
		if dead:
			fx.emit(b.position, 4, [b.col, Color.WHITE], 40.0, 0.2, 2.0)
			b.queue_free()
		else:
			keep.append(b)
	bullets = keep


class Orb:
	extends Node2D
	signal done(coin: bool)
	var vel := Vector2.ZERO
	var target: Node2D
	var delay := 0.2
	var is_coin := false
	var t := 0.0

	func _physics_process(delta: float) -> void:
		t += delta
		if not is_instance_valid(target):
			queue_free()
			return
		if t < delay:
			vel *= 0.9
			position += vel * delta
		else:
			var goal := target.global_position + Vector2(0, -10)
			var d := goal - position
			vel = vel.lerp(d.normalized() * (180.0 + t * 400.0), 0.25)
			position += vel * delta
			if d.length() < 8.0:
				done.emit(is_coin)
				queue_free()
		queue_redraw()

	func _draw() -> void:
		if is_coin:
			draw_rect(Rect2(-2, -2, 4, 4), Color("2e222f"))
			draw_rect(Rect2(-1, -1, 3, 3), Color("f9c22b"))
			draw_rect(Rect2(-1, -1, 1, 1), Color("fbff86"))
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -3), Vector2(3, 0), Vector2(0, 3), Vector2(-3, 0)]), Color("30e1b9"))
			draw_rect(Rect2(-1, -1, 1, 1), Color.WHITE)


class ClockHands:
	extends Node2D
	var center := Vector2.ZERO
	var angles: Array = []
	var length := 150.0
	var active := false
	var shown := false

	func _draw() -> void:
		if not shown:
			return
		for a in angles:
			var tip := center + Vector2.RIGHT.rotated(float(a)) * length
			if active:
				draw_line(center, tip, Color("2e222f"), 7.0)
				draw_line(center, tip, Color("f9c22b"), 5.0)
				draw_line(center, tip, Color("fbff86"), 2.0)
			else:
				var c := Color(0.93, 0.23, 0.21, 0.5 if int(Time.get_ticks_msec() / 100) % 2 == 0 else 0.25)
				draw_line(center, tip, c, 2.0)


func set_clock_hands(center: Vector2, angles: Array, length: float, active: bool) -> void:
	var h := hands_node as ClockHands
	h.shown = true
	h.center = center
	h.angles = angles
	h.length = length
	h.active = active
	h.queue_redraw()


func _update_hands(delta: float) -> void:
	var h := hands_node as ClockHands
	if not h.shown:
		return
	if boss == null or not boss.alive:
		h.shown = false
		h.queue_redraw()
		return
	hand_hit_cd -= delta
	if h.active and hand_hit_cd <= 0.0:
		var p: Vector2 = hero.global_position + Vector2(0, -6)
		for a in h.angles:
			var tip := h.center + Vector2.RIGHT.rotated(float(a)) * h.length
			var q := Geometry2D.get_closest_point_to_segment(p, h.center, tip)
			if q.distance_to(p) < 7.0:
				hand_hit_cd = 0.6
				hurt_hero(_damage(int(boss.atk), hero_def()), (p - q).normalized())
				break


func time_stop_attack() -> void:
	hud.banner("시간 정지!", Color("a884f3"), 0.6, "섬광이 번쩍이면 대시!", 30)
	Audio.sfx("timestop_charge", 0.0)
	Audio.voice("zero_timestop")
	flash_screen(Color(0.66, 0.52, 0.95, 0.3), 0.8)
	time_stop_warn = 1.1
	await wait(0.95)
	if state != "play":
		time_stop_warn = 0.0
		return
	flash_screen(Color(0.85, 0.75, 1.0, 0.7), 0.15)
	Audio.sfx("clink", 0.0, 0.6)
	await wait(0.15)
	time_stop_warn = 0.0
	if state != "play":
		return
	if hero.dash_t > 0.0 or hero.dash_grace > 0.0:
		fx.popup(hero.global_position + Vector2(0, -30), "회피 성공!", Color("8fd3ff"), true)
		Audio.sfx("dodge", 0.0)
		return
	Audio.sfx("timestop", 0.0)
	hero.frozen = 1.3
	flash_screen(Color(0.4, 0.3, 0.8, 0.5), 1.3)
	fx.popup(hero.global_position + Vector2(0, -30), "정지!", Color("a884f3"), true)


func zero_transform(b: Boss) -> void:
	if state != "play":
		return
	state = "cutscene"
	b.intangible = true
	Audio.stop_music(0.3)
	Audio.sfx("boss_appear", 2.0, 0.7)
	shake(10.0, 1.2)
	flash_screen(Color(1, 1, 1, 1), 0.6)
	for e in enemies:
		if is_instance_valid(e) and e != b and e.alive:
			e.die()
	for bl in bullets:
		if is_instance_valid(bl):
			bl.queue_free()
	bullets.clear()
	hud.letterbox(true)
	await wait(0.6)
	b.begin_phase2()
	b.intangible = false
	hud.banner(str(b.data.get("name2", "진짜 모습")), Color("a884f3"), 1.4, str(b.data.get("title2", "")), 36)
	Audio.voice("zero_phase2")
	await wait(1.8)
	hud.letterbox(false)
	hud.show_boss(str(b.data.get("name2", b.name_ko)))
	Audio.play_music("final2", 0.3)
	state = "play"


# ================================================================== echo recording / ghost / allies
func _record(delta: float) -> void:
	rec_acc += delta
	while rec_acc >= 0.05:
		rec_acc -= 0.05
		record.append(int(hero.global_position.x))
		record.append(int(hero.global_position.y))
		record.append(hero.sprite.frame)


func record_array() -> Array:
	return Array(record)


func ghost_pos_at(t: float) -> Variant:
	if prev_record.size() < 3:
		return null
	var i := int(t / 0.05) * 3
	if i + 2 >= prev_record.size():
		return null
	return Vector2(prev_record[i], prev_record[i + 1])


func _update_ghost() -> void:
	if ghost == null:
		return
	var g := ghost as Sprite2D
	var i := int(play_time / 0.05) * 3
	if i + 2 >= prev_record.size():
		if g.visible:
			g.visible = false
			fx.emit(g.position + Vector2(0, -10), 14, [Color("30e1b9"), Color("8ff8e2")], 60.0, 0.6, 2.0, -30.0)
			ghost_line.clear_points()
		return
	g.position = Vector2(prev_record[i], prev_record[i + 1])
	g.frame = clampi(int(prev_record[i + 2]), 0, 11)
	if Engine.get_physics_frames() % 6 == 0:
		ghost_line.clear_points()
		var j := i
		var n := 0
		while j + 2 < prev_record.size() and n < 40:
			if n % 2 == 0:
				ghost_line.add_point(Vector2(prev_record[j], prev_record[j + 1]) + Vector2(0, -2))
			j += 3
			n += 1
	ev.on_ghost(g.position)


func spawn_echo_allies(n: int) -> void:
	for i in n:
		var a := Sprite2D.new()
		a.texture = load("res://assets/sprites/chars/hero.png")
		a.hframes = 3
		a.vframes = 4
		a.frame = 1
		a.offset = Vector2(0, -13)
		a.material = Shaders.material("ghost")
		a.position = hero.global_position + Vector2.RIGHT.rotated(TAU * i / max(1, n)) * 30.0
		world.add_child(a)
		allies.append({"node": a, "ang": TAU * i / max(1, n), "t": 1.0 + i * 0.37, "dash": 0.0, "from": Vector2.ZERO})
		fx.emit(a.position + Vector2(0, -10), 10, [Color("30e1b9"), Color("8ff8e2"), Color.WHITE], 70.0, 0.6, 2.0, -30.0)


func _update_allies(delta: float) -> void:
	if allies.is_empty() or boss == null or not boss.alive:
		return
	for a in allies:
		var n: Sprite2D = a.node
		a.ang += delta * 0.8
		a.t -= delta
		var home: Vector2 = boss.global_position + Vector2.RIGHT.rotated(a.ang) * 58.0
		if a.dash > 0.0:
			a.dash -= delta
			n.position = n.position.lerp(boss.global_position, 0.35)
			if a.dash <= 0.0 or n.position.distance_to(boss.global_position) < 12.0:
				a.dash = 0.0
				if not boss.intangible and not boss.invulnerable:
					var dmg: int = maxi(1, int(hero_atk() * 0.45 * boss.dmg_mul))
					boss.hp -= dmg
					boss.flash(Color(0.6, 1, 0.9), 0.08)
					fx.popup(boss.world_pos_top() + Vector2(randf_range(-10, 10), 0), str(dmg), Color("8ff8e2"))
					fx.emit(boss.center(), 6, [Color("30e1b9"), Color.WHITE], 80.0, 0.3, 2.0)
					Audio.sfx("hit", -9.0, 1.3)
					if boss.hp <= 0 and boss.alive:
						boss.die()
		else:
			n.position = n.position.lerp(home, 0.08)
			if a.t <= 0.0:
				a.t = randf_range(2.0, 3.2)
				a.dash = 0.35
		n.frame = int(Time.get_ticks_msec() / 120) % 3 + 3 * (1 if (boss.global_position.x < n.position.x) else 2)


# ================================================================== touches / interaction
func _touches() -> void:
	var hp: Vector2 = hero.global_position
	for p in touch_props:
		if not is_instance_valid(p):
			continue
		var near: bool = hp.distance_to(p.global_position) < p.touch_radius
		if p.kind == "plate":
			continue
		if near and not p.used:
			ev.prop_touch(p)
	touch_props = touch_props.filter(func(x): return is_instance_valid(x))
	ev.update_plates(get_physics_process_delta_time())
	if sd.get("dark", false) and Engine.get_physics_frames() % 5 == 0:
		_explore()


func _interact_near() -> void:
	var best = null
	var bd := 30.0
	var hp := hero.global_position + hero.facing * 4.0
	for n in npcs.values():
		if is_instance_valid(n):
			var d: float = hp.distance_to(n.global_position)
			if d < bd:
				bd = d
				best = n
	for p in props:
		if is_instance_valid(p) and p.collision_layer != 0:
			var d2: float = hp.distance_to(p.global_position)
			if d2 < bd:
				bd = d2
				best = p
	if best == null:
		return
	if best is NPC:
		talk_to(best)
	else:
		prop_bump(best, hero)


func talk_to(n: NPC) -> void:
	ev.talk_to(n)


func prop_bump(p: Prop, h) -> void:
	ev.prop_bump(p, h)


func npc_indicator(n: NPC) -> String:
	return ev.npc_indicator(n)


func has_buff(b: String) -> bool:
	return run.buffs.has(b)


func learn(k: String) -> void:
	ev.learn(k)


# ================================================================== darkness / exploration
func _explore() -> void:
	var cx := int(hero.global_position.x / T)
	var cy := int(hero.global_position.y / T)
	var r := 4
	var changed := false
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= map.w or y >= map.h:
				continue
			if Vector2(x - cx, y - cy).length() > r:
				continue
			var key := "%d,%d" % [x, y]
			if not explored.has(key):
				explored[key] = true
				mini_img.set_pixel(x, y, _mini_color(x, y))
				changed = true
	if changed:
		mem.explored = explored
		mini_dirty = true


func _mini_color(x: int, y: int) -> Color:
	if _mini_full == null:
		_mini_full = map.minimap_image()
	return _mini_full.get_pixel(x, y)


func _apply_fog_to_minimap() -> void:
	_mini_full = map.minimap_image()
	for y in map.h:
		for x in map.w:
			if not explored.has("%d,%d" % [x, y]):
				mini_img.set_pixel(x, y, Color("1a1420"))


func _update_darkness() -> void:
	var m := dark_rect.material as ShaderMaterial
	var arr: Array = []
	var hp := world_to_screen(hero.global_position + Vector2(0, -8))
	var r := 92.0 + (40.0 if run.buffs.has("lantern") else 0.0)
	arr.append(Vector4(hp.x, hp.y, r, 1.0))
	if boss and boss.alive and boss.engaged:
		var bp := world_to_screen(boss.center())
		arr.append(Vector4(bp.x, bp.y, 90.0, 0.8))
	for p in props:
		if not is_instance_valid(p) or p.light <= 0.0:
			continue
		var sp := world_to_screen(p.global_position + Vector2(0, -10))
		if sp.x < -120 or sp.y < -120 or sp.x > 760 or sp.y > 480:
			continue
		arr.append(Vector4(sp.x, sp.y, p.light * (0.95 + 0.05 * sin(Time.get_ticks_msec() * 0.01)), 0.9))
		if arr.size() >= 16:
			break
	while arr.size() < 16:
		arr.append(Vector4(-999, -999, 1, 0))
	m.set_shader_parameter("lights", arr)
	m.set_shader_parameter("count", 16)


# ================================================================== lava / hints
func _lava(delta: float) -> void:
	for le in lava_events:
		if le.get("done", false):
			continue
		var at := float(le.at)
		if not le.get("warned", false) and time_left <= at + 6.0:
			le.warned = true
			hud.banner("용암이 차오른다!", Color("fb6b1d"), 0.9, str(le.get("warn", "저지대가 곧 잠긴다")), 30)
			Audio.sfx("rumble", 0.0)
			Audio.voice("lava_warn")
			shake(4.0, 1.0)
		if time_left <= at:
			le.done = true
			flags["flooded:" + str(le.marker)] = true
			_flood(str(le.marker))
			if le.has("know"):
				learn(str(le.know))
			hud.set_objective(ev.objective_text())
	var _d := delta


func predict_bonus() -> float:
	## Bosses seen in an earlier loop telegraph their big attacks a little sooner.
	return 0.28 if boss_known_before else 0.0


func _flood(ch: String) -> void:
	var cells: Array = map.markers.get(ch, [])
	Audio.sfx("lava_flood", 2.0)
	shake(7.0, 0.8)
	flash_screen(Color(1, 0.4, 0.1, 0.35), 0.4)
	var hc := Vector2i(int(hero.global_position.x / T), int(hero.global_position.y / T))
	var hero_caught := false
	cells = cells.duplicate()
	# entity markers inside the zone are dry cells: swallow any cell mostly surrounded by the zone
	var zone := {}
	for c in cells:
		zone[c] = true
	for _pass in 2:
		var add: Array = []
		for c in zone.keys():
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if zone.has(n) or map.is_solid(n.x, n.y):
					continue
				var around := 0
				for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if zone.has(n + d2) or map.is_solid(n.x + d2.x, n.y + d2.y):
						around += 1
				if around >= 3:
					add.append(n)
		for n in add:
			zone[n] = true
	cells = zone.keys()
	for c in cells:
		map.set_terrain(c.x, c.y, "~")
		if c == hc:
			hero_caught = true
		if randf() < 0.3:
			fx.emit(Vector2(c.x * T + 8, c.y * T + 8), 3, [Color("f79617"), Color("ea4f36")], 40.0, 0.6, 2.0, -40.0)
	for e in enemies:
		if is_instance_valid(e) and e.alive and not e.is_boss and map.solid_at(e.global_position):
			e.die()
	var flooded := {}
	for c in cells:
		flooded[c] = true
	var near_lava := func(pos: Vector2) -> bool:
		var pc := Vector2i(int(pos.x / T), int(pos.y / T))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if flooded.has(pc + Vector2i(dx, dy)):
					return true
		return false
	for p in props:
		if is_instance_valid(p) and p.kind in ["statue", "chest", "pot", "pickup", "sign"] and (map.solid_at(p.global_position) or near_lava.call(p.global_position)):
			fx.emit(p.global_position + Vector2(0, -8), 12, [Color("f79617"), Color("ea4f36")], 60.0, 0.6, 2.0, -40.0)
			p.vanish()
	for key in npcs.keys():
		var n = npcs[key]
		if is_instance_valid(n) and (map.solid_at(n.global_position) or near_lava.call(n.global_position)):
			fx.emit(n.global_position + Vector2(0, -12), 12, [Color("fbff86"), Color.WHITE], 60.0, 0.5, 2.0, -40.0)
			fx.popup(n.global_position + Vector2(0, -30), "대피!", UIKit.PALE)
			n.queue_free()
			npcs.erase(key)
	if respawn_pos != start_pos and (map.solid_at(respawn_pos) or near_lava.call(respawn_pos)):
		respawn_pos = start_pos
	if hero_caught or map.solid_at(hero.global_position):
		hero.global_position = _nearest_free(hero.global_position)
		hurt_hero(int(run.max_hp * 0.25), Vector2.UP)
	mini_img = map.minimap_image()
	hud.refresh_minimap(mini_img)
	if bot:
		bot.on_terrain_changed()


func _nearest_free(p: Vector2) -> Vector2:
	var c := Vector2i(int(p.x / T), int(p.y / T))
	for r in range(1, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				if not map.is_solid(c.x + dx, c.y + dy):
					return Vector2((c.x + dx) * T + 8, (c.y + dy) * T + 12)
	return start_pos


func _hints() -> void:
	if hint_queue.is_empty():
		return
	var h: Dictionary = hint_queue[0]
	if play_time >= float(h.get("at", 0.0)) and ev.check(h.get("if", [])):
		hint_queue.pop_front()
		if int(mem.clears) == 0 or h.get("always", false):
			hud.hint(str(h.text), float(h.get("dur", 5.0)))
			if h.has("voice"):
				Audio.voice(str(h.voice))
	elif play_time >= float(h.get("at", 0.0)) + 20.0:
		hint_queue.pop_front()


# ================================================================== minimap / objective
func minimap_marks() -> Array:
	var out: Array = []
	for n in npcs.values():
		if is_instance_valid(n):
			var ind := npc_indicator(n)
			if ind != "" or n.def.has("shop"):
				out.append({"pos": n.global_position, "color": Color("30e1b9") if ind == "echo" else Color("fbff86"), "size": 3.0})
	for p in props:
		if not is_instance_valid(p):
			continue
		if p.kind == "statue":
			out.append({"pos": p.global_position, "color": Color("f9c22b"), "size": 3.0})
		elif p.kind == "chest" and not p.used and mem.chests.has(p.pid):
			out.append({"pos": p.global_position, "color": Color("fb6b1d"), "size": 3.0})
		elif p.kind == "pickup" and str(p.def.get("item", "")) == "star":
			if mem.known.has(str(p.def.get("know", "_"))):
				out.append({"pos": p.global_position, "color": Color("8ff8e2"), "size": 3.0, "blink": true})
	for k in mem.known:
		var kd: Dictionary = sd.get("knowledge", {}).get(k, {})
		if kd.has("marker"):
			out.append({"pos": map.marker_pos(str(kd.marker)), "color": Color("8ff8e2"), "size": 3.0, "blink": true})
	if ghost and (ghost as Sprite2D).visible:
		out.append({"pos": ghost.position, "color": Color("30e1b9"), "size": 2.0})
	if boss and boss.alive:
		out.append({"pos": boss.global_position, "color": Color("e83b3b"), "size": 4.0, "blink": not boss.engaged})
	out.append({"pos": hero.global_position, "color": Color.WHITE, "size": 3.0})
	return out


func objective_target() -> Variant:
	if state != "play":
		return null
	return ev.objective_pos()


# ================================================================== boss
func check_boss_trigger() -> void:
	if boss == null or boss.engaged or not boss.alive or state != "play":
		return
	var bd: Dictionary = sd.get("boss", {})
	if bd.has("trigger_rect"):
		# Optional room bounds [x, y, width, height] in map tiles. Distance alone
		# can reach through walls into an adjacent room (e.g. S4's gallery).
		var r: Array = bd.trigger_rect
		var room := Rect2(float(r[0]) * T, float(r[1]) * T, float(r[2]) * T, float(r[3]) * T)
		if not room.has_point(hero.global_position):
			return
	var trig := float(bd.get("trigger", 140))
	if hero.global_position.distance_to(boss.global_position) < trig:
		_boss_intro()


func _boss_intro() -> void:
	state = "cutscene"
	hero.move_vel = Vector2.ZERO
	var seen: bool = mem.boss_seen
	Audio.stop_music(0.25)
	hud.letterbox(true)
	hud.set_hud_visible(false)
	cam_target_override = boss.global_position + Vector2(0, -20)
	await wait(0.45)
	Audio.sfx("boss_appear", 0.0)
	shake(6.0, 0.5)
	flash_screen(Color(1, 1, 1, 0.5), 0.25)
	boss.sprite.scale = Vector2(1.3, 0.7)
	var tw := boss.create_tween()
	tw.tween_property(boss.sprite, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	hud.banner(boss.name_ko, Color("fca790"), 1.3 if not seen else 0.6, boss.title_ko, 36)
	Game.moment("boss_intro", 0.5)
	if not seen:
		await wait(1.6)
		if sd.get("boss", {}).has("lines"):
			await ev.say(sd.boss.lines)
	else:
		Audio.voice("%s_boss" % id)
		await wait(0.8)
	cam_target_override = null
	hud.letterbox(false)
	hud.set_hud_visible(true)
	hud.show_boss(boss.name_ko)
	Audio.play_music(str(sd.get("boss_music", "boss")), 0.2)
	mem.boss_seen = true
	boss.engaged = true
	var bk: String = str(sd.get("boss", {}).get("know", ""))
	if bk != "":
		learn(bk)
	if sd.get("echo_allies", false):
		var n: int = clampi(int(Game.save.total_loops) + int(Game.save.total_deaths), 1, 12)
		spawn_echo_allies(n)
		hud.banner("메아리 x%d" % n, UIKit.ECHO, 1.0, "지금까지의 모든 실패가 함께 싸운다!", 30)
		Audio.voice("echo_allies")
	state = "play"
	ev.on_boss_engaged()


func _on_boss_died(_b) -> void:
	_on_boss_dead()


func _on_boss_dead(peaceful := false) -> void:
	if state == "clear":
		return
	print("[dbg] CLEAR %s loop=%d left=%.1f t=%.1f lv=%d kills=%d gold=%d peaceful=%s" % [id, loop_idx, time_left, play_time, int(run.lv), int(run.kills), int(run.gold), peaceful])
	if Game.dbg.quit_on_clear:
		get_tree().quit()
		return
	state = "clear"
	hero.control = false
	var bp: Vector2 = boss.center() if boss else hero.global_position
	for e in enemies:
		if is_instance_valid(e) and e.alive and e != boss:
			e.die()
	for bl in bullets:
		if is_instance_valid(bl):
			bl.queue_free()
	bullets.clear()
	(hands_node as ClockHands).shown = false
	hands_node.queue_redraw()
	Audio.stop_music(0.05)
	Audio.set_music_pitch(1.0, 0.1)
	hurry = false
	vig = 0.0
	hitstop(0.0)
	Engine.time_scale = 0.2
	flash_screen(Color(1, 1, 1, 1), 0.5)
	shake(12.0, 1.0)
	Audio.sfx("boss_die", 2.0)
	if not peaceful:
		for i in 4:
			fx.emit(bp, 20, [Color.WHITE, Color("fbff86"), Color("f79617"), Color("e83b3b")], 180.0, 1.2, 3.0, 40.0)
		fx.ring(bp, 90.0, Color.WHITE, 0.6, 3.0)
	else:
		fx.emit(bp, 40, [Color("eaaded"), Color("a884f3"), Color.WHITE], 60.0, 1.6, 2.0, -40.0)
	await wait(1.1)
	Engine.time_scale = 1.0
	hud.hide_boss()
	hero.celebrate()
	Audio.play_jingle("victory")
	hud.banner("STAGE CLEAR!", UIKit.GOLD, 1.6, "", 45)
	Audio.voice("clear")
	await wait(2.0)
	await ev.show_result()


# ================================================================== fail states
func _on_hero_down() -> void:
	if state != "play":
		return
	print("[dbg] DOWN %s t=%.1f lv=%d" % [id, play_time, int(run.lv)])
	state = "dead"
	hero.control = false
	Audio.sfx("hero_down", 0.0)
	hitstop(0.15)
	Engine.time_scale = 0.35
	shake(8.0, 0.5)
	flash_screen(Color(1, 0.1, 0.1, 0.5), 0.5)
	mem.deaths.append([int(hero.global_position.x), int(hero.global_position.y)])
	Game.save.total_deaths = int(Game.save.total_deaths) + 1
	var tw := hero.create_tween()
	tw.tween_property(hero.sprite, "rotation", PI * 0.5, 0.3)
	await wait(0.6)
	Engine.time_scale = 1.0
	var penalty := 10.0
	hud.banner("쓰러졌다!", UIKit.RED, 1.0, "-%d초 · 시작 지점에서 재출발" % int(penalty), 36)
	Audio.voice("chocho_down")
	await wait(1.1)
	time_left -= penalty
	if time_left <= 0.0:
		time_left = 0.0
		state = "play"
		_on_time_up()
		return
	hero.sprite.rotation = 0.0
	run.hp = run.max_hp
	hud.update_stats(run)
	hero.global_position = respawn_pos
	hero.move_vel = Vector2.ZERO
	hero.knock = Vector2.ZERO
	_snap_camera()
	fx.beam(hero.global_position, Color(0.6, 1.0, 0.9), 0.5)
	Audio.sfx("respawn", -2.0)
	hero.invuln = 1.6
	hero.control = true
	state = "play"


func _on_time_up() -> void:
	if state != "play":
		return
	print("[dbg] TIMEUP %s loop=%d lv=%d kills=%d boss=%s" % [id, loop_idx, int(run.lv), int(run.kills), ("%d/%d engaged=%s" % [boss.hp, boss.max_hp, boss.engaged]) if boss else "-"])
	state = "timeup"
	hero.control = false
	Audio.stop_music(0.05)
	Audio.set_music_pitch(1.0, 0.1)
	Audio.sfx("bell_toll", 3.0)
	flash_screen(Color(1, 1, 1, 1), 0.9)
	shake(12.0, 1.2)
	Engine.time_scale = 0.3
	var fail: Dictionary = sd.get("fail", {})
	hud.banner("TIME UP", UIKit.RED, 1.4, str(fail.get("text", "종이 울렸다…")), 50)
	Audio.voice("timeup")
	var tw := create_tween()
	tw.tween_property(tint, "color", Color(0.55, 0.45, 0.6), 1.0)
	await wait(1.9)
	Engine.time_scale = 1.0
	await ev.fail_card()
	await rewind("timeup")


func rewind(reason := "manual") -> void:
	## Loop reset. Knowledge, shortcuts and the ghost recording survive.
	state = "rewind"
	get_tree().paused = false
	Audio.set_muffled(false)
	mem.loops = int(mem.loops) + 1
	Game.save.total_loops = int(Game.save.total_loops) + 1
	mem.last_lv = max(int(run.lv), int(run.get("lv_peak", run.lv)))
	mem.record = record_array()
	mem.explored = explored
	Game.save_game()
	rewind_rect.visible = true
	var m := rewind_rect.material as ShaderMaterial
	Audio.sfx("rewind", 0.0)
	if reason != "manual":
		Audio.voice("chocho_rewind_%d" % (1 + randi() % 3))
	hud.set_hud_visible(false, 0.15)
	Game.moment("rewind", 0.7)
	var n := record.size() / 3
	var dur := 1.5
	var t := 0.0
	while t < dur:
		var dt := get_process_delta_time()
		t += dt
		var k := t / dur
		m.set_shader_parameter("amount", clamp(k * 2.0, 0.0, 1.0))
		m.set_shader_parameter("t", t)
		if n > 0:
			var idx := int(lerp(float(n - 1), 0.0, ease(k, 0.6)))
			hero.global_position = Vector2(record[idx * 3], record[idx * 3 + 1])
			hero.sprite.frame = record[idx * 3 + 2]
			if Engine.get_process_frames() % 2 == 0:
				fx.afterimage(hero.sprite, Color(0.19, 0.88, 0.73, 0.5), 0.3)
		time_left = lerp(0.0, time_total, k)
		cam.position = hero.global_position + Vector2(0, -10)
		await get_tree().process_frame
	flash_screen(Color(0.6, 1.0, 0.95, 1.0), 0.2)
	Game.goto("stage", {"id": id, "rewound": true})


func _rewind_in() -> void:
	rewind_rect.visible = true
	var m := rewind_rect.material as ShaderMaterial
	m.set_shader_parameter("amount", 1.0)
	var tw := rewind_rect.create_tween()
	tw.tween_method(func(v: float):
		m.set_shader_parameter("amount", v)
		m.set_shader_parameter("t", v * 3.0), 1.0, 0.0, 0.45)
	tw.tween_callback(func(): rewind_rect.visible = false)
