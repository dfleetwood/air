shader_type spatial;

#include "res://season.gdshaderinc"

global uniform float season;

uniform vec3 rock_color : source_color = vec3(0.44, 0.40, 0.38);
uniform vec3 cliff_color : source_color = vec3(0.30, 0.27, 0.29);

void fragment() {
	vec3 n_world = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
	float up = clamp(n_world.y, 0.0, 1.0);
	vec3 grass = season_grass(season);
	// COLOR.g is the grass mask painted into vertex colors at build time.
	vec3 base = mix(cliff_color, rock_color, up);
	base = mix(base, grass, COLOR.g * smoothstep(0.5, 0.75, up));
	float snow = winterness(season) * smoothstep(0.45, 0.8, up);
	ALBEDO = mix(base, vec3(0.93, 0.95, 1.0), snow);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
