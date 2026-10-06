class_name Enemy
extends CharacterBody2D
## Field monster. Contact ("bump") combat is resolved by Stage; this class
## owns stats, behaviour, hit reactions and the little readable UI above it.

signal died(e)

var stage
var kind := ""
var data: Dictionary = {}
var lv := 1
var max_hp := 10
var hp := 10
var atk := 1
var def := 0
var exp_val := 1
var gold := 0
var speed := 30.0
var ai := "wander"
var radius := 6.0
var aggro := 90.0
var home := Vector2.ZERO
var alive := true
var is_boss := false
var invulnerable := false
var intangible := false
var flying := false
var respawn := true
var counter := false
var drop := ""
var spawn_info: Dictionary = {}

var sprite: Sprite2D
var shadow: Sprite2D
var lv_label: Label
var bar: Node2D
var move_vel := Vector2.ZERO
var knock := Vector2.ZERO
var think_t := 0.0
var state := "idle"
var state_t := 0.0
var clash_cd := 0.0
var hit_show := 0.0
var anim_t := 0.0
var hop_t := 0.0
var shoot_t := 1.5
var charge_dir := Vector2.ZERO
var tex_h := 16.0
var color := Color.WHITE
var _flash_tw: Tween
var dmg_mul := 1.0


func setup(k: String, overrides: Dictionary = {}) -> void:
	kind = k
	data = DB.enemy(k).duplicate(true)
	for key in overrides:
		data[key] = overrides[key]
	lv = int(data.get("lv", 1))
	var L := float(lv)
	var km: Array = data.get("k", [1, 1, 1, 1, 1])
	# level-scaled stats unless the entry gives explicit numbers
	max_hp = int(data.get("hp", round(float(km[0]) * (8.0 + 8.0 * L))))
	atk = int(data.get("atk", round(float(km[1]) * (4.0 + 2.6 * L))))
	def = int(data.get("def", round(float(km[2]) * 0.6 * L)))
	exp_val = int(data.get("exp", round(float(km[3]) * (3.0 + 2.2 * L + 0.35 * L * L))))
	gold = int(data.get("gold", round(float(km[4]) * (1.0 + L))))
	hp = max_hp
	speed = float(data.get("speed", 30))
	ai = str(data.get("ai", "wander"))
	radius = float(data.get("radius", 6))
	aggro = float(data.get("aggro", 90))
	flying = bool(data.get("flying", false))
	counter = bool(data.get("counter", false))
	drop = str(data.get("drop", ""))
	color = Color(str(data.get("color", "ffffff")))
	respawn = bool(data.get("respawn", true))


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = max(3.0, radius * 0.7)
	cs.shape = c
	cs.position = Vector2(0, -c.radius)
	add_child(cs)
	var tex: Texture2D = load("res://assets/sprites/%s.png" % data.get("sprite", "monsters/slime"))
	tex_h = tex.get_height()
	shadow = Sprite2D.new()
	shadow.texture = Hero.shadow_texture(int(clamp(tex.get_width() * 0.7, 8, 60)))
	shadow.position = Vector2(0, -1)
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.offset = Vector2(0, -tex_h * 0.5)
	sprite.material = Shaders.material("flash")
	add_child(sprite)
	home = global_position
	anim_t = randf() * 10.0
	think_t = randf() * 1.5
	if not is_boss:
		lv_label = Label.new()
		lv_label.add_theme_font_override("font", Game.font("tiny"))
		lv_label.add_theme_font_size_override("font_size", 8)
		lv_label.add_theme_color_override("font_outline_color", Color("2e222f"))
		lv_label.add_theme_constant_override("outline_size", 3)
		lv_label.text = "Lv%d" % lv
		lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv_label.size = Vector2(30, 10)
		lv_label.position = Vector2(-15, -tex_h - 11)
		add_child(lv_label)
		bar = Node2D.new()
		bar.position = Vector2(0, -tex_h - 2)
		bar.visible = false
		bar.draw.connect(_draw_bar)
		add_child(bar)
	refresh_label()


func refresh_label() -> void:
	if lv_label == null or stage == null:
		return
	var d: int = lv - int(stage.run.lv)
	# colour AND a suffix, so danger is readable without colour vision
	var col := Color("c7dcd0")
	var suffix := ""
	if d <= -3:
		col = Color("7f708a")
	elif d >= 6:
		col = Color("e83b3b")
		suffix = "!!"
	elif d >= 3:
		col = Color("fb6b1d")
		suffix = "!"
	elif d >= 1:
		col = Color("f9c22b")
		suffix = "+"
	lv_label.text = "Lv%d%s" % [lv, suffix]
	lv_label.add_theme_color_override("font_color", col)
	lv_label.visible = d > -6


