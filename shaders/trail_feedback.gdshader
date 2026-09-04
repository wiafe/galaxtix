// Phosphor persistence: new_trail = mix(current_scene, blur(previous_trail) * decay, feedback)
// Two of these ping-pong (A reads B, B reads A). Ported from system.js:2819 / :2844.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_tex : filter_linear, repeat_disable;
uniform sampler2D prev_tex : filter_linear, repeat_disable;
uniform float feedback = 0.86;
uniform float blur_radius = 1.0;
uniform vec2 texel = vec2(0.000625, 0.0011111);

void fragment() {
	vec2 uv = UV;
	vec2 t = texel * blur_radius;
	vec3 c = texture(prev_tex, uv).rgb * 0.25;
	c += (texture(prev_tex, uv + vec2(t.x, 0.0)).rgb + texture(prev_tex, uv - vec2(t.x, 0.0)).rgb
		+ texture(prev_tex, uv + vec2(0.0, t.y)).rgb + texture(prev_tex, uv - vec2(0.0, t.y)).rgb) * 0.125;
	c += (texture(prev_tex, uv + t).rgb + texture(prev_tex, uv - t).rgb
		+ texture(prev_tex, uv + vec2(t.x, -t.y)).rgb + texture(prev_tex, uv + vec2(-t.x, t.y)).rgb) * 0.0625;
	c *= vec3(0.95, 0.97, 0.94);                 // decay bias: trails cool as they fade
	float lum = dot(c, vec3(0.04, 0.77, 0.28));
	c = mix(vec3(lum), c, 1.06);                 // nudge saturation
	vec3 cur = texture(scene_tex, uv).rgb;
	COLOR = vec4(mix(cur, c, feedback), 1.0);
}
