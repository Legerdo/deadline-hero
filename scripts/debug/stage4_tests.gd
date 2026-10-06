extends TestRunner
## Drives the real S4 scene through its gameplay methods, without player input.
## --scenario=stage4-tests selects a fresh, isolated bot save automatically.


func run_stage(s: Stage) -> int:
	_suite = "stage4 runtime"
	Game.dbg.bot = false  # Test inputs, not the pathfinding bot, drive gameplay.
	if is_instance_valid(s.bot):
		s.bot.free()  # StageBot is not a child node; the test no longer needs it.
		s.bot = null
	# Freeze autonomous movement; UI/dialog timers still run for the real intro.
	s.set_process(false)
	s.set_physics_process(false)
	s.world.process_mode = Node.PROCESS_MODE_DISABLED
	_test_plates(s)
	await _test_boss_room(s)
	# Let audio playback release before this automated process exits.
	for player in Audio.get_children():
		if player is AudioStreamPlayer:
			player.stop()
	await s.get_tree().create_timer(0.05, true, false, true).timeout
	print("[test] stage4 runtime: %d passed, %d failed" % [passed, failed])
	return failed


func _test_plates(s: Stage) -> void:
	var pa = s.props_by_id["pa"]
	var pb = s.props_by_id["pb"]
	var gate = s.props_by_id["gallery"]
	ok(not gate.is_open, "fresh gallery starts closed")
	s.hero.global_position = pa.global_position
	s._touches()
	ok(pa.pressed and not pb.pressed, "hero presses only plate A")
	ok(not gate.is_open, "one plate cannot open the gallery")
	s.hero.global_position = s.start_pos
	s._touches()
	ok(not pa.pressed, "plate A releases immediately when the hero leaves")
	s.hero.global_position = pb.global_position
	s._touches()
	ok(not gate.is_open, "walking from A to B without an echo cannot open the gallery")
	if gate.is_open:
		return  # Do not let an incorrectly latched gate mask later assertions.
	s.hero.global_position = pa.global_position
	s._touches()
	ok(not pb.pressed and not gate.is_open, "walking from B to A cannot open the gallery")

	# Use the game's recorded-echo playback, including a departure this frame.
	s.prev_record = [int(pa.position.x), int(pa.position.y), 1,
		int(s.start_pos.x), int(s.start_pos.y), 1]
	s.play_time = 0.0
	s._spawn_ghost()
	s._physics_process(0.0)
	ok(not gate.is_open, "hero and echo on the same plate cannot open the gallery")
	s.hero.global_position = pb.global_position
	s.play_time = 0.05
	s._physics_process(0.0)
	ok(not pa.pressed and not gate.is_open, "echo departure is applied before this frame's plate check")
	if gate.is_open:
		return

	s.hero.global_position = s.start_pos
	s.play_time = 0.0
	s._physics_process(0.0)
	ok(pa.pressed, "recorded echo can press plate A on its own")
	s.hero.global_position = pb.global_position
	s.play_time = 1.0
	s._physics_process(0.0)
	ok(not s.ghost.visible, "echo disappears when its recording ends")
	ok(not pa.pressed and not gate.is_open, "expired echo cannot keep a plate pressed")
	if gate.is_open:
		return

	# A visible echo on A and the hero on B must still solve the puzzle.
	s.ghost.visible = true
	s.play_time = 0.0
	s._physics_process(0.0)
	ok(pa.pressed and pb.pressed and gate.is_open, "simultaneous hero and echo occupancy opens the gallery")
	ok(s.mem.shortcuts.has("gallery"), "successful opening saves the gallery shortcut")
	s.hero.global_position = s.start_pos
	s.play_time = 1.0
	s._process(0.1)  # Let the gate-opening hitstop elapse before the next physics tick.
	s._physics_process(0.0)
	ok(not pa.pressed and not pb.pressed and gate.is_open, "opened gallery stays open after both plates release")
	# init_prop is also used when rebuilding a stage after a rewind.
	gate.is_open = false
	s.ev.init_prop(gate)
	ok(gate.is_open, "saved shortcut reopens the gallery on prop initialization")


func _test_boss_room(s: Stage) -> void:
	# Independent expected room geometry from tools/maps.py:s4(), in tile units.
	var ballroom := Rect2i(10, 2, 36, 5)
	var checked := 0
	for y in s.map.h:
		for x in s.map.w:
			if ballroom.has_point(Vector2i(x, y)) or MapBuilder.SOLID.contains(s.map.cell(x, y)):
				continue
			s.hero.global_position = Vector2(x * Stage.T + 8, y * Stage.T + 14)
			if s.hero.global_position.distance_to(s.boss.global_position) >= float(s.sd.boss.trigger):
				continue
			checked += 1
			s.check_boss_trigger()
			ok(s.state == "play" and not s.boss.engaged and not s.mem.boss_seen,
				"outside-room tile (%d,%d) cannot start or record the boss encounter" % [x, y])
			if s.state != "play":
				return  # An erroneous intro is already awaiting its cinematic timer.
	ok(checked > 0, "checked accessible tiles outside the room but inside the old trigger radius")
	s.hero.global_position = Vector2(10 * Stage.T + 8, 6 * Stage.T + 14)
	s.check_boss_trigger()
	ok(s.state == "play", "being in the room but outside the encounter radius does not start the boss")
	s.hero.global_position = s.boss.global_position + Vector2(0, 32)
	s.state = "pause"
	s.check_boss_trigger()
	ok(s.state == "pause" and not s.boss.engaged, "paused game cannot start a boss encounter")
	s.state = "play"
	Game.dbg.bot = true  # Confirm the real boss dialogue without manual input.
	s.check_boss_trigger()
	ok(s.state == "cutscene", "approaching the boss inside the ballroom starts its actual intro")
	var deadline := Time.get_ticks_msec() + 10000
	while not s.boss.engaged and Time.get_ticks_msec() < deadline:
		await s.get_tree().process_frame
	ok(s.boss.engaged and s.mem.boss_seen and s.state == "play", "actual intro completes and records the encounter inside the room")
	s.check_boss_trigger()
	ok(s.state == "play", "engaged boss does not restart its intro")
