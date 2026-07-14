shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// The island, SEEN. Bold shapes, hard value steps, a small curated palette.
// Not a photograph and not trying to be — the spirit sees, but what it sees is
// still a percept. Banding the light into a few steps is what keeps it graphic.

uniform vec3 rock_lit : source_color = vec3(0.72, 0.70, 0.66);
uniform vec3 rock_shade : source_color = vec3(0.24, 0.26, 0.34);
uniform vec3 grass_lit : source_color = vec3(0.44, 0.56, 0.38);
uniform vec3 grass_shade : source_color = vec3(0.17, 0.28, 0.30);
uniform vec3 rim_col : source_color = vec3(0.95, 0.80, 0.58);
uniform float steps = 3.0;

varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Grass takes the flat tops; rock takes anything that leans.
	float up = clamp(world_normal.y, 0.0, 1.0);
	float grass = smoothstep(0.55, 0.82, up);
	ALBEDO = mix(rock_lit, grass_lit, grass);
	NORMAL = normalize(NORMAL);
	ROUGHNESS = 1.0;
}

void light() {
	float d = dot(normalize(NORMAL), normalize(LIGHT));
	// Quantised light. This single line is most of the "graphic" in the look.
	float band = floor(clamp(d, 0.0, 1.0) * steps + 0.5) / steps;
	float up = clamp(world_normal.y, 0.0, 1.0);
	float grass = smoothstep(0.55, 0.82, up);
	vec3 lit = mix(rock_lit, grass_lit, grass);
	vec3 shade = mix(rock_shade, grass_shade, grass);
	DIFFUSE_LIGHT += mix(shade, lit, band) * LIGHT_COLOR * ATTENUATION * 0.75;
}
