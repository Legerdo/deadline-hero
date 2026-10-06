class_name StageEvents
extends RefCounted
## Data-driven stage scripting: conditions, effects, NPC talk (with déjà vu),
## shops, the time shop, interactive props, menus and the result screen.

const SPEAKERS := {
	"chocho": {"name": "초초", "portrait": "chocho", "pitch": 1.6},
	"hero": {"name": "리오", "portrait": "hero", "pitch": 1.15},
	"zero": {"name": "마왕 제로", "portrait": "zero", "pitch": 0.55},
	"narrator": {"name": "", "portrait": "", "pitch": 1.0},
}

var s  # Stage
var pause_sel := 0


func _init(stage) -> void:
	s = stage


# ================================================================== conditions
func check(conds, ctx: Dictionary = {}) -> bool:
	if conds is String:
		conds = [conds]
	for c in conds:
		if not _check1(str(c), ctx):
			return false
	return true


func _check1(c: String, ctx: Dictionary) -> bool:
	var neg := c.begins_with("!")
	if neg:
		c = c.substr(1)
	var r := false
	var mem: Dictionary = s.mem
	if c.begins_with("flag:"):
		r = s.flags.has(c.substr(5))
	elif c.begins_with("know:"):
		r = mem.known.has(c.substr(5))
	elif c.begins_with("cut:"):
		r = mem.shortcuts.has(c.substr(4))
	elif c.begins_with("item:"):
		var body := c.substr(5)
		var need := 1
		if body.contains(">="):
			var parts := body.split(">=")
			body = parts[0]
			need = int(parts[1])
		r = int(s.run.items.get(body, 0)) >= need or str(s.run.weapon) == body or str(s.run.armor) == body
	elif c == "met":
		var nid: String = ctx.get("npc", "")
		r = mem.met.has(nid) and int(mem.met[nid]) < s.loop_idx
	elif c == "talked":
		r = s.flags.has("talked:" + str(ctx.get("npc", "")))
	elif c.begins_with("talked:"):
		r = s.flags.has(c)
	elif c.begins_with("lv>="):
		r = int(s.run.lv) >= int(c.substr(4))
	elif c.begins_with("watk>="):
		r = int(DB.item(str(s.run.weapon)).get("atk", 0)) >= int(c.substr(6))
	elif c.begins_with("gold>="):
		r = int(s.run.gold) >= int(c.substr(6))
	elif c.begins_with("loop>="):
		r = s.loop_idx >= int(c.substr(6))
	elif c.begins_with("buff:"):
		r = s.run.buffs.has(c.substr(5))
	elif c.begins_with("time<="):
		r = s.time_left <= float(c.substr(6))
	elif c == "cleared":
		r = int(mem.clears) > 0
	elif c == "boss_seen":
		r = bool(mem.boss_seen)
	elif c == "first":
		r = s.loop_idx == 1 and int(mem.clears) == 0
	elif c.begins_with("chest:"):
		r = s.flags.has(c)
	elif c.begins_with("open:"):
		r = s.flags.has(c)
	return r != neg


const COND_PREFIXES := ["flag:", "know:", "cut:", "item:", "talked:", "lv>=", "watk>=", "gold>=", "loop>=", "buff:", "time<=", "chest:", "open:"]
const COND_WORDS := ["met", "talked", "cleared", "boss_seen", "first"]
const EFFECT_OPS := ["flag", "unflag", "know", "shortcut", "item", "take", "gold", "exp", "time", "heal", "buff", "shop",
	"timeshop", "open", "remove", "warp", "sfx", "voice", "toast", "hint", "say", "choice", "pay", "win", "spawn",
	"spawn_npc", "music", "cart", "respawn_here", "star"]


## True when _check1 understands the condition (used by the data tests so a typo
## in stage JSON fails loudly instead of silently evaluating to false).
static func is_known_condition(c: String) -> bool:
	c = c.trim_prefix("!")
	if c in COND_WORDS:
		return true
	for p in COND_PREFIXES:
		if c.begins_with(p) and c.length() > p.length():
			var arg := c.substr(p.length())
			if p.ends_with("=") and not arg.is_valid_float():
				return false
			if p == "item:" and arg.contains(">=") and not arg.split(">=")[1].is_valid_int():
				return false
			return true
	return false


# ================================================================== effects
func run_effects(effs: Array, ctx: Dictionary = {}) -> void:
	for e in effs:
		if not (e is Array) or e.is_empty():
			continue
		var op := str(e[0])
		var a1 = e[1] if e.size() > 1 else null
		var a2 = e[2] if e.size() > 2 else null
		match op:
			"flag":
				s.flags[str(a1)] = true
			"unflag":
				s.flags.erase(str(a1))
			"know":
				learn(str(a1))
			"shortcut":
				open_shortcut(str(a1))
			"item":
				give_item(str(a1), int(a2) if a2 != null else 1)
			"take":
				take_item(str(a1), int(a2) if a2 != null else 1)
			"gold":
				s.run.gold = max(0, int(s.run.gold) + int(a1))
				if int(a1) > 0:
					Audio.sfx("coin", -2.0)
					s.hud.toast("+%dG" % int(a1), "coin", UIKit.GOLD)
			"exp":
				s.gain(int(a1), 0)
			"time":
				add_time(float(a1), str(a2) if a2 != null else "")
			"heal":
				s.run.hp = s.run.max_hp
				Audio.sfx("heal", -2.0)
				s.fx.emit(s.hero.global_position + Vector2(0, -10), 14, [Color("91db69"), Color.WHITE], 50.0, 0.7, 2.0, -40.0)
			"buff":
				s.run.buffs[str(a1)] = true
				if a2 != null:
					s.hud.toast(str(a2), "star", UIKit.ECHO, "panel_echo")
			"shop":
				await open_shop(str(a1))
			"timeshop":
				await open_timeshop()
			"open":
				open_entity(str(a1))
			"remove":
				var p = s.props_by_id.get(str(a1))
				if p and is_instance_valid(p):
					p.vanish()
				var n = s.npcs.get(str(a1))
				if n and is_instance_valid(n):
					n.queue_free()
					s.npcs.erase(str(a1))
			"warp":
				await warp_hero(str(a1))
			"sfx":
				Audio.sfx(str(a1))
			"voice":
				Audio.voice(str(a1))
			"toast":
				s.hud.toast(str(a1), str(a2) if a2 != null else "", UIKit.WHITE)
			"hint":
				s.hud.hint(str(a1))
			"say":
				await say(a1 if a1 is Array else [a1], ctx.get("npc_node"))
			"choice":
				await choice(e, ctx)
			"pay":
				s.run.gold = max(0, int(s.run.gold) - int(a1))
				Audio.sfx("buy", -2.0)
			"win":
				s.pause_world(false)
				s.state = "play"
				s._on_boss_dead(true)
			"spawn":
				s.spawn_enemy(str(a1), s.map.marker_pos(str(a2)), {}, false)
			"spawn_npc":
				spawn_npc(str(a1))
			"music":
				Audio.play_music(str(a1))
			"cart":
				await ride_cart(ctx.get("prop"))
			"respawn_here":
				s.respawn_pos = s.hero.global_position
			"star":
				collect_star()
	s.hud.update_stats(s.run)


