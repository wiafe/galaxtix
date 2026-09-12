shader_type canvas_item;
render_mode unshaded;

uniform float clock = 0.0;
uniform float opacity = 1.0;
uniform float subdued = 1.0;
uniform bool compatibility = false;
// Roguelite, Jump, Tube, Arcade, Battle Royale, Log, Options, Quit.
uniform float motif_weights[8];

float diamond(vec2 p, vec2 radius) {
	return abs(p.x) / radius.x + abs(p.y) / radius.y;
}

float motif_band(vec2 p, int motif) {
	if (motif == 0) {
		float d = diamond(p, vec2(475.0, 670.0));
		return max(d - 1.0, 0.64 - d) * 475.0;
	}
	if (motif == 1) { // Jump: forward chevrons.
		float edge = 240.0 - abs(p.y) * 0.8;
		return max(min(abs(p.x - edge), abs(p.x - edge + 240.0)) - 48.0, abs(p.y) - 500.0);
	}
	if (motif == 2) { // Tube: nested scope frames.
		float d = max(abs(p.x) / 420.0, abs(p.y) / 520.0);
		return min(abs(d - 0.90) - 0.07, abs(d - 0.55) - 0.06) * 420.0;
	}
	if (motif == 3) { // Arcade: an hourglass.
		float sides = max(abs(abs(p.x) - (60.0 + abs(p.y) * 0.6)) - 36.0, abs(p.y) - 450.0);
		float caps = max(abs(p.x) - 364.0, abs(abs(p.y) - 450.0) - 36.0);
		return min(sides, caps);
	}
	if (motif == 4) { // Battle Royale: competing, interlocked emblems.
		float a = diamond(p - vec2(-155.0, -115.0), vec2(320.0, 450.0));
		float b = diamond(p - vec2(155.0, 115.0), vec2(320.0, 450.0));
		return min(max(a - 1.0, 0.70 - a), max(b - 1.0, 0.70 - b)) * 320.0;
	}
	if (motif == 5) { // Log: three archive plates.
		float y = abs(p.y);
		float row = min(y, abs(y - 270.0));
		return max(abs(p.x + p.y * 0.18) - 370.0, row - 75.0);
	}
	if (motif == 6) { // Options: a tuning dial with a notched rim.
		float r = length(p);
		float rim = 410.0 + 25.0 * cos(atan(p.y, p.x) * 12.0);
		return max(r - rim, 260.0 - r);
	}
	// Quit: a power symbol, with an open ring and central switch.
	float ring = abs(length(p) - 360.0) - 55.0;
	if (p.y < -160.0 && abs(p.x) < 115.0) ring = max(ring, 115.0 - abs(p.x));
	float switch_bar = max(abs(p.x) - 43.0, abs(p.y + 290.0) - 205.0);
	return min(ring, switch_bar);
}

float territory(vec2 cell, int motif) {
	return 1.0 - step(0.0, motif_band(cell, motif));
}

vec3 motif_ink(int motif) {
	if (motif == 1) return vec3(0.045, 0.34, 0.30);
	if (motif == 2) return vec3(0.22, 0.14, 0.43);
	if (motif == 3) return vec3(0.43, 0.29, 0.045);
	if (motif == 4) return vec3(0.43, 0.13, 0.18);
	if (motif == 5) return vec3(0.08, 0.30, 0.42);
	if (motif == 6) return vec3(0.18, 0.28, 0.38);
	if (motif == 7) return vec3(0.38, 0.19, 0.07);
	return vec3(0.035, 0.24, 0.39);
}

vec3 motif_pixel(vec2 p, int motif) {
	// Rasterize on one fixed local grid, then filter its pixels in fragment().
	vec2 cell = (floor(p / 8.0) + 0.5) * 8.0;
	float body = territory(cell, motif);
	vec2 within = mod(p, 8.0);
	float edge = 8.0;
	if (territory(cell - vec2(8.0, 0.0), motif) < 0.5) edge = min(edge, within.x);
	if (territory(cell + vec2(8.0, 0.0), motif) < 0.5) edge = min(edge, 8.0 - within.x);
	if (territory(cell - vec2(0.0, 8.0), motif) < 0.5) edge = min(edge, within.y);
	if (territory(cell + vec2(0.0, 8.0), motif) < 0.5) edge = min(edge, 8.0 - within.y);
	float outline = body * (1.0 - smoothstep(0.5, 1.8, edge));
	float glow = exp(-abs(motif_band(p, motif)) * 0.20);
	float depth = territory(cell - vec2(24.0, 32.0), motif) * (1.0 - body);
	vec2 tile = abs(fract(p / 8.0) - 0.5);
	float squares = 1.0 - smoothstep(0.22, 0.29, max(tile.x, tile.y));
	float sweep = pow(0.5 + 0.5 * sin(p.y * 0.005 - p.x * 0.002 - clock * 0.32), 5.0);
	vec3 base = motif_ink(motif);
	vec3 ink = mix(base, base * 1.3 + vec3(0.065, 0.15, 0.06), sweep);
	float facet = p.x * p.y > 0.0 ? 0.72 : 1.0;
	return ink * body * facet * (0.023 + squares * 0.17 + sweep * 0.065)
		+ base * depth * 0.025 + ink * outline * (0.32 + sweep * 0.85) + ink * glow * 0.045;
}

void fragment() {
	vec2 screen = UV * vec2(1600.0, 900.0);
	vec2 center = vec2(1280.0 + sin(clock * 0.10) * 16.0, 420.0 + sin(clock * 0.13) * 12.0);
	vec2 p = screen - center;
	vec2 pixel = floor(p - 0.5) + 0.5;
	vec2 blend = fract(p - 0.5);
	vec3 art = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (motif_weights[i] > 0.001) {
			// Bilinear reconstruction lets the grid translate by fractions of a pixel.
			vec3 top = mix(motif_pixel(pixel, i), motif_pixel(pixel + vec2(1.0, 0.0), i), blend.x);
			vec3 bottom = mix(motif_pixel(pixel + vec2(0.0, 1.0), i), motif_pixel(pixel + vec2(1.0, 1.0), i), blend.x);
			art += mix(top, bottom, blend.y) * motif_weights[i];
		}
	}
	vec3 color = vec3(0.0015, 0.002, 0.003) + art;
	color *= mix(0.28, 1.0, smoothstep(570.0, 850.0, screen.x)) * subdued;
	if (compatibility) {
		color = mix(color * 12.92, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), color));
	}
	COLOR = vec4(color, opacity);
}
