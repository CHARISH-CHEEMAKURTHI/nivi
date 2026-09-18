shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Sea around the island: rolling waves, a paler shelf near the shore and a
// band of foam that hugs the island's rounded-square outline.

uniform vec3 deep_color : source_color = vec3(0.09, 0.42, 0.56);
uniform vec3 shallow_color : source_color = vec3(0.29, 0.71, 0.78);
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 1.0);
uniform vec2 island_half = vec2(23.0, 23.0);
uniform float island_round = 6.0;
uniform float foam_width = 1.6;
uniform float wave_height = 0.06;
uniform float wave_speed = 0.7;

varying vec3 world_pos;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float wave(vec2 p, float t) {
	return sin(p.x * 0.55 + t) * 0.5 + sin(p.y * 0.42 - t * 1.13) * 0.3 + sin((p.x + p.y) * 0.27 + t * 0.7) * 0.2;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave(world_pos.xz, TIME * wave_speed) * wave_height;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * wave_speed;
	float d = sd_round_box(p, island_half, island_round);
	float w = wave(p, t);

	// depth shading: pale over the shelf, deep further out
	float depth_mix = clamp(d / 26.0, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, depth_mix);

	// crests catch the light
	col += vec3(0.05) * smoothstep(0.55, 1.0, w);

	// foam ring hugging the shore, wobbled by the swell
	float edge = d - w * 0.35;
	float foam = 1.0 - smoothstep(0.0, foam_width, edge);
	foam *= smoothstep(-0.9, -0.1, edge);
	float lace = smoothstep(0.35, 0.9, sin(d * 5.5 - t * 2.4) * 0.5 + 0.5);
	col = mix(col, foam_color, clamp(foam * (0.55 + 0.45 * lace), 0.0, 1.0));

	ALBEDO = col;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	NORMAL_MAP = vec3(0.5 + w * 0.06, 0.5 + sin(p.y * 0.6 + t) * 0.06, 1.0);
}
