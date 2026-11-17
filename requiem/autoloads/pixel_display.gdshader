shader_type canvas_item;
render_mode unshaded;

// Exact area-coverage resampling of the fixed world image (sharp bilinear).
// Each output pixel integrates its footprint over the nearest-neighbour source:
// whole-number scales are plain nearest, in-between upscales keep every art pixel a
// solid block and blend only the one-pixel seam, downscales are a box filter.

uniform vec2 source_size = vec2(1920.0, 1080.0);
uniform float image_scale = 1.0;

const int TAPS = 4;
const float EDGE_EPSILON = 1e-6;
const float INTEGER_SCALE_EPSILON = 1e-4;

void fragment() {
	vec2 center = UV * source_size;
	if (abs(image_scale - round(image_scale)) < INTEGER_SCALE_EPSILON) {
		ivec2 texel = clamp(ivec2(floor(center)), ivec2(0), ivec2(source_size) - ivec2(1));
		COLOR = vec4(texelFetch(TEXTURE, texel, 0).rgb, 1.0);
	} else {
		vec2 half_footprint = vec2(0.5 / image_scale);
		vec2 from = center - half_footprint;
		vec2 to = center + half_footprint;
		ivec2 first = ivec2(floor(from));
		ivec2 max_texel = ivec2(source_size) - ivec2(1);
		vec3 sum = vec3(0.0);
		float total = 0.0;
		for (int y = 0; y < TAPS; y++) {
			int ty = first.y + y;
			float wy = min(to.y, float(ty + 1)) - max(from.y, float(ty));
			if (wy <= EDGE_EPSILON || float(ty) > to.y - EDGE_EPSILON) {
				continue;
			}
			for (int x = 0; x < TAPS; x++) {
				int tx = first.x + x;
				float wx = min(to.x, float(tx + 1)) - max(from.x, float(tx));
				if (wx <= EDGE_EPSILON || float(tx) > to.x - EDGE_EPSILON) {
					continue;
				}
				float w = wx * wy;
				sum += texelFetch(TEXTURE, clamp(ivec2(tx, ty), ivec2(0), max_texel), 0).rgb * w;
				total += w;
			}
		}
		COLOR = vec4(sum / max(total, EDGE_EPSILON), 1.0);
	}
}
