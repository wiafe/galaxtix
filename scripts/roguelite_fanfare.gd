extends RefCounted
static func make_split() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(rate * 0.16) * 2)
	for i in data.size() / 2:
		var t := float(i) / rate
		var envelope := minf(t / 0.008, 1.0) * exp(-t * 32.0) * clampf((0.16 - t) / 0.03, 0.0, 1.0)
		data.encode_s16(i * 2, int(sin(TAU * 440.0 * t) * envelope * 0.3 * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

## Short, self-contained synth cues routed through the normal Master bus.
static func make_cue(install := false) -> AudioStreamWAV:
	var rate := 22050
	var length := 0.48 if install else 0.82
	var data := PackedByteArray()
	data.resize(int(rate * length) * 2)
	var notes := [659.25, 830.61, 987.77] if install else [329.63, 415.30, 493.88, 659.25]
	for i in data.size() / 2:
		var t := float(i) / rate
		var sample := 0.0
		for n in notes.size():
			var age := t - n * (0.065 if install else 0.12)
			if age < 0.0:
				continue
			var envelope := minf(age / 0.008, 1.0) * exp(-age * 9.0) * minf((length - t) / 0.04, 1.0)
			sample += sin(TAU * float(notes[n]) * age) * envelope * 0.15
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

static func make_victory() -> AudioStreamWAV:
	var rate := 22050
	var length := 2.1
	var data := PackedByteArray()
	data.resize(int(rate * length) * 2)
	# Rising fifths resolve into a sustained major chord with a low impact.
	var notes := [261.63, 392.0, 523.25, 659.25, 783.99, 1046.5, 130.81]
	var starts := [0.0, 0.14, 0.28, 0.52, 0.52, 0.52, 0.52]
	for i in data.size() / 2:
		var t := float(i) / rate
		var sample := 0.0
		for n in notes.size():
			var age := t - float(starts[n])
			if age < 0.0:
				continue
			var decay := 5.5 if n < 3 else 2.5
			var envelope := minf(age / 0.012, 1.0) * exp(-age * decay) * clampf((length - t) / 0.12, 0.0, 1.0)
			var fundamental := TAU * float(notes[n]) * age
			sample += (sin(fundamental) + 0.18 * sin(fundamental * 2.0)) * envelope * 0.15
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
