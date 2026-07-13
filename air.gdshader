shader_type particles;

// THE AIR PERCEPT.
//
// Every particle is a tracer in the medium — not a decoration drawn over a
// scene, but the only thing there is. It is advected by the same wind field the
// bird flies through (see island_field.gd; this is its GLSL twin).
//
// What the player is reading, and how it gets encoded:
//
//   coherent warm rising column  -> a thermal. Ride it.
//   coherent rising sheet        -> ridge lift on a windward face.
//   still, crowded, dim air      -> a surface is near. This is the ground.
//   churn                        -> a wake. Something solid is upwind of you.
//   nothing at all               -> rock. Air cannot be there.
//   slow laminar drift           -> open sky.
//
// Note that the ground is not drawn: stagnant air simply accumulates tracers,
// because they stop moving. The floor is emergent.

uniform vec3 islands[5];
uniform float island_r[5];
uniform vec4 thermals[5];     // xyz = axis position, w = radius
uniform vec4 thermal_p[5];    // x = base y, y = top y, z = power
uniform vec3 prevailing;      // wind direction * strength
uniform vec3 observer;        // the bird
uniform vec3 carrier;         // the bird's own velocity — see below
uniform float spawn_extent = 26.0;
uniform float reach = 38.0;   // you feel the air at your body, and not a mile off

const float SQUASH_UP = 0.32;
const float SQUASH_DOWN = 1.35;
const float BOUNDARY = 9.0;
const float RIDGE_GAIN = 1.5;
const float TURB_GAIN = 0.9;

float hash11(float n) {
	return fract(sin(n) * 43758.5453123);
}

vec3 hash31(float n) {
	return vec3(hash11(n), hash11(n + 17.13), hash11(n + 43.77));
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

// Divergence-free-ish churn. Real wakes swirl; they do not jitter.
vec3 curl(vec3 p) {
	float e = 0.6;
	float x1 = vnoise(p + vec3(0.0, e, 0.0)) - vnoise(p - vec3(0.0, e, 0.0));
	float x2 = vnoise(p + vec3(0.0, 0.0, e)) - vnoise(p - vec3(0.0, 0.0, e));
	float y1 = vnoise(p + vec3(0.0, 0.0, e)) - vnoise(p - vec3(0.0, 0.0, e));
	float y2 = vnoise(p + vec3(e, 0.0, 0.0)) - vnoise(p - vec3(e, 0.0, 0.0));
	float z1 = vnoise(p + vec3(e, 0.0, 0.0)) - vnoise(p - vec3(e, 0.0, 0.0));
	float z2 = vnoise(p + vec3(0.0, e, 0.0)) - vnoise(p - vec3(0.0, e, 0.0));
	return vec3(x1 - x2, y1 - y2, z1 - z2) / (2.0 * e);
}

// Real air is never laminar. Eddies live inside eddies, all the way down, and it
// is that nesting — not the mean flow — that makes a fluid look like a fluid.
vec3 eddies(vec3 p, float t) {
	vec3 q = p + vec3(0.0, t * 0.6, 0.0);
	return curl(q * 0.045) * 1.00
		+ curl(q * 0.115 + 31.7) * 0.45
		+ curl(q * 0.290 + 77.1) * 0.18;
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
	float e = 0.6;
	vec3 g = vec3(
		scene_sdf(p + vec3(e, 0, 0)) - scene_sdf(p - vec3(e, 0, 0)),
		scene_sdf(p + vec3(0, e, 0)) - scene_sdf(p - vec3(0, e, 0)),
		scene_sdf(p + vec3(0, 0, e)) - scene_sdf(p - vec3(0, 0, e)));
	return (length(g) > 1e-5) ? normalize(g) : vec3(0.0, 1.0, 0.0);
}

// A thermal is not only its column. It DRAWS AIR IN around its base — so the air
// at your body, eighty metres out, is already leaning toward it. That inflow is
// the whole reason a thermal can be found without being seen: you do not spot the
// column, you notice the medium tilting, and you follow it upstream.
const float INFLOW_REACH = 4.0;   // multiples of the core radius

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
			float core = 1.0 - dxz / r;
			v.y += power * core * core * fade;
		} else {
			float f = 1.0 - (dxz - r) / (outer - r);
			f = f * f;
			vec2 toward = -off / max(dxz, 0.001);
			v.xz += toward * power * 0.40 * f * fade;
			v.y += power * 0.28 * f * fade;
		}
	}
	return v;
}

