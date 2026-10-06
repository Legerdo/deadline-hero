class_name StageBot
extends Node
## Automated playtester (--bot). It only uses information a player sees:
## the objective arrow, the objective text and visible enemies. If it can
## finish a stage, the guidance is sufficient. Also used for balance logs.

var s  # Stage
var astar: AStarGrid2D
var path: PackedVector2Array = PackedVector2Array()
var path_i := 0
var repath_t := 0.0
var target = null
var target_pos := Vector2.ZERO
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var mode := ""
var ignore := {}
var wait_plate := 0.0
var log_t := 0.0
var interact_t := 0.0


func _init(stage) -> void:
	s = stage


func build_grid() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, s.map.w, s.map.h)
	astar.cell_size = Vector2(16, 16)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	refresh_solids()


func on_terrain_changed() -> void:
	## called by the stage after floods / repairs: rebuild solids and re-route now
	if astar == null:
		return
	refresh_solids()
	path = PackedVector2Array()
	path_i = 0
	repath_t = 0.0


func refresh_solids() -> void:
	for y in s.map.h:
		for x in s.map.w:
			astar.set_point_solid(Vector2i(x, y), s.map.is_solid(x, y))
	for n in s.npcs.values():
		if is_instance_valid(n):
			var nc := cell_of(n.global_position)
			if astar.region.has_point(nc):
				astar.set_point_solid(nc, true)
	for p in s.props:
		if not is_instance_valid(p) or p.collision_layer == 0 or p.shape == null:
			continue
		var r: RectangleShape2D = p.shape.shape
		var c: Vector2 = p.global_position + p.shape.position
		var x0 := int(floor((c.x - r.size.x * 0.5 + 2) / 16.0))
		var x1 := int(floor((c.x + r.size.x * 0.5 - 2) / 16.0))
		var y0 := int(floor((c.y - r.size.y * 0.5 + 2) / 16.0))
		var y1 := int(floor((c.y + r.size.y * 0.5 - 2) / 16.0))
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				if astar.region.has_point(Vector2i(xx, yy)):
					astar.set_point_solid(Vector2i(xx, yy), true)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / 16.0), 0, s.map.w - 1), clampi(int((p.y - 4) / 16.0), 0, s.map.h - 1))


func find_path(to: Vector2) -> PackedVector2Array:
	var a := cell_of(s.hero.global_position)
	var b := cell_of(to)
	var was_a := astar.is_point_solid(a)
	var was_b := astar.is_point_solid(b)
	astar.set_point_solid(a, false)
	astar.set_point_solid(b, false)
	var pts := astar.get_point_path(a, b, true)
	astar.set_point_solid(a, was_a)
	astar.set_point_solid(b, was_b)
	return pts


func path_len(to: Vector2) -> float:
	var p := find_path(to)
	if p.is_empty():
		return INF
	return p.size() * 16.0