func choice(e: Array, ctx: Dictionary) -> void:
	## ["choice", "question", [["label", [effects], [conds]], ...]]
	var q := str(e[1])
	var opts: Array = e[2]
	var entries: Array = []
	var valid: Array = []
	for o in opts:
		var ok := true
		if o.size() > 2:
			ok = check(o[2], ctx)
		entries.append({"text": str(o[0]), "disabled": not ok})
		valid.append(o)
	if Game.dbg.bot:
		for bi in entries.size():
			if not entries[bi].disabled:
				await run_effects(valid[bi][1], ctx)
				return
		return
	var i: int = await MenuList.open(s.ui, q, entries, Rect2(380, 150, 240, 0), true)
	if i < 0:
		return
	await run_effects(valid[i][1], ctx)


# ================================================================== dialogue
func make_line(l, npc = null) -> Dictionary:
	var d := {}
	if l is Dictionary:
		d = l.duplicate()
		# voiced lines keep their text in data/voice_lines.json (single source of truth)
		if d.has("voice") and not d.has("text"):
			var vl: Dictionary = DB.line(str(d.voice))
			d.text = str(vl.get("text", ""))
			if not d.has("who"):
				d.who = str(vl.get("who", ""))
				if d.who == "announcer":
					d.who = "narrator"
	else:
		var txt := str(l)
		d.text = txt
		var idx := txt.find(":")
		var known_who := false
		if idx > 0 and idx < 14:
			var cand := txt.substr(0, idx).strip_edges()
			known_who = SPEAKERS.has(cand) or (s != null and (s.sd.get("speakers", {}).has(cand) or s.sd.get("npcs", {}).has(cand)))
		if known_who:
			d.who = txt.substr(0, idx).strip_edges()
			d.text = txt.substr(idx + 1).strip_edges()
	var who: String = str(d.get("who", ""))
	if who == "" and npc != null and is_instance_valid(npc):
		who = npc.id
	var extra: Dictionary = {}
	if s != null:
		extra = s.sd.get("speakers", {})
	if SPEAKERS.has(who):
		var sp: Dictionary = SPEAKERS[who]
		d.name = sp.name
		d.portrait = sp.portrait
		d.pitch = sp.pitch
	elif extra.has(who):
		var sp2: Dictionary = extra[who]
		d.name = str(sp2.get("name", ""))
		d.portrait = str(sp2.get("portrait", ""))
		d.pitch = float(sp2.get("pitch", 1.0))
	elif s != null and s.sd.get("npcs", {}).has(who):
		var nd: Dictionary = s.sd.npcs[who]
		d.name = str(nd.get("name", ""))
		d.portrait = str(nd.get("portrait", ""))
		d.pitch = float(nd.get("pitch", 1.0))
	return d


func say(lines: Array, npc = null) -> void:
	var was_paused: bool = s.get_tree().paused
	if not was_paused:
		s.pause_world(true)
	var out: Array = []
	for l in lines:
		out.append(make_line(l, npc))
	await s.dialog.play(out)
	if not was_paused:
		s.pause_world(false)


func talk_to(n) -> void:
	if s.state != "play" or s.busy or not is_instance_valid(n):
		return
	var d: Dictionary = n.def
	var ctx := {"npc": n.id, "npc_node": n}
	var variants: Array = d.get("talk", [])
	for vi in variants.size():
		var v: Dictionary = variants[vi]
		var once_key := "once:%s:%d" % [n.id, vi]
		if v.get("once", false) and s.flags.has(once_key):
			continue
		if not check(v.get("if", []), ctx):
			continue
		s.busy = true
		s.pause_world(true)
		n.hop()
		var nid: String = n.id
		Audio.sfx("talk", -4.0, float(d.get("pitch", 1.0)))
		var is_deja: bool = "met" in v.get("if", [])
		if is_deja:
			s.fx.popup(n.global_position + Vector2(0, -34), "데자뷔…!", UIKit.ECHO)
			Audio.sfx("deja", -2.0)
		await say(v.get("lines", []), n)
		await run_effects(v.get("do", []), ctx)
		if v.get("once", false):
			s.flags[once_key] = true
		if not s.mem.met.has(nid):
			s.mem.met[nid] = s.loop_idx
		s.flags["talked:" + nid] = true
		if s.state == "play":
			s.pause_world(false)
		s.busy = false
		s.hud.set_objective(objective_text())
		return


func npc_indicator(n) -> String:
	var d: Dictionary = n.def
	if s.flags.has("talked:" + n.id):
		# something new to say (a variant unlocked by what we learned since)?
		var ctx0 := {"npc": n.id}
		for vi in d.get("talk", []).size():
			var v0: Dictionary = d.talk[vi]
			if v0.get("important", false) and v0.get("once", false) and not s.flags.has("once:%s:%d" % [n.id, vi]) and check(v0.get("if", []), ctx0):
				return "excl"
		return "shop" if d.has("shop") else ""
	var ctx := {"npc": n.id}
	for v in d.get("talk", []):
		if check(v.get("if", []), ctx):
			if "met" in v.get("if", []):
				return "echo"
			if v.get("important", false):
				return "excl"
			break
	if d.has("shop"):
		return "shop"
	return ""


func chocho_loop_quip() -> void:
	var lines: Array = s.sd.get("loop_quips", [])
	var pool := ["chocho_loop_1", "chocho_loop_2", "chocho_loop_3"]
	var i: int = (s.loop_idx - 2) % pool.size()
	var txt := ["이번엔 알고 있지냥? 같은 실수는 없다냥!", "메아리가 길을 기억하고 있다냥. 따라가 봐!", "시간은 없어도 기억은 남았다냥!"]
	if not lines.is_empty():
		txt = lines
	s.hud.toast("초초: " + str(txt[i % txt.size()]), "cat", UIKit.ECHO, "panel_echo")
	Audio.voice(pool[i])


