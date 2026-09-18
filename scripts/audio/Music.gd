extends Node
## Two looping tracks, composed here and rendered on a worker thread so the
## game is on screen straight away: a calm one for the kingdom and a driving
## one for a raid. They cross-fade when the scene changes.

const FADE := 1.1

var _players: Dictionary = {}
var _current := ""
var _pending := "kingdom"
var _thread: Thread
var _ready_to_play := false

func _ready() -> void:
	for name in ["kingdom", "raid"]:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_players[name] = p
	_thread = Thread.new()
	_thread.start(_render_tracks)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()

## Fade to a track. Safe to call before the music has finished rendering.
func play(track: String) -> void:
	_pending = track
	if not _ready_to_play or track == _current:
		return
	_current = track
	for name in _players:
		var p: AudioStreamPlayer = _players[name]
		var target := -2.0 if name == track else -60.0
		if name == track and not p.playing:
			p.play()
		create_tween().tween_property(p, "volume_db", target, FADE)

func _render_tracks() -> void:
	var kingdom := _compose_kingdom()
	var raid := _compose_raid()
	_on_rendered.call_deferred(kingdom, raid)

func _on_rendered(kingdom: PackedFloat32Array, raid: PackedFloat32Array) -> void:
	_players["kingdom"].stream = Synth.stream(kingdom, true)
	_players["raid"].stream = Synth.stream(raid, true)
	_ready_to_play = true
	var want := _pending
	_current = ""
	play(want)

# ---------------------------------------------------------------- the music
## Calm and pastoral: a warm pad, a plucked arpeggio and a simple tune over
## C - G - Am - F, the progression every village theme is built on.
func _compose_kingdom() -> PackedFloat32Array:
	var bpm := 92.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var bars := 8
	var buf := Synth.buffer(bar * bars + 1.2)

	# chord per bar, as root plus the notes of the triad
	var roots := [48, 43, 45, 41, 48, 43, 41, 48]
	var triads := [[60, 64, 67], [59, 62, 67], [60, 64, 69], [60, 65, 69],
		[60, 64, 67], [59, 62, 67], [60, 65, 69], [60, 64, 67]]

	for b in bars:
		var t: float = b * bar
		var triad: Array = triads[b]
		# pad: soft, slow to arrive, sits under everything
		Synth.chord(buf, t, bar * 1.02, triad, 0.10, "saw", 0.5, 0.7, 0.008, 1400.0)
		# bass on the first and third beat
		Synth.note(buf, t, beat * 1.6, Synth.hz(roots[b]), 0.30, "triangle", 0.01, 2.0)
		Synth.note(buf, t + beat * 2.0, beat * 1.4, Synth.hz(roots[b] + 12), 0.16, "triangle", 0.01, 2.4)
		# plucked arpeggio on the eighths
		for e in 8:
			var n: int = triad[e % 3] + (12 if e >= 5 else 0)
			Synth.note(buf, t + e * beat * 0.5, beat * 0.62, Synth.hz(n), 0.11, "triangle", 0.004, 3.4)
		# a soft heartbeat
		Synth.noise(buf, t, 0.10, 0.10, 500.0, 120.0, 4.0, 0.002, 7 + b)
		Synth.noise(buf, t + beat * 2.0, 0.09, 0.07, 450.0, 120.0, 4.0, 0.002, 21 + b)
		# brushed offbeats
		for e2 in 4:
			Synth.noise(buf, t + beat * (e2 + 0.5), 0.05, 0.030, 9000.0, 4000.0, 5.0, 0.001, 51 + b * 4 + e2)

	# the tune, two four-bar phrases
	var phrase_a := [[0.0, 72, 1.0], [1.0, 76, 1.0], [2.0, 79, 1.5], [3.5, 76, 0.5],
		[4.0, 74, 1.0], [5.0, 71, 1.0], [6.0, 67, 2.0],
		[8.0, 69, 1.0], [9.0, 72, 1.0], [10.0, 76, 1.5], [11.5, 74, 0.5],
		[12.0, 72, 1.0], [13.0, 69, 1.0], [14.0, 65, 2.0]]
	var phrase_b := [[16.0, 72, 1.0], [17.0, 76, 1.0], [18.0, 81, 1.5], [19.5, 79, 0.5],
		[20.0, 76, 1.0], [21.0, 74, 1.0], [22.0, 71, 2.0],
		[24.0, 69, 1.5], [25.5, 71, 0.5], [26.0, 72, 2.0],
		[28.0, 67, 1.0], [29.0, 64, 1.0], [30.0, 60, 2.0]]
	for entry in phrase_a + phrase_b:
		var at: float = float(entry[0]) * beat
		var dur: float = float(entry[2]) * beat
		Synth.note(buf, at, dur * 0.95, Synth.hz(int(entry[1])), 0.20, "triangle", 0.02, 1.7, 0.5, 0.004)
		Synth.note(buf, at, dur * 0.5, Synth.hz(int(entry[1]) + 12), 0.05, "sine", 0.02, 2.4)

	Synth.fold_tail(buf, bar * bars)
	Synth.normalise(buf, 0.86)
	return buf

