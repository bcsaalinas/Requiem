shader_type canvas_item;
// La Amortajada exists only where a real light lands on her: no ambient, no rim, no floor.
render_mode light_only;
// Same grade as scenery.gdshader, so the shroud sits in the painted world.
uniform float saturation : hint_range(0.0,1.0) = .5;
uniform float contrast : hint_range(0.0,1.0) = 1.0;
uniform float gain : hint_range(0.0,1.0) = 1.0;
// How much incoming light makes her fully opaque; lower lets faint light leave her half-seen.
uniform float reveal_gain = 4.0;
void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float value = dot(tex.rgb,vec3(.2126,.7152,.0722));
    vec3 color = mix(vec3(value),tex.rgb,saturation);
    color = (vec3(.40) + (color-vec3(.40))*contrast)*gain;
    COLOR = vec4(color,tex.a)*COLOR;
}
void light() {
    // Opacity follows the light that reaches her, so a lamp's dark falloff or a shadow never
    // draws a black cut-out: where no light lands, nothing of her is drawn.
    float reach = clamp(max(LIGHT_COLOR.r,max(LIGHT_COLOR.g,LIGHT_COLOR.b))*LIGHT_ENERGY*reveal_gain,0.0,1.0);
    LIGHT = vec4(COLOR.rgb*LIGHT_COLOR.rgb*LIGHT_ENERGY,LIGHT_COLOR.a*reach);
}