# ================================================================== knowledge / world memory
func learn(k: String) -> void:
	if s.mem.known.has(k):
		return
	s.mem.known[k] = s.loop_idx
	if not s.sd.get("knowledge", {}).has(k):
		return
	var kd: Dictionary = s.sd.get("knowledge", {}).get(k, {})
	var txt := str(kd.get("text", k))
	# short headline for the toast; the full sentence lives in the journal (C)
	var cut := txt.length()
	for sep in [" →", " (", ":", " ·"]:
		var i := txt.find(sep)
		if i > 6 and i < cut:
			cut = i
	var short := txt.substr(0, min(cut, 26)) + ("…" if min(cut, 26) < txt.length() and cut > 26 else "")
	s.hud.toast("수첩 +1  " + short + "  [C]", "echo", UIKit.ECHO, "panel_echo")
	Audio.sfx("learn", -2.0)
	Game.save_game()


func open_shortcut(k: String) -> void:
	if not s.mem.shortcuts.has(k):
		s.mem.shortcuts[k] = s.loop_idx
		s.hud.toast("지름길 고정! 되감아도 남는다", "echo", UIKit.ECHO, "panel_echo")
		Game.save_game()
	_apply_shortcut(k)


func _apply_shortcut(k: String) -> void:
	for p in s.props.duplicate():
		if not is_instance_valid(p):
			continue
		if str(p.def.get("shortcut", "")) == k:
			match p.kind:
				"bridge":
					_repair_bridge(p, false)
				"crack":
					p.vanish()
				"gate":
					_open_gate(p, false)


func init_prop(p) -> void:
	var sc := str(p.def.get("shortcut", ""))
	if sc != "" and s.mem.shortcuts.has(sc):
		match p.kind:
			"bridge":
				_repair_bridge(p, true)
			"crack":
				p.queue_free()
			"gate":
				_open_gate(p, true)
	if p.kind == "crystal" and s.mem.get("lit", {}).has(p.pid):
		p.set_texture("props/crystal_on")
		p.light = 100.0
		p.used = true
	if p.kind == "lever" and sc != "" and s.mem.shortcuts.has(sc):
		p.set_texture("props/lever_on")
		p.used = true
		for g in p.def.get("opens", []):
			s.flags["open:" + str(g)] = true
	if p.kind == "chest" and p.def.get("hidden_until", "") != "" and not check(p.def.hidden_until):
		p.visible = false
		p.set_solid(false)


func give_item(it: String, n := 1) -> void:
	var info := DB.item(it)
	var t := str(info.get("type", "key"))
	if info.has("buff"):
		s.run.buffs[str(info.buff)] = true
	if t == "weapon":
		if int(info.get("atk", 0)) >= int(DB.item(str(s.run.weapon)).get("atk", 0)):
			s.run.weapon = it
	elif t == "armor":
		if int(info.get("def", 0)) >= int(DB.item(str(s.run.armor)).get("def", 0)):
			s.run.armor = it
	else:
		s.run.items[it] = int(s.run.items.get(it, 0)) + n
	var nm := str(info.get("name", it))
	s.hud.toast("%s 획득!%s" % [nm, (" x%d" % n) if n > 1 else ""], it, UIKit.WHITE)
	Audio.sfx("item_get", -2.0)
	s.fx.popup(s.hero.global_position + Vector2(0, -32), nm, Color("fbff86"))
	s.hud.update_stats(s.run)


func take_item(it: String, n := 1) -> void:
	s.run.items[it] = max(0, int(s.run.items.get(it, 0)) - n)


func add_time(sec: float, why := "") -> void:
	s.time_left += sec
	s.hud.bump_time()
	Audio.sfx("time_add", 0.0)
	s.fx.popup(s.hero.global_position + Vector2(0, -36), "+%d초!" % int(sec), UIKit.ECHO, true)
	s.fx.ring(s.hero.global_position + Vector2(0, -8), 30.0, UIKit.ECHO, 0.4, 2.0)
	if why != "":
		s.hud.toast(why, "clock", UIKit.ECHO, "panel_echo")


func collect_star() -> void:
	if not s.mem.star:
		s.mem.star = true
		Game.save_game()
	Audio.sfx("star", 0.0)
	s.hud.banner("★ 시간의 별 조각", UIKit.GOLD, 0.8, "비밀 발견! 별의 가호: 모든 스테이지 제한 시간 +2초", 30)
	s.fx.emit(s.hero.global_position + Vector2(0, -12), 30, [Color("fbff86"), Color("8ff8e2"), Color.WHITE], 120.0, 0.8, 2.0)


func open_entity(eid: String) -> void:
	s.flags["open:" + eid] = true
	var p = s.props_by_id.get(eid)
	if p and is_instance_valid(p) and p.kind == "gate":
		_open_gate(p, false)


func _open_gate(p, instant: bool) -> void:
	if p.is_open:
		return
	p.is_open = true
	p.set_solid(false)
	p.set_texture("props/gate_open")
	if not instant:
		Audio.sfx("gate", 0.0)
		s.shake(3.0, 0.3)
		s.fx.emit(p.global_position + Vector2(0, -8), 12, [Color("9babb2"), Color("c7dcd0")], 60.0, 0.5, 2.0)


func _repair_bridge(p, instant: bool) -> void:
	var c := Vector2i(int(p.global_position.x / 16), int(p.global_position.y / 16))
	# the repair marker sits next to the broken planks: find the nearest '%'
	var start := c
	var best := 999
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if s.map.cell(c.x + dx, c.y + dy) == "%" and abs(dx) + abs(dy) < best:
				best = abs(dx) + abs(dy)
				start = Vector2i(c.x + dx, c.y + dy)
	var cells: Array = s.map.flood_cells(start, "%")
	for cc in cells:
		s.map.set_terrain(cc.x, cc.y, "=")
		if not instant:
			s.fx.emit(Vector2(cc.x * 16 + 8, cc.y * 16 + 8), 5, [Color("cd683d"), Color("fbb954"), Color.WHITE], 50.0, 0.5, 2.0)
	p.used = true
	p.set_solid(false)
	if not instant:
		Audio.sfx("build", 0.0)
		s.shake(4.0, 0.4)
		s.mini_img = s.map.minimap_image()
		s.hud.refresh_minimap(s.mini_img)
	if s.bot:
		s.bot.on_terrain_changed()
	p.queue_free()


