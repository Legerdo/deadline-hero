extends Node
## Root node: owns the current screen and the global fade layer.

const SCREENS := {
	"title": "res://scripts/ui/title_screen.gd",
	"worldmap": "res://scripts/ui/world_map.gd",
	"stage": "res://scripts/game/stage.gd",
	"ending": "res://scripts/ui/ending_screen.gd",
}

var current: Node
var fade_layer: CanvasLayer
var fade: ColorRect
var busy := false


func _ready() -> void:
	Game.main = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 100
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Game.BG
	fade.size = Game.VIEW
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade)
	var start := "title"
	if Game.dbg.stage != "":
		start = "stage"
		Game.params = {"id": Game.dbg.stage}
		if Game.dbg.loop > 0:
			Game.stage_mem(Game.dbg.stage).loops = Game.dbg.loop - 1
	elif Game.dbg.screen != "":
		start = Game.dbg.screen
	_swap(start)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.4)


func change_screen(screen: String, fade_time := 0.22) -> void:
	if busy:
		return
	busy = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, fade_time)
	await tw.finished
	_swap(screen)
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(fade, "color:a", 0.0, fade_time)
	busy = false


func _swap(screen: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if is_instance_valid(current):
		current.queue_free()
	var scr: GDScript = load(SCREENS[screen])
	current = scr.new()
	current.name = screen.capitalize()
	add_child(current)
	move_child(current, 0)
