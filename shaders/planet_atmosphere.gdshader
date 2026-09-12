shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
void fragment() {
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 12.0);
	ALBEDO = vec3(0.06, 0.10, 0.16) * rim;
	ALPHA = rim * 0.12;
}
