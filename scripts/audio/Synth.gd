class_name Synth
extends RefCounted
## A small software synthesiser. Every sound in the game is rendered from these
## primitives at startup, so the project still ships without audio files.
##
## Samples are worked on as floats in the range -1..1 and only converted to
## 16-bit PCM at the very end.

const RATE := 22050

# ---------------------------------------------------------------- helpers
## Frequency of a MIDI note number. 69 is A above middle C, at 440 Hz.
static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

static func buffer(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	buf.fill(0.0)
	return buf

const SHAPE_SINE := 0
const SHAPE_TRIANGLE := 1
const SHAPE_SQUARE := 2
const SHAPE_SAW := 3

static func _shape_id(shape: String) -> int:
	match shape:
		"triangle": return SHAPE_TRIANGLE
		"square": return SHAPE_SQUARE
		"saw": return SHAPE_SAW
	return SHAPE_SINE

# ---------------------------------------------------------------- voices
## A pitched note. `bend` slides the pitch by that many semitones across the
## note, `detune` layers a second copy slightly out of tune for thickness.
##
## The sample loop below is deliberately flat, with the waveform and envelope
## worked out inline: rendering the soundtrack means millions of iterations, and
## a function call per sample is the difference between a moment and a stall.
static func note(buf: PackedFloat32Array, at: float, dur: float, freq: float, amp: float,
		shape := "sine", attack := 0.006, curve := 3.0, duty := 0.5,
		detune := 0.0, bend := 0.0, vibrato := 0.0, lowpass := 0.0) -> void:
	var start := int(at * RATE)
	var count := int(dur * RATE)
	if start < 0 or count <= 0 or start >= buf.size():
		return
	count = mini(count, buf.size() - start)
	var kind := _shape_id(shape)

	# pitch as a per-sample phase step, swept linearly when the note bends
	var inc_a := freq / float(RATE)
	var inc_b := freq * pow(2.0, bend / 12.0) / float(RATE)
	var inc_step := (inc_b - inc_a) / float(count)

	# attack ramp, then an exponential fall, then a short fade so it never clicks
	var attack_n := maxi(1, int(attack * RATE))
	var decay_mul := exp(-(curve * 2.6) / maxf(float(count - attack_n), 1.0))
	var fade_n := mini(int(0.004 * RATE), count / 4)
	var fade_from := count - fade_n

	var filter_k := 0.0
	if lowpass > 0.0:
		filter_k = clampf(1.0 - exp(-TAU * lowpass / float(RATE)), 0.01, 1.0)

	var phase := 0.0
	var phase2 := 0.0
	var inc := inc_a
	var env := 0.0
	var filtered := 0.0
	var detune_mul := 1.0 + detune
	var use_detune := detune > 0.0
	var use_vibrato := vibrato > 0.0
	var vib_phase := 0.0
	var vib_inc := 5.5 / float(RATE)

	for i in count:
		# envelope
		if i < attack_n:
			env = float(i) / float(attack_n)
		elif i == attack_n:
			env = 1.0
		else:
			env *= decay_mul
		if i >= fade_from:
			env *= float(count - i) / float(fade_n)

		var step := inc
		if use_vibrato:
			vib_phase += vib_inc
			step = inc * (1.0 + sin(vib_phase * TAU) * vibrato)

		phase += step
		if phase >= 1.0:
			phase -= 1.0

		var v := 0.0
		if kind == SHAPE_SINE:
			v = sin(phase * TAU)
		elif kind == SHAPE_TRIANGLE:
			v = 4.0 * absf(phase - 0.5) - 1.0
		elif kind == SHAPE_SQUARE:
			v = 1.0 if phase < duty else -1.0
		else:
			v = phase * 2.0 - 1.0

		if use_detune:
			phase2 += step * detune_mul
			if phase2 >= 1.0:
				phase2 -= 1.0
			var v2 := 0.0
			if kind == SHAPE_SINE:
				v2 = sin(phase2 * TAU)
			elif kind == SHAPE_TRIANGLE:
				v2 = 4.0 * absf(phase2 - 0.5) - 1.0
			elif kind == SHAPE_SQUARE:
				v2 = 1.0 if phase2 < duty else -1.0
			else:
				v2 = phase2 * 2.0 - 1.0
			v = (v + v2) * 0.5

		v *= env * amp
		if filter_k > 0.0:
			filtered += (v - filtered) * filter_k
			v = filtered
		buf[start + i] += v
		inc += inc_step

## Filtered noise, for thuds, hits and drums. Uses its own small generator so it
## stays deterministic and safe to call from a worker thread.
static func noise(buf: PackedFloat32Array, at: float, dur: float, amp: float,
		lowpass_from := 6000.0, lowpass_to := 600.0, curve := 3.0, attack := 0.001, seed_value := 12345) -> void:
	var start := int(at * RATE)
	var count := int(dur * RATE)
	if start < 0 or count <= 0 or start >= buf.size():
		return
	count = mini(count, buf.size() - start)
	var attack_n := maxi(1, int(attack * RATE))
	var decay_mul := exp(-(curve * 2.6) / maxf(float(count - attack_n), 1.0))
	var fade_n := mini(int(0.004 * RATE), count / 4)
	var fade_from := count - fade_n
	var cut := lowpass_from
	var cut_step := (lowpass_to - lowpass_from) / float(count)
	var filtered := 0.0
	var env := 0.0
	var rng: int = seed_value | 1

	for i in count:
		if i < attack_n:
			env = float(i) / float(attack_n)
		elif i == attack_n:
			env = 1.0
		else:
			env *= decay_mul
		if i >= fade_from:
			env *= float(count - i) / float(fade_n)

		# xorshift: cheap, repeatable white noise
		rng ^= (rng << 13) & 0x7FFFFFFF
		rng ^= rng >> 17
		rng ^= (rng << 5) & 0x7FFFFFFF
		var white := float(rng % 20001) / 10000.0 - 1.0

		var k := clampf(1.0 - exp(-TAU * cut / float(RATE)), 0.01, 1.0)
		filtered += (white - filtered) * k
		buf[start + i] += filtered * env * amp
		cut += cut_step

## A chord: several notes struck together.
static func chord(buf: PackedFloat32Array, at: float, dur: float, midi_notes: Array, amp: float,
		shape := "triangle", attack := 0.01, curve := 2.0, detune := 0.0, lowpass := 0.0) -> void:
	for m in midi_notes:
		note(buf, at, dur, hz(float(m)), amp, shape, attack, curve, 0.5, detune, 0.0, 0.0, lowpass)

# ---------------------------------------------------------------- output
## Bring the loudest moment to a set level, so quiet arrangements are not left
## inaudible and dense ones never clip into a crackle.
static func normalise(buf: PackedFloat32Array, peak := 0.82, max_gain := 6.0) -> void:
	var loudest := 0.0
	for v in buf:
		loudest = maxf(loudest, absf(v))
	if loudest <= 0.0001:
		return
	var gain: float = minf(peak / loudest, max_gain)
	for i in buf.size():
		buf[i] = buf[i] * gain

## Make a loop join cleanly. The track is rendered a little longer than the
## loop so the last notes can ring on; that overhang is added back onto the
## start and trimmed off, so whatever was still sounding carries over the join
## exactly as it would mid-track.
static func fold_tail(buf: PackedFloat32Array, loop_seconds: float) -> void:
	var loop_n := int(loop_seconds * RATE)
	if loop_n <= 0 or loop_n >= buf.size():
		return
	for i in range(loop_n, buf.size()):
		buf[i - loop_n] += buf[i]
	buf.resize(loop_n)

static func to_pcm(buf: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	return bytes

static func stream(buf: PackedFloat32Array, looping := false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = to_pcm(buf)
	if looping:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s
