shader_type canvas_item;

// Clean Solid-Color Pixel-Art River Shader for 50 Hertz — Desa Sukamaju
// Pure Godot 4 GLSL: flat stylized water color + simple crisp scrolling ripples,
// gentle animated shoreline foam, subtle WaterGear ripple rings, and storm rain rings.

uniform vec2 river_size = vec2(178.0, 1344.0);
uniform float pixel_size = 3.0;
uniform vec4 env_tint : source_color = vec4(1.0, 1.0, 0.98, 1.0);
uniform float sun_factor : hint_range(0.0, 1.0) = 0.75;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float flow_speed : hint_range(0.2, 3.0) = 1.0;
uniform float lightning_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec2 gear_world_pos = vec2(148.8, 600.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float rain_ring(vec2 wpos, float t) {
	vec2 cell_sz = vec2(54.0, 54.0);
	vec2 id = floor(wpos / cell_sz);
	vec2 local = fract(wpos / cell_sz) - vec2(0.5, 0.5);
	float h = hash21(id);
	float phase = fract(t * (0.75 + h * 0.45) + h * 6.28);
	vec2 center = (vec2(hash21(id + vec2(3.1, 1.7)), hash21(id + vec2(7.4, 5.2))) - vec2(0.5, 0.5)) * 0.4;
	float d = length(local - center);
	float ring = 1.0 - smoothstep(0.0, 0.055, abs(d - phase * 0.40));
	float fade = (1.0 - phase) * smoothstep(0.0, 0.15, phase);
	return step(0.45, ring) * fade;
}

void fragment() {
	// Crisp 3x3 pixel-art grid matching Kenney 16px * 3x tiles
	vec2 wpos = floor(UV * river_size / pixel_size) * pixel_size;
	float t = TIME * flow_speed;

	// Clean straight riverbank edge matching the tile grid
	float bank_x = river_size.x - 10.0;
	float dist_to_bank = bank_x - wpos.x;

	if (dist_to_bank < -10.0) {
		discard;
	}

	// Simple solid earthen riverbank with crisp dark outline
	if (dist_to_bank < 0.0) {
		float edge = -dist_to_bank;
		vec3 bank_col = vec3(0.45, 0.35, 0.24);
		if (edge < 3.0) {
			bank_col = vec3(0.32, 0.24, 0.16); // wet water edge
		} else if (edge >= 7.0) {
			bank_col = vec3(0.24, 0.19, 0.13); // crisp pixel border
		}
		COLOR = vec4(bank_col * env_tint.rgb, 1.0);
	} else {
		// Clean flat solid river blue (matches Kenney pixel-art simplicity!)
		vec3 water = vec3(0.15, 0.49, 0.72);
		vec3 foam_col = vec3(0.74, 0.92, 0.98);
		vec3 ripple_col = vec3(0.36, 0.72, 0.90);

		// Simple animated shoreline foam strip gently waving along the bank
		float wave_w = 5.0 + sin(wpos.y * 0.045 - t * 2.2) * 2.5;
		if (dist_to_bank < wave_w) {
			water = foam_col;
		} else if (dist_to_bank < wave_w + 6.0) {
			water = vec3(0.20, 0.56, 0.78); // single clean shallow step
		}

		// Simple clean scrolling horizontal pixel ripple dashes flowing southward
		vec2 flow_pos = vec2(wpos.x, wpos.y - floor(t * 28.0 / pixel_size) * pixel_size);
		vec2 cell = floor(flow_pos / vec2(42.0, 54.0));
		vec2 local = fract(flow_pos / vec2(42.0, 54.0));
		float h = hash21(cell);
		if (h > 0.45 && dist_to_bank > 14.0) {
			float rx = 0.20 + fract(h * 11.3) * 0.35 + sin(t * 1.8 + h * 6.28) * 0.06;
			float ry = 0.30 + fract(h * 7.1) * 0.40;
			float rw = 0.28 + fract(h * 5.7) * 0.18;
			bool in_dash = (local.x >= rx && local.x <= rx + rw && abs(local.y - ry) < 0.055);
			// Optional shorter second highlight pixel line right below
			bool in_sub = (local.x >= rx + 0.06 && local.x <= rx + rw * 0.65 && abs(local.y - (ry + 0.10)) < 0.045);
			if (in_dash) {
				water = ripple_col;
			} else if (in_sub && h > 0.72) {
				water = mix(water, foam_col, 0.55);
			}
		}

		// Simple concentric white ripple arcs pulsing around the spinning WaterGear
		vec2 rel = wpos - (gear_world_pos + vec2(0.0, 6.0));
		float gd = length(rel);
		if (gd > 16.0 && gd < 48.0 && rel.y > -8.0) {
			float ring_pos = fract(gd * 0.065 - TIME * 1.15);
			if (ring_pos < 0.14) {
				float fade = 1.0 - smoothstep(20.0, 48.0, gd);
				water = mix(water, foam_col, fade * 0.85);
			}
		}

		// Simple raindrop rings during storms
		if (rain_intensity > 0.08) {
			float rip = rain_ring(wpos, TIME) * rain_intensity;
			water = mix(water, foam_col, rip * 0.65);
		}

		// Day / dusk / night tint + lightning flash
		vec3 final_col = water * mix(env_tint.rgb, vec3(1.0), 0.12);
		if (lightning_flash > 0.01) {
			final_col = mix(final_col, vec3(0.90, 0.96, 1.0), lightning_flash * 0.45);
		}
		COLOR = vec4(final_col, 1.0);
	}
}