var label_lift := 0.0


func set_label_lift(v: float) -> void:
	if lv_label == null or is_equal_approx(v, label_lift):
		return
	label_lift = v
	lv_label.position.y = -tex_h - 11 - v


func _draw_bar() -> void:
	var w := 16.0
	bar.draw_rect(Rect2(-w * 0.5 - 1, -1, w + 2, 4), Color("2e222f"))
	bar.draw_rect(Rect2(-w * 0.5, 0, w * float(hp) / float(max_hp), 2), Color("e83b3b"))


func world_pos_top() -> Vector2:
	return global_position + Vector2(0, -tex_h)


func center() -> Vector2:
	return global_position + Vector2(0, -tex_h * 0.45)


# ------------------------------------------------------------------ behaviour
func _physics_process(delta: float) -> void:
	if not alive:
		return
	anim_t += delta
	clash_cd = max(0.0, clash_cd - delta)
	if hit_show > 0.0:
		hit_show -= delta
		if bar:
			bar.visible = hit_show > 0.0
			bar.queue_redraw()
	if not stage.world_active():
		velocity = Vector2.ZERO
		_animate(delta, false)
		return
	think_t -= delta
	state_t -= delta
	var hero = stage.hero
	var to_hero: Vector2 = hero.global_position - global_position
	var dist := to_hero.length()
	think(delta, to_hero, dist)
	velocity = move_vel + knock
	knock = knock.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	_animate(delta, move_vel.length() > 5.0)
	if counter and not is_boss:
		_counter_glow()


func think(delta: float, to_hero: Vector2, dist: float) -> void:
	var from_home := global_position.distance_to(home)
	var chasing: bool = dist < aggro and from_home < 200.0 and not stage.hero_hidden()
	match ai:
		"wander", "chase":
			if chasing:
				move_vel = move_vel.move_toward(to_hero.normalized() * speed, 400 * delta)
			else:
				_wander(delta, from_home)
		"hop":
			hop_t -= delta
			if hop_t <= 0.0:
				hop_t = randf_range(0.55, 0.9)
				var d := to_hero.normalized() if chasing else Vector2.RIGHT.rotated(randf() * TAU)
				if not chasing and from_home > 60.0:
					d = (home - global_position).normalized()
				move_vel = d * speed * 2.6
				sprite.scale = Vector2(1.3, 0.7)
				var tw := create_tween()
				tw.tween_property(sprite, "scale", Vector2(0.85, 1.2), 0.12)
				tw.tween_property(sprite, "scale", Vector2.ONE, 0.2)
			move_vel = move_vel.move_toward(Vector2.ZERO, speed * 5.0 * delta)
		"flyer":
			var t := anim_t * 3.0
			var wob := Vector2(cos(t * 1.3), sin(t * 1.9)) * speed * 0.9
			if chasing:
				move_vel = move_vel.move_toward(to_hero.normalized() * speed + wob, 500 * delta)
			else:
				move_vel = move_vel.move_toward((home - global_position).limit_length(1.0) * speed * 0.5 + wob, 300 * delta)
		"charge":
			match state:
				"idle":
					if chasing and dist < aggro * 0.9:
						state = "wind"
						state_t = 0.5
						charge_dir = to_hero.normalized()
						move_vel = Vector2.ZERO
						flash(Color(1, 0.4, 0.3), 0.45)
					else:
						_wander(delta, from_home)
				"wind":
					move_vel = Vector2.ZERO
					sprite.position.x = sin(anim_t * 60.0) * 1.0
					if state_t <= 0.0:
						state = "run"
						state_t = 0.45
						sprite.position.x = 0
				"run":
					move_vel = charge_dir * speed * 3.4
					if state_t <= 0.0 or get_slide_collision_count() > 0:
						state = "rest"
						state_t = 0.9
				"rest":
					move_vel = move_vel.move_toward(Vector2.ZERO, 600 * delta)
					if state_t <= 0.0:
						state = "idle"
		"shooter":
			if chasing:
				var want := -to_hero.normalized() if dist < 70.0 else (to_hero.normalized() if dist > 110.0 else Vector2.ZERO)
				move_vel = move_vel.move_toward(want * speed, 300 * delta)
				shoot_t -= delta
				if shoot_t <= 0.0:
					shoot_t = float(data.get("fire_rate", 2.0))
					flash(Color(1, 1, 0.6), 0.15)
					stage.spawn_bullet(center(), to_hero.normalized() * float(data.get("bullet_speed", 90)), atk, data.get("bullet_color", "a884f3"))
			else:
				_wander(delta, from_home)
		"flee":
			if dist < 110.0:
				move_vel = move_vel.move_toward(-to_hero.normalized() * speed + Vector2(cos(anim_t * 5), sin(anim_t * 4)) * 20, 600 * delta)
			else:
				_wander(delta, from_home)
		"guard":
			move_vel = move_vel.move_toward((home - global_position).limit_length(1.0) * speed, 300 * delta)
			if dist < 34.0:
				move_vel = to_hero.normalized() * speed
		"phase":
			if state_t <= 0.0:
				intangible = not intangible
				state_t = 1.1 if intangible else 1.8
				var tw2 := create_tween()
				tw2.tween_property(sprite, "modulate:a", 0.18 if intangible else 1.0, 0.25)
			if chasing:
				move_vel = move_vel.move_toward(to_hero.normalized() * speed, 200 * delta)
			else:
				_wander(delta, from_home)
		_:
			_wander(delta, from_home)


