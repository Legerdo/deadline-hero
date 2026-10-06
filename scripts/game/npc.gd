class_name NPC
extends StaticBody2D
## Town character. Bump into them (or press Z nearby) to talk.
## A teal "echo" bubble means they remember you from an earlier loop.

var stage
var id := ""
var def: Dictionary = {}
var sprite: Sprite2D
var bubble: Sprite2D
var t := 0.0
var tex_h := 24.0


func setup(npc_id: String, d: Dictionary) -> void:
	id = npc_id
	def = d


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(12, 8)
	cs.shape = r
	cs.position = Vector2(0, -4)
	add_child(cs)
	var sh := Sprite2D.new()
	sh.texture = Hero.shadow_texture(14)
	sh.position = Vector2(0, -1)
	add_child(sh)
	sprite = Sprite2D.new()
	var tex: Texture2D = load("res://assets/sprites/chars/%s.png" % def.get("sprite", "npc_kid"))
	sprite.texture = tex
	tex_h = tex.get_height()
	sprite.offset = Vector2(0, -tex_h * 0.5)
	sprite.flip_h = bool(def.get("flip", false))
	if def.get("ghostly", false):
		sprite.modulate = Color(1, 1, 1, 0.8)
	add_child(sprite)
	bubble = Sprite2D.new()
	bubble.position = Vector2(0, -tex_h - 7)
	bubble.visible = false
	add_child(bubble)
	t = randf() * 5.0


func _process(delta: float) -> void:
	t += delta
	prompt_cd -= delta
	sprite.scale.y = 1.0 + sin(t * 2.4) * 0.03
	var ind: String = stage.npc_indicator(self) if stage else ""
	if ind == "":
		bubble.visible = false
	else:
		bubble.visible = true
		bubble.texture = load("res://assets/ui/icon_%s.png" % ind)
		bubble.position.y = -tex_h - 7 + sin(t * 5.0) * 1.5


var prompt_cd := 0.0


func on_bump(_hero) -> void:
	# First contact in a loop talks immediately (fast). Afterwards bumping only
	# shows a prompt so walking past a shopkeeper never traps the player.
	if not stage.flags.has("talked:" + id) or stage.npc_indicator(self) in ["excl", "echo"]:
		stage.talk_to(self)
	elif prompt_cd <= 0.0:
		prompt_cd = 1.5
		stage.fx.popup(global_position + Vector2(0, -tex_h - 10), "Z: 대화", Color("c7dcd0"), false, 6.0, 0.6)


func hop() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "position:y", -5.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
