shader_type fog;

// THE AIR, AS DYE.
//
// Lines were the wrong primitive. Fluid does not look like hair — it looks like
// SMOKE, and smoke is a density, not a curve. So here the air carries dye, and
// what you perceive is how much dye is in front of you and what it is doing.
// Godot's volumetric fog raymarches it; we only have to say how thick the air is
// at a point, and what colour.
//
//   luminous warm column climbing   -> a thermal.
//   bright sheet peeling off a face -> ridge lift.
//   thick, motionless, pale haze    -> a surface. That is the ground.
//   torn, churning murk             -> a wake. Rock is upwind of you.
//   a clean hole in the smoke       -> rock. Air cannot be there.
//
// (Third twin of the field — see island_field.gd and air.gdshader. Keep in step.)

uniform vec3 islands[5];
uniform float island_r[5];
uniform vec4 thermals[5];     // xyz = axis, w = radius
uniform vec4 thermal_p[5];    // x = base, y = top, z = power
uniform vec3 prevailing;
uniform float haze = 0.16;

const float SQUASH_UP = 0.32;
const float SQUASH_DOWN = 1.35;
const float BOUNDARY = 9.0;
const float INFLOW_REACH = 4.0;

float hash11(float n) {
	return fract(sin(n) * 43758.5453123);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = i.x + i.y * 57.0 + i.z * 113.0;
	return mix(
		mix(mix(hash11(n), hash11(n + 1.0), f.x),
			mix(hash11(n + 57.0), hash11(n + 58.0), f.x), f.y),
		mix(mix(hash11(n + 113.0), hash11(n + 114.0), f.x),
			mix(hash11(n + 170.0), hash11(n + 171.0), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	return 0.55 * vnoise(p)
		+ 0.26 * vnoise(p * 2.03 + 17.3)
		+ 0.13 * vnoise(p * 4.11 + 41.9)
		+ 0.06 * vnoise(p * 8.07 + 73.1);
}

float scene_sdf(vec3 p) {
	float d = 1e9;
	for (int i = 0; i < 5; i++) {
		vec3 q = p - islands[i];
		q.y /= (q.y > 0.0) ? SQUASH_UP : SQUASH_DOWN;
		d = min(d, (length(q) - island_r[i]) * SQUASH_UP);
	}
	return d;
}

vec3 scene_grad(vec3 p) {
	float e = 0.8;
	vec3 g = vec3(
		scene_sdf(p + vec3(e, 0, 0)) - scene_sdf(p - vec3(e, 0, 0)),
		scene_sdf(p + vec3(0, e, 0)) - scene_sdf(p - vec3(0, e, 0)),
		scene_sdf(p + vec3(0, 0, e)) - scene_sdf(p - vec3(0, 0, e)));
	return (length(g) > 1e-5) ? normalize(g) : vec3(0.0, 1.0, 0.0);
}

vec3 thermal_vel(vec3 p) {
	vec3 v = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		vec3 c = thermals[i].xyz;
		float r = thermals[i].w;
		float base = thermal_p[i].x;
		float top = thermal_p[i].y;
		float power = thermal_p[i].z;
		if (p.y < base || p.y > top) {
			continue;
		}
		vec2 off = p.xz - c.xz;
		float dxz = length(off);
		float outer = r * INFLOW_REACH;
		if (dxz >= outer) {
			continue;
		}
		float h = clamp((p.y - base) / max(top - base, 1.0), 0.0, 1.0);
		float fade = smoothstep(1.0, 0.65, h);
		if (dxz < r) {
			v.y += power * (1.0 - dxz / r) * (1.0 - dxz / r) * fade;
		} else {
			float f = 1.0 - (dxz - r) / (outer - r);
			f *= f;
			v.xz += (-off / max(dxz, 0.001)) * power * 0.40 * f * fade;
			v.y += power * 0.28 * f * fade;
		}
	}
	return v;
}

void fog() {
	vec3 p = WORLD_POSITION;
	float d = scene_sdf(p);

	// Rock is a clean hole in the smoke. Air cannot be there, so no dye is.
	if (d < 0.0) {
		DENSITY = 0.0;
		return;
	}

	vec3 n = scene_grad(p);
	float surf = 1.0 - smoothstep(0.0, BOUNDARY, d);   // 1 against the rock
	vec3 th = thermal_vel(p);
	vec3 flow = prevailing;
	float speed = length(prevailing);

	float lee = 0.0;
	float lift = th.y;
	if (speed > 0.001) {
		vec3 dir = prevailing / speed;
		lift += max(dot(dir, -n), 0.0) * speed * 1.5 * surf;   // ridge lift
		lee = max(dot(dir, n), 0.0) * surf;                    // wake
	}
	flow += th;

	// ADVECTED DYE. Back-trace the sample point along the flow and read the dye
	// there: the smoke stretches, shears and wraps along the streamlines instead
	// of just sitting in space. This is the cheap stand-in for a solver, and at
	// these scales the eye cannot tell the difference.
	vec3 warped = p - flow * TIME * 0.55;
	float dye = fbm(warped * 0.030);
	dye = dye * dye * 1.5;

	// Torn and shredded in a wake; smooth in clean air.
	float torn = fbm(warped * 0.11 + TIME * 0.25) * lee;

	float rising = smoothstep(0.6, 4.5, lift);

	// Thick where it MEANS something: in lift, in a wake, and in the dead still
	// air that clings to rock — which is the only reason the ground is visible.
	float dens = haze * (0.55 + dye)
		+ 1.40 * rising * (0.5 + dye)
		+ 0.90 * torn
		+ 1.80 * surf * surf * (0.6 + 0.4 * dye);

	DENSITY = dens;

	vec3 cool = vec3(0.34, 0.45, 0.62);
	vec3 warm = vec3(1.00, 0.66, 0.32);
	vec3 hush = vec3(0.60, 0.63, 0.68);
	vec3 col = mix(cool, hush, surf * 0.8);
	col = mix(col, warm, rising * 0.85);

	ALBEDO = col;
	// The air is self-luminous. There is no sun here — no sun is PERCEIVED here —
	// so the medium has to carry its own light, and what it lights up is what it
	// is doing. Lift glows warm, because it IS warm; that is why it is rising.
	EMISSION = warm * rising * 2.6
		+ hush * surf * surf * 0.55
		+ cool * (0.10 + 0.25 * torn);
}
