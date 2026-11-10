shader_type canvas_item;
render_mode unshaded;
// Nine fixed taps: blur the existing menu art without a screen-copy pass.
void fragment() {
	vec2 p = UV;
	vec3 art = texture(TEXTURE, p).rgb * 0.2;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398;
		art += texture(TEXTURE, p + vec2(cos(angle), sin(angle)) * 0.007).rgb * 0.1;
	}
	float gray = dot(art, vec3(0.2126, 0.7152, 0.0722));
	vec3 base = mix(vec3(gray), art, 0.15) * 0.19;
	vec2 uv = UV;
	float light = exp(-pow((uv.x - 0.5) / (0.13 + uv.y * 0.34), 2.0)) * exp(-uv.y * 3.5);
	float fog = sin(uv.x * 9.0 + uv.y * 5.0 + TIME * 0.07)
		* sin(uv.y * 13.0 - uv.x * 4.0 - TIME * 0.045) * 0.5 + 0.5;
	float edges = 1.0 - smoothstep(0.25, 0.77, length((uv - 0.5) * vec2(1.15, 0.8)));
	vec3 atmosphere = vec3(0.70, 0.74, 0.73) * (light * 0.25 + fog * 0.035);
	COLOR = vec4((base + atmosphere) * edges + vec3(0.007, 0.009, 0.011), 1.0);
}
