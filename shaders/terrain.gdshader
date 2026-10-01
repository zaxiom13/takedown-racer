shader_type spatial;
// 4-layer splat terrain. Weights come from splat.png laid over the whole terrain; each layer tiles
// with its own period (metres, from SR3 "scale"). A second, larger tiling breaks visible repetition.
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec4 origin_size;   // x, z of grid origin, world size
uniform sampler2D layer0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale0 = 6.0;
uniform float scale1 = 6.0;
uniform float scale2 = 6.0;
uniform float scale3 = 6.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 layer(sampler2D t, float s) {
	vec2 uv = wpos.xz / s;
	return mix(texture(t, uv).rgb, texture(t, uv * 0.23 + 0.37).rgb, 0.35);
}

void fragment() {
	vec4 w = texture(splat, (wpos.xz - origin_size.xy) / origin_size.z);
	w /= max(w.r + w.g + w.b + w.a, 0.001);
	vec3 col = layer(layer0, scale0) * w.r + layer(layer1, scale1) * w.g
		+ layer(layer2, scale2) * w.b + layer(layer3, scale3) * w.a;
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
