class_name Prop
extends StaticBody2D
## Map objects: decoration, chests, time statues, gates, levers, plates,
## cracked walls, bridge sites, warps, pickups, crystals, carts and pots.

const DEFS := {
	"house_red": {"tex": "props/house_red", "box": Vector2(44, 24)},
	"house_blue": {"tex": "props/house_blue", "box": Vector2(44, 24)},
	"tree": {"tex": "props/tree", "box": Vector2(10, 8)},
	"pine": {"tex": "props/pine", "box": Vector2(8, 8)},
	"boulder": {"tex": "props/boulder", "box": Vector2(16, 11)},
	"bush": {"tex": "props/bush", "box": Vector2(12, 8)},
	"well": {"tex": "props/well", "box": Vector2(20, 12)},
	"tomb": {"tex": "props/tomb", "box": Vector2(12, 8)},
	"bell": {"tex": "props/bell", "box": Vector2(40, 10)},
	"sign": {"tex": "props/sign", "box": Vector2(10, 6)},
	"chest": {"tex": "props/chest", "box": Vector2(14, 10)},
	"statue": {"tex": "props/cat_statue", "box": Vector2(12, 8)},
	"pot": {"tex": "props/pot", "box": Vector2(10, 8)},
	"torch": {"tex": "props/torch", "box": Vector2.ZERO, "light": 80.0},
	"cart": {"tex": "props/minecart", "box": Vector2(16, 10)},
	"gate": {"tex": "props/gate_closed", "box": Vector2(16, 14)},
	"lever": {"tex": "props/lever_off", "box": Vector2(10, 8)},
	"plate": {"tex": "props/plate_off", "box": Vector2.ZERO},
	"crack": {"tex": "props/crack", "box": Vector2(16, 16)},
	"crystal": {"tex": "props/crystal_off", "box": Vector2(10, 8)},
	"bridge": {"tex": "props/planks_site", "box": Vector2(16, 16)},
	"warp": {"tex": "props/portal", "box": Vector2.ZERO, "light": 60.0},
	"pickup": {"tex": "", "box": Vector2.ZERO},
	"blocker": {"tex": "", "box": Vector2(16, 16)},
}

var stage
var kind := ""
var pid := ""
var def: Dictionary = {}
var sprite: Sprite2D
var shape: CollisionShape2D
var used := false
var is_open := false
var pressed := false
var t := 0.0
var light := 0.0
var touch_radius := 10.0


func setup(k: String, d: Dictionary) -> void:
	kind = k
	def = d
	pid = str(d.get("id", ""))


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var info: Dictionary = DEFS.get(kind, {"tex": "", "box": Vector2(16, 16)})
	var box: Vector2 = info.box
	if def.has("box"):
		box = Vector2(def.box[0], def.box[1])
	if box != Vector2.ZERO:
		shape = CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = box
		shape.shape = r
		shape.position = Vector2(0, -box.y * 0.5 + 1)
		if kind in ["crack", "bridge", "blocker", "gate"]:
			shape.position = Vector2(0, -6)
		add_child(shape)
	var tex_name: String = str(def.get("tex", info.tex))
	if kind == "pickup":
		tex_name = "items/" + str(def.get("icon", def.get("item", "hourglass")))
	if tex_name != "":
		sprite = Sprite2D.new()
		sprite.texture = load("res://assets/sprites/%s.png" % tex_name)
		var th := sprite.texture.get_height()
		sprite.offset = Vector2(0, -th * 0.5 + 2)
		if kind == "plate":
			sprite.offset = Vector2(0, -7)
			sprite.z_index = -5
		if kind == "torch":
			sprite.offset = Vector2(0, -14)
		if kind == "warp":
			sprite.offset = Vector2.ZERO
			sprite.position = Vector2(0, -6)
			sprite.z_index = -4
		sprite.material = Shaders.material("flash")
		add_child(sprite)
		if kind in ["house_red", "house_blue", "tree", "pine", "bell", "well", "statue", "boulder", "tomb", "crystal", "cart"]:
			var sh := Sprite2D.new()
			sh.texture = Hero.shadow_texture(int(clamp(sprite.texture.get_width() * 0.8, 8, 50)))
			sh.position = Vector2(0, 0)
			sh.z_index = -1
			add_child(sh)
			move_child(sh, 0)
	light = float(info.get("light", 0.0))
	t = randf() * 5.0
	if kind == "pickup":
		touch_radius = 12.0
	if kind == "warp":
		touch_radius = 9.0


func _process(delta: float) -> void:
	t += delta
	if kind == "pickup" and sprite:
		sprite.position.y = -3.0 + sin(t * 4.0) * 2.0
		if int(t * 6.0) % 5 == 0:
			stage.fx.emit(global_position + Vector2(randf_range(-5, 5), -8), 1, [Color("fbff86"), Color("ffffff")], 10.0, 0.5, 1.0, -20.0)
	elif kind == "torch" and sprite:
		sprite.scale = Vector2(1.0 + sin(t * 17.0) * 0.06, 1.0 + sin(t * 13.0) * 0.08)
	elif kind == "warp" and sprite:
		sprite.rotation = t * 2.0
		sprite.scale = Vector2.ONE * (1.0 + sin(t * 4.0) * 0.08)
		if int(t * 10.0) % 3 == 0:
			stage.fx.emit(global_position + Vector2(randf_range(-6, 6), -6), 1, [Color("30e1b9"), Color("8ff8e2")], 20.0, 0.6, 1.0, -30.0)
	elif kind == "statue" and sprite:
		if int(t * 2.0) % 4 == 0:
			sprite.modulate = Color(1.15, 1.1, 0.9)
		else:
			sprite.modulate = Color.WHITE


func set_texture(tex_name: String) -> void:
	if sprite:
		sprite.texture = load("res://assets/sprites/%s.png" % tex_name)
		var th := sprite.texture.get_height()
		sprite.offset = Vector2(0, -th * 0.5 + 2)
		if kind == "plate":
			sprite.offset = Vector2(0, -7)


func set_solid(on: bool) -> void:
	collision_layer = 1 if on else 0


func pop() -> void:
	if sprite == null:
		return
	sprite.scale = Vector2(1.3, 0.75)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func flash(col := Color.WHITE, dur := 0.12) -> void:
	if sprite == null:
		return
	var m := sprite.material as ShaderMaterial
	m.set_shader_parameter("flash_color", col)
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("flash", v), 1.0, 0.0, dur)


func on_bump(hero) -> void:
	stage.prop_bump(self, hero)


func vanish() -> void:
	set_solid(false)
	if sprite:
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.25)
		tw.tween_callback(queue_free)
	else:
		queue_free()
