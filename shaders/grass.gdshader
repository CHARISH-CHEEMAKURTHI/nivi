shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Meadow on top of the island: patches of lighter and darker green so the
// ground never reads as one flat colour, plus worn dirt near the shore.

uniform vec3 grass : source_color = vec3(0.357, 0.659, 0.196);
uniform vec3 grass_light : source_color = vec3(0.486, 0.761, 0.267);
uniform vec3 grass_dark : source_color = vec3(0.247, 0.490, 0.133);
uniform vec3 dirt : source_color = vec3(0.541, 0.373, 0.220);
uniform vec2 island_half = vec2(22.0, 22.0);
uniform float island_round = 5.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.3) * 0.28 + noise(p * 5.1) * 0.17;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = fbm(p * 0.19);
	vec3 col = mix(grass_dark, grass, smoothstep(0.25, 0.55, n));
	col = mix(col, grass_light, smoothstep(0.58, 0.85, n));
	// fine speckle so it holds up close to the camera
	col *= 0.94 + 0.12 * fbm(p * 1.7);
	// sandy wear where the meadow meets the beach
	float d = sd_round_box(p, island_half, island_round);
	col = mix(col, dirt, smoothstep(-2.4, -0.2, d) * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.96;
	SPECULAR = 0.05;
}
