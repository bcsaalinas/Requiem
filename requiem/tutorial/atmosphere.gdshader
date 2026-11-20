shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
// 0 = calm, 1 = the entity is right here: the vignette closes in and colour drains.
uniform float pressure : hint_range(0.0, 1.0) = 0.0;
// 0 = unaware, 1 = entity focused / hunting the player (adds subtle aberration & heartbeat vignette).
uniform float focus : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
// Brief, deterministic visual shock when the entity first enters its chase state.
uniform float hunt_intro : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 uv = floor(FRAGCOORD.xy) * SCREEN_PIXEL_SIZE;
    vec2 centered = SCREEN_UV * 2.0 - 1.0;
    float dist = length(centered);
    float aberr = (0.0007 * pressure + 0.0015 * focus * (0.65 + 0.35 * pulse)) * smoothstep(0.3, 1.35, dist);
    vec2 dir = dist > 0.0001 ? (centered / dist) : vec2(0.0);
    float r = texture(screen_texture, clamp(uv + dir * aberr, vec2(0.0), vec2(1.0))).r;
    float g = texture(screen_texture, uv).g;
    float b = texture(screen_texture, clamp(uv - dir * aberr, vec2(0.0), vec2(1.0))).b;
    vec3 scene = vec3(r, g, b);

    float intro_edge = smoothstep(0.2, 1.35, dist);
    scene = mix(scene, vec3(dot(scene, vec3(.2126, .7152, .0722))), .25 * hunt_intro);
    scene = mix(scene, vec3(.20, .015, .025), .38 * hunt_intro * intro_edge);

    float eff_pressure = clamp(pressure + focus * (0.24 + 0.16 * pulse) + hunt_intro * 0.15, 0.0, 1.0);
    float vignette = 1.0 - (.14 + .46 * eff_pressure) * smoothstep(.25 - .15 * eff_pressure, 1.45, dist);
    float luma = dot(scene, vec3(.2126, .7152, .0722));
    scene = mix(scene, vec3(luma), .45 * eff_pressure);
    vec3 dread_tint = mix(vec3(1.0), vec3(1.03, 0.94, 0.92), focus * 0.22 * smoothstep(0.4, 1.4, dist));
    COLOR = vec4(scene * vignette * dread_tint, 1.0);
}
