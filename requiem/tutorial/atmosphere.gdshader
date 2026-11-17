shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
// 0 = calm, 1 = the entity is right here: the vignette closes in and colour drains.
uniform float pressure : hint_range(0.0, 1.0) = 0.0;
void fragment() {
    vec2 pixel = floor(FRAGCOORD.xy);
    vec3 scene = texture(screen_texture, pixel * SCREEN_PIXEL_SIZE).rgb;
    vec2 centered = SCREEN_UV * 2.0 - 1.0;
    float falloff = smoothstep(.25 - .2 * pressure, 1.4, length(centered));
    falloff = floor(falloff * 4.0) / 4.0;
    scene = mix(scene, vec3(dot(scene, vec3(.2126, .7152, .0722))), .55 * pressure);
    COLOR = vec4(mix(scene, vec3(0.055, 0.047, 0.051), (.14 + .5 * pressure) * falloff), 1.0);
}
