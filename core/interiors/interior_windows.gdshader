// Interior-mapped building facade ("fake 3D rooms behind every window").
//
// Adapted from "Fake 3D Interior Projection Shader (fixed & tuned)" by Lord0Sanz
// (godotshaders.com, MIT License, Copyright (c) 2026 PROJEKTSANSSTUDIOS), itself based on
// "Interior mapping shader" by AndreaTerenz. MIT notice:
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this
//   software and associated documentation files (the "Software"), to deal in the Software
//   without restriction, including without limitation the rights to use, copy, modify, merge,
//   publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
//   to whom the Software is furnished to do so, subject to the following conditions:
//   The above copyright notice and this permission notice shall be included in all copies or
//   substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.
//
// Changes from the original (it maps ONE room onto one quad in object space):
//  * One room per UV cell, so a whole facade gets hundreds of rooms. The mesh's UVs must
//    put one window bay x one floor into each 1x1 UV cell (u to the right, v up in Blender).
//  * The room box comes from the surface's own UV derivatives, so any wall orientation,
//    size or curvature works without tangents or per-object setup.
//  * 8 room variants in one atlas (see core/interiors/interior_atlas.png), a cut-out
//    furniture layer half-way into the room, per-window lighting (warm / cool / neon,
//    on / off, flickering TVs), blinds and curtains, a window frame + wall drawn around
//    the glass, a reflective glass surface, and a smooth fade to an average colour in the
//    distance so far-away facades don't shimmer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms Rooms;
uniform sampler2D room_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform int atlas_columns = 8;
uniform int atlas_rows = 5;
uniform float atlas_tile_px = 256.0;
/// Which atlas columns (room types) this material picks from.
uniform int variant_min = 0;
uniform int variant_max = 4;
/// Room depth behind the glass, in metres.
uniform float room_depth = 4.0;
/// Where the cut-out furniture layer sits (0 = glass, 1 = back wall).
uniform float props_depth = 0.45;

group_uniforms Lighting;
/// Share of windows that are lit.
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.45;
/// Windows come in groups ("tenants") of this many bays that tend to share on/off.
uniform float cluster_bays = 4.0;
uniform float light_energy = 1.3;
uniform vec3 warm_light : source_color = vec3(1.0, 0.76, 0.48);
uniform vec3 cool_light : source_color = vec3(0.72, 0.88, 1.0);
uniform vec3 neon_light_a : source_color = vec3(1.0, 0.25, 0.75);
uniform vec3 neon_light_b : source_color = vec3(0.25, 0.9, 1.0);
uniform float cool_chance : hint_range(0.0, 1.0) = 0.35;
uniform float neon_chance : hint_range(0.0, 1.0) = 0.1;
/// Dark windows that show a flickering TV.
uniform float tv_chance : hint_range(0.0, 1.0) = 0.08;
uniform float dark_level = 0.015;
uniform float seed = 0.0;

group_uniforms Window;
/// Glass rectangle inside each cell: x0, y0 (from the floor), x1, y1.
uniform vec4 glass_rect = vec4(0.1, 0.28, 0.9, 0.92);
uniform float frame_width = 0.035;
/// Vertical glazing bars across the glass (0 = none).
uniform int mullions = 1;
uniform vec3 frame_color : source_color = vec3(0.06, 0.06, 0.07);
uniform float blinds_chance : hint_range(0.0, 1.0) = 0.45;
uniform vec3 blinds_color : source_color = vec3(0.85, 0.82, 0.75);
uniform float curtain_chance : hint_range(0.0, 1.0) = 0.25;
uniform vec3 glass_tint : source_color = vec3(0.02, 0.025, 0.03);
uniform float glass_roughness = 0.04;

group_uniforms Wall;
uniform vec3 wall_color : source_color = vec3(0.12, 0.12, 0.13);
uniform vec3 wall_color_2 : source_color = vec3(0.1, 0.1, 0.11);
/// 0 = plain, 1 = strong per-panel colour variation between wall_color and wall_color_2.
uniform float wall_variation : hint_range(0.0, 1.0) = 0.35;
uniform float wall_roughness = 0.55;
uniform float wall_metallic = 0.0;
/// Dark seam line between floors / panels.
uniform float seam_strength : hint_range(0.0, 1.0) = 0.5;
/// Fake bounce light so walls aren't pure silhouettes: a faint overall glow plus
/// a stronger tint near the ground (neon + street lights), fading with height.
uniform vec3 bounce_color : source_color = vec3(0.55, 0.35, 0.7);
uniform float wall_glow = 0.05;
uniform float street_glow = 0.35;
uniform float street_glow_height = 22.0;

varying float v_height;

