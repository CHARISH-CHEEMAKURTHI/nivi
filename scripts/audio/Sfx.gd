extends Node
## Every sound effect in the game, rendered at startup and played through a
## small pool of players so overlapping sounds never cut each other off.

const SETTINGS_PATH := "user://nivi_settings.cfg"
const VOICES := 10

var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}

var sfx_enabled := true:
	set(value):
		sfx_enabled = value
		AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not value)
		save_settings()
var music_enabled := true:
	set(value):
		music_enabled = value
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not value)
		save_settings()

func _ready() -> void:
	_make_buses()
	load_settings()
	_build_sounds()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

## Separate buses so music and effects can be muted independently.
func _make_buses() -> void:
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -8.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -4.0)

# ---------------------------------------------------------------- playback
func play(name: String, pitch := 1.0, throttle := 0.0) -> void:
	if not _sounds.has(name) or not sfx_enabled:
		return
	# some sounds fire many times a second in a raid; thin them out
	if throttle > 0.0:
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(_last_played.get(name, -99.0)) < throttle:
			return
		_last_played[name] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[name]
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()

# ---------------------------------------------------------------- settings
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		sfx_enabled = true
		music_enabled = true
		return
	sfx_enabled = bool(cfg.get_value("audio", "sfx", true))
	music_enabled = bool(cfg.get_value("audio", "music", true))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx", sfx_enabled)
	cfg.set_value("audio", "music", music_enabled)
	cfg.save(SETTINGS_PATH)

# ---------------------------------------------------------------- the sounds
func _add(name: String, buf: PackedFloat32Array, peak := 0.8) -> void:
	Synth.normalise(buf, peak)
	_sounds[name] = Synth.stream(buf)

func _build_sounds() -> void:
	_ui_sounds()
	_kingdom_sounds()
	_battle_sounds()

func _ui_sounds() -> void:
	# a soft wooden click
	var tap := Synth.buffer(0.10)
	Synth.note(tap, 0.0, 0.07, Synth.hz(93), 0.5, "triangle", 0.002, 6.0)
	Synth.noise(tap, 0.0, 0.03, 0.22, 4200.0, 1200.0, 5.0)
	_add("tap", tap)

	# panel sliding open, and shut again
	var open := Synth.buffer(0.26)
	Synth.note(open, 0.0, 0.20, Synth.hz(69), 0.34, "triangle", 0.01, 2.2, 0.5, 0.0, 7.0)
	Synth.noise(open, 0.0, 0.18, 0.13, 900.0, 3600.0, 1.6)
	_add("open", open)

	var close := Synth.buffer(0.24)
	Synth.note(close, 0.0, 0.17, Synth.hz(76), 0.34, "triangle", 0.005, 2.6, 0.5, 0.0, -7.0)
	Synth.noise(close, 0.0, 0.15, 0.12, 3200.0, 700.0, 2.0)
	_add("close", close)

	# a flat refusal
	var error := Synth.buffer(0.30)
	Synth.note(error, 0.0, 0.12, Synth.hz(51), 0.4, "square", 0.004, 2.0, 0.34)
	Synth.note(error, 0.15, 0.13, Synth.hz(48), 0.4, "square", 0.004, 2.0, 0.34)
	_add("error", error)

