shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
void fragment() {
    vec2 pixel = floor(FRAGCOORD.xy);
    vec3 scene = texture(screen_texture, pixel * SCREEN_PIXEL_SIZE).rgb;
    vec2 centered = SCREEN_UV * 2.0 - 1.0;
    float vignette = 1.0 - .14 * smoothstep(.25, 1.4, length(centered));
    COLOR = vec4(scene * vignette, 1.0);
}
