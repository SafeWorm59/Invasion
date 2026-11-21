class_name PharynxShape
extends RefCounted

## Single source of truth for the pharynx lumen silhouette.
##
## Every visual layer and both physics bodies sample these functions, so the
## drawn tissue and the physical boundary can never drift apart.
##
## One continuous vertical passage (+y is down, so the top of the screen is the
## nasopharynx):
##   Nasopharynx    TOP     .. NASO_END  narrow vault
##   Oropharynx     NASO_END.. ORO_END   broadest chamber
##   Laryngopharynx ORO_END .. BOTTOM    funnel to the esophageal opening

const TOP := -4000.0
const NASO_END := -2400.0
const ORO_END := 800.0
const BOTTOM := 4000.0

## The viewport is 1280x720, so the horizontal window is exactly 1280 wide:
## the camera pans vertically only and never shows the edge of the world.
const VIEW_LEFT := -640.0
const VIEW_RIGHT := 640.0
const VIEW_TOP := -4800.0
const VIEW_BOTTOM := 4800.0

## Half-width control points as flat [y, half_width] pairs. Interpolated with a
## smoothstep spline, which keeps the silhouette smooth through every knot and
## produces the organic, non-repetitive contour.
const PROFILE := [
	-4000.0, 80.0,
	-3600.0, 90.0,
	-3200.0, 110.0,
	-2800.0, 130.0,
	-2500.0, 140.0,
	-2300.0, 150.0,
	-2100.0, 150.0,
	-1900.0, 160.0,
	-1700.0, 180.0,
	-1500.0, 220.0,
	-1300.0, 280.0,
	-1100.0, 340.0,
	-900.0, 420.0,
	-700.0, 520.0,
	-500.0, 620.0,
	-300.0, 720.0,
	-100.0, 820.0,
	0.0, 960.0,
	100.0, 820.0,
	200.0, 620.0,
	400.0, 420.0,
	600.0, 340.0,
	800.0, 280.0,
	1000.0, 220.0,
	1200.0, 180.0,
	1400.0, 120.0,
	1600.0, 80.0,
	1800.0, 50.0,
	2000.0, 30.0,
	2500.0, 20.0,
	3000.0, 15.0,
	3500.0, 10.0,
	4000.0, 8.0,
]

const REGION_NAMES := ["Nasopharynx", "Oropharynx", "Laryngopharynx"]


## Half width of the lumen at the given y.
static func half_width(y: float) -> float:
	var count: int = PROFILE.size() / 2
	var y_first: float = PROFILE[0]
	var y_last: float = PROFILE[(count - 1) * 2]

	if y <= y_first:
		return PROFILE[1]
	if y >= y_last:
		return PROFILE[(count - 1) * 2 + 1]

	for i in range(count - 1):
		var y0: float = PROFILE[i * 2]
		var y1: float = PROFILE[(i + 1) * 2]
		if y <= y1:
			var t: float = (y - y0) / (y1 - y0)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(PROFILE[i * 2 + 1], PROFILE[(i + 1) * 2 + 1], t)

	return PROFILE[(count - 1) * 2 + 1]


## Gentle lateral meander of the passage centre line. Keeps the tube organic
## without ever making it hard to traverse.
static func center_x(y: float) -> float:
	var t: float = clampf((y - TOP) / (BOTTOM - TOP), 0.0, 1.0)
	return 15.0 * sin(t * TAU * 1.05 - 0.62) + 7.0 * sin(t * TAU * 2.35 + 1.9)


## A point inside the lumen: side is -1 (left wall) .. +1 (right wall).
static func lumen_point(y: float, side: float) -> Vector2:
	return Vector2(center_x(y) + side * half_width(y), y)


## Region index for a world y.
static func region_of(y: float) -> int:
	if y > ORO_END:
		return 2
	if y > NASO_END:
		return 1
	return 0


## Vertical span [top, bottom] of a region index.
static func region_bounds(region: int) -> Vector2:
	if region <= 0:
		return Vector2(TOP, NASO_END)
	if region == 1:
		return Vector2(NASO_END, ORO_END)
	return Vector2(ORO_END, BOTTOM)


## Closed silhouette of the lumen. `expand` grows (or shrinks, when negative)
## the contour along its own width, which is how the wall rings and the
## collision shells are derived from the very same curve.
static func outline(segments: int = 140, expand: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps: int = maxi(segments, 24)

	for i in range(steps + 1):
		var y: float = lerpf(TOP, BOTTOM, float(i) / float(steps))
		pts.append(Vector2(center_x(y) + half_width(y) + expand, y))

	# Rounded funnel at the bottom of the laryngopharynx.
	var cb: float = center_x(BOTTOM)
	var hb: float = half_width(BOTTOM) + expand
	var db: float = hb * 0.86
	for i in range(1, 25):
		var a: float = PI * float(i) / 24.0
		pts.append(Vector2(cb + cos(a) * hb, BOTTOM + sin(a) * db))

	for i in range(steps, -1, -1):
		var y: float = lerpf(TOP, BOTTOM, float(i) / float(steps))
		pts.append(Vector2(center_x(y) - half_width(y) - expand, y))

	# Rounded vault above the nasopharynx.
	var ct: float = center_x(TOP)
	var ht: float = half_width(TOP) + expand
	var dt: float = ht * 0.98
	for i in range(1, 25):
		var a: float = PI - PI * float(i) / 24.0
		pts.append(Vector2(ct + cos(a) * ht, TOP - sin(a) * dt))

	return pts


## Builds a tapered ribbon polygon around a centre line. Used for mucosal
## ridges, pillars and folds so they fade into the surrounding tissue instead
## of ending in a hard cap.
static func ribbon(path: PackedVector2Array, half_widths: PackedFloat32Array) -> PackedVector2Array:
	var n: int = path.size()
	var out := PackedVector2Array()
	if n < 2:
		return out

	var left := PackedVector2Array()
	var right := PackedVector2Array()

	for i in range(n):
		var prev: Vector2 = path[maxi(i - 1, 0)]
		var next: Vector2 = path[mini(i + 1, n - 1)]
		var tangent: Vector2 = next - prev
		if tangent.length() < 0.0001:
			tangent = Vector2.RIGHT
		tangent = tangent.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var h: float = half_widths[i]
		left.append(path[i] + normal * h)
		right.append(path[i] - normal * h)

	out.append_array(left)
	for i in range(n - 1, -1, -1):
		out.append(right[i])

	return out
