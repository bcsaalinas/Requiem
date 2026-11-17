shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0, 0.2) = 0.0;
uniform float tension : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // Keep the central play area clear; no screen sampling, blur or camera shake.
    vec2 offset = UV * 2.0 - 1.0;
    float edge = smoothstep(0.42, 1.30, length(offset));
    edge = floor(edge * 4.0) / 4.0;
    COLOR = vec4(vec3(0.055, 0.047, 0.051), edge * strength);
}
