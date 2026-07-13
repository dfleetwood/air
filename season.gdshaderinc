// Shared season helpers. `season` is a global uniform in [0, 4):
// 0 = spring, 1 = summer, 2 = autumn, 3 = winter (wraps back to spring).

const vec3 SEASON_COLS[4] = {
	vec3(0.45, 0.72, 0.35), // spring
	vec3(0.20, 0.52, 0.24), // summer
	vec3(0.78, 0.44, 0.15), // autumn
	vec3(0.86, 0.88, 0.92)  // winter
};

vec3 season_grass(float s) {
	s = mod(s, 4.0);
	int i = int(floor(s));
	int j = (i + 1) % 4;
	float f = smoothstep(0.0, 1.0, fract(s));
	return mix(SEASON_COLS[i], SEASON_COLS[j], f);
}

float winterness(float s) {
	s = mod(s, 4.0);
	float d = min(abs(s - 3.0), s + 1.0); // wrap: distance 3 -> 4/0
	return clamp(1.0 - d, 0.0, 1.0);
}
