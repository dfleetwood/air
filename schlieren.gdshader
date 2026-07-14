shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

// SCHLIEREN — the wind, made visible by what it BENDS.
//
// This is not a metaphor. Density gradients in air really do refract light, and
// imaging those gradients is literally how a fluid dynamicist photographs air
// that is otherwise invisible. So: no lines, no arrows, no particles. The air
// deforms the world behind it, and you read the shape of the air from the shape
// of the deformation.
//
//   calm air            -> almost nothing. As it should be.
//   a gust front        -> a soft ripple travelling downwind through the world.
//   turbulence / a wake -> an unstable shimmering pocket.
//   an updraft          -> the distortion STRETCHES upward, and the world with it.
//   a downdraft         -> it sags and compresses.
//
// The distortion is driven by the same wind field the bird flies through, so what
// you see bending is what will actually push you. (Fourth twin of the field —
// island_field.gd is the authority.)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 islands[5];
uniform float island_r[5];
uniform vec4 thermals[5];
uniform vec4 thermal_p[5];
uniform vec3 prevailing;
uniform float strength = 0.020;
uniform float far_ramp = 90.0;   // more air between you and it = more bending

const float SQUASH_UP = 0.32;
const float SQUASH_DOWN = 1.35;
const float BOUNDARY = 9.0;
const float INFLOW_REACH = 4.0;

// No sin() — this runs per pixel, and a transcendental per noise tap is real money.
float hash11(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
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

// Curl of a noise field: divergence-free by construction, so it cannot push air
// into or out of nothing. It has no choice but to swirl. This is what makes the
// shimmer read as a fluid instead of as static.
vec3 curl(vec3 p) {
	float e = 0.7;
	float a = vnoise(p + vec3(0.0, e, 0.0)) - vnoise(p - vec3(0.0, e, 0.0));
	float b = vnoise(p + vec3(0.0, 0.0, e)) - vnoise(p - vec3(0.0, 0.0, e));
	float c = vnoise(p + vec3(e, 0.0, 0.0)) - vnoise(p - vec3(e, 0.0, 0.0));
	return vec3(a - b, b - c, c - a) / (2.0 * e);
}

// Distance and normal in one pass. The islands are squashed spheres, so the
// normal is analytic — the finite-difference gradient this replaces cost thirty
// island tests per pixel, for exactly the same answer.
vec4 scene_nearest(vec3 p) {
	float best = 1e9;
	vec3 n = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < 5; i++) {
		vec3 q = p - islands[i];
		float s = (q.y > 0.0) ? SQUASH_UP : SQUASH_DOWN;
		q.y /= s;
		float len = max(length(q), 0.001);
		float d = (len - island_r[i]) * SQUASH_UP;
		if (d < best) {
			best = d;
			n = normalize(vec3(q.x, q.y / s, q.z) / len);
		}
	}
	return vec4(n, best);
}

float thermal_lift(vec3 p) {
	float lift = 0.0;
	for (int i = 0; i < 5; i++) {
		vec3 c = thermals[i].xyz;
		float r = thermals[i].w;
		float base = thermal_p[i].x;
		float top = thermal_p[i].y;
		if (p.y < base || p.y > top) { continue; }
		float dxz = length(p.xz - c.xz);
		float outer = r * INFLOW_REACH;
		if (dxz >= outer) { continue; }
		float h = clamp((p.y - base) / max(top - base, 1.0), 0.0, 1.0);
		float fade = smoothstep(1.0, 0.65, h);
		if (dxz < r) {
			float core = 1.0 - dxz / r;
			lift = max(lift, thermal_p[i].z * core * core * fade);
		} else {
			float f = 1.0 - (dxz - r) / (outer - r);
			lift = max(lift, thermal_p[i].z * 0.28 * f * f * fade);
		}
	}
	return lift;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);   // fullscreen, whatever the mesh was
}

void fragment() {
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float dist = -view.z;

	// Sky (no depth) still has air in front of it — and a lot of it.
	if (raw <= 0.0) { dist = far_ramp * 1.4; }

	// Sample the air roughly halfway to whatever we are looking at. Crude, but
	// heat haze has never needed to know exactly where it is.
	float samp = clamp(dist * 0.5, 2.0, far_ramp);
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz * (samp / max(dist, 0.001)), 1.0)).xyz;

	float speed = length(prevailing);
	vec3 dir = (speed > 0.001) ? prevailing / speed : vec3(1.0, 0.0, 0.0);

	vec4 near = scene_nearest(world);
	vec3 n = near.xyz;
	float d = near.w;
	float near_rock = 1.0 - smoothstep(0.0, BOUNDARY * 2.2, max(d, 0.0));
	float lee = max(dot(dir, n), 0.0) * near_rock;          // the wake: unstable
	float lift = thermal_lift(world);

	// A GUST FRONT: a plane of compression travelling downwind through the air.
	// You see it coming across the world before it reaches you and shoves you.
	float front = sin(dot(world, dir) * 0.055 - TIME * 1.35);
	float gust = smoothstep(0.55, 1.0, front) * speed * 0.09;

	// How troubled the air is here, in total.
	float shimmer = gust
		+ lee * 0.85
		+ smoothstep(0.8, 5.0, lift) * 0.55
		+ speed * 0.012;                                     // calm air: almost nothing

	// The direction of the bending follows the eddies themselves. One octave —
	// the second one cost as much as everything else here and you could not see it.
	vec3 eddy = curl(world * 0.06 + vec3(0.0, TIME * 0.35, 0.0));

	// Rising air stretches the distortion UPWARD, sinking air drags it down. The
	// world does not merely wobble — it is pulled the way the air is going.
	float vertical = smoothstep(0.5, 5.0, lift) - smoothstep(-0.5, -4.0, -lift * 0.0);
	eddy.y += vertical * 1.6;

	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec2 offset = vec2(dot(eddy, right), dot(eddy, up));
	offset.y *= 1.0 + vertical * 0.8;   // stretched, not just displaced

	// More air between you and a thing = more bending of it. Your own wingtip
	// does not shimmer; a far ridge seen through a wake does.
	float depth_gain = clamp(dist / far_ramp, 0.0, 1.0);

	vec2 uv = SCREEN_UV + offset * shimmer * depth_gain * strength;
	uv = clamp(uv, vec2(0.001), vec2(0.999));

	// DEPTH GUARD. Naive screen-space refraction happily drags a near silhouette
	// out over the sky behind it, which reads as the island's edge dissolving —
	// wrong, and ugly. Air can only bend what is BEHIND it, so if the pixel we
	// would pull in is nearer than this one, refuse the bend and stay put.
	float raw2 = texture(depth_tex, uv).r;
	vec4 v2 = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, raw2, 1.0);
	float dist2 = -(v2.z / v2.w);
	if (raw2 <= 0.0) { dist2 = far_ramp * 1.4; }
	float ok = step(dist * 0.985, dist2);
	uv = mix(SCREEN_UV, uv, ok);

	ALBEDO = texture(screen_tex, uv).rgb;
	ALPHA = 1.0;
}
