shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, particle_trails;

// Each filament is a STREAKLINE — the path a parcel of air actually took. This
// is not a line drawn over the wind; it is the wind, drawn by itself. Release
// smoke into moving air and this is precisely what you get.

void vertex() {
	// UV.y runs along the filament. Taper it to a point at the tail so the line
	// has a direction: it is going somewhere, and you can see which way.
	COLOR.a *= smoothstep(0.0, 0.35, UV.y);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
