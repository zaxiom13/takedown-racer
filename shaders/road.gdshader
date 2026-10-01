shader_type spatial;
// Procedural asphalt: noise grain + edge lines + dashed centre line. UV.x across, UV.y metres along.
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform vec3 asphalt = vec3(0.13, 0.13, 0.14);
uniform float lanes = 2.0;

void fragment() {
	float g = texture(grain, UV * vec2(4.0, 0.25)).r;
	float g2 = texture(grain, UV * vec2(0.5, 0.02)).r;
	vec3 col = asphalt * (0.75 + 0.5 * g) * (0.85 + 0.3 * g2);
	float x = UV.x;
	float edge = step(x, 0.035) * step(0.02, x) + step(0.965, x) * step(x, 0.98);
	float dash = step(fract(UV.y / 9.0), 0.45);
	float centre = 0.0;
	for (float i = 1.0; i < lanes; i += 1.0) {
		centre += step(abs(x - i / lanes), 0.006) * dash;
	}
	float paint = clamp(edge + centre, 0.0, 1.0);
	paint *= step(x, 1.0) * step(0.0, x);
	col = mix(col, vec3(0.85, 0.85, 0.8), paint * (0.7 + 0.3 * g));
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.6, paint);
	SPECULAR = 0.35;
}
