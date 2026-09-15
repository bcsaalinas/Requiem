shader_type canvas_item;
uniform float saturation : hint_range(0.0,1.0) = .23;
uniform float contrast : hint_range(0.0,1.0) = .55;
uniform float gain : hint_range(0.0,1.0) = .78;
uniform float detail_radius = 2.0;
varying vec4 item_color;
void vertex() { item_color = COLOR; }
void fragment() {
    vec2 d = TEXTURE_PIXEL_SIZE * detail_radius;
    vec4 center = texture(TEXTURE, UV);
    // Filter only color, preserving each silhouette's original alpha edge.
    vec3 color = center.rgb * .25;
    color += (texture(TEXTURE,UV+vec2(d.x,0)).rgb + texture(TEXTURE,UV-vec2(d.x,0)).rgb
            + texture(TEXTURE,UV+vec2(0,d.y)).rgb + texture(TEXTURE,UV-vec2(0,d.y)).rgb) * .125;
    color += (texture(TEXTURE,UV+d).rgb + texture(TEXTURE,UV-d).rgb
            + texture(TEXTURE,UV+vec2(d.x,-d.y)).rgb + texture(TEXTURE,UV+vec2(-d.x,d.y)).rgb) * .0625;
    float value = dot(color,vec3(.2126,.7152,.0722));
    color = mix(vec3(value),color,saturation);
    color = (vec3(.40) + (color-vec3(.40))*contrast)*gain;
    COLOR = vec4(color,center.a)*item_color;
}