func tick(delta: float) -> void:
	if astar == null:
		build_grid()
	var h: Hero = s.hero
	log_t -= delta
	repath_t -= delta
	if wait_plate > 0.0:
		wait_plate -= delta
		h.input_override = Vector2.ZERO
		return
	if target != null and not is_instance_valid(target):
		target = null
		repath_t = 0.0
	if repath_t <= 0.0:
		repath_t = 0.35
		_choose()
	if target_pos == Vector2.ZERO:
		h.input_override = Vector2.ZERO
		return
	# follow path
	while path_i < path.size() and h.global_position.distance_to(path[path_i] + Vector2(8, 12)) < 7.0:
		path_i += 1
	var goal: Vector2 = target_pos
	if path_i < path.size() - 1:
		goal = path[path_i] + Vector2(8, 12)
	var d := goal - h.global_position
	h.input_override = d.normalized() if d.length() > 2.0 else Vector2.ZERO
	if target != null and target is Enemy and not target.is_boss and target.intangible:
		ignore[target] = 1.5
		repath_t = 0.0
	var engaged_boss: bool = target != null and target is Boss and target.engaged and mode != "peace"
	if engaged_boss:
		path = PackedVector2Array()
		path_i = 0
	# fight
	if engaged_boss:
		_boss_tactics(h, target)
	elif target != null and target is Enemy and target.counter and not target.is_open() and h.global_position.distance_to(target.global_position) < 60.0:
		# counter-type monster: hover just outside reach until it winds up / rests (it glows)
		var away: Vector2 = h.global_position - target.global_position
		h.input_override = away.normalized().rotated(0.9) if away.length() < 44.0 else away.normalized().rotated(PI * 0.5)
	elif target != null and target is Enemy and h.global_position.distance_to(target.global_position) < 44.0 and h.dash_cd <= 0.0:
		h.input_override = (target.global_position - h.global_position).normalized()
		h.dash_request = true
	else:
		# anything blocking the way gets dashed through, like a player would
		for e in s.enemies:
			if is_instance_valid(e) and e.alive and not e.is_boss and h.global_position.distance_to(e.global_position) < 30.0 and h.dash_cd <= 0.0:
				h.input_override = (e.global_position - h.global_position).normalized()
				h.dash_request = true
				break
	# time stop: dash on the purple flash (what the tips teach)
	if s.time_stop_warn > 0.0 and s.time_stop_warn < 0.25 and h.dash_cd <= 0.0:
		h.dash_request = true
	# press Z at objectives (NPCs we already met only answer to the button)
	interact_t -= delta
	if mode == "goal" and interact_t <= 0.0 and h.global_position.distance_to(target_pos) < 24.0:
		interact_t = 0.8
		s._interact_near()
	# stuck detection
	if h.global_position.distance_to(last_pos) < 0.6:
		stuck_t += delta
		if stuck_t > 0.8:
			stuck_t = 0.0
			refresh_solids()
			# drop the old route too, otherwise _set_target keeps walking a path
			# that runs through terrain which changed (e.g. S6 lava floods)
			path = PackedVector2Array()
			path_i = 0
			repath_t = 0.0
			h.input_override = Vector2.RIGHT.rotated(randf() * TAU)
			if target != null:
				ignore[target] = 3.0
	else:
		stuck_t = 0.0
	last_pos = h.global_position
	for k in ignore.keys():
		ignore[k] -= delta
		if ignore[k] <= 0.0 or not is_instance_valid(k):
			ignore.erase(k)


func _scenario_plates() -> bool:
	## S4 test: loop 1 = stand on plate A then rewind; loop 2 = take plate B
	## while the echo holds A, grab the locket, return it to the countess.
	var pa = s.props_by_id.get("pa")
	var pb = s.props_by_id.get("pb")
	if s.loop_idx == 1:
		if pa and s.hero.global_position.distance_to(pa.global_position) < 6.0:
			target_pos = pa.global_position
			if s.play_time > 16.0 and s.state == "play":
				print("[bot] scenario: rewinding after waiting on plate A")
				s.rewind("manual")
			return true
		_set_target(null, pa.global_position, "plateA")
		return true
	if not s.mem.shortcuts.has("gallery"):
		if pb:
			_set_target(null, pb.global_position, "plateB")
		return true
	var lk = s.props_by_id.get("l")
	if int(s.run.items.get("locket", 0)) == 0:
		for p in s.props:
			if is_instance_valid(p) and p.kind == "pickup" and str(p.def.get("item", "")) == "locket":
				_set_target(null, p.global_position, "locket")
				return true
	if s.boss and s.boss.alive:
		_set_target(s.boss, s.boss.global_position, "peace")
		return true
	return false