## Urgent and percussive for a raid: a pounding bass, a kit, and a minor-key
## motif over Am - F - C - G.
func _compose_raid() -> PackedFloat32Array:
	var bpm := 128.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var bars := 8
	var buf := Synth.buffer(bar * bars + 1.0)

	var roots := [45, 45, 41, 43, 45, 48, 41, 43]
	var triads := [[57, 60, 64], [57, 60, 64], [53, 57, 60], [55, 59, 62],
		[57, 60, 64], [52, 55, 60], [53, 57, 60], [55, 59, 62]]

	for b in bars:
		var t: float = b * bar
		var root: int = roots[b]
		# driving eighth-note bass
		for e in 8:
			var n: int = root if e % 4 != 3 else root + 7
			Synth.note(buf, t + e * beat * 0.5, beat * 0.42, Synth.hz(n - 12), 0.34, "square", 0.004, 2.6, 0.32)
		# stabbed chords on the backbeat
		Synth.chord(buf, t + beat * 1.0, beat * 0.5, triads[b], 0.11, "saw", 0.006, 3.0, 0.012, 2600.0)
		Synth.chord(buf, t + beat * 3.0, beat * 0.5, triads[b], 0.11, "saw", 0.006, 3.0, 0.012, 2600.0)
		# kit: kick, snare, hats
		Synth.note(buf, t, 0.15, 90.0, 0.44, "sine", 0.002, 3.4, 0.5, 0.0, -14.0)
		Synth.note(buf, t + beat * 2.0, 0.15, 90.0, 0.44, "sine", 0.002, 3.4, 0.5, 0.0, -14.0)
		Synth.noise(buf, t + beat * 1.0, 0.16, 0.28, 7000.0, 1300.0, 3.2, 0.001, 101 + b)
		Synth.noise(buf, t + beat * 3.0, 0.16, 0.28, 7000.0, 1300.0, 3.2, 0.001, 131 + b)
		for e2 in 8:
			Synth.noise(buf, t + e2 * beat * 0.5, 0.045, 0.055, 11000.0, 6000.0, 5.0, 0.001, 200 + b * 8 + e2)

	# the motif, answered an octave up in the second half
	var motif := [[0.0, 69, 0.5], [0.5, 72, 0.5], [1.0, 76, 1.0], [2.0, 74, 0.5], [2.5, 72, 0.5], [3.0, 69, 1.0],
		[4.0, 65, 0.5], [4.5, 69, 0.5], [5.0, 72, 1.0], [6.0, 71, 2.0],
		[8.0, 67, 0.5], [8.5, 71, 0.5], [9.0, 74, 1.0], [10.0, 72, 0.5], [10.5, 71, 0.5], [11.0, 67, 1.0],
		[12.0, 69, 0.5], [12.5, 72, 0.5], [13.0, 76, 1.5], [14.5, 79, 1.5]]
	for entry in motif:
		var at: float = float(entry[0]) * beat
		var dur: float = float(entry[2]) * beat
		Synth.note(buf, at, dur * 0.9, Synth.hz(int(entry[1])), 0.17, "square", 0.008, 2.2, 0.42, 0.006)
		Synth.note(buf, at + bar * 4.0, dur * 0.9, Synth.hz(int(entry[1]) + 12), 0.13, "square", 0.008, 2.2, 0.28, 0.006)

	Synth.fold_tail(buf, bar * bars)
	Synth.normalise(buf, 0.86)
	return buf
