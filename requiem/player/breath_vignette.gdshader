shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0, 0.2) = 0.0;
uniform float tension : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // Keep the central play area clear; no screen sampling, blur or camera shake.
    vec2 offset = UV * 2.0 - 1.0;
    float edge = smoothstep(0.42, 1.30, length(offset));
    vec3 shade = mix(vec3(0.035, 0.055, 0.049), vec3(0.09, 0.046, 0.035), tension);
    COLOR = vec4(shade, edge * strength);
}
