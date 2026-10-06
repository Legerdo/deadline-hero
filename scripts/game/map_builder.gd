class_name MapBuilder
extends RefCounted
## Turns an ASCII map into TileMapLayers.
##   .  floor        ,  floor + decor      :  path          ~  liquid (solid)
##   T  trees/rocks (solid blob)           #  wall (solid)  =  bridge
##   %  broken bridge (solid)              ^  secret passage (looks like T, walkable)
## Any other character is an entity marker (see stage "markers"), floor underneath.

const T := 16
const TERRAIN := ".,:~T#=%^"
const SOLID := "~T#%"

var w := 0
var h := 0
var cells: Array = []          # Array[PackedByteArray-ish] of single-char Strings per row
var markers: Dictionary = {}   # char -> Array[Vector2i]
var root: Node2D
var ts: TileSet
var floor_l: TileMapLayer
var path_l: TileMapLayer
var liquid_l: TileMapLayer
var blob_l: TileMapLayer
var secret_l: TileMapLayer
var wall_l: TileMapLayer
var bridge_l: TileMapLayer
var col_l: TileMapLayer
var theme := "village"
var under := {}


func build(parent: Node2D, lines: PackedStringArray, theme_name: String, marker_under: Dictionary) -> void:
	theme = theme_name
	parse(lines, marker_under)
	root = Node2D.new()
	root.name = "Tiles"
	parent.add_child(root)
	_make_tileset()
	floor_l = _layer("floor", -20, Vector2.ZERO)
	path_l = _layer("path", -19, Vector2(-8, -8))
	liquid_l = _layer("liquid", -18, Vector2(-8, -8))
	bridge_l = _layer("bridge", -17, Vector2.ZERO)
	wall_l = _layer("wall", -16, Vector2.ZERO)
	blob_l = _layer("blob", -15, Vector2(-8, -8))
	secret_l = _layer("secret", 5, Vector2(-8, -8))
	col_l = _layer("collision", -30, Vector2.ZERO)
	col_l.collision_enabled = true
	col_l.self_modulate = Color(1, 1, 1, 0)
	for y in h:
		for x in w:
			_paint_floor(x, y)
			_paint_cell(x, y)
	for y in h + 1:
		for x in w + 1:
			_paint_dual(x, y)


## Data-only pass (no nodes): terrain grid + entity markers. Used by build()
## and by the automated tests.
func parse(lines: PackedStringArray, marker_under: Dictionary) -> void:
	under = marker_under
	h = lines.size()
	w = 0
	for l in lines:
		w = max(w, l.length())
	cells.clear()
	markers.clear()
	for y in h:
		var row: Array = []
		var l: String = lines[y]
		for x in w:
			var ch := l[x] if x < l.length() else "T"
			if not TERRAIN.contains(ch):
				if not markers.has(ch):
					markers[ch] = []
				markers[ch].append(Vector2i(x, y))
				ch = "?"
			row.append(ch)
		cells.append(row)
	# markers sit on whatever walkable terrain surrounds them (path, floor, bridge)
	for ch in markers:
		for c in markers[ch]:
			var fixed := str(under.get(ch, ""))
			if fixed == "":
				fixed = _guess_under(c.x, c.y, lines)
			cells[c.y][c.x] = fixed


func _guess_under(x: int, y: int, lines: PackedStringArray) -> String:
	var counts := {".": 0, ":": 0, "=": 0, "#": 0}
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var xx: int = x + d.x
		var yy: int = y + d.y
		if yy < 0 or yy >= lines.size() or xx < 0 or xx >= lines[yy].length():
			continue
		var c := lines[yy][xx]
		if c == ",":
			c = "."
		if counts.has(c):
			counts[c] += 1
	if counts["="] >= 2:
		return "="
	if counts[":"] >= 3:
		return ":"
	return "."


func _make_tileset() -> void:
	ts = TileSet.new()
	ts.tile_size = Vector2i(T, T)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/tiles/%s.png" % theme)
	src.texture_region_size = Vector2i(T, T)
	for y in 4:
		for x in 16:
			src.create_tile(Vector2i(x, y))
	for x in 16:
		var c := Vector2i(x, 4)
		src.create_tile(c)
		src.set_tile_animation_columns(c, 1)
		src.set_tile_animation_frames_count(c, 3)
		for f in 3:
			src.set_tile_animation_frame_duration(c, f, 0.3)
	ts.add_source(src, 0)
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var csrc := TileSetAtlasSource.new()
	csrc.texture = ImageTexture.create_from_image(img)
	csrc.texture_region_size = Vector2i(T, T)
	csrc.create_tile(Vector2i.ZERO)
	ts.add_source(csrc, 1)
	var td := csrc.get_tile_data(Vector2i.ZERO, 0)
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]))


func _layer(n: String, z: int, off: Vector2) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.name = n
	l.tile_set = ts
	l.z_index = z
	l.position = off
	l.collision_enabled = false
	l.y_sort_enabled = false
	root.add_child(l)
	return l