func _wander(delta: float, from_home: float) -> void:
	if think_t <= 0.0:
		think_t = randf_range(0.8, 2.2)
		if from_home > 70.0:
			move_vel = (home - global_position).normalized() * speed * 0.6
		elif randf() < 0.35:
			move_vel = Vector2.ZERO
		else:
			move_vel = Vector2.RIGHT.rotated(randf() * TAU) * speed * 0.5


func _animate(_delta: float, moving: bool) -> void:
	if ai == "hop":
		return
	if flying or ai == "flyer" or ai == "phase":
		sprite.position.y = -3.0 + sin(anim_t * 6.0) * 2.0
		shadow.scale = Vector2.ONE * (0.8 + sin(anim_t * 6.0) * 0.1)
	elif moving:
		sprite.rotation = sin(anim_t * 14.0) * 0.12
		sprite.position.y = -abs(sin(anim_t * 14.0)) * 1.5
	else:
		sprite.rotation = 0.0
		sprite.scale.y = 1.0 + sin(anim_t * 3.0) * 0.04
		sprite.position.y = 0.0
	if abs(move_vel.x) > 4.0:
		var f := str(data.get("facing", "front"))
		if f == "left":
			sprite.flip_h = move_vel.x > 0
		elif f == "right":
			sprite.flip_h = move_vel.x < 0


# ------------------------------------------------------------------ combat
func can_clash() -> bool:
	return alive and not intangible and clash_cd <= 0.0


func is_open() -> bool:
	## Counter-type monsters (spiky, armoured chargers) hit back on any bump,
	## dashes included, except while winding up or resting after a charge.
	if not counter:
		return true
	return state in ["wind", "rest"]


func _counter_glow() -> void:
	if is_open():
		var k := 0.5 + 0.5 * sin(anim_t * 20.0)
		sprite.modulate = Color(1.0 + 0.3 * k, 1.0 + 0.3 * k, 0.9, sprite.modulate.a)
	else:
		sprite.modulate = Color(0.92, 0.92, 1.0, sprite.modulate.a)


func take_hit(dmg: int, dir: Vector2, crit: bool) -> bool:
	hp -= dmg
	hit_show = 2.5
	var kb := 150.0 if not is_boss else 30.0
	knock = dir.normalized() * kb * (1.4 if crit else 1.0)
	flash(Color.WHITE, 0.1)
	sprite.scale = Vector2(1.3, 0.75) if not is_boss else Vector2(1.08, 0.94)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hp <= 0:
		die()
		return true
	return false


func flash(col: Color, dur := 0.1) -> void:
	var m := sprite.material as ShaderMaterial
	m.set_shader_parameter("flash_color", col)
	m.set_shader_parameter("flash", 1.0)
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_method(func(v: float): m.set_shader_parameter("flash", v), 1.0, 0.0, dur)


func die() -> void:
	alive = false
	hp = 0
	collision_layer = 0
	if lv_label:
		lv_label.visible = false
	if bar:
		bar.visible = false
	died.emit(self)
	var m := sprite.material as ShaderMaterial
	m.set_shader_parameter("flash_color", Color.WHITE)
	m.set_shader_parameter("flash", 1.0)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2(1.5, 0.3), 0.1)
	tw.tween_property(sprite, "scale", Vector2(0.1, 1.8), 0.08)
	tw.tween_callback(queue_free)
