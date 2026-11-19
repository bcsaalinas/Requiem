shader_type canvas_item;
render_mode unshaded;
// Held breath as tunnel vision: silence costs sight. Drawn over the finished world image.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
// Her position on screen (UV) and the screen's width / height.
uniform vec2 focus = vec2(0.5, 0.5);
uniform float aspect = 1.7778;
// 0 = breathing freely, 1 = the tunnel is fully drawn in.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Clear radius around her, in screen heights; the dark is complete `falloff` further out.
uniform float radius = 0.34;
uniform float falloff = 0.30;
uniform float darkness : hint_range(0.0, 1.0) = 0.85;
uniform float drain : hint_range(0.0, 1.0) = 0.6;
// Same grain as the light textures (4 art px per light texel).
const float BLOCK = 4.0;
const float BANDS = 5.0;

void fragment() {
    vec2 pixel = floor(FRAGCOORD.xy);
    vec3 scene = texture(screen_texture, (pixel + 0.5) * SCREEN_PIXEL_SIZE).rgb;
    vec2 block = (floor(pixel / BLOCK) + 0.5) * BLOCK * SCREEN_PIXEL_SIZE;
    vec2 offset = block - focus;
    offset.x *= aspect;
    float edge = smoothstep(radius, radius + falloff, length(offset));
    edge = ceil(edge * BANDS) / BANDS;
    float grey = dot(scene, vec3(0.2126, 0.7152, 0.0722));
    // Colour drains everywhere a little, and fully where the tunnel closes.
    scene = mix(scene, vec3(grey), amount * drain * (0.45 + 0.55 * edge));
    scene *= 1.0 - amount * darkness * edge;
    COLOR = vec4(scene, 1.0);
}
