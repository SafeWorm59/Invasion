shader_type canvas_item;
render_mode blend_mix, unshaded;

// Level 4 tissue renderer (trachea).
//
// The cavity is the union of the tube chambers and the two bronchial capsules.
// The same tables drive the collision shell and the minimap outline, so what
// the player sees and what the player touches cannot drift apart. The palette
// is pink/red respiratory mucosa rather than the larynx's darker muscle tones,
// with a very soft per-ring groove so the windpipe reads as a stack of
// cartilage-supported segments.

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
		if (abs(p.y - chambers[i].y) > chambers[i].w + WALL_DEPTH) {
			continue;
		}
		d = min(d, sd_ellipse(p, chambers[i].xy, chambers[i].zw));
	}
	for (int i = 0; i < 32; i++) {
		if (i >= corridor_count) {
			break;
		}
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

	// ---- Respiratory mucosa ----------------------------------------------
	vec3 cav_hi = vec3(0.455, 0.188, 0.192);
	vec3 cav_mid = vec3(0.385, 0.146, 0.156);
	vec3 cav_low = vec3(0.290, 0.100, 0.116);
	vec3 cav_deep = vec3(0.196, 0.062, 0.080);
	vec3 cavity = mix(cav_hi, cav_mid, smoothstep(0.00, 0.36, vy));
	cavity = mix(cavity, cav_low, smoothstep(0.34, 0.76, vy));
	cavity = mix(cavity, cav_deep, smoothstep(0.74, 1.00, vy));

	// Moist, slightly mottled epithelium.
	float mottle = fbm(p * 0.0044);
	cavity += (mottle - 0.5) * vec3(0.060, 0.026, 0.026);
	float grain = vnoise(p * 0.019 + 4.7);
	cavity += (grain - 0.5) * vec3(0.020, 0.009, 0.009);

	// Soft wet sheen along the lumen, strongest a little way in from the wall.
	float sheen = smoothstep(-260.0, -40.0, d) * (1.0 - smoothstep(-40.0, -6.0, d));
	sheen *= 0.5 + 0.5 * vnoise(p * 0.0026 + 11.0);
	cavity += vec3(0.030, 0.014, 0.012) * sheen;

	// A tube is deepest along its axis: a very soft bowl, never a spotlight.
	float bowl = smoothstep(0.0, 1.0, clamp(-d / 470.0, 0.0, 1.0));
	cavity *= mix(1.0, 0.92, bowl);

	// Very soft groove where each hyaline ring meets the mucosa.
	float ring_phase = (p.y + 3300.0) * 0.0125663706;
	float ring_groove = 0.5 + 0.5 * cos(ring_phase);
	cavity *= 1.0 - 0.030 * ring_groove * smoothstep(0.55, 1.0, -d / 340.0);

	// Mucosa rolls into shadow just before the wall begins.
	float edge = smoothstep(-78.0, -4.0, d);
	cavity *= mix(1.0, 0.60, edge);

	// ---- Muscle / adventitia wall ----------------------------------------
	float t = clamp(d / WALL_DEPTH, 0.0, 1.0);
	vec3 w0 = vec3(0.515, 0.220, 0.216);
	vec3 w1 = vec3(0.360, 0.140, 0.148);
	vec3 w2 = vec3(0.205, 0.074, 0.084);
	vec3 w3 = vec3(0.058, 0.020, 0.028);
	vec3 wall = mix(w0, w1, smoothstep(0.00, 0.11, t));
	wall = mix(wall, w2, smoothstep(0.10, 0.44, t));
	wall = mix(wall, w3, smoothstep(0.42, 1.00, t));

	// Fibres following the lumen edge, plus broad tissue variation.
	float layer = sin(d * 0.15 + fbm(p * 0.0031) * 8.0);
	wall += vec3(0.028, 0.011, 0.011) * (layer * 0.5 + 0.5) * (1.0 - t) * 0.40;
	float fibre = fbm(vec2(p.x * 0.011, p.y * 0.0032) + vnoise(p * 0.0034) * 1.5);
	wall += (fibre - 0.5) * vec3(0.034, 0.014, 0.015) * (1.0 - t * 0.7);
	wall += (vnoise(p * 0.0011 + 7.0) - 0.5) * vec3(0.020, 0.008, 0.009);

	// Faint mucosal lip keeps the boundary readable without a glowing rim.
	wall += vec3(0.018, 0.007, 0.008) * (1.0 - smoothstep(0.0, 16.0, abs(d)));

	vec3 col = mix(cavity, wall, smoothstep(-2.0, 2.0, d));
	COLOR = vec4(col, 1.0);
}
