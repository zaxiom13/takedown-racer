shader_type canvas_item;
// Cheap radial speed blur: samples the screen along the ray towards the screen centre.
// Strength 0 = off. Edges blur most, centre stays sharp (where the player looks).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.45);
const int SAMPLES = 6;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - center;
	float edge = smoothstep(0.08, 0.6, length(dir));
	float amount = strength * edge * 0.06;
	vec3 col = texture(screen_tex, uv).rgb;
	if (amount > 0.0005) {
		for (int i = 1; i < SAMPLES; i++) {
			col += texture(screen_tex, uv - dir * amount * float(i) / float(SAMPLES)).rgb;
		}
		col /= float(SAMPLES);
	}
	COLOR = vec4(col, 1.0);
}
