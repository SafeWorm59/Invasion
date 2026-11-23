shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform int chamber_count = 0;
uniform vec4 chambers[32];
uniform int corridor_count = 0;
uniform vec4 corridors[32];
uniform float corridor_widths[32];
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1.0);
uniform float top_y = -4000.0;
uniform float bottom_y = 4000.0;

const float WALL_DEPTH = 560.0;

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
		float min_y = min(corridors[i].y, corridors[i].w) - corridor_widths[i] - WALL_DEPTH;
		float max_y = max(corridors[i].y, corridors[i].w) + corridor_widths[i] + WALL_DEPTH;
		if (p.y < min_y || p.y > max_y) {
			continue;
		}
		d = min(d, sd_capsule(p, corridors[i].xy, corridors[i].zw, corridor_widths[i]));
	}
	return d;
}

void fragment() {
	vec2 p = rect_origin + UV * rect_size;
	float d = cavity_sdf(p);
	float vertical = clamp((p.y - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);

	vec3 lumen = mix(vec3(0.34, 0.20, 0.27), vec3(0.19, 0.09, 0.15), vertical);
	float mottling = fbm(p * 0.0040);
	lumen += (mottling - 0.5) * vec3(0.060, 0.035, 0.048);
	float alveolar_texture = vnoise(p * 0.014 + 5.2);
	lumen += (alveolar_texture - 0.5) * vec3(0.028, 0.018, 0.026);
	float wet_sheen = smoothstep(-240.0, -30.0, d) * (1.0 - smoothstep(-30.0, -5.0, d));
	wet_sheen *= 0.45 + 0.55 * vnoise(p * 0.0025 + 13.0);
	lumen += vec3(0.035, 0.022, 0.030) * wet_sheen;
	lumen *= mix(1.0, 0.90, smoothstep(0.0, 1.0, clamp(-d / 520.0, 0.0, 1.0)));
	lumen *= mix(1.0, 0.62, smoothstep(-82.0, -4.0, d));

	float wall_depth = clamp(d / WALL_DEPTH, 0.0, 1.0);
	vec3 wall = mix(vec3(0.46, 0.23, 0.30), vec3(0.10, 0.035, 0.060), wall_depth);
	float tissue_fibres = fbm(vec2(p.x * 0.009, p.y * 0.003) + vnoise(p * 0.003) * 1.4);
	wall += (tissue_fibres - 0.5) * vec3(0.045, 0.024, 0.032) * (1.0 - wall_depth * 0.7);
	wall += vec3(0.018, 0.008, 0.013) * (1.0 - smoothstep(0.0, 18.0, abs(d)));

	COLOR = vec4(mix(lumen, wall, smoothstep(-2.0, 2.0, d)), 1.0);
}
