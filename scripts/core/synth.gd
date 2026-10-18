class_name Synth
extends RefCounted
## Sintetizador chiptune/arcade 100% por código (sem assets): músicas em loop e efeitos sonoros.
## Tudo é renderizado em PCM mono 16 bits (22,05 kHz) e devolvido como PackedByteArray, para rodar
## numa thread (WorkerThreadPool); o AudioManager embrulha os bytes em AudioStreamWAV.

const RATE := 22050

enum Wave { PULSE25, PULSE12, TRIANGLE, SAW, SINE }

## Acordes: raiz (MIDI, oitava 3) e tipo.
const CHORDS := {
	"C": [48, 0], "D": [50, 0], "Dm": [50, 1], "E": [52, 0], "Em": [52, 1], "F": [53, 0],
	"G": [55, 0], "A": [57, 0], "Am": [57, 1], "Bb": [58, 0],
}
const NOTE_INDEX := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


static func midi_freq(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## "E5" -> 76, "F#4" -> 66.
static func note_midi(n: String) -> int:
	var base: int = NOTE_INDEX[n.substr(0, 1)]
	var i := 1
	if n.substr(1, 1) == "#":
		base += 1
		i = 2
	elif n.substr(1, 1) == "b":
		base -= 1
		i = 2
	return base + (n.substr(i).to_int() + 1) * 12


# ------------------------------------------------------------------ vozes

static func _osc(w: int, ph: float) -> float:
	match w:
		Wave.PULSE25:
			return 1.0 if ph < 0.25 else -1.0
		Wave.PULSE12:
			return 1.0 if ph < 0.125 else -1.0
		Wave.TRIANGLE:
			return 4.0 * absf(ph - 0.5) - 1.0
		Wave.SAW:
			return 2.0 * ph - 1.0
	return sin(ph * TAU)


## Soma uma nota em `buf` (com volta ao início: loop sem emenda).
## Envelope: ataque curto, decaimento até `sustain`, soltura em `release` s. Vibrato opcional.
static func add_note(buf: PackedFloat32Array, start: int, dur: float, freq: float, wave: int, vol: float,
		sustain: float = 0.6, decay: float = 0.08, release: float = 0.05, vibrato: float = 0.0, lp: float = 1.0) -> void:
	var n := buf.size()
	var held := int(dur * RATE)
	var total := held + int(release * RATE)
	var att := 0.004 * RATE
	var dec := maxf(decay * RATE, 1.0)
	var rel := maxf(release * RATE, 1.0)
	var ph := 0.0
	var inc := freq / RATE
	var y := 0.0
	for i in total:
		var env: float
		if i < att:
			env = i / att
		elif i < att + dec:
			env = 1.0 - (1.0 - sustain) * ((i - att) / dec)
		else:
			env = sustain
		if i >= held:
			env *= 1.0 - (i - held) / rel
		var f := inc
		if vibrato > 0.0 and i > 0.12 * RATE:
			f *= 1.0 + vibrato * sin(i * (TAU * 5.5 / RATE))
		ph += f
		ph -= floorf(ph)
		y += lp * (_osc(wave, ph) - y)
		var j := (start + i) % n
		buf[j] += y * env * vol


## Bateria: 0 = bumbo, 1 = caixa, 2 = chimbal.
static func add_drum(buf: PackedFloat32Array, start: int, kind: int, vol: float, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var len_s: float = [0.16, 0.14, 0.035][kind]
	var total := int(len_s * RATE)
	var ph := 0.0
	var lp := 0.0
	var prev := 0.0
	for i in total:
		var t := float(i) / RATE
		var s := 0.0
		match kind:
			0:
				var f := 45.0 + 110.0 * exp(-t * 35.0)
				ph += f / RATE
				s = sin(ph * TAU) * exp(-t * 18.0)
			1:
				var nz := rng.randf_range(-1.0, 1.0)
				lp += 0.55 * (nz - lp)
				ph += 190.0 / RATE
				s = (lp * 0.8 + sin(ph * TAU) * 0.35 * exp(-t * 30.0)) * exp(-t * 22.0)
			2:
				var nz2 := rng.randf_range(-1.0, 1.0)
				s = (nz2 - prev) * 0.5 * exp(-t * 90.0)
				prev = nz2
		buf[(start + i) % n] += s * vol


# ------------------------------------------------------------------ músicas

## Renderiza uma música. `song`: {bpm, chords: Array[String] (1 por compasso), melody: Array[String]
## (colcheias; "-" sustenta, "." pausa), drums: String por compasso em semicolcheias
## ("k" bumbo, "s" caixa, "h" chimbal, "x" caixa+chimbal, "." nada), arp16: bool}.
static func render_song(song: Dictionary) -> PackedByteArray:
	var bpm: float = song["bpm"]
	var chords: Array = song["chords"]
	var bars := chords.size()
	var eighth := 60.0 / bpm * 0.5
	var sixteenth := eighth * 0.5
	var n := int(round(bars * 8 * eighth * RATE))
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var s8 := func(k: int) -> int: return int(round(k * eighth * RATE))
	var s16 := func(k: int) -> int: return int(round(k * sixteenth * RATE))

	# Melodia (pulso 25% com vibrato leve + eco de pulso 12% uma oitava abaixo, bem baixinho).
	var mel: Array = song["melody"]
	var i := 0
	while i < mel.size():
		var tok: String = mel[i]
		if tok == "-" or tok == ".":
			i += 1
			continue
		var len8 := 1
		while i + len8 < mel.size() and mel[i + len8] == "-":
			len8 += 1
		var m := note_midi(tok)
		var d := len8 * eighth * 0.92
		add_note(buf, s8.call(i), d, midi_freq(m), Wave.PULSE25, 0.2, 0.55, 0.1, 0.06, 0.006, 0.55)
		add_note(buf, s8.call(i) + int(eighth * 1.5 * RATE), d * 0.8, midi_freq(m), Wave.PULSE12, 0.05, 0.5, 0.1, 0.05, 0.0, 0.4)
		i += len8

	var bass_pat: Array = song.get("bass", [0, 12, 0, 12, 7, 12, 0, 12])
	var drums: Array = song["drums"]
	var arp16: bool = song.get("arp16", true)
	for b in bars:
		var ch: Array = CHORDS[chords[b]]
		var root: int = ch[0]
		var third := 3 if ch[1] == 1 else 4
		var tones: Array[int] = [0, third, 7, 12, 7, third]
		# Baixo (triângulo) em colcheias.
		for e in 8:
			var bi: int = bass_pat[e]
			if bi < 0:
				continue
			add_note(buf, s8.call(b * 8 + e), eighth * 0.7, midi_freq(root - 12 + bi), Wave.TRIANGLE, 0.34, 0.8, 0.05, 0.03)
		# Arpejo (pulso 12%) em semicolcheias ou colcheias.
		var steps := 16 if arp16 else 8
		for e in steps:
			var tone: int = tones[e % tones.size()]
			var st: int = s16.call(b * 16 + e) if arp16 else s8.call(b * 8 + e)
			add_note(buf, st, (sixteenth if arp16 else eighth) * 0.6, midi_freq(root + 12 + tone), Wave.PULSE12, 0.07, 0.4, 0.04, 0.02, 0.0, 0.5)
		# Bateria.
		var pat: String = drums[b % drums.size()]
		for e in mini(pat.length(), 16):
			var c := pat.substr(e, 1)
			var st2: int = s16.call(b * 16 + e)
			if c == "k":
				add_drum(buf, st2, 0, 0.6, rng)
			elif c == "s":
				add_drum(buf, st2, 1, 0.3, rng)
			elif c == "h":
				add_drum(buf, st2, 2, 0.16, rng)
			elif c == "x":
				add_drum(buf, st2, 1, 0.3, rng)
				add_drum(buf, st2, 2, 0.16, rng)
	return to_pcm16(buf, 0.78)


## Normaliza pelo pico (sem clipping) e converte para PCM 16 bits.
static func to_pcm16(buf: PackedFloat32Array, peak_target: float = 0.8) -> PackedByteArray:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var g := peak_target / peak * 32767.0
	var out := PackedByteArray()
	out.resize(buf.size() * 2)
	for i in buf.size():
		out.encode_s16(i * 2, int(clampf(buf[i] * g, -32767.0, 32767.0)))
	return out


static func title_song() -> Dictionary:
	return {
		"bpm": 118.0,
		"chords": ["F", "G", "Em", "Am", "Dm", "G", "C", "C", "F", "G", "Em", "Am", "Dm", "G", "C", "G"],
		"melody": [
			"A4", "-", "C5", "-", "F5", "-", "E5", "-",
			"D5", "-", "-", "B4", "G4", "-", "-", ".",
			"E5", "-", "G5", "-", "B5", "-", "A5", "G5",
			"A5", "-", "-", "-", "E5", "-", "-", ".",
			"F5", "-", "E5", "-", "D5", "-", "A4", "-",
			"B4", "-", "D5", "-", "G5", "-", "F5", "D5",
			"E5", "-", "-", "G5", "-", "-", "C5", "-",
			"C5", "-", "-", "-", ".", ".", ".", ".",
			"C6", "-", "A5", "-", "F5", "-", "A5", "C6",
			"B5", "-", "G5", "-", "D5", "-", "G5", "B5",
			"G5", "-", "E5", "-", "B4", "-", "E5", "G5",
			"A5", "-", "E5", "-", "C5", "-", "E5", "A5",
			"F5", "-", "A5", "-", "D6", "-", "C6", "A5",
			"B5", "-", "-", "A5", "G5", "-", "F5", "D5",
			"E5", "-", "G5", "-", "C6", "-", "-", "-",
			"D6", "-", "-", "-", "B5", "-", "G5", "-",
		],
		"bass": [0, -1, 12, -1, 7, -1, 12, -1],
		"drums": ["k...h...s...h...", "k...h.k.s...h..h"],
		"arp16": true,
	}


static func race_song() -> Dictionary:
	return {
		"bpm": 150.0,
		"chords": ["C", "G", "Am", "F", "C", "G", "F", "G", "F", "G", "Em", "Am", "F", "G", "C", "G"],
		"melody": [
			"E5", ".", "G5", ".", "C6", "-", "B5", "A5",
			"G5", "-", "D5", ".", "G5", "A5", "B5", "-",
			"C6", "-", "B5", "A5", "E5", "-", "A5", "-",
			"F5", "G5", "A5", "-", "C6", "-", "A5", ".",
			"E5", ".", "G5", ".", "C6", "-", "D6", "E6",
			"D6", "-", "B5", "G5", "D5", "-", "G5", "-",
			"A5", "G5", "F5", "A5", "C6", "-", "A5", "F5",
			"G5", "-", "-", ".", "B4", "C5", "D5", ".",
			"A5", "-", "C6", "-", "F6", "-", "E6", "D6",
			"D6", "-", "B5", "-", "G5", "-", "A5", "B5",
			"G5", "-", "E5", "-", "B5", "-", "G5", "E5",
			"A5", "-", "-", "C6", "E6", "-", "D6", "C6",
			"A5", "-", "C6", "-", "F6", "E6", "D6", "C6",
			"B5", "-", "D6", "-", "G6", "-", "F6", "D6",
			"E6", "-", "C6", "-", "G5", "-", "E5", "G5",
			"C6", "-", "-", "-", ".", ".", "G5", "B5",
		],
		"bass": [0, 12, 0, 12, 7, 12, 0, 12],
		"drums": ["k.h.x.h.k.hkx.h.", "k.h.x.h.k.h.x.hh", "k.h.x.h.k.hkx.h.", "k.h.x.hkk.x.xxxx"],
		"arp16": true,
	}


# ------------------------------------------------------------------ efeitos

static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Varredura de frequência (f0 -> f1) com decaimento exponencial.
static func _sweep(b: PackedFloat32Array, f0: float, f1: float, wave: int, vol: float, decay: float, start: int = 0, length: int = -1) -> void:
	var total := b.size() - start if length < 0 else length
	var ph := 0.0
	for i in total:
		var t := float(i) / float(total)
		ph += lerpf(f0, f1, t) / RATE
		ph -= floorf(ph)
		b[start + i] += _osc(wave, ph) * vol * exp(-t * decay)


static func _noise(b: PackedFloat32Array, vol: float, decay: float, cutoff0: float, cutoff1: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var lp := 0.0
	var n := b.size()
	for i in n:
		var t := float(i) / float(n)
		lp += lerpf(cutoff0, cutoff1, t) * (rng.randf_range(-1.0, 1.0) - lp)
		b[i] += lp * vol * exp(-t * decay)


static func _notes(b: PackedFloat32Array, midis: Array, step: float, wave: int, vol: float) -> void:
	for k in midis.size():
		add_note(b, int(k * step * RATE), step * 0.9, midi_freq(midis[k]), wave, vol, 0.7, 0.03, 0.03)


## Todos os efeitos: nome -> [bytes PCM16, loop?].
static func render_sfx() -> Dictionary:
	var out := {}
	# Motor: laço curto de período inteiro (50 Hz) com harmônicos; o pitch sobe com a velocidade.
	var eng := _buf(441.0 * 8.0 / RATE)
	var ph := 0.0
	for i in eng.size():
		ph = float(i % 441) / 441.0
		var s := (2.0 * ph - 1.0) * 0.45 + (1.0 if fmod(ph * 2.0, 1.0) < 0.3 else -1.0) * 0.2 + sin(ph * TAU * 3.0) * 0.2
		s *= 0.75 + 0.25 * sin(float(i) / eng.size() * TAU * 4.0)
		eng[i] = s
	out["engine"] = [to_pcm16(eng, 0.6), true]
	var b := _buf(0.24)
	_notes(b, [84, 88, 91, 96], 0.05, Wave.PULSE25, 0.5)
	out["item"] = [to_pcm16(b, 0.6), false]
	b = _buf(0.6)
	_sweep(b, 180.0, 900.0, Wave.SAW, 0.4, 3.0)
	_noise(b, 0.6, 4.0, 0.2, 0.7, 3)
	out["boost"] = [to_pcm16(b, 0.6), false]
	b = _buf(0.7)
	_noise(b, 0.9, 3.5, 0.05, 0.6, 5)
	_sweep(b, 500.0, 160.0, Wave.PULSE25, 0.15, 2.0)
	out["rocket"] = [to_pcm16(b, 0.65), false]
	b = _buf(0.9)
	_noise(b, 1.0, 5.0, 0.5, 0.03, 9)
	_sweep(b, 90.0, 35.0, Wave.SINE, 0.8, 6.0)
	out["explosion"] = [to_pcm16(b, 0.8), false]
	b = _buf(0.5)
	var ph2 := 0.0
	for i in b.size():
		var t := float(i) / b.size()
		ph2 += (900.0 - 700.0 * t) * (1.0 + 0.2 * sin(t * TAU * 12.0)) / RATE
		ph2 -= floorf(ph2)
		b[i] = (1.0 if ph2 < 0.5 else -1.0) * 0.35 * (1.0 - t)
	out["spin"] = [to_pcm16(b, 0.55), false]
	b = _buf(0.16)
	_sweep(b, 1800.0, 1800.0, Wave.SINE, 0.5, 12.0)
	_sweep(b, 2700.0, 2700.0, Wave.SINE, 0.25, 16.0)
	out["spark"] = [to_pcm16(b, 0.5), false]
	b = _buf(0.08)
	_sweep(b, 420.0, 760.0, Wave.PULSE25, 0.4, 4.0)
	out["hop"] = [to_pcm16(b, 0.45), false]
	b = _buf(0.22)
	_sweep(b, 440.0, 440.0, Wave.PULSE25, 0.5, 5.0)
	out["count"] = [to_pcm16(b, 0.6), false]
	b = _buf(0.6)
	_sweep(b, 880.0, 880.0, Wave.PULSE25, 0.5, 3.5)
	out["go"] = [to_pcm16(b, 0.65), false]
	b = _buf(0.6)
	_notes(b, [72, 76, 79, 84, 84], 0.1, Wave.PULSE25, 0.45)
	out["lastlap"] = [to_pcm16(b, 0.6), false]
	b = _buf(0.04)
	_sweep(b, 1250.0, 1250.0, Wave.PULSE12, 0.4, 6.0)
	out["move"] = [to_pcm16(b, 0.35), false]
	b = _buf(0.16)
	_notes(b, [79, 86], 0.07, Wave.PULSE25, 0.45)
	out["confirm"] = [to_pcm16(b, 0.5), false]
	b = _buf(0.16)
	_notes(b, [86, 79], 0.07, Wave.PULSE25, 0.45)
	out["back"] = [to_pcm16(b, 0.45), false]
	return out