# ================================================================== props
func prop_bump(p, _h) -> void:
	if s.state != "play" or s.busy or not is_instance_valid(p):
		return
	match p.kind:
		"chest":
			if p.used:
				return
			p.used = true
			p.set_texture("props/chest_open")
			p.pop()
			Audio.sfx("chest", 0.0)
			s.hitstop(0.05)
			s.fx.emit(p.global_position + Vector2(0, -10), 16, [Color("fbff86"), Color("f9c22b"), Color.WHITE], 80.0, 0.6, 2.0, -30.0)
			s.flags["chest:" + p.pid] = true
			var first_find: bool = not s.mem.chests.has(p.pid)
			s.mem.chests[p.pid] = true
			await run_effects(p.def.get("give", []), {"prop": p})
			if first_find:
				s.hud.toast("상자 위치를 기억했다 (다음 루프 지도 표시)", "chest", UIKit.ECHO, "panel_echo")
		"sign", "tomb", "well", "bell":
			if p.def.has("text"):
				s.busy = true
				await say(p.def.text if p.def.text is Array else [p.def.text])
				await run_effects(p.def.get("do", []), {"prop": p})
				s.busy = false
		"statue":
			s.busy = true
			s.respawn_pos = p.global_position + Vector2(0, 14)
			await open_timeshop()
			s.busy = false
		"gate":
			if p.is_open:
				return
			var need := str(p.def.get("need", ""))
			if need != "" and int(s.run.items.get(need, 0)) > 0:
				if p.def.get("consume", true):
					take_item(need)
				_open_gate(p, false)
				if p.def.has("shortcut"):
					open_shortcut(str(p.def.shortcut))
				await run_effects(p.def.get("do", []), {"prop": p})
			elif p.def.has("locked"):
				if not s.flags.has("lockmsg:" + p.pid):
					s.flags["lockmsg:" + p.pid] = true
					s.busy = true
					await say(p.def.locked if p.def.locked is Array else [p.def.locked])
					s.busy = false
				else:
					s.fx.popup(p.global_position + Vector2(0, -24), "잠겨 있다", UIKit.DIM)
		"lever":
			if p.used and not p.def.get("toggle", false):
				return
			p.used = true
			p.set_texture("props/lever_on")
			Audio.sfx("lever", 0.0)
			for g in p.def.get("opens", []):
				open_entity(str(g))
			if p.def.has("shortcut"):
				open_shortcut(str(p.def.shortcut))
			await run_effects(p.def.get("do", []), {"prop": p})
		"crack":
			var tool := str(p.def.get("need", "pickaxe"))
			if int(s.run.items.get(tool, 0)) > 0:
				Audio.sfx("rock_break", 2.0)
				s.shake(5.0, 0.3)
				s.hitstop(0.08)
				s.fx.emit(p.global_position + Vector2(0, -8), 22, [Color("625565"), Color("9babb2"), Color("c7dcd0")], 110.0, 0.7, 3.0, 200.0)
				if p.def.has("shortcut"):
					open_shortcut(str(p.def.shortcut))
				p.vanish()
			else:
				s.fx.popup(p.global_position + Vector2(0, -24), str(p.def.get("hint", "금이 간 벽… 곡괭이가 필요하다")), UIKit.PALE, false, 14.0, 1.2)
				Audio.sfx("clink", -4.0)
		"bridge":
			var need_n := int(p.def.get("count", 3))
			var have := int(s.run.items.get("planks", 0))
			if have >= need_n:
				take_item("planks", need_n)
				s.busy = true
				await say(p.def.get("repair_lines", ["hero: (판자를 덧대어 다리를 고쳤다!)"]))
				s.busy = false
				open_shortcut(str(p.def.get("shortcut", "bridge")))
			else:
				s.fx.popup(p.global_position + Vector2(0, -20), "판자 %d/%d" % [have, need_n], UIKit.PALE, false, 14.0, 1.2)
				if not s.flags.has("bridge_msg"):
					s.flags["bridge_msg"] = true
					s.hud.hint(str(p.def.get("hint", "끊어진 다리. 판자가 %d개 필요하다" % need_n)))
		"crystal":
			if p.used:
				return
			p.used = true
			p.set_texture("props/crystal_on")
			p.light = 100.0
			p.flash(Color(0.6, 1, 0.9), 0.3)
			Audio.sfx("crystal", 0.0)
			if not s.mem.has("lit"):
				s.mem.lit = {}
			s.mem.lit[p.pid] = true
			s.fx.emit(p.global_position + Vector2(0, -8), 14, [Color("30e1b9"), Color("8ff8e2"), Color.WHITE], 70.0, 0.6, 2.0, -20.0)
			s.hud.toast("수정에 불이 켜졌다 (되감아도 유지)", "echo", UIKit.ECHO, "panel_echo")
		"cart":
			await ride_cart(p)
		"pot":
			if p.used:
				return
			p.used = true
			Audio.sfx("pot", 0.0)
			s.fx.emit(p.global_position + Vector2(0, -6), 12, [Color("cd683d"), Color("e6904e"), Color("6e2727")], 90.0, 0.5, 2.0, 200.0)
			var g := int(p.def.get("gold", randi_range(2, 6)))
			if p.def.has("time"):
				add_time(float(p.def.time), "항아리 속 시간의 모래!")
			else:
				s.gain(0, g)
				s.fx.popup(p.global_position + Vector2(0, -20), "+%dG" % g, UIKit.GOLD)
			p.vanish()


func prop_touch(p) -> void:
	match p.kind:
		"pickup":
			p.used = true
			var it := str(p.def.get("item", ""))
			if it == "star":
				collect_star()
			elif it == "hourglass" or p.def.has("time"):
				add_time(float(p.def.get("time", 8)), str(p.def.get("why", "시간의 모래래시계!")))
			elif it == "coin":
				s.gain(0, int(p.def.get("gold", 10)))
				Audio.sfx("coin", 0.0)
			elif it != "":
				give_item(it, int(p.def.get("count", 1)))
			await run_effects(p.def.get("do", []), {"prop": p})
			if p.def.has("pid_flag"):
				s.flags[str(p.def.pid_flag)] = true
			p.vanish()
		"warp":
			if s.state != "play":
				return
			p.used = true
			await warp_hero(str(p.def.to))
			await run_effects(p.def.get("do", []), {"prop": p})
			s.hud.set_objective(objective_text())
			await s.wait(0.3)
			p.used = false


