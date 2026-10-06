class_name TestRunner
extends RefCounted
## Automated checks: `godot --headless --path . -- --scenario=tests`
## Prints "[test] FAIL ..." per problem and a summary line; the process exit
## code is the number of failures clamped to 1. Nothing here writes the save.

var passed := 0
var failed := 0
var warnings := 0
var _suite := ""


func run() -> int:
	_suite = "conditions"
	_test_conditions()
	_suite = "formulas"
	_test_formulas()
	_suite = "save"
	_test_save()
	_suite = "data"
	_test_global_data()
	for sid in DB.stage_ids():
		_suite = "stage " + str(sid)
		_test_stage(str(sid))
	print("[test] %d passed, %d failed, %d warnings" % [passed, failed, warnings])
	return failed


# ------------------------------------------------------------------ helpers
func ok(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("[test] FAIL %s: %s" % [_suite, what])


func eq(got, want, what: String) -> void:
	ok(got == want, "%s (got %s, want %s)" % [what, str(got), str(want)])


func warn(what: String) -> void:
	warnings += 1
	print("[test] WARN %s: %s" % [_suite, what])


# ------------------------------------------------------------------ conditions
func _fake_stage() -> Dictionary:
	# StageEvents only reads these fields, so a Dictionary stands in for Stage
	return {
		"mem": {"known": {"a": 1}, "shortcuts": {"bridge": true}, "met": {"elder": 1, "kid": 2}, "clears": 0, "boss_seen": true},
		"flags": {"f1": true, "talked:elder": true, "chest:grove": true},
		"run": {"items": {"herb": 2}, "weapon": "iron_sword", "armor": "", "lv": 4, "gold": 30, "buffs": {"rage": true}},
		"loop_idx": 2,
		"time_left": 20.0,
		"sd": {},
	}


func _test_conditions() -> void:
	var ev := StageEvents.new(_fake_stage())
	var cases := [
		["know:a", {}, true], ["!know:a", {}, false], ["know:zz", {}, false],
		["cut:bridge", {}, true], ["!cut:ferry", {}, true],
		["flag:f1", {}, true], ["flag:nope", {}, false],
		["item:herb", {}, true], ["item:herb>=2", {}, true], ["item:herb>=3", {}, false],
		["item:iron_sword", {}, true], ["item:pickaxe", {}, false],
		["lv>=4", {}, true], ["lv>=5", {}, false], ["gold>=30", {}, true], ["gold>=31", {}, false],
		["watk>=1", {}, true], ["watk>=99", {}, false],
		["loop>=2", {}, true], ["loop>=3", {}, false],
		["buff:rage", {}, true], ["buff:holy", {}, false],
		["time<=20", {}, true], ["time<=19", {}, false],
		["met", {"npc": "elder"}, true], ["met", {"npc": "kid"}, false], ["met", {"npc": "nobody"}, false],
		["talked", {"npc": "elder"}, true], ["talked:elder", {}, true], ["talked:kid", {}, false],
		["cleared", {}, false], ["boss_seen", {}, true], ["first", {}, false],
		["chest:grove", {}, true], ["open:gate", {}, false],
	]
	for c in cases:
		eq(ev.check([c[0]], c[1]), c[2], "check(%s)" % c[0])
	eq(ev.check("lv>=1"), true, "single string condition")
	eq(ev.check(["lv>=2", "gold>=10"]), true, "AND of true conditions")
	eq(ev.check(["lv>=2", "gold>=99"]), false, "AND with one false")
	eq(ev.check([]), true, "empty condition list is true")
	for good in ["know:x", "!flag:y", "item:key>=2", "lv>=5", "met", "!talked", "time<=10"]:
		ok(StageEvents.is_known_condition(good), "parser accepts '%s'" % good)
	for bad in ["knw:x", "lv>=five", "lv>=", "item:key>=x", "metx", ""]:
		ok(not StageEvents.is_known_condition(bad), "parser rejects '%s'" % bad)


# ------------------------------------------------------------------ formulas
func _test_formulas() -> void:
	var st := Stage.new()
	eq(st.exp_next(1), 12, "exp_next(1)")
	var prev := 0
	var mono := true
	for lv in range(1, 40):
		var n: int = st.exp_next(lv)
		if n <= prev:
			mono = false
		prev = n
	ok(mono, "exp_next strictly increases")
	st.loop_idx = 1
	eq(st.exp_bonus(), 1.0, "exp bonus loop 1")
	st.loop_idx = 3
	ok(is_equal_approx(st.exp_bonus(), 1.2), "exp bonus loop 3 = +20%")
	st.loop_idx = 12
	ok(is_equal_approx(st.exp_bonus(), 1.5), "exp bonus capped at +50%")
	var lo := 999
	var hi := -1
	for i in 300:
		var d: int = st._damage(10, 4)
		lo = mini(lo, d)
		hi = maxi(hi, d)
	ok(lo >= 7 and hi <= 9, "damage(10 atk, 4 def) within 7..9 (got %d..%d)" % [lo, hi])
	eq(st._damage(1, 50), 1, "damage never below 1")
	# echo inheritance: ~60% of last loop's level, 3 s per level, from loop 2 on
	st.mem = {"last_lv": 10}
	st.loop_idx = 2
	eq(st.inherit_offer(), {"lv": 6, "cost": 15.0}, "inherit Lv10 -> Lv6 for 15 s")
	st.mem = {"last_lv": 3}
	eq(st.inherit_offer(), {"lv": 2, "cost": 3.0}, "inherit floor is Lv2")
	st.mem = {"last_lv": 2}
	eq(st.inherit_offer(), {}, "no offer below Lv3")
	st.mem = {"last_lv": 10}
	st.loop_idx = 1
	eq(st.inherit_offer(), {}, "no offer on loop 1")
	var ev := StageEvents.new(_fake_stage())
	eq(ev.rank_for(1.0), "S", "rank at 100% time left")
	eq(ev.rank_for(0.0), "C", "rank at 0% time left")
	var order := "CBAS"
	var last := 0
	var rank_mono := true
	for i in 101:
		var r := order.find(ev.rank_for(i / 100.0))
		if r < last:
			rank_mono = false
		last = r
	ok(rank_mono, "rank never drops as time left grows")
	eq(UIKit.josa("불도롱뇽", "은", "는"), "불도롱뇽은", "josa after final consonant")
	eq(UIKit.josa("잿빛늑대", "은", "는"), "잿빛늑대는", "josa after open syllable")
	eq(UIKit.josa("Lv5", "은", "는"), "Lv5는", "josa on non-Hangul")
	st.free()


# ------------------------------------------------------------------ save
func _test_save() -> void:
	var v1 := {"version": 1, "settings": {"music": 0.5, "voice": 1.0, "voice_on": false}, "unlocked": 3.0,
		"stages": {"s1": {"best": 12.5, "rank": "A"}}, "cleared": {"s1": true}}
	var m := Game.migrate_save(v1)
	eq(int(m.version), Game.SAVE_VERSION, "migrated version")
	eq(float(m.settings.voice), 0.0, "v1 voice off -> volume 0")
	eq(m.settings.voice_on, false, "voice_on stays false")
	eq(float(m.settings.music), 0.5, "music kept")
	eq(typeof(m.unlocked), TYPE_INT, "unlocked coerced to int")
	eq(int(m.settings.text_speed), 1, "new setting gets its default")
	eq(m.settings.assist, false, "assist defaults off")
	eq(float(m.stages.s1.best), 12.5, "stage record kept")
	var v1on := Game.migrate_save({"version": 1, "settings": {"voice": 0.8, "voice_on": true}})
	ok(is_equal_approx(float(v1on.settings.voice), 0.8) and v1on.settings.voice_on, "v1 voice on keeps its volume")
	var junk := Game.migrate_save({"settings": "oops", "stages": [], "cleared": 5})
	ok(junk.settings is Dictionary and junk.settings.has("music"), "broken settings replaced by defaults")
	ok(junk.stages is Dictionary and junk.cleared is Dictionary, "broken containers replaced")
	# default save survives a JSON round trip unchanged
	var a := Game.migrate_save(Game.default_save())
	var b := Game.migrate_save(JSON.parse_string(JSON.stringify(Game.default_save())))
	eq(JSON.stringify(b), JSON.stringify(a), "JSON round trip")
	var again := Game.migrate_save(m)
	eq(JSON.stringify(again), JSON.stringify(m), "migration is idempotent")


# ------------------------------------------------------------------ data
func _test_global_data() -> void:
	ok(DB.stage_ids().size() >= 1, "campaign lists stages")
	for id in DB.voice_lines:
		if str(id).begins_with("_"):
			continue
		ok(ResourceLoader.exists("res://assets/audio/voice/%s.ogg" % id), "voice file for '%s'" % id)
	for k in DB.enemies:
		if str(k).begins_with("_"):
			continue
		var e: Dictionary = DB.enemies[k]
		ok(e.has("hp") or (e.has("k") and e.k is Array and e.k.size() == 5), "enemy '%s' has stats (hp or k[5])" % k)
		ok(e.has("ai") and e.has("sprite"), "enemy '%s' has ai + sprite" % k)
	var pos: Dictionary = DB.campaign.get("map_pos", {})
	for sid in DB.stage_ids():
		ok(pos.has(sid), "world map position for %s" % sid)


func _test_stage(sid: String) -> void:
	var sd := DB.stage(sid)
	ok(not sd.is_empty(), "stage json loads")
	if sd.is_empty():
		return
	var lines := DB.map_lines(str(sd.get("map", "")))
	ok(not lines.is_empty(), "map file loads")
	if lines.is_empty():
		return
	var map := MapBuilder.new()
	map.parse(lines, sd.get("under", {}))
	var specs: Dictionary = sd.get("markers", {})
	var npcs: Dictionary = sd.get("npcs", {})
	var knowledge: Dictionary = sd.get("knowledge", {})
	eq(map.markers.get("@", []).size(), 1, "exactly one hero start '@'")
	eq(map.markers.has("B"), sd.has("boss"), "boss marker 'B' matches boss data")
	if sd.has("boss"):
		ok(not DB.enemy(str(sd.boss.get("kind", ""))).is_empty(), "boss kind '%s' defined" % sd.boss.get("kind", ""))
	# every description is used (map chars are checked after the reference walk)
	for ch in specs:
		if not map.markers.has(ch):
			warn("marker '%s' is never placed on the map" % ch)
	# marker cells must stand on walkable terrain
	for ch in map.markers:
		for c in map.markers[ch]:
			ok(not map.is_solid(c.x, c.y), "marker '%s' at %s not on solid terrain" % [ch, str(c)])
	# references from marker specs
	for ch in specs:
		var sp: Dictionary = specs[ch]
		match str(sp.get("type", "")):
			"enemy":
				ok(DB.enemies.has(str(sp.get("kind", ""))), "enemy kind '%s' (marker %s)" % [sp.get("kind", ""), ch])
			"npc":
				ok(npcs.has(str(sp.get("id", ""))), "npc '%s' (marker %s) defined" % [sp.get("id", ""), ch])
			"prop":
				ok(sp.has("kind"), "prop marker %s has a kind" % ch)
				if str(sp.get("kind", "")) == "warp":
					ok(map.markers.has(str(sp.get("to", ""))), "warp %s target '%s' exists" % [ch, sp.get("to", "")])
				for pch in sp.get("path", []):
					ok(map.markers.has(str(pch)), "path point '%s' of %s exists" % [pch, ch])
	for sh in sd.get("shops", {}):
		for it in sd.shops[sh].get("items", []):
			ok(DB.items.has(str(it)), "shop %s item '%s' defined" % [sh, it])
	var start: Dictionary = sd.get("start", {})
	for slot in ["weapon", "armor"]:
		if start.has(slot):
			ok(DB.items.has(str(start[slot])), "start %s '%s' defined" % [slot, start[slot]])
	# walk the whole stage document for conditions, effects, voices and markers
	var refs := _new_refs()
	_collect(sd, refs)
	for en in refs.enemy:
		ok(DB.enemies.has(str(en)), "spawned enemy '%s' defined" % en)
	for c in refs.cond:
		ok(StageEvents.is_known_condition(str(c)), "condition '%s' is understood" % c)
	for e in refs.eff:
		ok(str(e[0]) in StageEvents.EFFECT_OPS, "effect op '%s' is known" % e[0])
	for v in refs.voice:
		ok(DB.voice_lines.has(str(v)), "voice line '%s' exists" % v)
	for mk in refs.marker:
		ok(map.markers.has(str(mk)), "referenced marker '%s' is on the map" % mk)
	# every marker char in the map is either an entity spec or a named spot that
	# the data refers to (lava zones, warp targets, goal points…)
	for ch in map.markers:
		if ch in ["@", "B"]:
			continue
		ok(specs.has(ch) or ch in refs.marker, "map char '%s' is described or referenced" % ch)
	for sh in refs.shop:
		ok(sd.get("shops", {}).has(str(sh)), "shop '%s' defined" % sh)
	for n in refs.npc:
		ok(npcs.has(str(n)), "spawned npc '%s' defined" % n)
	for k in refs.know:
		if not knowledge.has(str(k)):
			warn("knowledge '%s' has no journal text" % k)
	for k in knowledge:
		if knowledge[k].has("marker"):
			ok(map.markers.has(str(knowledge[k].marker)), "knowledge %s marker exists" % k)
	_test_reachability(sid, sd, map)


func _collect(v, refs: Dictionary, key := "") -> void:
	if v is Dictionary:
		for k in v:
			var x = v[k]
			match str(k):
				"if":
					for c in (x if x is Array else [x]):
						refs.cond.append(str(c))
					continue
				"do", "on_start", "on_boss":
					if x is Array:
						for item in x:
							if item is Array and not item.is_empty() and item[0] is String:
								_collect_effect(item, refs)
				"voice":
					if x is String:
						refs.voice.append(x)
				"marker":
					if x is String and x != "" and x != "boss":
						refs.marker.append(x)
				"know":
					if x is String:
						refs.know.append(x)
			_collect(x, refs, str(k))
	elif v is Array:
		for x in v:
			_collect(x, refs, key)


func _collect_effect(e: Array, refs: Dictionary) -> void:
	refs.eff.append(e)
	var a1 = e[1] if e.size() > 1 else null
	match str(e[0]):
		"know":
			refs.know.append(str(a1))
		"voice":
			refs.voice.append(str(a1))
		"warp":
			refs.marker.append(str(a1))
		"spawn":
			if e.size() > 2:
				refs.marker.append(str(e[2]))
			refs.enemy.append(str(a1))
		"shop":
			refs.shop.append(str(a1))
		"spawn_npc":
			refs.npc.append(str(a1))
		"choice":
			# ["choice", question, [[label, [effects], [conds]], ...]]
			for o in (e[2] if e.size() > 2 and e[2] is Array else []):
				if o is Array and o.size() > 1 and o[1] is Array:
					for sub in o[1]:
						if sub is Array and not sub.is_empty():
							_collect_effect(sub, refs)
				if o is Array and o.size() > 2:
					for c in (o[2] if o[2] is Array else [o[2]]):
						refs.cond.append(str(c))


# ------------------------------------------------------------------ reachability
func _test_reachability(sid: String, sd: Dictionary, map: MapBuilder) -> void:
	## BFS from '@' over walkable cells. Repairable bridges ('%') count as open,
	## gates/cracks sit on marker cells (walkable here), and warps / carts / NPC
	## "warp" effects add jumps once their source cell has been reached.
	var start: Array = map.markers.get("@", [])
	if start.is_empty():
		return
	var specs: Dictionary = sd.get("markers", {})
	var jumps: Dictionary = {}  # Vector2i source cell -> Array of marker chars
	for ch in specs:
		var sp: Dictionary = specs[ch]
		var targets: Array = []
		if sp.has("to"):
			targets.append(str(sp.to))
		for pch in sp.get("path", []):
			targets.append(str(pch))
		var sub := _new_refs()
		var src: Dictionary = sp
		if str(sp.get("type", "")) == "npc":
			src = sd.get("npcs", {}).get(str(sp.get("id", "")), {})
		_collect(src, sub)
		for e in sub.eff:
			if str(e[0]) == "warp" and e.size() > 1:
				targets.append(str(e[1]))
		if targets.is_empty():
			continue
		for c in map.markers.get(ch, []):
			jumps[c] = targets
	var seen := {}
	var queue: Array = [start[0]]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		if seen.has(c):
			continue
		if c.x < 0 or c.y < 0 or c.x >= map.w or c.y >= map.h:
			continue
		var t := map.cell(c.x, c.y)
		if map.is_solid(c.x, c.y) and t != "%":
			continue
		seen[c] = true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			queue.append(c + d)
		if jumps.has(c):
			for ch in jumps[c]:
				for tc in map.markers.get(ch, []):
					queue.append(tc)
	var skip := ["@"]
	for ch in map.markers:
		if ch in skip:
			continue
		for c in map.markers[ch]:
			# props like houses may sit against trees: touching a reached cell is enough
			var reach := seen.has(c)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if seen.has(c + d):
					reach = true
			ok(reach, "marker '%s' at %s reachable from start" % [ch, str(c)])


func _new_refs() -> Dictionary:
	return {"cond": [], "eff": [], "voice": [], "marker": [], "know": [], "shop": [], "npc": [], "enemy": []}
