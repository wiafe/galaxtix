// Final composite to the screen:
//   lighten(trail, scene) -> color grade -> scanlines -> vignette -> grain, sampled through
//   barrel curvature + triangular chromatic aberration. Ported from the demo's CRT/GRADE/NOISE passes.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_tex : filter_linear, repeat_disable;
uniform sampler2D trail_tex : filter_linear, repeat_disable;
uniform float dry = 1.0;
uniform float curve = 0.06;
uniform float scan_depth = 0.18;
uniform float scan_lines = 450.0;
uniform float vignette = 0.45;
uniform float aberr = 1.0;
uniform float grain = 0.035;
uniform float contrast = 1.15;
uniform float gamma_adj = 1.25;
uniform float saturation = 1.15;
uniform float warmth = 0.0;
uniform float amp = 1.0;
uniform float time = 0.0;
uniform bool to_srgb = true;
uniform float fake_bloom = 0.0;   // Compatibility renderer has no HDR glow: cheap ring bloom instead
uniform vec2 pix = vec2(0.000625, 0.0011111);

vec3 samp(vec2 uv) {
	// "lighten" (max) blend: brightest contribution wins, like real phosphor
	vec3 c = max(texture(trail_tex, uv).rgb, texture(scene_tex, uv).rgb * dry);
	if (fake_bloom > 0.0) {
		// two rings of taps (radius 3 and 7 px): a soft halo around every beam
		vec3 b = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398 + 0.19;
			vec2 o = vec2(cos(a), sin(a)) * pix;
			b += texture(scene_tex, uv + o * 3.0).rgb;
			b += texture(scene_tex, uv + o * 7.0).rgb * 0.6;
		}
		c += b * (fake_bloom / 12.8);
	}
	return c;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 barrel(vec2 uv, float k) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + k * dot(c, c);
	return c * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = barrel(UV, curve);
	uv = (uv - 0.5) / (1.0 + curve) + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec2 ctr = uv - 0.5;
		float radN = dot(ctr, ctr) * 2.0;
		float shift = aberr * (0.35 + 0.65 * radN);
		vec3 col = vec3(
			samp(uv + vec2(-shift, shift) * pix).r,
			samp(uv + vec2(shift, shift) * pix).g,
			samp(uv + vec2(0.0, -shift) * pix).b);
		if (to_srgb) {
			col = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
		}
		// grade: green-heavy luma (phosphor bias), per-channel gamma split by warmth
		float lum = dot(col, vec3(0.01, 0.77, 0.08));
		col = mix(vec3(lum), col, saturation);
		col = pow(max(col, vec3(0.0)), vec3((1.0 - warmth) / gamma_adj, 1.0 / gamma_adj, (1.0 + warmth) / gamma_adj));
		col = mix(vec3(0.5), col, contrast);
		col *= amp;
		// scanlines
		float sl = 0.5 + 0.5 * sin(uv.y * scan_lines * 6.28318530718);
		col *= 1.0 - scan_depth * (1.0 - sl);
		// rounded vignette
		vec2 d = abs(uv - 0.5) * 2.0;
		float vig = smoothstep(1.5, 0.35, length(d));
		col *= mix(1.0, vig, vignette);
		// animated dark-biased grain
		float n = hash12(floor(uv / pix + vec2(time * 61.0, time * 37.0)));
		n = n * n;
		col += (n * 2.0 - 1.0) * grain;
		COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
	}
}
