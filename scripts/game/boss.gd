class_name Boss
extends Enemy
## Bosses: readable, telegraphed patterns with clear "punish" windows.

var pattern_t := 2.0
var special_t := 5.0
var phase := 1
var face := Vector2.DOWN
var perches: Array = []
var perch_i := 0
var arena_center := Vector2.ZERO
var hands: Array = []
var shield_node: Node2D
var core_open := false
var engaged := false
var name_ko := ""
var title_ko := ""
var spawned_clones := false
var aim_ang := 0.0


var base_mul := 0.6


func _ready() -> void:
	is_boss = true
	super._ready()
	arena_center = home
	name_ko = str(data.get("name", kind))
	title_ko = str(data.get("title", ""))
	# outside of its openings a boss shrugs off most damage
	base_mul = {"golem": 0.12, "countess": 1.0, "mirror_knight": 1.0, "fire_drake": 1.0, "zero": 0.75}.get(kind, 0.6)
	dmg_mul = base_mul
	if kind == "mirror_knight":
		shield_node = Node2D.new()
		shield_node.draw.connect(_draw_shield)
		add_child(shield_node)


func think(delta: float, to_hero: Vector2, dist: float) -> void:
	if not engaged:
		move_vel = Vector2.ZERO
		return
	pattern_t -= delta
	special_t -= delta
	match kind:
		"king_slime": _slime(delta, to_hero, dist)
		"troll": _troll(delta, to_hero, dist)
		"golem": _golem(delta, to_hero, dist)
		"countess": _countess(delta, to_hero, dist)
		"mirror_knight": _knight(delta, to_hero, dist)
		"fire_drake": _drake(delta, to_hero, dist)
		"zero": _zero(delta, to_hero, dist)
		"crab_boss": _crab(delta, to_hero, dist)
		_: move_vel = to_hero.normalized() * speed


func _animate(_delta: float, moving: bool) -> void:
	if kind in ["countess", "zero"] or (kind == "fire_drake" and state == "fly"):
		sprite.position.y = -6.0 + sin(anim_t * 3.0) * 3.0
	elif state == "stun":
		sprite.rotation = sin(anim_t * 30.0) * 0.05
	elif moving and kind != "king_slime":
		sprite.rotation = sin(anim_t * 8.0) * 0.05
	else:
		sprite.rotation = 0.0
	if kind == "king_slime" and state != "air" and state != "stun":
		sprite.scale = Vector2(1.0 + sin(anim_t * 5.0) * 0.04, 1.0 - sin(anim_t * 5.0) * 0.04)
	if shield_node:
		shield_node.queue_redraw()
	if core_open and int(anim_t * 10.0) % 2 == 0:
		flash(Color(1, 0.6, 0.2), 0.08)
	# openings glow so they read at a glance
	var open := dmg_mul >= 1.5 or state in ["stun", "exposed", "core"]
	if open and not intangible:
		var k := 0.5 + 0.5 * sin(anim_t * 18.0)
		sprite.modulate = Color(1.0 + 0.35 * k, 1.0 + 0.3 * k, 0.85 + 0.1 * k, sprite.modulate.a)
		if Engine.get_process_frames() % 8 == 0:
			stage.fx.emit(world_pos_top() + Vector2(randf_range(-14, 14), 4), 1, [Color("fbff86"), Color.WHITE], 20.0, 0.5, 2.0, -30.0)
	else:
		sprite.modulate = Color(1, 1, 1, sprite.modulate.a)


func set_state(s: String, t: float) -> void:
	state = s
	state_t = t


func _stun(t: float, mul := 1.8) -> void:
	set_state("stun", t)
	dmg_mul = mul
	move_vel = Vector2.ZERO
	stage.fx.popup(world_pos_top(), "기회!", Color("fbff86"), true)
	var sk := str(stage.sd.get("boss", {}).get("stun_know", ""))
	if sk != "":
		stage.learn(sk)
	Audio.sfx("stun", -2.0)
	stage.fx.emit(world_pos_top(), 10, [Color("fbff86"), Color("ffffff")], 30.0, 0.8, 2.0, -20.0)


func _end_stun() -> void:
	dmg_mul = base_mul
	set_state("idle", 0.0)


