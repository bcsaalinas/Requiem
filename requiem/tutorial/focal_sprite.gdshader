shader_type canvas_item;
// Sprite bodies receive the same lights and occlusion as the environment.
uniform sampler2D atlas_texture : filter_nearest;
uniform vec4 atlas_bounds;
uniform vec2 edge_step;
uniform vec4 accent : source_color = vec4(.80,.89,.87,1.0);
uniform float value_floor = .42;
uniform float value_range = .40;
uniform float rim_strength = .60;
uniform float color_mix = .18;
float coverage(vec2 uv) {
    if (uv.x<atlas_bounds.x || uv.y<atlas_bounds.y || uv.x>atlas_bounds.z || uv.y>atlas_bounds.w) return 0.0;
    return texture(atlas_texture,uv).a;
}
void fragment() {
    vec4 tex = texture(atlas_texture,UV);
    float a = coverage(UV);
    float edge = max(max(coverage(UV+vec2(edge_step.x,0)),coverage(UV-vec2(edge_step.x,0))),
                     max(coverage(UV+vec2(0,edge_step.y)),coverage(UV-vec2(0,edge_step.y))));
    vec2 outer = edge_step*2.0;
    float keyline = max(max(coverage(UV+vec2(outer.x,0)),coverage(UV-vec2(outer.x,0))),
                       max(coverage(UV+vec2(0,outer.y)),coverage(UV-vec2(0,outer.y))));
    float value = dot(tex.rgb,vec3(.2126,.7152,.0722));
    float shaped_value = value_floor + pow(value,.58)*value_range;
    vec3 chroma = tex.rgb/max(value,.025);
    vec3 body = shaped_value*mix(vec3(1.0),chroma,.38);
    body = mix(body,body*accent.rgb*1.25,color_mix);
    vec3 silhouette = mix(vec3(.025,.032,.030),accent.rgb*rim_strength,edge);
    COLOR = vec4(mix(silhouette,body,a),max(a,keyline*rim_strength));
}
