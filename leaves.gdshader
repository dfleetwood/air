shader_type spatial;

#include "res://season.gdshaderinc"

global uniform float season;
global uniform float wind_strength;
global uniform vec3 wind_dir;

uniform float sway_amount = 0.12;

void vertex() {
	float phase = NODE_POSITION_WORLD.x * 0.9 + NODE_POSITION_WORLD.z * 1.3;
	float sway = sin(TIME * 1.8 + phase) * 0.6 + sin(TIME * 3.1 + phase * 1.7) * 0.4;
	vec3 local_wind = transpose(mat3(MODEL_MATRIX)) * wind_dir;
	VERTEX += local_wind * sway * wind_strength * sway_amount;
}

void fragment() {
	vec3 n_world = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
	float up = clamp(n_world.y, 0.0, 1.0);
	vec3 leaf = season_grass(season) * vec3(0.9, 1.05, 0.9);
	float snow = winterness(season) * smoothstep(0.25, 0.8, up);
	ALBEDO = mix(leaf, vec3(0.94, 0.96, 1.0), snow);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
