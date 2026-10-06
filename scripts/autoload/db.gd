extends Node
## Data access: all game content lives in res://data as JSON / text so new
## stages, enemies, items and NPCs can be added without touching code.

var items: Dictionary = {}
var enemies: Dictionary = {}
var campaign: Dictionary = {}
var voice_lines: Dictionary = {}
var _stages: Dictionary = {}


func _ready() -> void:
	items = _json("res://data/items.json")
	enemies = _json("res://data/enemies.json")
	campaign = _json("res://data/campaign.json")
	voice_lines = _json("res://data/voice_lines.json")


func line(id: String) -> Dictionary:
	return voice_lines.get(id, {})


func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("missing data file " + path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		return d
	push_error("bad json " + path)
	return {}


func item(id: String) -> Dictionary:
	return items.get(id, {"name": id, "type": "key", "icon": ""})


func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})


func stage(id: String) -> Dictionary:
	if not _stages.has(id):
		_stages[id] = _json("res://data/stages/%s.json" % id)
	return _stages[id]


func stage_ids() -> Array:
	return campaign.get("stages", [])


func stage_index(id: String) -> int:
	return stage_ids().find(id) + 1


func map_lines(path: String) -> PackedStringArray:
	var txt := FileAccess.get_file_as_string(path)
	var out := PackedStringArray()
	for l in txt.split("\n"):
		var s := l.rstrip("\r")
		if s.begins_with(";"):
			continue
		out.append(s)
	while out.size() > 0 and out[out.size() - 1].strip_edges() == "":
		out.remove_at(out.size() - 1)
	return out
