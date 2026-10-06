class_name Hero
extends CharacterBody2D
## The player. Movement + dash + animation only; stats live in Stage.run.

const SPEED := 110.0
const ACCEL := 1500.0
const DASH_SPEED := 310.0
const DASH_TIME := 0.15
const DASH_CD := 0.50
const WALK_SEQ := [1, 0, 1, 2]

var stage
var sprite: Sprite2D
var shadow: Sprite2D
var facing := Vector2.DOWN
var dir_row := 0
var anim_t := 0.0
var dash_t := 0.0
var dash_grace := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.DOWN
var move_vel := Vector2.ZERO
var knock := Vector2.ZERO
var invuln := 0.0
var control := true
var frozen := 0.0
var step_t := 0.0
var after_t := 0.0
var bump_cd := {}
var input_override: Variant = null
var dash_request := false
var _flash_tw: Tween

static var _shadow_tex := {}


static func shadow_texture(w: int) -> Texture2D:
	if _shadow_tex.has(w):
		return _shadow_tex[w]
	var h: int = max(3, w / 3)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c := Vector2(w, h) * 0.5
	for y in h:
		for x in w:
			var d := Vector2((x + 0.5 - c.x) / c.x, (y + 0.5 - c.y) / c.y)
			if d.length() <= 1.0:
				img.set_pixel(x, y, Color(0.12, 0.08, 0.14, 0.38))
	var t := ImageTexture.create_from_image(img)
	_shadow_tex[w] = t
	return t


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 5.0
	cs.shape = c
	cs.position = Vector2(0, -4)
	add_child(cs)
	shadow = Sprite2D.new()
	shadow.texture = shadow_texture(14)
	shadow.position = Vector2(0, -1)
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/sprites/chars/hero.png")
	sprite.hframes = 3
	sprite.vframes = 4
	sprite.frame = 1
	sprite.offset = Vector2(0, -13)
	sprite.material = Shaders.material("flash")
	add_child(sprite)


func get_move_input() -> Vector2:
	if input_override != null:
		return input_override
	if not control:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func is_dashing() -> bool:
	return dash_t > 0.0 or dash_grace > 0.0


func set_facing(v: Vector2) -> void:
	if v.length() < 0.1:
		return
	facing = v.normalized()
	if abs(v.x) >= abs(v.y) * 0.9:
		dir_row = 1 if v.x < 0 else 2
	else:
		dir_row = 3 if v.y < 0 else 0


func _physics_process(delta: float) -> void:
	if stage.hitstop_left > 0.0 or stage.state == "rewind":
		return
	dash_cd = max(0.0, dash_cd - delta)
	dash_grace = max(0.0, dash_grace - delta)
	invuln = max(0.0, invuln - delta)
	for k in bump_cd.keys():
		bump_cd[k] -= delta
		if bump_cd[k] <= 0:
			bump_cd.erase(k)
	var active: bool = stage.world_active()
	var inp := get_move_input() if active else Vector2.ZERO
	if frozen > 0.0:
		frozen -= delta
		inp = Vector2.ZERO
	if inp.length() > 0.2:
		set_facing(inp)
	# X is also "cancel": ignore the press that just closed a menu or dialogue
	var fresh_input: bool = Time.get_ticks_msec() - int(stage.unpause_ms) > 160
	var want_dash := active and control and frozen <= 0.0 and ((Input.is_action_just_pressed("dash") and fresh_input) or dash_request)
	dash_request = false
	if want_dash and dash_cd <= 0.0:
		_start_dash(inp)
	if dash_t > 0.0:
		dash_t -= delta
		if dash_t <= 0.0:
			dash_grace = 0.08
		move_vel = dash_dir * DASH_SPEED
		after_t -= delta
		if after_t <= 0.0:
			after_t = 0.03
			stage.fx.afterimage(sprite)
	else:
		var target: Vector2 = inp * SPEED * float(stage.hero_speed_mul())
		move_vel = move_vel.move_toward(target, ACCEL * delta)
	velocity = move_vel + knock
	knock = knock.move_toward(Vector2.ZERO, 1000.0 * delta)
	move_and_slide()
	if active:
		for i in get_slide_collision_count():
			var col = get_slide_collision(i).get_collider()
			if col and col.has_method("on_bump"):
				var id: int = col.get_instance_id()
				if not bump_cd.has(id):
					bump_cd[id] = 0.35
					col.on_bump(self)
	_animate(delta)


func _start_dash(inp: Vector2) -> void:
	dash_dir = inp.normalized() if inp.length() > 0.2 else facing
	set_facing(dash_dir)
	dash_t = DASH_TIME
	dash_cd = DASH_CD
	after_t = 0.0
	Audio.sfx("dash", -3.0, 1.0, 0.08)
	stage.fx.emit(global_position + Vector2(0, -2), 6, [Color("c7dcd0"), Color("9babb2")], 45.0, 0.3, 2.0, 0.0, -dash_dir, 1.4)
	sprite.scale = Vector2(1.25, 0.8)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


var _lunge_tw: Tween


func lunge(dir: Vector2) -> void:
	## tiny forward jab on every hit so the hero visibly "attacks"
	set_facing(dir)
	if _lunge_tw and _lunge_tw.is_valid():
		_lunge_tw.kill()
	sprite.position.x = clampf(dir.x * 3.0, -3.0, 3.0)
	sprite.rotation = clampf(dir.x * 0.18, -0.18, 0.18)
	_lunge_tw = create_tween().set_parallel(true)
	_lunge_tw.tween_property(sprite, "position:x", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tw.tween_property(sprite, "rotation", 0.0, 0.12)


func hurt(dir: Vector2, strength := 170.0) -> void:
	invuln = 0.55
	knock = dir.normalized() * strength
	flash(Color(1, 0.25, 0.25), 0.14)
	sprite.scale = Vector2(0.8, 1.2)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)


func flash(col: Color, dur := 0.1) -> void:
	var m := sprite.material as ShaderMaterial
	m.set_shader_parameter("flash_color", col)
	m.set_shader_parameter("flash", 1.0)
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_method(func(v: float): m.set_shader_parameter("flash", v), 1.0, 0.0, dur)


func _animate(delta: float) -> void:
	var moving := move_vel.length() > 14.0 or dash_t > 0.0
	if moving:
		anim_t += delta * (14.0 if dash_t > 0.0 else 9.0)
		sprite.frame = dir_row * 3 + WALK_SEQ[int(anim_t) % 4]
		step_t -= delta
		if step_t <= 0.0:
			step_t = 0.24
			stage.fx.emit(global_position + Vector2(randf_range(-3, 3), -1), 2, [Color("c7dcd0"), Color("ab947a")], 18.0, 0.28, 1.0, -10.0, Vector2.UP, 1.6)
			Audio.sfx("step", -16.0, 1.0, 0.15)
	else:
		anim_t = 0.0
		sprite.frame = dir_row * 3 + 1
	sprite.position.y = -1.0 if (moving and int(anim_t) % 2 == 1) else 0.0
	if invuln > 0.0:
		sprite.visible = int(invuln * 30.0) % 2 == 0
	else:
		sprite.visible = true
	if frozen > 0.0:
		sprite.modulate = Color(0.6, 0.7, 1.0)
	else:
		sprite.modulate = Color.WHITE


func celebrate() -> void:
	dir_row = 0
	sprite.frame = 1
	var tw := create_tween()
	tw.tween_property(sprite, "position:y", -10.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(sprite, "position:y", -6.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
