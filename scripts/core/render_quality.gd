class_name RenderQuality
extends RefCounted
## Presets de qualidade gráfica. Aplicados à viewport raiz e às SubViewports
## (split-screen, ferramenta de captura), que NÃO herdam MSAA/AA do project.godot.

enum Preset { LOW, MEDIUM, HIGH, ULTRA }

const PRESET_NAMES: Array[String] = ["Baixa", "Média", "Alta", "Ultra"]


static func apply_to_viewport(vp: Viewport, preset: Preset, split_screen: bool = false) -> void:
	match preset:
		Preset.LOW:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.scaling_3d_scale = 0.85
		Preset.MEDIUM:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.scaling_3d_scale = 1.0
		Preset.HIGH:
			vp.msaa_3d = Viewport.MSAA_4X if not split_screen else Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.scaling_3d_scale = 1.0
		Preset.ULTRA:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.scaling_3d_scale = 1.0
	vp.use_debanding = true
	vp.mesh_lod_threshold = 1.0 if preset >= Preset.HIGH else 2.0
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X


## Liga/desliga efeitos caros do Environment conforme o preset.
static func apply_to_environment(env: Environment, preset: Preset, split_screen: bool = false) -> void:
	if env == null:
		return
	env.ssao_enabled = preset >= Preset.MEDIUM
	env.glow_enabled = preset >= Preset.MEDIUM
	env.ssil_enabled = preset >= Preset.ULTRA and not split_screen
	env.volumetric_fog_enabled = false


static func apply_global(preset: Preset) -> void:
	var shadow_size := 4096 if preset >= Preset.HIGH else 2048
	RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
	var filter := RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	if preset == Preset.LOW:
		filter = RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW
	elif preset == Preset.ULTRA:
		filter = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	RenderingServer.directional_soft_shadow_filter_set_quality(filter)
	# Pele dos ETs (dispersão subsuperficial): poucas amostras bastam para o efeito suave;
	# qualidade alta só no Ultra (o passe roda por viewport, duas vezes no split-screen).
	RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH if preset == Preset.ULTRA else RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW)
