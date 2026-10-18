class_name Synth
extends RefCounted
## Sintetizador 100% por código (sem assets): músicas eletrônicas em loop (estéreo: bumbo 4x4 com
## sidechain, supersaws, baixo rolante, arpejo e lead com delay) e efeitos sonoros chiptune/arcade.
## Tudo é renderizado em PCM 16 bits (22,05 kHz; efeitos mono, músicas estéreo) e devolvido como PackedByteArray, para rodar
## numa thread (WorkerThreadPool); o AudioManager embrulha os bytes em AudioStreamWAV.

const RATE := 22050

enum Wave { PULSE25, PULSE12, TRIANGLE, SAW, SINE }

## Acordes: raiz (MIDI, oitava 3) e tipo.
const CHORDS := {
	"C": [48, 0], "D": [50, 0], "Dm": [50, 1], "E": [52, 0], "Em": [52, 1], "F": [53, 0],
	"G": [55, 0], "A": [57, 0], "Am": [57, 1], "Bb": [58, 0], "B": [59, 0],
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


## Bateria: 0 = bumbo, 1 = caixa, 2 = chimbal, 3 = prato de ataque.
static func add_drum(buf: PackedFloat32Array, start: int, kind: int, vol: float, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var len_s: float = [0.16, 0.14, 0.035, 1.3][kind]
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
			3:
				var nz3 := rng.randf_range(-1.0, 1.0)
				s = (nz3 - prev) * 0.5 * (exp(-t * 3.2) * 0.8 + exp(-t * 25.0) * 0.6)
				prev = nz3
		buf[(start + i) % n] += s * vol


# ------------------------------------------------------------------ músicas

## Renderiza uma música. `song`: {bpm, chords: Array[String] (1 por compasso), melody: Array[String]
## (colcheias; "-" sustenta, "." pausa), drums: String por compasso em semicolcheias
## ("k" bumbo, "s" caixa, "h" chimbal, "x" caixa+chimbal, "." nada), arp16: bool}.
static func render_song(song: Dictionary) -> PackedByteArray:
	if song.get("style", "") == "edm":
		return _render_edm(song)
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


# ------------------------------------------------------------------ eletrônica

## Serra com PolyBLEP: arredonda a quina da onda (sem o chiado de aliasing de uma serra ingênua).
static func _saw(ph: float, dt: float) -> float:
	var s := 2.0 * ph - 1.0
	if ph < dt:
		var x := ph / dt
		s -= x + x - x * x - 1.0
	elif ph > 1.0 - dt:
		var x := (ph - 1.0) / dt
		s -= x * x + x + x + 1.0
	return s


## Soma `src` em `dst` a partir de `start` (com volta ao início: o loop não tem emenda).
static func _paste(dst: PackedFloat32Array, src: PackedFloat32Array, start: int, gain: float) -> void:
	var n := dst.size()
	for i in mini(src.size(), n):
		var j := start + i
		if j >= n:
			j -= n
		dst[j] += src[i] * gain


## Bumbo eletrônico: corpo senoidal com queda de afinação + clique de ataque, saturado.
static func _edm_kick() -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(0.34 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (48.0 + 190.0 * exp(-t * 30.0)) / RATE
		var body := sin(ph * TAU) * exp(-t * 8.5)
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 900.0) * 0.5
		b[i] = tanh((body + click) * 1.8) * 0.9
	return b


## Palma: três estalos de ruído quase juntos + cauda curta, em faixa média.
static func _edm_clap() -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(0.26 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	var lo := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := exp(-t * 16.0) * 0.55
		for k in 3:
			var tk := t - k * 0.011
			if tk >= 0.0:
				env += exp(-tk * 260.0)
		lp += 0.45 * (rng.randf_range(-1.0, 1.0) - lp)
		lo += 0.08 * (lp - lo)
		b[i] = (lp - lo) * env * 0.9
	return b


## Chimbal: ruído passa-alta, fechado (curto) ou aberto (longo).
static func _edm_hat(open: bool) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int((0.22 if open else 0.05) * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9 if open else 13
	var prev := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var nz := rng.randf_range(-1.0, 1.0)
		lp += 0.7 * ((nz - prev) - lp)
		prev = nz
		b[i] = lp * exp(-t * (13.0 if open else 70.0)) * 0.5
	return b


## Subida (riser) de um compasso antes do drop: ruído com filtro abrindo e volume crescendo.
static func _edm_riser(length: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(length)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var a := 0.0
	var c := 0.0
	for i in length:
		var x := float(i) / length
		var cut := 0.02 + 0.6 * x * x
		a += cut * (rng.randf_range(-1.0, 1.0) - a)
		c += cut * (a - c)
		b[i] = c * x * x * 0.8
	return b


## Acorde "supersaw": 3 serras desafinadas por nota, abertas no estéreo, passa-baixa de 2 polos.
## Renderizado uma vez por acorde e colado nos compassos. Devolve [L, R].
static func _pad_stem(notes: Array, length: int, cut: float) -> Array:
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(length)
	r.resize(length)
	var inc := PackedFloat32Array()
	var ph := PackedFloat32Array()
	var gl := PackedFloat32Array()
	var gr := PackedFloat32Array()
	var k := 0
	for m: int in notes:
		for v in 3:
			inc.append(midi_freq(m + (v - 1) * 0.12) / RATE)
			ph.append(fmod(0.37 * k, 1.0))
			gl.append([1.0, 0.75, 0.3][v])
			gr.append([0.3, 0.75, 1.0][v])
			k += 1
	var norm := 1.0 / sqrt(float(k))
	var al := 0.0
	var bl := 0.0
	var ar := 0.0
	var br := 0.0
	var rel := 0.06 * RATE
	for i in length:
		var sl := 0.0
		var sr := 0.0
		for v in k:
			var p := ph[v] + inc[v]
			p -= floorf(p)
			ph[v] = p
			var s := _saw(p, inc[v])
			sl += s * gl[v]
			sr += s * gr[v]
		var env := minf(float(i) / (0.015 * RATE), 1.0) * minf(float(length - i) / rel, 1.0) * norm
		al += cut * (sl - al)
		bl += cut * (al - bl)
		ar += cut * (sr - ar)
		br += cut * (ar - br)
		l[i] = bl * env
		r[i] = br * env
	return [l, r]


## Baixo: sub senoidal + duas serras com envelope de filtro (ataque "plucado").
static func _bass_stem(m: int, length: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(length)
	var dt := midi_freq(m) / RATE
	var ph := 0.0
	var ph2 := 0.0
	var a := 0.0
	var c := 0.0
	for i in length:
		var t := float(i) / RATE
		ph += dt
		ph -= floorf(ph)
		ph2 += dt * 1.006
		ph2 -= floorf(ph2)
		var cut := 0.04 + 0.3 * exp(-t * 22.0)
		a += cut * ((_saw(ph, dt) + _saw(ph2, dt)) * 0.5 - a)
		c += cut * (a - c)
		var env := minf(t / 0.003, 1.0) * minf(float(length - i) / (0.012 * RATE), 1.0)
		b[i] = (c * 0.8 + sin(ph * TAU) * 0.7) * env
	return b


## Pluck do arpejo: duas serras com filtro que fecha rápido (som moderno, curto e brilhante).
static func _pluck_stem(m: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(0.2 * RATE))
	var dt := midi_freq(m) / RATE
	var dt2 := dt * 1.005
	var ph := 0.0
	var ph2 := 0.5
	var a := 0.0
	var c := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += dt
		ph -= floorf(ph)
		ph2 += dt2
		ph2 -= floorf(ph2)
		var cut := 0.05 + 0.5 * exp(-t * 26.0)
		a += cut * ((_saw(ph, dt) + _saw(ph2, dt2)) * 0.5 - a)
		c += cut * (a - c)
		b[i] = c * minf(t / 0.002, 1.0) * exp(-t * 11.0)
	return b


## Lead do drop: supersaw de 3 vozes com vibrato tardio, `len8` colcheias de duração.
static func _lead_stem(m: int, dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	var held := int(dur * RATE)
	var rel := int(0.08 * RATE)
	b.resize(held + rel)
	var f := midi_freq(m)
	var ph: Array[float] = [0.0, 0.33, 0.71]
	var det: Array[float] = [0.993, 1.0, 1.007]
	var a := 0.0
	var c := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var vib := 1.0 + (0.005 * sin(t * TAU * 5.8) * minf(maxf(t - 0.18, 0.0) * 5.0, 1.0))
		var s := 0.0
		for v in 3:
			var dt: float = f * det[v] * vib / RATE
			ph[v] += dt
			ph[v] -= floorf(ph[v])
			s += _saw(ph[v], dt)
		var cut := 0.22 + 0.25 * exp(-t * 9.0)
		a += cut * (s * 0.4 - a)
		c += cut * (a - c)
		var env := minf(t / 0.006, 1.0) * (0.75 + 0.25 * exp(-t * 7.0))
		if i >= held:
			env *= 1.0 - float(i - held) / rel
		b[i] = c * env
	return b


## Eletrônica (house/electro de corrida). `song`: {bpm, sections: String (1 letra por compasso:
## "i" intro/pausa, "v" verso, "b" subida, "d" drop), chords: Array de voicings (midi), bass: tônicas,
## prog: índice do acorde por compasso (em loop), arp: 16 índices (>= 4: nota + 12), melody: colcheias
## do drop ("-" sustenta, "." pausa; 8 por compasso)}. Bumbo 4x4 com sidechain (pad, baixo e arpejo
## "respiram" a cada batida), baixo rolante no drop, lead com delay ping-pong. Saída estéreo.
static func _render_edm(song: Dictionary) -> PackedByteArray:
	var bpm: float = song["bpm"]
	var sections: String = song["sections"]
	var chords: Array = song["chords"]
	var roots: Array = song["bass"]
	var prog: Array = song["prog"]
	var arp: Array = song["arp"]
	var mel: Array = song["melody"]
	var bars := sections.length()
	var beat := 60.0 / bpm
	var s16 := beat * 0.25
	var bar_len := int(round(4.0 * beat * RATE))
	var n := bar_len * bars
	var drums := PackedFloat32Array()
	var bass := PackedFloat32Array()
	var arpb := PackedFloat32Array()
	var lead := PackedFloat32Array()
	var pl := PackedFloat32Array()
	var pr := PackedFloat32Array()
	drums.resize(n)
	bass.resize(n)
	arpb.resize(n)
	lead.resize(n)
	pl.resize(n)
	pr.resize(n)
	var kick := _edm_kick()
	var clap := _edm_clap()
	var hat_c := _edm_hat(false)
	var hat_o := _edm_hat(true)
	var riser := _edm_riser(bar_len)
	var crash_buf := PackedFloat32Array()
	crash_buf.resize(int(1.4 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	add_drum(crash_buf, 0, 3, 0.5, rng)
	var cache := {}
	var pos := func(b: int, k16: float) -> int: return b * bar_len + int(round(k16 * s16 * RATE))
	var di := 0  # índice do compasso de drop (para a melodia)
	for b in bars:
		var sec := sections.substr(b, 1)
		var ci: int = prog[b % prog.size()]
		var notes: Array = chords[ci]
		var root: int = roots[ci]
		# Bateria.
		if sec == "v" or sec == "d":
			for q in 4:
				_paste(drums, kick, pos.call(b, q * 4), 1.0)
			_paste(drums, clap, pos.call(b, 4), 0.7)
			_paste(drums, clap, pos.call(b, 12), 0.7)
			for q in 4:
				_paste(drums, hat_o, pos.call(b, q * 4 + 2), 0.5 if sec == "d" else 0.42)
			for q in 16:
				if q % 2 == 1 or sec == "d":
					_paste(drums, hat_c, pos.call(b, q), 0.3 if q % 2 == 1 else 0.18)
			if sec == "d" and b > 0 and sections.substr(b - 1, 1) == "b":
				_paste(drums, crash_buf, pos.call(b, 0), 0.6)
		elif sec == "b":
			for q in 16:
				if (q < 8 and q % 4 != 0) or (q >= 8 and q < 12 and q % 2 != 0):
					continue
				_paste(drums, clap, pos.call(b, q), 0.25 + 0.5 * q / 15.0)
			_paste(drums, riser, pos.call(b, 0), 0.5)
		else:
			for q in 4:
				_paste(drums, hat_o, pos.call(b, q * 4 + 2), 0.16)
		# Baixo: colcheias no contratempo (verso) ou semicolcheias rolantes (drop).
		if sec == "v" or sec == "d":
			var rolling := sec == "d"
			var blen := int((s16 if rolling else s16 * 2.0) * 0.88 * RATE)
			var key := "b%d|%d" % [root, blen]
			if not cache.has(key):
				cache[key] = _bass_stem(root, blen)
			for q in 16:
				if (rolling and q % 4 != 0) or (not rolling and q % 4 == 2):
					_paste(bass, cache[key], pos.call(b, q), 0.62 if rolling else 0.8)
		# Pad supersaw (drop forte; intro/subida suave).
		if sec != "v":
			var pkey := "p%d" % ci
			if not cache.has(pkey):
				cache[pkey] = _pad_stem(notes, bar_len, 0.42)
			var g := 0.62 if sec == "d" else 0.34
			_paste(pl, cache[pkey][0], pos.call(b, 0), g)
			_paste(pr, cache[pkey][1], pos.call(b, 0), g)
		# Arpejo em semicolcheias.
		var arp_gain: float = {"i": 0.6, "v": 0.85, "b": 0.7, "d": 0.5}[sec]
		for q in 16:
			var ai: int = arp[q]
			var m: int = (notes[ai] if ai < 4 else int(notes[ai - 4]) + 12) + 12
			var akey := "a%d" % m
			if not cache.has(akey):
				cache[akey] = _pluck_stem(m)
			_paste(arpb, cache[akey], pos.call(b, q), arp_gain)
		# Lead (só no drop).
		if sec == "d":
			var base := (di * 8) % mel.size()
			di += 1
			var e := 0
			while e < 8:
				var tok: String = mel[base + e]
				var len8 := 1
				while e + len8 < 8 and mel[base + e + len8] == "-":
					len8 += 1
				if tok != "-" and tok != ".":
					var lkey := "l%s|%d" % [tok, len8]
					if not cache.has(lkey):
						cache[lkey] = _lead_stem(note_midi(tok), len8 * s16 * 2.0 * 0.92)
					_paste(lead, cache[lkey], pos.call(b, e * 2), 1.0)
				e += len8
	# Mixagem: sidechain do bumbo, delay ping-pong (3 semicolcheias) no arpejo + lead, saturação suave.
	var beat_len := beat * RATE
	var dly := int(round(3.0 * s16 * RATE))
	var wl := PackedFloat32Array()
	var wr := PackedFloat32Array()
	wl.resize(n)
	wr.resize(n)
	var out_l := PackedFloat32Array()
	var out_r := PackedFloat32Array()
	out_l.resize(n)
	out_r.resize(n)
	var peak := 0.0001
	for b in bars:
		var pump := sections.substr(b, 1) == "v" or sections.substr(b, 1) == "d"
		for k in range(b * bar_len, (b + 1) * bar_len):
			var j := k - dly
			if j < 0:
				j += n
			wl[k] = 0.36 * (arpb[j] * 0.5 + lead[j] * 0.4 + wr[j])
			wr[k] = 0.36 * wl[j]
			var sc := 1.0
			if pump:
				var x := clampf(fmod(float(k), beat_len) / (beat_len * 0.38), 0.0, 1.0)
				sc = 0.22 + 0.78 * x * x * (3.0 - 2.0 * x)
			var mid := drums[k] + (bass[k] + arpb[k] * 0.8) * sc + lead[k] * 0.5
			var lv := mid + pl[k] * sc + wl[k]
			var rv := mid + pr[k] * sc + wr[k]
			out_l[k] = lv
			out_r[k] = rv
			peak = maxf(peak, maxf(absf(lv), absf(rv)))
	var g := 1.5 / peak
	var norm := 1.0 / tanh(1.5)
	var out := PackedByteArray()
	out.resize(n * 4)
	for k in n:
		out.encode_s16(k * 4, int(tanh(out_l[k] * g) * norm * 0.5 * 32767.0))
		out.encode_s16(k * 4 + 2, int(tanh(out_r[k] * g) * norm * 0.5 * 32767.0))
	return out


## Título: pop eletrônico animado em tom maior (126 bpm, fá maior; F C Dm Bb com nonas), intro curta.
static func title_song() -> Dictionary:
	return {
		"style": "edm",
		"bpm": 126.0,
		"sections": "iivvvvvbdddddddd",
		"chords": [[57, 60, 65, 67], [55, 60, 62, 64], [57, 62, 64, 65], [58, 60, 62, 65]],
		"bass": [41, 36, 38, 46],
		"prog": [0, 1, 2, 3],
		"arp": [0, 2, 4, 2, 1, 3, 5, 3, 0, 2, 4, 2, 1, 3, 5, 2],
		"melody": [
			"C6", "-", "-", "A5", "-", "C6", "F6", "-",
			"E6", "-", "D6", "-", "C6", "-", "G5", "-",
			"A5", "-", "D6", "-", "F6", "-", "E6", "D6",
			"D6", "-", "C6", "-", "-", "-", ".", ".",
			"C6", "-", "F6", "-", "A6", "-", "G6", "F6",
			"G6", "-", "E6", "-", "C6", "-", "E6", "G6",
			"F6", "-", "E6", "-", "D6", "-", "A5", "-",
			"D6", "-", "C6", "-", "A#5", "-", "C6", "-",
		],
	}


## Corrida: electro-pop rápido e alegre em tom maior (152 bpm, ré maior; D A Bm G com nonas), verso
## com baixo no contratempo, subida com palmas e riser, drop com supersaw, baixo rolante e lead agudo.
static func race_song() -> Dictionary:
	return {
		"style": "edm",
		"bpm": 152.0,
		"sections": "vvvvvvvbddddddddvvvvvvvbdddddddd",
		"chords": [[62, 64, 66, 69], [61, 64, 69, 71], [59, 62, 66, 73], [59, 62, 67, 69]],
		"bass": [38, 45, 47, 43],
		"prog": [0, 1, 2, 3],
		"arp": [0, 1, 2, 4, 2, 1, 0, 1, 2, 4, 5, 4, 2, 1, 2, 3],
		"melody": [
			"A5", "-", "D6", "-", "F#6", "-", "E6", "D6",
			"E6", "-", "C#6", "-", "A5", "-", "E6", "-",
			"F#6", "-", "D6", "-", "B5", "-", "D6", "F#6",
			"G6", "-", "F#6", "-", "E6", "-", "D6", "E6",
			"F#6", "-", "A6", "-", "F#6", "D6", "E6", "F#6",
			"E6", "-", "A6", "-", "C#6", "-", "E6", "-",
			"D6", "-", "F#6", "-", "B6", "-", "A6", "F#6",
			"G6", "-", "-", "F#6", "E6", "-", "D6", "-",
		],
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
