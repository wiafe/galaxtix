shader_type spatial;
render_mode unshaded;
uniform sampler2D surface_map : filter_nearest, repeat_disable;
uniform float resolution = 24.0;
uniform vec3 land_color : source_color = vec3(0.22, 0.66, 1.0);
uniform float clock = 0.0;
void fragment() {
	float state = texture(surface_map, UV).r;
	vec2 tile = fract(UV * vec2(resolution * 6.0, resolution));
	// The void is quiet, just like the 2D arena. Patterns belong to land only.
	vec3 color = vec3(0.003);
	if (state > 0.2 && state < 0.5) {
		vec2 square = abs(tile - vec2(0.5));
		float pattern = 1.0 - smoothstep(0.20, 0.25, max(square.x, square.y));
		color += land_color * (0.025 + 0.11 * pattern);
		// Green channel stores the reveal time of newly claimed cells.
		float age = clock - texture(surface_map, UV).g;
		float fresh = texture(surface_map, UV).b;
		color += land_color * fresh * max(0.0, 1.0 - age / 0.5) * 0.16;
	} else if (state >= 0.85) {
		float hatch = 1.0 - smoothstep(0.045, 0.10, abs(fract((UV.x * 6.0 + UV.y) * resolution) - 0.5));
		color += vec3(0.018, 0.020, 0.025) * hatch;
	}
	ALBEDO = color;
}
