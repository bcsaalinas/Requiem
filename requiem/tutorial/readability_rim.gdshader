shader_type canvas_item;
render_mode unshaded;
uniform sampler2D atlas_texture : filter_nearest;
uniform vec4 atlas_bounds;
uniform vec2 edge_step;
uniform vec4 accent : source_color;
uniform float rim_strength = .3;
float coverage(vec2 uv) {
    if (uv.x<atlas_bounds.x || uv.y<atlas_bounds.y || uv.x>atlas_bounds.z || uv.y>atlas_bounds.w) return 0.0;
    return texture(atlas_texture,uv).a;
}
void fragment() {
    float a = coverage(UV);
    float edge = max(max(coverage(UV+vec2(edge_step.x,0)),coverage(UV-vec2(edge_step.x,0))),
                     max(coverage(UV+vec2(0,edge_step.y)),coverage(UV-vec2(0,edge_step.y))));
    // Only the outer contour survives darkness; the sprite body receives real light.
    COLOR = vec4(accent.rgb*.6,max(0.0,edge-a)*rim_strength);
}