# ------------------------------------------------------------------ king slime
func _slime(delta: float, to_hero: Vector2, _dist: float) -> void:
	if hp <= max_hp / 2:
		phase = 2
	match state:
		"idle":
			hop_t -= delta
			move_vel = move_vel.move_toward(Vector2.ZERO, 200 * delta)
			if hop_t <= 0.0:
				hop_t = 0.85 if phase == 1 else 0.6
				move_vel = to_hero.normalized() * speed * 2.4
				Audio.sfx("squish", -6.0, 0.7)
			if special_t <= 0.0:
				special_t = 5.5 if phase == 1 else 4.2
				_slime_jump()
		"stun":
			move_vel = Vector2.ZERO
			if state_t <= 0.0:
				_end_stun()


func _slime_jump() -> void:
	set_state("air", 99.0)
	intangible = true
	move_vel = Vector2.ZERO
	var target: Vector2 = stage.hero.global_position
	Audio.sfx("jump", 0.0, 0.6)
	var pb := _predict()
	var tw := create_tween()
	tw.tween_property(sprite, "position:y", -90.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(shadow, "scale", Vector2(0.5, 0.5), 0.35)
	tw.tween_property(self, "global_position", target, 0.45)
	stage.fx.telegraph_circle(target, 38.0, 0.85 + pb, _slime_fall)


func _predict() -> float:
	var pb: float = stage.predict_bonus()
	if pb > 0.0:
		stage.fx.popup(world_pos_top() + Vector2(0, -12), "예측!", Color("8ff8e2"), false, 10.0, 0.5)
	return pb


func _slime_fall() -> void:
	if not alive:
		return
	var tw := create_tween()
	tw.tween_property(sprite, "position:y", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(shadow, "scale", Vector2.ONE, 0.1)
	tw.tween_callback(_slime_land)


func _slime_land() -> void:
	if not alive:
		return
	intangible = false
	sprite.scale = Vector2(1.4, 0.6)
	stage.shake(6.0, 0.35)
	Audio.sfx("slam", 0.0)
	stage.fx.ring(global_position, 44.0, Color("91db69"), 0.35, 3.0)
	stage.fx.emit(global_position, 18, [Color("91db69"), Color("1ebc73"), Color("cddf6c")], 120.0, 0.6, 3.0, 200.0)
	stage.area_damage(global_position, 38.0, int(atk * 1.2), "shock")
	var n := 2 if phase == 1 else 3
	for i in n:
		stage.spawn_minion("slime", global_position + Vector2.RIGHT.rotated(randf() * TAU) * 26.0)
	_stun(1.4, 1.6)


# ------------------------------------------------------------------ troll
func _troll(delta: float, to_hero: Vector2, dist: float) -> void:
	if hp <= max_hp / 2:
		phase = 2
	match state:
		"idle":
			move_vel = move_vel.move_toward(to_hero.normalized() * speed, 200 * delta)
			face = to_hero.normalized()
			if dist < 34.0 and pattern_t <= 0.0:
				pattern_t = 1.6
				set_state("club", 99.0)
				move_vel = Vector2.ZERO
				stage.fx.telegraph_circle(global_position + face * 14.0, 30.0, 0.55, _troll_club)
			elif special_t <= 0.0:
				special_t = 4.5 if phase == 1 else 3.4
				var pb := _predict()
				set_state("aim", 0.75 + pb)
				move_vel = Vector2.ZERO
				charge_dir = to_hero.normalized()
				Audio.sfx("roar", -2.0, 0.9)
				stage.fx.telegraph_line(global_position, global_position + charge_dir * 240.0, 26.0, 0.75 + pb, Callable())
		"aim":
			sprite.position.x = sin(anim_t * 50.0) * 1.5
			if state_t <= 0.0:
				sprite.position.x = 0
				set_state("charge", 1.3)
		"charge":
			move_vel = charge_dir * 240.0
			if get_slide_collision_count() > 0:
				stage.shake(8.0, 0.4)
				Audio.sfx("slam", 2.0, 0.6)
				stage.fx.emit(global_position, 16, [Color("9babb2"), Color("c7dcd0"), Color("ab947a")], 100.0, 0.6, 3.0, 150.0)
				_stun(2.2, 2.0)
			elif state_t <= 0.0:
				set_state("idle", 0.0)
		"stun":
			if state_t <= 0.0:
				_end_stun()
		"club":
			move_vel = Vector2.ZERO


func _troll_club() -> void:
	if not alive:
		return
	Audio.sfx("slam", -2.0, 0.8)
	stage.shake(4.0, 0.2)
	stage.area_damage(global_position + face * 14.0, 30.0, int(atk * 1.1), "club")
	set_state("idle", 0.0)


# ------------------------------------------------------------------ golem
func _golem(delta: float, to_hero: Vector2, _dist: float) -> void:
	if hp <= max_hp / 2:
		phase = 2
	match state:
		"idle":
			dmg_mul = 0.12
			move_vel = move_vel.move_toward(to_hero.normalized() * speed, 100 * delta)
			if pattern_t <= 0.0:
				pattern_t = 3.0 if phase == 1 else 2.2
				var tgt: Vector2 = stage.hero.global_position
				Audio.sfx("throw", -2.0, 0.8)
				stage.fx.telegraph_circle(tgt, 18.0, 0.9, _golem_rock.bind(tgt))
			if special_t <= 0.0:
				special_t = 6.0 if phase == 1 else 4.8
				set_state("slam", 99.0)
				move_vel = Vector2.ZERO
				stage.fx.telegraph_circle(global_position, 56.0, 1.0 + _predict(), _golem_slam)
		"core":
			move_vel = Vector2.ZERO
			if state_t <= 0.0:
				core_open = false
				dmg_mul = 0.12
				set_state("idle", 0.0)
		"slam":
			move_vel = Vector2.ZERO


func _golem_rock(tgt: Vector2) -> void:
	Audio.sfx("slam", -6.0, 1.2)
	stage.fx.emit(tgt, 10, [Color("625565"), Color("9babb2"), Color("fb6b1d")], 90.0, 0.5, 3.0, 150.0)
	stage.area_damage(tgt, 18.0, int(atk * 0.9), "rock")


func _golem_slam() -> void:
	if not alive:
		return
	stage.shake(9.0, 0.45)
	Audio.sfx("slam", 3.0, 0.5)
	stage.fx.ring(global_position, 64.0, Color("fb6b1d"), 0.4, 3.0)
	stage.area_damage(global_position, 56.0, int(atk * 1.3), "slam")
	set_state("core", 3.3)
	core_open = true
	dmg_mul = 2.0
	stage.fx.popup(world_pos_top(), "핵이 열렸다!", Color("f79617"), true)
	stage.learn("golem_core")


# ------------------------------------------------------------------ countess
func _countess(delta: float, _to_hero: Vector2, _dist: float) -> void:
	if hp <= max_hp / 2:
		phase = 2
	invulnerable = not stage.has_buff("holy")
	if state == "tired":
		move_vel = move_vel.move_toward(Vector2.ZERO, 300 * delta)
		if state_t <= 0.0:
			dmg_mul = base_mul
			set_state("idle", 0.0)
		return
	var wob := Vector2(cos(anim_t * 1.3), sin(anim_t * 1.7)) * 26.0
	move_vel = move_vel.move_toward((arena_center + wob - global_position) * 1.5, 120 * delta)
	if pattern_t <= 0.0:
		pattern_t = 3.0 if phase == 1 else 2.3
		var n := 8 if phase == 1 else 12
		var off := randf() * TAU
		Audio.sfx("magic", -4.0, 0.8)
		for i in n:
			stage.spawn_bullet(center(), Vector2.RIGHT.rotated(off + TAU * i / n) * 62.0, int(atk * 0.8), "a884f3")
		# after each ring she sways, exhausted: the opening
		set_state("tired", 1.7)
		dmg_mul = 1.6
		flash(Color(0.8, 0.7, 1.0), 0.2)
	if special_t <= 0.0:
		special_t = 6.0
		for i in 2:
			stage.spawn_minion("ghost", center() + Vector2.RIGHT.rotated(randf() * TAU) * 30.0)


# ------------------------------------------------------------------ mirror knight
func _draw_shield() -> void:
	var a := face.angle()
	var c := Color("8ff8e2") if state != "exposed" and state != "stun" else Color("7f708a")
	shield_node.draw_arc(Vector2(0, -tex_h * 0.45), 24.0, a - 0.9, a + 0.9, 12, c, 3.0)


func blocks(from_dir: Vector2) -> bool:
	## from_dir: direction from the knight towards the hero
	return kind == "mirror_knight" and state != "exposed" and state != "stun" and face.dot(from_dir.normalized()) > 0.35


func _knight(delta: float, to_hero: Vector2, _dist: float) -> void:
	match state:
		"idle":
			var want := to_hero.normalized()
			var turn := 2.0 if phase == 1 else 2.8
			face = Vector2.RIGHT.rotated(lerp_angle(face.angle(), want.angle(), min(1.0, turn * delta)))
			move_vel = move_vel.move_toward(face * speed, 150 * delta)
			if special_t <= 0.0:
				special_t = 3.6 if phase == 1 else 2.8
				var pb := _predict()
				set_state("aim", 0.5 + pb)
				charge_dir = want
				face = want
				move_vel = Vector2.ZERO
				Audio.sfx("blade", -2.0)
				stage.fx.telegraph_line(global_position, global_position + charge_dir * 160.0, 20.0, 0.5 + pb, Callable())
		"aim":
			if state_t <= 0.0:
				set_state("dash", 0.55)
		"dash":
			move_vel = charge_dir * 260.0
			if state_t <= 0.0 or get_slide_collision_count() > 0:
				set_state("exposed", 1.9)
				face = -charge_dir
				dmg_mul = 1.8
				move_vel = Vector2.ZERO
				stage.fx.popup(world_pos_top(), "빈틈!", Color("fbff86"), true)
		"exposed":
			move_vel = move_vel.move_toward(Vector2.ZERO, 400 * delta)
			if state_t <= 0.0:
				dmg_mul = 1.0
				set_state("idle", 0.0)
		"stun":
			if state_t <= 0.0:
				_end_stun()
	if hp <= max_hp / 2 and not spawned_clones:
		spawned_clones = true
		phase = 2
		for i in 2:
			stage.spawn_minion("mirror_shard", global_position + Vector2(-30 + 60 * i, 10))
		stage.fx.popup(world_pos_top(), "거울 분신!", Color("8ff8e2"), true)


# ------------------------------------------------------------------ fire drake
func _drake(delta: float, to_hero: Vector2, _dist: float) -> void:
	if hp <= max_hp / 2:
		phase = 2
	if perches.is_empty():
		for i in 3:
			perches.append(home + Vector2.RIGHT.rotated(TAU * i / 3.0 + 0.5) * 70.0)
	match state:
		"idle":
			set_state("perch", 4.0 if phase == 1 else 3.0)
			pattern_t = 1.0
			intangible = false
			dmg_mul = base_mul
		"perch":
			move_vel = move_vel.move_toward(Vector2.ZERO, 300 * delta)
			if dmg_mul > 1.0 and state_t < 0.3:
				dmg_mul = base_mul
			if pattern_t <= 0.0:
				pattern_t = 99.0
				aim_ang = to_hero.angle()
				Audio.sfx("roar", -2.0, 1.2)
				stage.fx.telegraph_cone(global_position, aim_ang, 0.9, 110.0, 0.8 + _predict(), _drake_breath)
			if state_t <= 0.0:
				perch_i = (perch_i + 1) % perches.size()
				set_state("fly", 1.7)
				intangible = true
				dmg_mul = base_mul
				var tw := create_tween()
				tw.tween_property(sprite, "position:y", -40.0, 0.3)
				tw.tween_property(self, "global_position", perches[perch_i], 1.0).set_trans(Tween.TRANS_SINE)
				tw.tween_property(sprite, "position:y", 0.0, 0.3)
				for k in 2:
					var tgt: Vector2 = stage.hero.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
					stage.fx.telegraph_circle(tgt, 16.0, 0.9 + k * 0.3, _drake_fireball.bind(tgt))
		"fly":
			move_vel = Vector2.ZERO
			if state_t <= 0.0:
				set_state("idle", 0.0)
		"stun":
			if state_t <= 0.0:
				_end_stun()


func _drake_breath() -> void:
	if not alive:
		return
	Audio.sfx("fire", 0.0)
	for i in 14:
		stage.fx.emit(global_position + Vector2.RIGHT.rotated(aim_ang) * (10 + i * 7), 3, [Color("f79617"), Color("ea4f36"), Color("f9c22b")], 40.0, 0.5, 3.0, -30.0)
	stage.cone_damage(global_position, aim_ang, 0.9, 110.0, int(atk * 1.1))
	# out of breath right after the flame: the opening
	dmg_mul = 1.8
	flash(Color(1, 0.8, 0.5), 0.2)
	stage.fx.popup(world_pos_top(), "숨 고르기!", Color("fbff86"), false, 12.0, 0.6)
	state_t = max(state_t, 2.2)


func _drake_fireball(tgt: Vector2) -> void:
	stage.fx.emit(tgt, 10, [Color("f79617"), Color("ea4f36")], 70.0, 0.5, 3.0, -40.0)
	Audio.sfx("fire", -8.0, 1.3)
	stage.area_damage(tgt, 16.0, int(atk * 0.8), "fire")


# ------------------------------------------------------------------ zero
func _zero(delta: float, to_hero: Vector2, dist: float) -> void:
	if phase == 1:
		move_vel = move_vel.move_toward(Vector2(cos(anim_t), sin(anim_t * 1.3)) * 30.0, 100 * delta)
		if pattern_t <= 0.0:
			pattern_t = 1.8
			var off := randf() * TAU
			Audio.sfx("magic", -3.0, 0.7)
			for i in 8:
				stage.spawn_bullet(center(), Vector2.RIGHT.rotated(off + TAU * i / 8.0) * 80.0, int(atk * 0.8), "f9c22b")
		if special_t <= 0.0:
			special_t = 3.2
			_teleport()
		if hp <= max_hp / 2:
			stage.zero_transform(self)
	else:
		_zero2(delta, to_hero, dist)


func _teleport() -> void:
	var tgt: Vector2 = arena_center + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30.0, 80.0)
	Audio.sfx("warp", -3.0)
	stage.fx.emit(center(), 14, [Color("a884f3"), Color("6b3e75"), Color("ffffff")], 80.0, 0.5, 2.0)
	intangible = true
	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 0.0, 0.15)
	tw.tween_property(self, "global_position", tgt, 0.01)
	tw.tween_property(sprite, "modulate:a", 1.0, 0.2)
	tw.tween_callback(_end_teleport)