func spawn_npc(npc_id: String) -> void:
	if s.npcs.has(npc_id) and is_instance_valid(s.npcs[npc_id]):
		return
	var mk: Dictionary = s.sd.get("markers", {})
	for ch in mk:
		if str(mk[ch].get("type", "")) == "npc" and str(mk[ch].get("id", "")) == npc_id:
			var pos: Vector2 = s.map.marker_pos(ch)
			if pos != Vector2.ZERO:
				var d: Dictionary = s.sd.get("npcs", {}).get(npc_id, {}).duplicate()
				d.erase("if")
				var n := NPC.new()
				n.stage = s
				n.setup(npc_id, d)
				n.position = pos
				s.world.add_child(n)
				s.npcs[npc_id] = n
				s.fx.emit(pos + Vector2(0, -10), 10, [Color.WHITE, Color("c7dcd0")], 50.0, 0.4, 2.0)
			return


func warp_hero(marker: String) -> void:
	var dest: Vector2 = s.map.marker_pos(marker)
	if dest == Vector2.ZERO:
		return
	Audio.sfx("door", -2.0)
	s.flash_screen(Color(0.18, 0.13, 0.18, 1.0), 0.3)
	s.hero.global_position = dest
	s.hero.move_vel = Vector2.ZERO
	s._snap_camera()


func ride_cart(p) -> void:
	if p == null or p.used:
		return
	var path: Array = p.def.get("path", [])
	if path.is_empty():
		return
	var need := str(p.def.get("need_cut", ""))
	if need != "" and not s.mem.shortcuts.has(need):
		s.fx.popup(p.global_position + Vector2(0, -22), "선로가 꺼져 있다", UIKit.PALE, false, 14.0, 1.0)
		Audio.sfx("clink", -4.0)
		if not s.flags.has("cart_msg"):
			s.flags["cart_msg"] = true
			s.busy = true
			await say(p.def.get("locked", ["hero: 광차 선로가 막혀 있어. 깊은 곳의 전환 레버를 당기면 움직일 것 같은데…"]))
			s.busy = false
			if p.def.has("know"):
				learn(str(p.def.know))
		return
	p.used = true
	s.state = "cutscene"
	s.hero.visible = false
	Audio.sfx("cart", 0.0)
	var pts: Array = [p.global_position]
	for m in path:
		pts.append(s.map.marker_pos(str(m)))
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var dur: float = a.distance_to(b) / 260.0
		var t := 0.0
		while t < dur:
			var dt: float = s.get_process_delta_time()
			t += dt
			p.global_position = a.lerp(b, clamp(t / dur, 0.0, 1.0))
			s.hero.global_position = p.global_position
			if Engine.get_process_frames() % 3 == 0:
				s.fx.emit(p.global_position + Vector2(randf_range(-6, 6), 0), 2, [Color("fbff86"), Color("f79617")], 60.0, 0.25, 1.0)
			s.shake(1.0, 0.05)
			await s.get_tree().process_frame
	s.hero.visible = true
	s.hero.global_position = pts[pts.size() - 1] + Vector2(0, 16)
	Audio.sfx("slam", -4.0, 1.4)
	s.state = "play"
	s.hud.toast("광차 도착!", "", UIKit.WHITE)


# ================================================================== plates (echo co-op)
func update_plates(_delta: float) -> void:
	var any := false
	var occupied_plates: Dictionary = {}
	for p in s.props:
		if not is_instance_valid(p) or p.kind != "plate":
			continue
		any = true
		var hp: Vector2 = s.hero.global_position
		var occupied: bool = hp.distance_to(p.global_position) < 9.0
		var by_ghost := false
		if s.ghost and (s.ghost as Sprite2D).visible and s.ghost.global_position.distance_to(p.global_position) < 9.0:
			occupied = true
			by_ghost = true
		if occupied:
			occupied_plates[p.pid] = true
			if not p.pressed:
				Audio.sfx("plate", -2.0, 1.2 if by_ghost else 1.0)
				s.fx.emit(p.global_position + Vector2(0, -6), 8, [Color("30e1b9"), Color.WHITE], 50.0, 0.4, 2.0)
				if by_ghost:
					s.fx.popup(p.global_position + Vector2(0, -20), "메아리!", UIKit.ECHO)
		if occupied != p.pressed:
			p.pressed = occupied
			p.set_texture("props/plate_on" if occupied else "props/plate_off")
	if not any:
		return
	for g in s.props:
		if not is_instance_valid(g) or g.kind != "gate" or not g.def.has("plates") or g.is_open:
			continue
		var all_lit := true
		for pid in g.def.plates:
			if not occupied_plates.has(str(pid)):
				all_lit = false
		if all_lit:
			_open_gate(g, false)
			s.hud.toast("두 개의 발판이 동시에 눌렸다!", "echo", UIKit.ECHO, "panel_echo")
			s.hitstop(0.08)
			s.shake(4.0, 0.4)
			if g.def.has("know"):
				learn(str(g.def.know))
			if g.def.has("shortcut"):
				open_shortcut(str(g.def.shortcut))


func on_ghost(_pos: Vector2) -> void:
	pass


# ================================================================== shops
func _bot_shop(shop: Dictionary) -> void:
	var overrides: Dictionary = shop.get("prices", {})
	var bought := true
	while bought:
		bought = false
		for it in shop.get("items", []):
			var info := DB.item(str(it))
			var price := int(overrides.get(str(it), info.get("price", 10)))
			var better := false
			if info.has("atk"):
				better = int(info.atk) > int(DB.item(str(s.run.weapon)).get("atk", 0))
			elif info.has("def"):
				better = int(info.def) > int(DB.item(str(s.run.armor)).get("def", 0))
			elif info.has("buff"):
				better = not s.run.buffs.has(str(info.buff))
			elif str(it) == "pickaxe":
				better = int(s.run.items.get("pickaxe", 0)) == 0
			if better and int(s.run.gold) >= price:
				s.run.gold = int(s.run.gold) - price
				give_item(str(it), 1)
				print("[bot] bought ", it, " for ", price)
				bought = true
				break


