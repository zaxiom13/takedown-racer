shader_type spatial;
// Cheap world-space grass/dirt ground with large-scale colour variation.
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a = vec3(0.20, 0.32, 0.10);
uniform vec3 grass_b = vec3(0.33, 0.38, 0.16);
uniform vec3 dirt = vec3(0.36, 0.30, 0.21);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fine = texture(grain, wpos.xz * 0.25).r;
	float mid = texture(grain, wpos.xz * 0.02).r;
	float big = texture(grain, wpos.xz * 0.003).r;
	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.7, mid));
	col = mix(col, dirt, smoothstep(0.62, 0.8, big) * 0.8);
	col *= 0.8 + 0.4 * fine;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
