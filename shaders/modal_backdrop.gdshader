shader_type canvas_item;
render_mode unshaded;

uniform sampler2D backdrop : hint_screen_texture, filter_linear, repeat_disable;
uniform float brightness = 1.0;

void fragment() {
	// A small weighted blur softens the frozen arena beneath a cool, dark tint.
	vec2 step_uv = SCREEN_PIXEL_SIZE * 3.0;
	vec3 blurred = vec3(0.0);
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			float weight = float(3 - abs(x)) * float(3 - abs(y));
			blurred += texture(backdrop, SCREEN_UV + vec2(float(x), float(y)) * step_uv).rgb * weight;
		}
	}
	COLOR = vec4(blurred / 81.0 * vec3(0.12, 0.15, 0.20) * brightness, 1.0);
}