func _end_teleport() -> void:
	intangible = false
	# dizzy for a moment after warping: the opening
	dmg_mul = 1.6
	get_tree().create_timer(1.1, false).timeout.connect(func():
		if is_instance_valid(self) and phase == 1:
			dmg_mul = base_mul)


func begin_phase2() -> void:
	phase = 2
	sprite.texture = load("res://assets/sprites/bosses/zero2.png")
	tex_h = sprite.texture.get_height()
	sprite.offset = Vector2(0, -tex_h * 0.5)
	shadow.texture = Hero.shadow_texture(60)
	max_hp = int(data.get("hp2", max_hp))
	hp = max_hp
	atk = int(data.get("atk2", atk))
	global_position = arena_center
	set_state("idle", 0.0)
	pattern_t = 2.0
	special_t = 7.0
	hands = [randf() * TAU, randf() * TAU + PI]


func _zero2(delta: float, _to_hero: Vector2, _dist: float) -> void:
	move_vel = (arena_center - global_position) * 2.0
	var cycle := fmod(anim_t, 6.0)
	var active := cycle > 1.3 and cycle < 4.8
	# while the hands rest, the clock face is exposed
	dmg_mul = base_mul if active else 1.6
	var speeds := [0.85, -1.3]
	for i in hands.size():
		hands[i] = float(hands[i]) + float(speeds[i]) * delta * (1.0 if active else 0.3)
	stage.set_clock_hands(global_position + Vector2(0, -tex_h * 0.45), hands, 150.0, active)
	if pattern_t <= 0.0:
		pattern_t = 2.6
		var off := randf() * TAU
		for i in 10:
			stage.spawn_bullet(center(), Vector2.RIGHT.rotated(off + TAU * i / 10.0) * 66.0, int(atk * 0.6), "a884f3")
	if special_t <= 0.0:
		special_t = 11.0
		stage.time_stop_attack()


# ------------------------------------------------------------------ crab (mini boss)
func _crab(delta: float, to_hero: Vector2, dist: float) -> void:
	if dist < 130.0:
		var side := Vector2(signf(to_hero.x), signf(to_hero.y) * 0.5)
		move_vel = move_vel.move_toward(side * speed, 200 * delta)
	else:
		move_vel = move_vel.move_toward((home - global_position).limit_length(1.0) * speed, 200 * delta)
	if pattern_t <= 0.0 and dist < 110.0:
		pattern_t = 2.2
		Audio.sfx("magic", -6.0, 1.4)
		for i in 3:
			stage.spawn_bullet(center(), to_hero.normalized().rotated(-0.3 + 0.3 * i) * 90.0, int(atk * 0.7), "8fd3ff")