func open_shop(shop_id: String) -> void:
	var shop: Dictionary = s.sd.get("shops", {}).get(shop_id, {})
	if Game.dbg.bot and Game.dbg.scenario != "ui":
		_bot_shop(shop)
		return
	var sel := 0
	while true:
		var entries: Array = []
		var items: Array = shop.get("items", [])
		var overrides: Dictionary = shop.get("prices", {})
		for it in items:
			var info := DB.item(str(it))
			var price := int(overrides.get(str(it), info.get("price", 10)))
			var owned := str(s.run.weapon) == str(it) or str(s.run.armor) == str(it)
			var stat := ""
			if info.has("atk"):
				var diff := int(info.atk) - int(DB.item(str(s.run.weapon)).get("atk", 0))
				stat = "ATK %+d" % diff
			elif info.has("def"):
				var diff2 := int(info.def) - int(DB.item(str(s.run.armor)).get("def", 0))
				stat = "DEF %+d" % diff2
			var desc := str(info.get("desc", ""))
			if stat != "":
				desc = stat + "  " + desc
			entries.append({"text": str(info.get("name", it)), "value": "보유" if owned else "%dG" % price,
				"icon": str(info.get("icon", it)), "disabled": owned or int(s.run.gold) < price, "desc": desc})
		entries.append({"text": "나가기", "desc": "소지금 %dG" % int(s.run.gold)})
		var i: int = await MenuList.open(s.ui, "%s  (소지금 %dG)" % [shop.get("title", "상점"), int(s.run.gold)], entries, Rect2(170, 60, 300, 0), true, sel)
		if i < 0 or i >= items.size():
			return
		sel = i
		var it2 := str(items[i])
		var price2 := int(overrides.get(it2, DB.item(it2).get("price", 10)))
		if int(s.run.gold) >= price2:
			s.run.gold = int(s.run.gold) - price2
			Audio.sfx("buy", 0.0)
			give_item(it2, 1)
			s.hud.update_stats(s.run)


func open_timeshop() -> void:
	var ts: Dictionary = s.sd.get("timeshop", {})
	var prices: Array = ts.get("price", [10, 25, 50, 90])
	var sec := int(ts.get("sec", 15))
	var was: bool = s.get_tree().paused
	s.pause_world(true)
	var first: bool = not s.flags.has("timeshop_seen") and not s.mem.known.has("timeshop")
	s.flags["timeshop_seen"] = true
	learn("timeshop")
	if Game.dbg.bot and Game.dbg.scenario != "ui":
		var bp: int = int(prices[mini(int(s.run.time_bought), prices.size() - 1)])
		if s.time_left < 35.0 and int(s.run.gold) >= bp:
			s.run.gold = int(s.run.gold) - bp
			s.run.time_bought = int(s.run.time_bought) + 1
			add_time(float(sec))
			print("[bot] bought time for ", bp)
		if not was:
			s.pause_world(false)
		return
	while true:
		var n := int(s.run.time_bought)
		var price: int = int(prices[mini(n, prices.size() - 1)]) * (1 + maxi(0, n - prices.size() + 1))
		if first:
			first = false
			await say([{"who": "chocho", "text": "냥! 여기선 골드를 시간으로 바꿔준다냥. 대신… 살수록 비싸진다냥!", "voice": "chocho_shop"}])
		var entries := [
			{"text": "+%d초 사기" % sec, "value": "%dG" % price, "icon": "hourglass", "disabled": int(s.run.gold) < price,
				"desc": "소지금 %dG · 구매 %d회째" % [int(s.run.gold), n + 1]},
			{"text": "그만둔다", "desc": "여기가 새 부활 지점이 됐다냥"},
		]
		var i: int = await MenuList.open(s.ui, "초초의 시간 상점", entries, Rect2(190, 100, 260, 0), true)
		if i != 0:
			break
		s.run.gold = int(s.run.gold) - price
		s.run.time_bought = n + 1
		s.pause_world(false)
		add_time(float(sec))
		Audio.voice("chocho_buy")
		s.hud.update_stats(s.run)
		s.pause_world(true)
	if not was:
		s.pause_world(false)


# ================================================================== menus
func open_pause() -> void:
	if s.busy:
		return
	s.busy = true
	s.pause_world(true)
	var dim := UIKit.rect(Color(0.1, 0.07, 0.12, 0.6), Rect2(Vector2.ZERO, Game.VIEW))
	s.ui.add_child(dim)
	var done := false
	while not done:
		var entries := [
			{"text": "계속하기"},
			{"text": "되감기 (루프 재시작)", "desc": "지식·지름길·메아리는 남는다"},
			{"text": "메아리 수첩", "desc": "이번 스테이지에서 알아낸 것"},
			{"text": "설정", "desc": "볼륨·글자 속도·미니맵·여유 모드"},
			{"text": "월드맵으로", "desc": "이번 루프는 기록되지 않는다"},
		]
		var i: int = await MenuList.open(s.ui, "일시정지 — %s" % s.sd.get("name", ""), entries, Rect2(200, 90, 240, 0), true, pause_sel)
		pause_sel = maxi(i, 0)
		match i:
			-1, 0:
				done = true
			1:
				dim.queue_free()
				s.busy = false
				s.pause_world(false)
				s.rewind("manual")
				return
			2:
				await open_journal(true)
			3:
				await SettingsMenu.open(s.ui, true, s.apply_visual_settings)
			4:
				dim.queue_free()
				s.busy = false
				Game.save_game()
				Game.goto("worldmap", {})
				return
	Game.save_game()
	dim.queue_free()
	s.pause_world(false)
	s.busy = false


