shader_type canvas_item;
render_mode blend_mix, unshaded;

// Level 2 tissue renderer.
//
// The cavity is the union of the chamber ellipses and corridor capsules. The
// same tables drive the collision shell, so what you can see and what you can
// touch cannot drift apart. The palette is deliberately low-contrast: mucosa
// and muscle are layered with soft gradients instead of bright rims, so the
// anatomy reads as a place rather than a set of interactive props.

uniform int chamber_count = 0;
uniform vec4 chambers[32];          // cx, cy, rx, ry
uniform int corridor_count = 0;
uniform vec4 corridors[32];         // ax, ay, bx, by
uniform float corridor_widths[32];
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1.0);
uniform float top_y = -4000.0;
uniform float bottom_y = 4000.0;

const float WALL_DEPTH = 540.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return 0.68 * vnoise(p) + 0.32 * vnoise(p * 2.03);
}

float sd_ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / max(r, vec2(1.0));
	return (length(q) - 1.0) * min(r.x, r.y);
}

float sd_capsule(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h) - w;
}

float cavity_sdf(vec2 p) {
	float d = 1.0e7;
	for (int i = 0; i < 32; i++) {
		if (i >= chamber_count) {
			break;
		}
		// Fast vertical culling: skip distant chambers
		if (abs(p.y - chambers[i].y) > chambers[i].w + WALL_DEPTH) {
			continue;
		}
		d = min(d, sd_ellipse(p, chambers[i].xy, chambers[i].zw));
	}
	for (int i = 0; i < 32; i++) {
		if (i >= corridor_count) {
			break;
		}
		// Fast vertical culling: skip distant corridors
		float c_min_y = min(corridors[i].y, corridors[i].w) - corridor_widths[i] - WALL_DEPTH;
		float c_max_y = max(corridors[i].y, corridors[i].w) + corridor_widths[i] + WALL_DEPTH;
		if (p.y < c_min_y || p.y > c_max_y) {
			continue;
		}
		d = min(d, sd_capsule(p, corridors[i].xy, corridors[i].zw, corridor_widths[i]));
	}
	return d;
}

void fragment() {
	vec2 p = rect_origin + UV * rect_size;
	float d = cavity_sdf(p);
	float vy = clamp((p.y - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);

	// ---- Cavity floor -----------------------------------------------------
	vec3 cav_hi = vec3(0.247, 0.110, 0.146);
	vec3 cav_mid = vec3(0.208, 0.089, 0.124);
	vec3 cav_low = vec3(0.150, 0.060, 0.096);
	vec3 cav_deep = vec3(0.108, 0.042, 0.074);
	vec3 cavity = mix(cav_hi, cav_mid, smoothstep(0.00, 0.36, vy));
	cavity = mix(cavity, cav_low, smoothstep(0.34, 0.76, vy));
	cavity = mix(cavity, cav_deep, smoothstep(0.74, 1.00, vy));

	float mottle = fbm(p * 0.0046);
	cavity += (mottle - 0.5) * vec3(0.052, 0.024, 0.032);
	float grain = vnoise(p * 0.021 + 13.7);
	cavity += (grain - 0.5) * vec3(0.016, 0.007, 0.010);

	// A tube is deepest along its axis: a very soft bowl, never a spotlight.
	float bowl = smoothstep(0.0, 1.0, clamp(-d / 460.0, 0.0, 1.0));
	cavity *= mix(1.0, 0.90, bowl);

	// Mucosa rolls into shadow just before the wall begins.
	float edge = smoothstep(-76.0, -4.0, d);
	cavity *= mix(1.0, 0.58, edge);

	// ---- Muscle wall ------------------------------------------------------
	float t = clamp(d / WALL_DEPTH, 0.0, 1.0);
	vec3 w0 = vec3(0.352, 0.166, 0.205);
	vec3 w1 = vec3(0.223, 0.098, 0.133);
	vec3 w2 = vec3(0.112, 0.044, 0.071);
	vec3 w3 = vec3(0.032, 0.012, 0.024);
	vec3 wall = mix(w0, w1, smoothstep(0.00, 0.11, t));
	wall = mix(wall, w2, smoothstep(0.10, 0.44, t));
	wall = mix(wall, w3, smoothstep(0.42, 1.00, t));

	// Fibres following the lumen edge, plus broad tissue variation.
	float layer = sin(d * 0.16 + fbm(p * 0.0032) * 8.0);
	wall += vec3(0.026, 0.010, 0.014) * (layer * 0.5 + 0.5) * (1.0 - t) * 0.42;
	float fibre = fbm(vec2(p.x * 0.012, p.y * 0.0035) + vnoise(p * 0.0036) * 1.5);
	wall += (fibre - 0.5) * vec3(0.032, 0.013, 0.018) * (1.0 - t * 0.7);
	wall += (vnoise(p * 0.0012 + 7.0) - 0.5) * vec3(0.018, 0.007, 0.011);

	// A faint mucosal lip keeps the boundary readable without a glowing rim.
	wall += vec3(0.016, 0.006, 0.009) * (1.0 - smoothstep(0.0, 16.0, abs(d)));

	vec3 col = mix(cavity, wall, smoothstep(-2.0, 2.0, d));
	COLOR = vec4(col, 1.0);
}