func _choose() -> void:
	if Game.dbg.scenario == "plates" and _scenario_plates():
		return
	var lv := int(s.run.lv)
	var rec := int(s.sd.get("rec_level", 6))
	var goal = s.ev.objective_pos()
	var boss_ok: bool = s.boss != null and is_instance_valid(s.boss) and s.boss.alive
	var boss_pos: Vector2 = s.boss.global_position if boss_ok else Vector2.ZERO
	var go_boss: bool = boss_ok and (lv >= rec or s.time_left < 20.0 or s.boss.engaged)
	# 1) scripted objective (NPC / prop / door) the arrow is pointing at.
	#    "grind" goals mean: level up around here first, the arrow shows where to go next.
	var grind_first: bool = bool(s.ev.current_goal().get("grind", false)) and s.time_left > 25.0
	if grind_first:
		var e = _best_enemy(lv)
		if e != null:
			_set_target(e, e.global_position, "grind")
			return
	if goal != null and (boss_pos == Vector2.ZERO or goal.distance_to(boss_pos) > 4.0):
		_set_target(null, goal, "goal")
		_try_plate_wait()
		return
	# 2) boss when strong enough (or out of time) - if it is reachable on foot
	if go_boss:
		var pth := find_path(boss_pos)
		if pth.size() > 0 and Vector2(pth[pth.size() - 1]).distance_to(Vector2(cell_of(boss_pos)) * 16.0) < 20.0:
			_set_target(s.boss, boss_pos, "boss")
			return
		if goal != null:
			_set_target(null, goal, "goal")
			return
	# 3) grind: nearest enemy that is not too strong
	var best = _best_enemy(lv)
	if best != null:
		_set_target(best, best.global_position, "grind")
	elif goal != null:
		_set_target(null, goal, "goal")
	elif boss_pos != Vector2.ZERO:
		_set_target(s.boss, boss_pos, "boss")
	else:
		target_pos = Vector2.ZERO


func _best_enemy(lv: int):
	var best = null
	var best_d := INF
	for e in s.enemies:
		if not is_instance_valid(e) or not e.alive or e.is_boss:
			continue
		if ignore.has(e):
			continue
		if e.lv > lv + 2:
			continue
		var straight: float = s.hero.global_position.distance_to(e.global_position)
		if straight > 420.0:
			continue
		var weak: bool = e.lv < lv - 3
		var dd: float = straight + (200.0 if weak else 0.0)
		if dd < best_d:
			best_d = dd
			best = e
	return best


func _set_target(t, pos: Vector2, m: String) -> void:
	target = t
	mode = m
	if pos.distance_to(target_pos) > 10.0 or path.is_empty() or path_i >= path.size():
		path = find_path(pos)
		path_i = 0
	target_pos = pos
	if log_t <= 0.0:
		log_t = 5.0
		print("[bot] t=%.1f lv=%d mode=%s hp=%d gold=%d pos=%s%s -> %s path=%d/%d" % [s.play_time, int(s.run.lv), m, int(s.run.hp), int(s.run.gold), s.map.terrain_at(s.hero.global_position), cell_of(s.hero.global_position), cell_of(pos), path_i, path.size()])


func _boss_tactics(h: Hero, b: Boss) -> void:
	## Only strike during the openings the in-game tips describe; otherwise keep distance.
	var to := b.global_position - h.global_position
	var dist := to.length()
	# the same visual rule a player reads: glowing boss = opening
	var open: bool = b.dmg_mul >= 1.5 or b.state in ["stun", "exposed", "core"]
	if b.kind == "countess" and b.invulnerable:
		open = false
	if b.intangible:
		open = false
	if open:
		if b.kind == "mirror_knight" and b.blocks(-to.normalized()):
			# circle to the back
			var back: Vector2 = b.global_position - b.face * 26.0
			h.input_override = (back - h.global_position).normalized()
		else:
			h.input_override = to.normalized()
			if dist < 60.0 and h.dash_cd <= 0.0:
				h.dash_request = true
	else:
		var keep := 80.0
		if dist < keep:
			h.input_override = (-to.normalized()).rotated(0.6)
		elif dist > keep + 30.0:
			h.input_override = to.normalized()
		else:
			h.input_override = to.normalized().rotated(PI * 0.5)


func _try_plate_wait() -> void:
	## If the objective asks for the echo plate trick, stand on a plate for a while.
	for p in s.props:
		if is_instance_valid(p) and p.kind == "plate" and s.hero.global_position.distance_to(p.global_position) < 8.0:
			if not s.ghost and s.loop_idx == 1:
				wait_plate = 6.0
