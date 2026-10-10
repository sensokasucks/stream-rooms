class_name GraphicsQuality
extends RefCounted
## Graphics quality (Room tab → Performance): one preset switches the expensive effects
## together, applied on top of each room's own Environment when it loads (RoomHost).
##   high    what the rooms are built with (SDFGI bounce light, volumetric fog, SSAO, SSR,
##           MSAA 2x, soft shadows), full resolution.
##   medium  no SDFGI (a little extra ambient light makes up for the lost bounce light),
##           low-res volumetric fog, SSAO on, SSR off, MSAA 2x, medium shadows.
##   low     no SDFGI / fog / SSAO / SSR, no MSAA (FXAA instead), small soft shadows, the 3D
##           view drawn at 75% and scaled up with AMD FSR (text and the panel stay sharp).
##   custom  whatever the individual switches say (changing one switch picks "custom").
## Glow, emissive materials and lights that are part of a room's look are never touched.
## Settings are per machine (settings.cfg), not per room.

const PRESETS: Dictionary = {
	"low": {"gfx_gi": false, "gfx_fog": "off", "gfx_ssao": false, "gfx_ssr": false, "gfx_msaa": 0,
		"gfx_shadows": "low", "gfx_render_scale": 0.75},
	"medium": {"gfx_gi": false, "gfx_fog": "low", "gfx_ssao": true, "gfx_ssr": false, "gfx_msaa": 2,
		"gfx_shadows": "medium", "gfx_render_scale": 1.0},
	"high": {"gfx_gi": true, "gfx_fog": "full", "gfx_ssao": true, "gfx_ssr": true, "gfx_msaa": 2,
		"gfx_shadows": "high", "gfx_render_scale": 1.0},
}
const KEYS: PackedStringArray = ["gfx_gi", "gfx_fog", "gfx_ssao", "gfx_ssr", "gfx_msaa", "gfx_shadows", "gfx_render_scale"]
## Ambient light added per unit of the room's SDFGI energy when SDFGI is switched off, so
## rooms lit mostly by bounce light don't go murky.
const GI_OFF_AMBIENT: float = 0.12
## Volumetric fog froxel grid: [size, depth]. "full" = the engine defaults.
const FOG_GRID: Dictionary = {"low": [40, 48], "full": [64, 64]}


## Which preset the individual switches match ("custom" if none).
static func detect_level() -> String:
	for level: String in PRESETS.keys():
		var p: Dictionary = PRESETS[level]
		var same := true
		for k: String in KEYS:
			var a: Variant = AppState.get_setting(k)
			var b: Variant = p[k]
			if typeof(b) == TYPE_FLOAT:
				same = same and absf(float(a) - float(b)) < 0.001
			else:
				same = same and str(a) == str(b)
		if same:
			return level
	return "custom"


## Picks a preset: writes its switches ("custom" keeps the current switches).
static func set_level(level: String) -> void:
	if PRESETS.has(level):
		var p: Dictionary = PRESETS[level]
		for k: String in KEYS:
			AppState.set_setting(k, p[k])
	AppState.set_setting("graphics_quality", level)


## The room's Environment with the quality switches applied. Returns `src` itself when nothing
## needs changing (High), otherwise a copy, so the room's own resource is never edited and
## going back to High restores it exactly.
static func environment_for(src: Environment) -> Environment:
	if src == null:
		return null
	var gi := bool(AppState.get_setting("gfx_gi"))
	var fog := String(AppState.get_setting("gfx_fog"))
	var ssao := bool(AppState.get_setting("gfx_ssao"))
	var ssr := bool(AppState.get_setting("gfx_ssr"))
	var change := (src.sdfgi_enabled and not gi) or (src.volumetric_fog_enabled and fog == "off") \
		or (src.ssao_enabled and not ssao) or (src.ssr_enabled and not ssr)
	if not change:
		return src
	var env := src.duplicate() as Environment
	if src.sdfgi_enabled and not gi:
		env.sdfgi_enabled = false
		env.ambient_light_energy = src.ambient_light_energy + GI_OFF_AMBIENT * src.sdfgi_energy
	if fog == "off":
		env.volumetric_fog_enabled = false
	if not ssao:
		env.ssao_enabled = false
	if not ssr:
		env.ssr_enabled = false
	return env


## Viewport-wide settings: MSAA, render scale, shadow atlas and soft-shadow quality, fog grid.
static func apply_viewport(vp: Viewport) -> void:
	var msaa := int(AppState.get_setting("gfx_msaa"))
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(msaa, Viewport.MSAA_2X)
	# no MSAA: cheap FXAA so edges don't crawl
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if msaa == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	var scale := clampf(float(AppState.get_setting("gfx_render_scale")), 0.5, 1.0)
	vp.scaling_3d_scale = scale
	if scale >= 0.999:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	else:
		# FSR 1 needs Forward+ / Mobile (a RenderingDevice); the Compatibility renderer only has bilinear
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if RenderingServer.get_rendering_device() != null else Viewport.SCALING_3D_MODE_BILINEAR
	var sh := String(AppState.get_setting("gfx_shadows"))
	var pos_q := int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2))
	var dir_q := int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2))
	var atlas := int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 4096))
	var dir_size := int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096))
	match sh:
		"low":
			pos_q = 1
			dir_q = 1
			atlas = 2048
			dir_size = 2048
		"medium":
			pos_q = mini(pos_q, 2)
			dir_q = mini(dir_q, 2)
	vp.positional_shadow_atlas_size = atlas
	RenderingServer.positional_soft_shadow_filter_set_quality(pos_q)
	RenderingServer.directional_soft_shadow_filter_set_quality(dir_q)
	RenderingServer.directional_shadow_atlas_set_size(dir_size, true)
	var grid: Array = FOG_GRID["low"] if String(AppState.get_setting("gfx_fog")) == "low" else FOG_GRID["full"]
	RenderingServer.environment_set_volumetric_fog_volume_size(int(grid[0]), int(grid[1]))


## Frame-rate cap and V-Sync. 0 = unlimited.
static func apply_fps() -> void:
	Engine.max_fps = maxi(int(AppState.get_setting("fps_cap")), 0)
	var mode := DisplayServer.VSYNC_ENABLED if bool(AppState.get_setting("vsync")) else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != mode:
		DisplayServer.window_set_vsync_mode(mode)


## Rough cost hint for the panel.
static func describe(level: String) -> String:
	match level:
		"low":
			return "Low: no bounce light, fog, ambient occlusion or reflections; 3D drawn at 75% and sharpened back up (FSR). For laptops streaming at the same time (RTX 3060 class)."
		"medium":
			return "Medium: no bounce light (a bit of extra ambient instead), low-res fog, ambient occlusion on, softer shadows. Most of High's look for a good deal less GPU time."
		"high":
			return "High: what the rooms are built with. Bounce light (SDFGI) and volumetric fog are the expensive parts."
	return "Custom: your own mix of the switches below."
