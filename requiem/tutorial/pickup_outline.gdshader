shader_type canvas_item;
render_mode unshaded;
// A pickup's outline in one flat colour: the ring of pixels just outside the item's silhouette.
// It is drawn over the item (not behind it), so y-sorted furniture can never cover it, and it is
// unshaded, so it says "this one, now" even with no light on it. The sprite's region is the
// texture grown by one pixel on every side; outside the texture there is no silhouette.
uniform vec4 tint : source_color = vec4(0.729, 0.706, 0.667, 1.0);

// 1 inside the texture rectangle, 0 outside it (the grown border samples nothing).
float inside(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 right = UV + vec2(px.x, 0.0);
	vec2 left = UV - vec2(px.x, 0.0);
	vec2 down = UV + vec2(0.0, px.y);
	vec2 up = UV - vec2(0.0, px.y);
	float own = step(0.5, texture(TEXTURE, UV).a) * inside(UV);
	float around = max(
		max(step(0.5, texture(TEXTURE, right).a) * inside(right), step(0.5, texture(TEXTURE, left).a) * inside(left)),
		max(step(0.5, texture(TEXTURE, down).a) * inside(down), step(0.5, texture(TEXTURE, up).a) * inside(up)));
	COLOR = vec4(tint.rgb, tint.a * around * (1.0 - own));
}