// out params carry what the air is DOING, so the draw can speak it.
vec3 wind_at(vec3 p, float t, out float warmth, out float churn, out float surf) {
	warmth = 0.0;
	churn = 0.0;
	float d = scene_sdf(p);
	surf = 1.0 - smoothstep(0.0, BOUNDARY, d);   // 1 against the rock
	if (d < 0.0) {
		return vec3(0.0);
	}
	vec3 n = scene_grad(p);
	float bl = 1.0 - surf;
	float near = surf;

	vec3 v = prevailing;
	float speed = length(prevailing);
	v -= n * dot(v, n) * near;

	if (speed > 0.001) {
		vec3 dir = prevailing / speed;
		float windward = max(dot(dir, -n), 0.0);
		float lift = windward * speed * RIDGE_GAIN * near;
		v += vec3(0.0, 1.0, 0.0) * lift;
		warmth += lift;

		// Open air is never still: it always carries eddies, and they are what
		// makes it read as a fluid rather than as a diagram of one.
		vec3 e = eddies(p, t);
		v += e * speed * 0.30;

		// The wake: air that has just let go of a surface tumbles hard.
		float lee = max(dot(dir, n), 0.0) * near;
		v += e * lee * speed * TURB_GAIN * 2.2;
		churn = lee + clamp(length(e) * 0.35, 0.0, 0.35);
	}

	vec3 th = thermal_vel(p);
	v += th;
	warmth += max(th.y, 0.0);

	v *= mix(0.06, 1.0, bl);   // the air stops dead at the rock
	return v;
}

void start() {
	float s = float(INDEX) + TIME * 61.7;
	vec3 r = hash31(s) * 2.0 - 1.0;
	// Scatter through the volume around the bird. As it moves, the medium is
	// continually re-seeded around it: the world assembles around you.
	vec3 p = observer + r * spawn_extent;
	TRANSFORM[3].xyz = p;
	VELOCITY = vec3(0.0);
	CUSTOM = vec4(0.0);
	COLOR = vec4(0.0);
	ACTIVE = true;
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	float warmth;
	float churn;
	float surf;
	vec3 v = wind_at(p, TIME, warmth, churn, surf);

	// EGO-MOTION CANCELLATION. The tracers are carried along at the bird's own
	// velocity, so what streams past you is the air's OWN motion and not your
	// speed through it. This is a wind tunnel: the body holds still, the fluid
	// moves. It is also the honest percept — a wing subtracts its own airspeed,
	// exactly as vision subtracts your gait. You do not perceive the rush. You
	// perceive the wind.
	//
	// It buys the ground for free, too: air that has gone still against rock now
	// APPEARS still, while everything else streams. The floor is where the world
	// stops moving.
	VELOCITY = v + carrier;

	float inside = step(scene_sdf(p), 0.0);       // 1 where there is rock
	float speed = length(v);
	float rise = clamp(v.y / 5.0, -1.0, 1.0);

	// PROXIMITY. You feel the air at your body, and nothing of the air a mile off.
	// You do not need to: a thermal reaches out through the medium and tilts the
	// air you are already in, and the rock stills the air you are already in. The
	// far world arrives locally, or not at all.
	float dist = length(p - observer);
	float presence = 1.0 - smoothstep(reach * 0.45, reach, dist);

	// Still air crowds. It is not emptiness — it is the floor.
	float stillness = 1.0 - smoothstep(0.0, 2.0, speed);

	vec3 calm = vec3(0.40, 0.49, 0.60);      // the drift: cool, quiet
	vec3 warm = vec3(1.00, 0.70, 0.34);      // rising air is warm. That is WHY it rises.
	vec3 cold = vec3(0.22, 0.32, 0.50);      // sink
	vec3 skin = vec3(0.62, 0.66, 0.70);      // the hush against rock
	vec3 c = calm;
	c = mix(c, warm, smoothstep(0.06, 0.65, rise));
	c = mix(c, cold, smoothstep(-0.06, -0.6, rise));
	c = mix(c, vec3(0.58, 0.56, 0.56), churn * 0.6);   // churn desaturates
	c = mix(c, skin, surf * 0.7);

	// A filament is a single legible line, so it can afford to be seen — but only
	// just. The quiet drift is a whisper; lift, churn and the hush against rock
	// are what speak up.
	float a = 0.045
		+ 0.26 * smoothstep(0.08, 0.7, abs(rise))
		+ 0.10 * churn
		+ 0.18 * surf * stillness;
	a *= presence;
	a *= (1.0 - inside);   // rock is a silence in the medium

	COLOR = vec4(c, a);

	// Scale is the filament's thickness. Fast air draws out into thin taut lines;
	// still air thickens and clots into the hush that means "a surface is here."
	float sz = mix(1.5, 0.7, clamp(speed / 14.0, 0.0, 1.0));
	sz *= mix(1.0, 2.0, surf * stillness);
	TRANSFORM[0].xyz = vec3(sz, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, sz, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, sz);
}
