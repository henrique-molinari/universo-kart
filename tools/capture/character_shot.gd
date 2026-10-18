extends SceneTree
## Retratos de QA dos personagens (não-headless): estúdio neutro com luz principal, preenchimento e
## contorno; para cada personagem tira close do rosto (frente e 3/4) e corpo inteiro no kart.
## Uso: Godot_console.exe --path <projeto> -s res://tools/capture/character_shot.gd -- --out=<pasta> [--chars=0,1] [--pose=drive|victory|defeat]

var _out := "user://"
var _chars: Array[int] = [0, 1]
var _pose := AlienDriver.Pose.DRIVE


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--chars="):
			_chars.clear()
			for c in a.substr(8).split(","):
				_chars.append(c.to_int())
		elif a == "--pose=victory":
			_pose = AlienDriver.Pose.VICTORY
		elif a == "--pose=defeat":
			_pose = AlienDriver.Pose.DEFEAT
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1200, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	for l: Array in [[Vector3(-0.6, -0.6, -0.55), 1.6, Color(1, 0.96, 0.9), true], [Vector3(0.7, -0.2, -0.3), 0.45, Color(0.8, 0.86, 1.0), false], [Vector3(0.2, -0.5, 1.0), 2.0, Color(0.9, 0.94, 1.0), false]]:
		var dl := DirectionalLight3D.new()
		dl.basis = Basis.looking_at((l[0] as Vector3).normalized())
		dl.light_energy = l[1]
		dl.light_color = l[2]
		dl.shadow_enabled = l[3]
		world.add_child(dl)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	for ch in _chars:
		var cfg := PlayerConfig.new()
		cfg.character = ch
		cfg.player_index = -1
		cfg.set_color(Palette.KART_COLORS[ch % Palette.KART_COLORS.size()])
		var m := KartModel.new()
		m.build(cfg)
		world.add_child(m)
		m.set_pose(_pose)
		for i in 60:
			m.animate(0.0, 0.0, 1.0 / 60.0)
			await process_frame
		var head := m.driver.head.global_position + Vector3(0, 0.36, 0)
		var shots := {
			"rosto": [head + Vector3(0, 0.05, -1.25), head, 30.0],
			"rosto34": [head + Vector3(-0.85, 0.15, -0.95), head, 30.0],
			"corpo": [Vector3(-1.9, 1.5, -2.6), Vector3(0, 0.75, 0), 34.0],
			"costas": [Vector3(1.0, 1.75, 2.6), Vector3(0, 1.0, 0.3), 34.0],
		}
		for nm: String in shots:
			var s: Array = shots[nm]
			cam.fov = s[2]
			cam.global_transform = Transform3D(Basis.looking_at((s[1] as Vector3) - (s[0] as Vector3)), s[0])
			for i in 8:
				await process_frame
			var path := _out.path_join("char%d_%s.png" % [ch, nm])
			root.get_texture().get_image().save_png(path)
		m.queue_free()
		await process_frame
	print("[retratos] ok")
	quit()