func _kingdom_sounds() -> void:
	# a building set down: dust, then weight
	var place := Synth.buffer(0.55)
	Synth.note(place, 0.0, 0.34, 78.0, 0.62, "sine", 0.003, 3.4, 0.5, 0.0, -4.0)
	Synth.noise(place, 0.0, 0.30, 0.34, 3000.0, 380.0, 2.6)
	Synth.noise(place, 0.06, 0.24, 0.16, 5200.0, 1800.0, 2.2)
	_add("place", place)

	# construction finished: a bright little fanfare
	var done := Synth.buffer(0.95)
	var chime := [72, 76, 79, 84]
	for i in chime.size():
		Synth.note(done, i * 0.10, 0.62 - i * 0.05, Synth.hz(chime[i]), 0.42, "triangle", 0.004, 3.2)
		Synth.note(done, i * 0.10, 0.30, Synth.hz(chime[i] + 12), 0.14, "sine", 0.004, 4.0)
	_add("done", done)

	# resources collected
	var collect := Synth.buffer(0.42)
	for i in 3:
		Synth.note(collect, i * 0.055, 0.26, Synth.hz(79 + i * 5), 0.4, "triangle", 0.002, 4.2)
	Synth.note(collect, 0.0, 0.08, Synth.hz(91), 0.18, "sine", 0.001, 6.0)
	_add("collect", collect)

	# hammer on an anvil
	var train := Synth.buffer(0.40)
	Synth.note(train, 0.0, 0.26, 1180.0, 0.34, "square", 0.001, 5.5, 0.28, 0.011)
	Synth.note(train, 0.0, 0.10, 320.0, 0.30, "triangle", 0.001, 6.0)
	Synth.noise(train, 0.0, 0.07, 0.24, 8000.0, 2600.0, 5.0)
	_add("train", train)

	# a star awarded
	var star := Synth.buffer(0.85)
	Synth.note(star, 0.0, 0.70, Synth.hz(88), 0.4, "sine", 0.003, 2.6)
	Synth.note(star, 0.0, 0.45, Synth.hz(95), 0.18, "sine", 0.003, 3.4)
	Synth.note(star, 0.08, 0.55, Synth.hz(93), 0.22, "triangle", 0.004, 3.0)
	_add("star", star)

	# raid won, and raid lost
	var victory := Synth.buffer(1.7)
	var fanfare := [72, 76, 79, 84, 79, 84]
	var times := [0.0, 0.14, 0.28, 0.44, 0.62, 0.76]
	for i in fanfare.size():
		Synth.note(victory, times[i], 0.9, Synth.hz(fanfare[i]), 0.34, "triangle", 0.006, 2.4, 0.5, 0.008)
	Synth.chord(victory, 0.76, 0.9, [48, 60, 64, 67, 72], 0.14, "saw", 0.02, 1.8, 0.01, 2200.0)
	_add("victory", victory)

	var defeat := Synth.buffer(1.5)
	for i in 3:
		Synth.note(defeat, i * 0.22, 1.0 - i * 0.1, Synth.hz(64 - i * 3), 0.34, "triangle", 0.01, 2.0, 0.5, 0.01)
	Synth.chord(defeat, 0.66, 0.8, [40, 47, 51], 0.2, "saw", 0.04, 1.6, 0.012, 1100.0)
	_add("defeat", defeat)

func _battle_sounds() -> void:
	# troops dropping onto the field
	var deploy := Synth.buffer(0.5)
	Synth.noise(deploy, 0.0, 0.26, 0.26, 700.0, 4200.0, 1.3)
	Synth.note(deploy, 0.14, 0.26, 96.0, 0.5, "sine", 0.003, 3.6, 0.5, 0.0, -5.0)
	_add("deploy", deploy)

	# steel on stone
	var sword := Synth.buffer(0.26)
	Synth.noise(sword, 0.0, 0.14, 0.42, 7200.0, 1500.0, 4.5)
	Synth.note(sword, 0.0, 0.10, 520.0, 0.22, "square", 0.001, 5.0, 0.22)
	_add("sword", sword)

	# a creature's bolt
	var magic := Synth.buffer(0.45)
	Synth.note(magic, 0.0, 0.34, 620.0, 0.34, "sine", 0.004, 2.6, 0.5, 0.0, 9.0, 0.02)
	Synth.note(magic, 0.02, 0.28, 930.0, 0.16, "triangle", 0.004, 3.0, 0.5, 0.0, 7.0)
	Synth.noise(magic, 0.0, 0.3, 0.1, 5000.0, 900.0, 2.0)
	_add("magic", magic)

	# the short-fire cannon
	var cannon := Synth.buffer(0.7)
	Synth.note(cannon, 0.0, 0.42, 72.0, 0.7, "sine", 0.002, 3.0, 0.5, 0.0, -8.0)
	Synth.noise(cannon, 0.0, 0.34, 0.5, 5200.0, 260.0, 3.0)
	_add("cannon", cannon)

	# a building coming down
	var destroy := Synth.buffer(1.3)
	Synth.note(destroy, 0.0, 0.7, 58.0, 0.72, "sine", 0.003, 2.4, 0.5, 0.0, -7.0)
	Synth.noise(destroy, 0.0, 0.85, 0.55, 3800.0, 190.0, 2.0)
	Synth.noise(destroy, 0.22, 0.6, 0.24, 1500.0, 320.0, 1.6)
	_add("destroy", destroy)

	# a troop falling
	var fell := Synth.buffer(0.55)
	Synth.note(fell, 0.0, 0.36, 210.0, 0.3, "triangle", 0.005, 2.6, 0.5, 0.0, -10.0)
	Synth.noise(fell, 0.05, 0.28, 0.18, 1800.0, 400.0, 2.4)
	_add("fell", fell)