func open_journal(from_pause := false) -> void:
	if s.busy and not from_pause:
		return
	if not from_pause:
		s.busy = true
		s.pause_world(true)
	var root := Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	UIKit.full(root)
	s.ui.add_child(root)
	var pnl := UIKit.panel("panel_echo", Rect2(90, 34, 460, 292))
	root.add_child(pnl)
	var title := UIKit.label("메아리 수첩 — %s   (루프 %d)" % [s.sd.get("name", ""), s.loop_idx], "bold", UIKit.WHITE, 3)
	title.position = Vector2(12, 8)
	pnl.add_child(title)
	var y := 30
	var kn: Dictionary = s.sd.get("knowledge", {})
	var found := 0
	for k in kn:
		var got: bool = s.mem.known.has(k)
		if got:
			found += 1
		var l := UIKit.label(("◆ " + str(kn[k].text)) if got else "◇ ??? (아직 모른다)", "small", UIKit.WHITE if got else UIKit.DIM)
		l.position = Vector2(14, y)
		l.size = Vector2(432, 12)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pnl.add_child(l)
		y += 16 if str(kn[k].text).length() < 44 else 28
	var chests_total := 0
	for p in s.props:
		if is_instance_valid(p) and p.kind == "chest":
			chests_total += 1
	var foot := UIKit.label("지식 %d/%d · 상자 기억 %d/%d · 지름길 %d개 · 별 조각 %s" % [found, kn.size(), s.mem.chests.size(), chests_total, s.mem.shortcuts.size(), "★" if s.mem.star else "☆"], "small", UIKit.GOLD)
	foot.position = Vector2(14, 268)
	pnl.add_child(foot)
	var close := UIKit.label("[Z / X] 닫기", "tiny", UIKit.PALE)
	close.position = Vector2(390, 10)
	pnl.add_child(close)
	await s.get_tree().create_timer(0.15, true, false, true).timeout
	var open_t := 0.0
	while true:
		await s.get_tree().process_frame
		open_t += s.get_process_delta_time()
		if Game.ok_pressed() or Game.back_pressed() or Input.is_action_just_pressed("journal"):
			break
		if Game.dbg.bot and open_t > 1.4:
			break
	Audio.sfx("menu_back", -4.0)
	root.queue_free()
	if not from_pause:
		s.pause_world(false)
		s.busy = false


# ================================================================== objective
func objective_text() -> String:
	var g := current_goal()
	if not g.is_empty():
		return str(g.text)
	return str(s.sd.get("objective", "보스를 쓰러뜨려라"))


func current_goal() -> Dictionary:
	for g in s.sd.get("goals", []):
		if check(g.get("if", [])):
			return g
	return {}


func objective_pos() -> Variant:
	for g in s.sd.get("goals", []):
		if check(g.get("if", [])):
			var mk := str(g.get("marker", "boss"))
			if mk == "":
				return null
			if mk == "boss":
				break
			var mp: Vector2 = s.map.marker_pos(mk)
			if mp != Vector2.ZERO:
				return mp
			break
	if s.boss and is_instance_valid(s.boss) and s.boss.alive:
		return s.boss.global_position
	return null


# ================================================================== hooks
func on_start() -> void:
	for e in s.sd.get("on_start", []):
		if check(e.get("if", [])):
			await run_effects(e.get("do", []))


func on_kill(e) -> void:
	if s.run.kills == 1 and s.sd.get("index", 1) == 1 and s.loop_idx == 1 and int(s.mem.clears) == 0:
		s.hud.hint("적에게 부딪히면 공격! 대시 박치기(X)는 반격을 받지 않는다", 5.0)
	var _k = e


func on_level_up() -> void:
	if int(s.run.lv) == 2 and s.sd.get("index", 1) == 1 and int(s.mem.clears) == 0:
		s.hud.hint("레벨업하면 HP가 전부 회복된다! 레벨 색: 노랑=강함, 빨강=위험", 5.0)


func on_boss_engaged() -> void:
	for e in s.sd.get("on_boss", []):
		if check(e.get("if", [])):
			await run_effects(e.get("do", []))


func on_blocked(_e) -> void:
	if not s.flags.has("block_hint"):
		s.flags["block_hint"] = true
		s.hud.hint("정면은 방패에 막힌다! 돌진 직후의 등이나 옆을 노려라", 5.0)
		learn("knight_back")


func on_boss_touch(e) -> bool:
	## Returns true when touching the boss triggers a story resolution instead of combat.
	if e.kind == "countess" and int(s.run.items.get("locket", 0)) > 0 and s.state == "play":
		_countess_peace()
		return true
	return false


func on_invulnerable_hit(e) -> void:
	if not s.flags.has("invuln_hint"):
		s.flags["invuln_hint"] = true
		s.hud.hint(str(s.sd.get("invuln_hint", "공격이 통하지 않는다… 방법을 찾아라")), 5.0)


func _countess_peace() -> void:
	if s.state != "play":
		return
	s.state = "cutscene"
	s.hud.letterbox(true)
	var lines: Array = s.sd.get("peace_lines", [])
	await say(lines)
	take_item("locket")
	s.hud.letterbox(false)
	s.mem.peace = true
	s.state = "play"
	s._on_boss_dead(true)


# ================================================================== failure analysis
func fail_tip() -> String:
	for t in s.sd.get("tips", []):
		if check(t.get("if", [])):
			return str(t.text)
	var rec := int(s.sd.get("rec_level", 5))
	if s.boss == null or not s.boss.engaged:
		if int(s.run.lv) < rec - 1:
			return "레벨이 부족했다. 가까운 적부터 대시 박치기로 빠르게 잡자"
		return "보스까지 가지 못했다. 화살표를 따라 곧장 향하자"
	if int(s.run.lv) < rec - 1:
		return "보스는 찾았다! 다음엔 권장 Lv%d까지 올리고 도전하자" % rec
	return "보스의 빈틈(기절·경직)에 대시 박치기를 몰아넣자"