void vertex() {
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float box_mask(vec2 p, vec4 r, vec2 aa) {
	vec2 lo = smoothstep(r.xy - aa, r.xy + aa, p);
	vec2 hi = 1.0 - smoothstep(r.zw - aa, r.zw + aa, p);
	return lo.x * lo.y * hi.x * hi.y;
}

vec4 atlas(vec2 tuv, int col, int row, float lod) {
	vec2 cell = vec2(float(col), float(row));
	vec2 uv = (cell + clamp(tuv, vec2(0.004), vec2(0.996))) / vec2(float(atlas_columns), float(atlas_rows));
	return textureLod(room_atlas, uv, lod);
}

void fragment() {
	// Cell space: x to the right, y up (glTF flips v, so undo that here).
	vec2 uvc = vec2(UV.x, -UV.y);
	vec2 cell = floor(uvc);
	vec2 f = fract(uvc);

	// Surface axes from derivatives: T = metres per +u, B = metres per +v (view space).
	vec3 p = VERTEX;
	vec3 dpx = dFdx(p);
	vec3 dpy = dFdy(p);
	vec2 dux = dFdx(uvc);
	vec2 duy = dFdy(uvc);
	float det = dux.x * duy.y - dux.y * duy.x;
	det = abs(det) < 1e-12 ? 1e-12 : det;
	vec3 T = (dpx * duy.y - dpy * dux.y) / det;
	vec3 B = (dpy * dux.x - dpx * duy.x) / det;

	vec2 fw = fwidth(uvc);
	float cell_px = 1.0 / max(max(fw.x, fw.y), 1e-6);
	vec2 aa = fw * 0.75;

	// ── per-window randomness ──
	float h0 = hash21(cell + seed * 17.13);
	float h1 = hash21(cell.yx * 1.37 + seed + 5.1);
	float h2 = hash21(cell * 2.11 - seed + 9.7);
	float h3 = hash21(cell * 0.73 + seed * 3.3 + 21.4);
	float tenant = hash21(vec2(floor(cell.x / cluster_bays), cell.y) + seed * 7.7);
	bool lit = mix(tenant, h0, 0.35) < lit_ratio;
	int nvar = max(variant_max - variant_min + 1, 1);
	int variant = variant_min + int(floor(h1 * float(nvar))) % nvar;
	vec3 lcol = warm_light;
	if (h2 < neon_chance) {
		lcol = h3 < 0.5 ? neon_light_a : neon_light_b;
	} else if (h2 < neon_chance + cool_chance) {
		lcol = cool_light;
	}
	float energy = light_energy * (0.7 + 0.6 * h3);
	bool tv = !lit && h3 < tv_chance;
	float tv_flick = 0.0;
	if (tv) {
		float t = TIME * (5.0 + 6.0 * h0) + h1 * 40.0;
		tv_flick = 0.35 + 0.35 * sin(t) * sin(t * 0.37 + 1.7) + 0.3 * step(0.8, fract(t * 0.13));
	}

	// ── room ray march (one box per cell) ──
	vec3 d = normalize(p); // camera -> fragment, view space
	vec3 into = -NORMAL;   // into the wall
	vec3 rd = vec3(dot(d, T) / max(dot(T, T), 1e-6), dot(d, B) / max(dot(B, B), 1e-6), dot(d, into) / room_depth);
	rd.z = max(rd.z, 1e-4);
	vec3 ro = vec3(f, 0.0);
	vec3 tb = vec3(
		rd.x > 0.0 ? (1.0 - ro.x) / rd.x : -ro.x / rd.x,
		rd.y > 0.0 ? (1.0 - ro.y) / rd.y : -ro.y / rd.y,
		1.0 / rd.z);
	float t = min(min(tb.x, tb.y), tb.z);
	vec3 hit = ro + rd * t;
	float lod = clamp(log2(atlas_tile_px / max(cell_px, 1.0)), 0.0, 8.0);
	vec3 room;
	float shade = 1.0;
	if (t == tb.z) {
		room = atlas(vec2(hit.x, 1.0 - hit.y), variant, 0, lod).rgb;
	} else if (t == tb.x) {
		room = atlas(vec2(hit.z, 1.0 - hit.y), variant, 1, lod).rgb;
		shade = 0.8;
	} else if (rd.y < 0.0) {
		room = atlas(vec2(hit.x, hit.z), variant, 2, lod).rgb;
		shade = 0.7;
	} else {
		room = atlas(vec2(hit.x, hit.z), variant, 3, lod).rgb;
		shade = 1.15;
	}
	// cut-out furniture half-way in
	float tp = props_depth / rd.z;
	if (tp < t) {
		vec2 pp = ro.xy + rd.xy * tp;
		if (pp.x > 0.0 && pp.x < 1.0 && pp.y > 0.0 && pp.y < 1.0) {
			vec4 pr = atlas(vec2(pp.x, 1.0 - pp.y), variant, 4, lod);
			room = mix(room * shade, pr.rgb, pr.a);
			shade = mix(shade, 0.9, pr.a);
		}
	}
	float depth_fall = 1.0 - 0.45 * clamp(hit.z, 0.0, 1.0);
	vec3 interior;
	if (lit) {
		interior = room * shade * lcol * energy * depth_fall;
	} else {
		interior = room * shade * dark_level + (tv ? room * vec3(0.35, 0.55, 1.0) * tv_flick * 0.9 * depth_fall : vec3(0.0));
	}

	// ── blinds / curtains on the glass plane ──
	vec4 g = glass_rect;
	vec2 gl = (f - g.xy) / max(g.zw - g.xy, vec2(1e-3)); // 0..1 across the glass
	float blind_drop = h2 > (1.0 - blinds_chance) ? mix(0.15, 0.95, fract(h0 * 7.31)) : 0.0;
	float blinds = step(1.0 - blind_drop, gl.y);
	float slats = 0.75 + 0.25 * smoothstep(0.3, 0.5, abs(fract(gl.y * 24.0) - 0.5) * 2.0);
	float curtain = 0.0;
	if (h1 > 1.0 - curtain_chance) {
		float cw = mix(0.12, 0.4, fract(h3 * 5.7));
		curtain = max(1.0 - smoothstep(cw - 0.02, cw, gl.x), smoothstep(1.0 - cw, 1.0 - cw + 0.02, gl.x));
	}
	vec3 lit_from_inside = lit ? lcol * energy * 0.55 : vec3(dark_level) + (tv ? vec3(0.2, 0.3, 0.6) * tv_flick * 0.3 : vec3(0.0));
	interior = mix(interior, blinds_color * slats * lit_from_inside, blinds * 0.9);
	vec3 curtain_col = mix(vec3(0.6, 0.2, 0.25), vec3(0.2, 0.3, 0.5), h0);
	interior = mix(interior, curtain_col * lit_from_inside * (0.7 + 0.3 * sin(gl.x * 60.0)), curtain * 0.95);

	// ── window frame / wall masks ──
	float in_rect = box_mask(f, g, aa);
	vec4 gi = g + vec4(frame_width, frame_width, -frame_width, -frame_width);
	float glass = box_mask(f, gi, aa);
	if (mullions > 0) {
		float n = float(mullions + 1);
		float mx = abs(fract(gl.x * n + 0.5) - 0.5) / n * (g.z - g.x); // distance to a bar, cell units
		glass *= smoothstep(frame_width * 0.35 - aa.x, frame_width * 0.35 + aa.x, mx);
	}
	float frame = max(in_rect - glass, 0.0);
	float wall = 1.0 - in_rect;

	// wall panels: colour varies per floor band + per bay, seams between floors
	float panel = hash21(vec2(floor(cell.x / 2.0), cell.y) + seed * 3.1);
	vec3 wcol = mix(wall_color, wall_color_2, clamp(panel * wall_variation * 2.0, 0.0, 1.0));
	float seam = 1.0 - seam_strength * (1.0 - smoothstep(0.0, 0.015 + aa.y, f.y)) ;
	wcol *= seam;

	// ── distance fallback (average colour, no aliasing) ──
	float glass_area = (gi.z - gi.x) * (gi.w - gi.y);
	vec3 far_emit = lit ? lcol * energy * 0.32 : (tv ? vec3(0.08, 0.12, 0.25) * tv_flick : vec3(0.0));
	float near = smoothstep(2.5, 7.0, cell_px);

	vec3 albedo = wcol * wall + frame_color * frame + glass_tint * glass;
	float rough = wall_roughness * wall + 0.35 * frame + glass_roughness * glass;
	float metal = wall_metallic * wall + 0.6 * frame;
	float bounce = wall_glow + street_glow * exp(-max(v_height, 0.0) / street_glow_height);
	vec3 emit = interior * glass + wcol * bounce_color * bounce * (wall + frame * 0.5);

	vec3 albedo_far = mix(wall_color, glass_tint, glass_area);
	vec3 emit_far = far_emit * glass_area + wall_color * bounce_color * bounce * (1.0 - glass_area);
	ALBEDO = mix(albedo_far, albedo, near);
	ROUGHNESS = mix(mix(wall_roughness, glass_roughness, glass_area), rough, near);
	METALLIC = mix(wall_metallic, metal, near);
	SPECULAR = 0.5;
	EMISSION = mix(emit_far, emit, near);
}
