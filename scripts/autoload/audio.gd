extends Node
## Music (cross-fade, pitch "hurry" mode), pooled SFX and cached TTS voice lines.

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const VOICE_DIR := "res://assets/audio/voice/"

var players: Array[AudioStreamPlayer] = []
var active := 0
var current := ""
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_i := 0
var voice_player: AudioStreamPlayer
var cache := {}
var music_bus := 0
var duck_db := 0.0
var base_music_db := 0.0
var _duck_tween: Tween
var _pitch_tween: Tween
var _last_sfx := {}
var lowpass: AudioEffectLowPassFilter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music_bus = _bus("Music")
	_bus("SFX")
	_bus("Voice")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 900.0
	AudioServer.add_bus_effect(music_bus, lowpass)
	AudioServer.set_bus_effect_enabled(music_bus, 0, false)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		players.append(p)
	for i in 16:
		var s := AudioStreamPlayer.new()
		s.bus = "SFX"
		add_child(s)
		sfx_pool.append(s)
	voice_player = AudioStreamPlayer.new()
	voice_player.bus = "Voice"
	add_child(voice_player)
	voice_player.finished.connect(_on_voice_done)
	apply_volumes(Game.save.settings)


func _bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


func _lin_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


func apply_volumes(st: Dictionary) -> void:
	base_music_db = _lin_db(float(st.get("music", 0.75)))
	AudioServer.set_bus_volume_db(music_bus, base_music_db + duck_db)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _lin_db(float(st.get("sfx", 0.9))))
	var vv := float(st.get("voice", 1.0)) if st.get("voice_on", true) else 0.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), _lin_db(vv))


func _load(path: String) -> Resource:
	if cache.has(path):
		return cache[path]
	var r: Resource = null
	if ResourceLoader.exists(path):
		r = load(path)
	cache[path] = r
	return r


# ------------------------------------------------------------------ music
func play_music(track: String, fade := 0.6, restart := false) -> void:
	if track == current and not restart:
		return
	var st: AudioStream = _load(MUSIC_DIR + track + ".ogg")
	if st == null:
		stop_music(fade)
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	var old := players[active]
	active = 1 - active
	var p := players[active]
	p.stream = st
	p.volume_db = -40.0 if fade > 0 else 0.0
	p.pitch_scale = 1.0
	p.play()
	current = track
	var tw := create_tween().set_parallel(true)
	if fade > 0:
		tw.tween_property(p, "volume_db", 0.0, fade)
	if old.playing:
		tw.tween_property(old, "volume_db", -40.0, max(fade, 0.05))
		tw.chain().tween_callback(old.stop)


func play_jingle(track: String) -> void:
	## One-shot music (victory / fail). Stops the loop.
	var st: AudioStream = _load(MUSIC_DIR + track + ".ogg")
	stop_music(0.15)
	if st == null:
		return
	var p := players[1 - active]
	if st is AudioStreamOggVorbis:
		var one := (st as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		one.loop = false
		st = one
	p.stream = st
	p.volume_db = 0.0
	p.pitch_scale = 1.0
	p.play()
	active = 1 - active
	current = "#" + track


func stop_music(fade := 0.5) -> void:
	current = ""
	for p in players:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -40.0, max(fade, 0.05))
			tw.tween_callback(p.stop)


func set_music_pitch(pitch: float, t := 0.5) -> void:
	if _pitch_tween and _pitch_tween.is_valid():
		_pitch_tween.kill()
	_pitch_tween = create_tween().set_parallel(true)
	for p in players:
		_pitch_tween.tween_property(p, "pitch_scale", pitch, t)


func set_muffled(on: bool) -> void:
	AudioServer.set_bus_effect_enabled(music_bus, 0, on)


func _set_duck(db: float, t: float) -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(v: float):
		duck_db = v
		AudioServer.set_bus_volume_db(music_bus, base_music_db + duck_db), duck_db, db, t)


# ------------------------------------------------------------------ sfx
func sfx(sfx_name: String, vol := 0.0, pitch := 1.0, rand := 0.0) -> void:
	var st: AudioStream = _load(SFX_DIR + sfx_name + ".wav")
	if st == null:
		return
	# avoid machine-gun stacking of the same sample within one frame
	var now := Time.get_ticks_msec()
	if _last_sfx.get(sfx_name, -100) > now - 25:
		return
	_last_sfx[sfx_name] = now
	var p := sfx_pool[sfx_i]
	sfx_i = (sfx_i + 1) % sfx_pool.size()
	p.stream = st
	p.volume_db = vol
	p.pitch_scale = max(0.05, pitch * (1.0 + randf_range(-rand, rand)))
	p.play()


# ------------------------------------------------------------------ voice
func has_voice(id: String) -> bool:
	return id != "" and Game.save.settings.get("voice_on", true) and ResourceLoader.exists(VOICE_DIR + id + ".ogg")


func voice(id: String) -> float:
	## Plays a cached Fish Audio line. Returns its length (0 if unavailable).
	if not has_voice(id):
		return 0.0
	var st: AudioStream = _load(VOICE_DIR + id + ".ogg")
	if st == null:
		return 0.0
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = false
	voice_player.stream = st
	voice_player.play()
	_set_duck(-8.0, 0.15)
	return st.get_length()


func stop_voice() -> void:
	if voice_player.playing:
		voice_player.stop()
	_on_voice_done()


func _on_voice_done() -> void:
	_set_duck(0.0, 0.4)