func cell(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= w or y >= h:
		return "T"
	return cells[y][x]


func is_solid(x: int, y: int) -> bool:
	return SOLID.contains(cell(x, y))


func solid_at(p: Vector2) -> bool:
	return is_solid(int(floor(p.x / T)), int(floor(p.y / T)))


func terrain_at(p: Vector2) -> String:
	return cell(int(floor(p.x / T)), int(floor(p.y / T)))


func _hash(x: int, y: int) -> int:
	return abs((x * 73856093) ^ (y * 19349663)) % 1000


func _paint_floor(x: int, y: int) -> void:
	var c := cell(x, y)
	var v := _hash(x, y)
	var col := v % 4
	if v % 11 == 0:
		col = 3
	elif v % 3 == 0:
		col = 1
	elif v % 5 == 0:
		col = 2
	else:
		col = 0
	if c == ",":
		floor_l.set_cell(Vector2i(x, y), 0, Vector2i(4 + v % 4, 0))
	else:
		floor_l.set_cell(Vector2i(x, y), 0, Vector2i(col, 0))


func _paint_cell(x: int, y: int) -> void:
	var c := cell(x, y)
	var p := Vector2i(x, y)
	bridge_l.erase_cell(p)
	wall_l.erase_cell(p)
	col_l.erase_cell(p)
	if c == "=" or c == "%":
		var vertical := (cell(x, y - 1) in ["=", "%"] or cell(x, y + 1) in ["=", "%"]) and not (cell(x - 1, y) in ["=", "%"] or cell(x + 1, y) in ["=", "%"])
		if c == "%":
			bridge_l.set_cell(p, 0, Vector2i(11 if vertical else 10, 0))
		else:
			bridge_l.set_cell(p, 0, Vector2i(9 if vertical else 8, 0))
	elif c == "#":
		if cell(x, y + 1) != "#":
			wall_l.set_cell(p, 0, Vector2i(12 + _hash(x, y) % 4, 0))
		else:
			var m := 0
			if cell(x, y - 1) == "#":
				m |= 1
			if cell(x + 1, y) == "#":
				m |= 2
			if cell(x, y + 1) == "#":
				m |= 4
			if cell(x - 1, y) == "#":
				m |= 8
			wall_l.set_cell(p, 0, Vector2i(m, 3))
	if SOLID.contains(c):
		col_l.set_cell(p, 1, Vector2i.ZERO)


func _mask(x: int, y: int, chars: String) -> int:
	var m := 0
	if chars.contains(cell(x - 1, y - 1)):
		m |= 1
	if chars.contains(cell(x, y - 1)):
		m |= 2
	if chars.contains(cell(x - 1, y)):
		m |= 4
	if chars.contains(cell(x, y)):
		m |= 8
	return m


func _paint_dual(x: int, y: int) -> void:
	var p := Vector2i(x, y)
	var m := _mask(x, y, ":")
	if m:
		path_l.set_cell(p, 0, Vector2i(m, 1))
	else:
		path_l.erase_cell(p)
	m = _mask(x, y, "~=%")
	if m:
		liquid_l.set_cell(p, 0, Vector2i(m, 4))
	else:
		liquid_l.erase_cell(p)
	m = _mask(x, y, "T")
	if m:
		blob_l.set_cell(p, 0, Vector2i(m, 2))
	else:
		blob_l.erase_cell(p)
	m = _mask(x, y, "^T")
	var ms := _mask(x, y, "^")
	if ms:
		secret_l.set_cell(p, 0, Vector2i(m, 2))
	else:
		secret_l.erase_cell(p)


func set_terrain(x: int, y: int, ch: String) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	cells[y][x] = ch
	for yy in range(y - 1, y + 2):
		for xx in range(x - 1, x + 2):
			if xx >= 0 and yy >= 0 and xx < w and yy < h:
				_paint_floor(xx, yy)
				_paint_cell(xx, yy)
	for yy in range(y, y + 2):
		for xx in range(x, x + 2):
			_paint_dual(xx, yy)


func flood_cells(start: Vector2i, ch: String) -> Array:
	## connected cells of the same terrain char (4-neighbour)
	var out: Array = []
	var seen := {}
	var stack: Array = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if seen.has(c) or cell(c.x, c.y) != ch:
			continue
		seen[c] = true
		out.append(c)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(c + d)
	return out


func marker_pos(ch: String, i := 0) -> Vector2:
	## world position (bottom-centre of the cell) for an entity marker
	var arr: Array = markers.get(ch, [])
	if arr.is_empty():
		return Vector2.ZERO
	var c: Vector2i = arr[min(i, arr.size() - 1)]
	return Vector2(c.x * T + 8, c.y * T + 14)


func minimap_image() -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pal := {
		".": Color("239063"), ",": Color("239063"), ":": Color("ab947a"), "~": Color("4d65b4"),
		"T": Color("165a4c"), "#": Color("3e3546"), "=": Color("cd683d"), "%": Color("6e2727"), "^": Color("165a4c"),
	}
	match theme:
		"cave", "volcano":
			pal["."] = Color("694f62")
			pal[","] = Color("694f62")
			pal["T"] = Color("3e3546")
			pal["~"] = Color("ea4f36") if theme == "volcano" else Color("2e222f")
		"manor":
			pal["."] = Color("7a3045")
			pal[","] = Color("7a3045")
			pal[":"] = Color("ae2334")
		"temple":
			pal["."] = Color("0b8a8f")
			pal[","] = Color("0b8a8f")
			pal[":"] = Color("c7dcd0")
			pal["~"] = Color("30e1b9")
		"tower":
			pal["."] = Color("484a77")
			pal[","] = Color("484a77")
			pal[":"] = Color("f9c22b")
			pal["~"] = Color("2e222f")
		"forest":
			pal["."] = Color("547e64")
			pal[","] = Color("547e64")
			pal["T"] = Color("374e4a")
	for y in h:
		for x in w:
			img.set_pixel(x, y, pal.get(cell(x, y), Color("239063")))
	return img