func fail_card() -> void:
	var root := Control.new()
	UIKit.full(root)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	s.ui.add_child(root)
	var pnl := UIKit.panel("panel_red", Rect2(160, 96, 320, 168))
	root.add_child(pnl)
	var t := UIKit.label("루프 %d 실패 — 이번 루프의 기록" % s.loop_idx, "bold", UIKit.WHITE, 3)
	t.position = Vector2(12, 8)
	pnl.add_child(t)
	var rec := int(s.sd.get("rec_level", 5))
	var boss_txt := "발견 못 함"
	if s.boss and s.boss.engaged:
		boss_txt = "남은 체력 %d%%" % int(100.0 * float(max(0, s.boss.hp)) / float(max(1, s.boss.max_hp)))
	elif s.mem.boss_seen:
		boss_txt = "도달 못 함"
	var new_know := 0
	for k in s.mem.known:
		if int(s.mem.known[k]) == s.loop_idx:
			new_know += 1
	var rows := [
		["레벨", "Lv %d  (권장 Lv %d)" % [int(s.run.lv), rec]],
		["보스", boss_txt],
		["새로 알아낸 것", "%d개 → 메아리 수첩(C)" % new_know],
		["다음 루프", ("경험치 +%d%% · Lv%d 계승 가능" % [int(round(min(0.5, 0.1 * s.loop_idx) * 100)), maxi(2, int(floor(int(s.run.lv) * 0.6)))]) if int(s.run.lv) >= 3 else ("경험치 +%d%% · 메아리가 길을 안내" % int(round(min(0.5, 0.1 * s.loop_idx) * 100)))],
	]
	for i in rows.size():
		var a := UIKit.label(rows[i][0], "small", UIKit.PALE)
		a.position = Vector2(16, 34 + i * 18)
		pnl.add_child(a)
		var b := UIKit.label(rows[i][1], "main", UIKit.WHITE)
		b.position = Vector2(112, 32 + i * 18)
		pnl.add_child(b)
	var tip := UIKit.label("TIP  " + fail_tip(), "small", UIKit.GOLD)
	tip.position = Vector2(16, 110)
	tip.size = Vector2(290, 30)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pnl.add_child(tip)
	var go := UIKit.label("[Z] 즉시 되감기", "small", UIKit.WHITE)
	go.position = Vector2(200, 146)
	pnl.add_child(go)
	pnl.scale = Vector2(1, 0.1)
	pnl.pivot_offset = pnl.size * 0.5
	var tw := pnl.create_tween()
	tw.tween_property(pnl, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.sfx("menu_ok", -6.0, 0.8)
	Game.moment("fail_card", 0.5)
	var waited := 0.0
	while waited < 6.0:
		await s.get_tree().process_frame
		waited += s.get_process_delta_time()
		go.text = "[Z] 즉시 되감기  (%d)" % int(ceil(6.0 - waited))
		if waited > 0.35 and Game.ok_pressed():
			break
		if Game.dbg.bot and waited > 2.0:
			break
	root.queue_free()


# ================================================================== result
func rank_for(frac: float) -> String:
	if frac >= Stage.RANK_S:
		return "S"
	if frac >= Stage.RANK_A:
		return "A"
	if frac >= Stage.RANK_B:
		return "B"
	return "C"


func show_result() -> void:
	var left: float = s.time_left
	var frac: float = left / s.time_total
	var rank := rank_for(frac)
	var mem: Dictionary = s.mem
	# 여유 모드 clears count for progress, but best time / rank are kept apart
	var assist: bool = s.assist
	var best_key := "assist_best" if assist else "best"
	var rank_key := "assist_rank" if assist else "rank"
	var new_best: bool = left > float(mem.get(best_key, -1.0))
	if new_best:
		mem[best_key] = left
	var order := "CBAS"
	var prev_rank := str(mem.get(rank_key, ""))
	if prev_rank == "" or order.find(rank) > order.find(prev_rank):
		mem[rank_key] = rank
	mem.clears = int(mem.clears) + 1
	mem.last_lv = int(s.run.lv)
	mem.record = s.record_array()
	Game.save.cleared[s.id] = true
	var idx := DB.stage_index(s.id)
	Game.save.unlocked = max(int(Game.save.unlocked), idx + 1)
	Game.save_game()
	var root := Control.new()
	UIKit.full(root)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	s.ui.add_child(root)
	var pnl := UIKit.panel("panel_gold", Rect2(170, 70, 300, 190))
	root.add_child(pnl)
	var t1 := UIKit.label("%s 클리어!" % s.sd.get("name", ""), "bold", UIKit.GOLD, 3)
	t1.position = Vector2(14, 10)
	pnl.add_child(t1)
	var rows := [
		["남은 시간", "%.1f초" % left],
		["루프 횟수", "%d번째 루프" % s.loop_idx],
		["레벨", "Lv %d" % int(s.run.lv)],
		["처치", "%d마리" % int(s.run.kills)],
		["별 조각", "★ 발견" if mem.star else "☆ 미발견"],
	]
	if assist:
		rows.append(["모드", "여유 모드 (기록 별도)"])
	var labels: Array = []
	for i in rows.size():
		var a := UIKit.label(rows[i][0], "main", UIKit.PALE)
		a.position = Vector2(20, 36 + i * 18)
		pnl.add_child(a)
		var b := UIKit.label(rows[i][1], "main", UIKit.WHITE)
		b.position = Vector2(120, 36 + i * 18)
		b.modulate.a = 0.0
		pnl.add_child(b)
		labels.append(b)
	for b in labels:
		await s.wait(0.18)
		b.modulate.a = 1.0
		Audio.sfx("tick", -4.0, 1.3)
	await s.wait(0.3)
	var rk := UIKit.big_label(rank, 60, {"S": UIKit.GOLD, "A": Color("fb6b1d"), "B": Color("8fd3ff"), "C": UIKit.PALE}[rank], 8)
	rk.position = Vector2(222, 40)
	rk.pivot_offset = Vector2(20, 34)
	rk.scale = Vector2(3, 3)
	pnl.add_child(rk)
	var tw := rk.create_tween()
	tw.tween_property(rk, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.sfx("rank", 0.0)
	s.shake(5.0, 0.2)
	if new_best:
		var nb := UIKit.label("NEW RECORD!", "bold", UIKit.ECHO, 3)
		nb.position = Vector2(200, 112)
		pnl.add_child(nb)
	Game.moment("result", 0.4)
	var tip := UIKit.label("S랭크: 남은 시간 %d%% 이상" % int(Stage.RANK_S * 100), "tiny", UIKit.DIM)
	tip.position = Vector2(20, 36 + rows.size() * 18 + 4)
	pnl.add_child(tip)
	var cont := UIKit.label("[Z] 계속", "small", UIKit.WHITE)
	cont.position = Vector2(230, 168)
	pnl.add_child(cont)
	var res_t := 0.0
	while true:
		await s.get_tree().process_frame
		res_t += s.get_process_delta_time()
		if res_t > 0.3 and Game.ok_pressed():
			break
		if Game.dbg.bot and res_t > 2.0:
			break
	Audio.sfx("menu_ok", -2.0)
	root.queue_free()
	var outro: Array = s.sd.get("clear_lines", [])
	if s.mem.get("peace", false) and s.sd.has("peace_outro"):
		outro = s.sd.peace_outro
	if not outro.is_empty() and int(mem.clears) == 1:
		await say(outro)
	if s.sd.get("final", false):
		Game.goto("ending", {})
	else:
		Game.goto("worldmap", {"from": s.id, "cleared": true})
