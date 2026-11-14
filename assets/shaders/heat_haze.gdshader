// Heat shimmer around the reactor: a camera-facing disc that redraws what is behind it
// with a small wobble. It only exists near the reactor, so the screen copy it needs
// costs nothing elsewhere in the mine.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float radius = 26.0;
// The disc is drawn this far in front of the reactor, so the core itself shimmers.
uniform float pull = 12.0;
uniform float strength = 0.010;
uniform float fade = 1.0;

void vertex() {
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 p = center + vec3(VERTEX.xy * radius, 0.0);
	float d = length(center);
	// Sliding every corner toward the eye by the same ratio keeps the on-screen size.
	p *= max(d - pull, 1.0) / max(d, 1.0);
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	// Strongest in a band around the core, nothing at the rim so there is no seam.
	float mask = smoothstep(1.0, 0.55, r) * mix(0.55, 1.0, smoothstep(0.1, 0.45, r)) * fade;
	float t = TIME;
	vec2 wobble = vec2(
		sin(UV.y * 41.0 + t * 6.3) + sin(UV.y * 23.0 + UV.x * 9.0 - t * 4.1),
		sin(UV.x * 37.0 + t * 5.2) + sin(UV.x * 17.0 + UV.y * 13.0 + t * 3.6) + 0.6 * sin(UV.y * 9.0 - t * 2.0)
	) * 0.5;
	ALBEDO = texture(screen_tex, SCREEN_UV + wobble * strength * mask).rgb;
	ALPHA = smoothstep(0.0, 0.08, mask);
}
