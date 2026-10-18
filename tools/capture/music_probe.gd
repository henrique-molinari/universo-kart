extends SceneTree
## Renderiza as músicas, mede o tempo e salva WAVs (QA de áudio): godot --headless -s tools/capture/music_probe.gd -- --out=dir

func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	for s in [["title", Synth.title_song()], ["race", Synth.race_song()]]:
		var t0 := Time.get_ticks_msec()
		var bytes := Synth.render_song(s[1])
		var ms := Time.get_ticks_msec() - t0
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = Synth.RATE
		w.stereo = true
		w.data = bytes
		w.save_to_wav(out.path_join("musica_%s.wav" % s[0]))
		var n := bytes.size() / 4
		var sum := 0.0
		for i in range(0, n, 7):
			var v := bytes.decode_s16(i * 4) / 32767.0
			sum += v * v
		print("[music] %s: %.1f s de áudio em %d ms, RMS %.3f" % [s[0], float(n) / Synth.RATE, ms, sqrt(sum / (n / 7.0))])
	quit()
