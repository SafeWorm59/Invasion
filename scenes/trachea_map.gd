@tool
extends RefCounted

## Single source of truth for Level 4 (Trachea).
##
## Same geometry model as the pharynx and larynx maps: one continuous organ
## built from a union of anatomical chambers (ellipses) and passages (capsules).
## The tissue shader, the cartilage-ring relief, the collision shell, the spawn
## point, the camera limits and the minimap outline all read this file, so the
## visible lumen and the physical lumen cannot drift apart.
##
## Layout, top to bottom: upper trachea -> mid trachea -> lower trachea ->
## carina (the ridge where the windpipe splits) -> left and right main bronchi.
##
## The 12 tube segments overlap heavily, so their union is one smooth airway
## with a gentle per-ring waist. Each waist/bulge carries a hyaline cartilage
## ring (see `ring_*`), and the +x side of the lumen is the posterior
## membranous wall (no cartilage, trachealis muscle) - see `posterior_*`.

const PLAYER_SPEED := 200.0

## [name, center_x, center_y, radius_x, radius_y, region]
## region: 0 = Upper trachea, 1 = Mid trachea, 2 = Lower trachea, 3 = Carina,
## 4 = Distal bronchioles
const CHAMBERS := [
	## Upper trachea.
	["TracheaRing01", 0.0, -3300.0, 350.0, 430.0, 0],
	["TracheaRing02", 0.0, -2800.0, 355.0, 430.0, 0],
	["TracheaRing03", 22.0, -2300.0, 350.0, 430.0, 0],
	["TracheaRing04", 30.0, -1800.0, 345.0, 430.0, 0],

	## Mid trachea.
	["TracheaRing05", 8.0, -1300.0, 350.0, 430.0, 1],
	["TracheaRing06", -22.0, -800.0, 355.0, 430.0, 1],
	["TracheaRing07", -30.0, -300.0, 350.0, 430.0, 1],
	["TracheaRing08", -6.0, 200.0, 355.0, 430.0, 1],

	## Lower trachea.
	["TracheaRing09", 18.0, 700.0, 350.0, 430.0, 2],
	["TracheaRing10", 28.0, 1200.0, 360.0, 435.0, 2],
	["TracheaRing11", 12.0, 1700.0, 372.0, 440.0, 2],
	["TracheaRing12", 0.0, 2200.0, 392.0, 450.0, 2],

	## Bifurcation.
	["Carina", 0.0, 2680.0, 520.0, 340.0, 3],
	["LeftMainBronchus", -420.0, 3120.0, 270.0, 300.0, 3],
	["RightMainBronchus", 420.0, 3120.0, 270.0, 300.0, 3],

	## Distal side chambers branching from the extended main bronchi.
	["LeftBronchiolePocketA", -760.0, 3500.0, 175.0, 150.0, 4],
	["LeftBronchiolePocketB", -1040.0, 3740.0, 165.0, 145.0, 4],
	["RightBronchiolePocketA", 760.0, 3500.0, 175.0, 150.0, 4],
	["RightBronchiolePocketB", 1040.0, 3740.0, 165.0, 145.0, 4],
]

## [start_x, start_y, end_x, end_y, half_width, region]
const CORRIDORS := [
	## The two main bronchi open out of the carina and continue into the lungs.
	[0.0, 2380.0, -540.0, 3420.0, 240.0, 3],
	[0.0, 2380.0, 540.0, 3420.0, 240.0, 3],
	## Two connected distal pockets branch from each extended main bronchus.
	[-540.0, 3420.0, -760.0, 3500.0, 130.0, 4],
	[-760.0, 3500.0, -1040.0, 3740.0, 120.0, 4],
	[540.0, 3420.0, 760.0, 3500.0, 130.0, 4],
	[760.0, 3500.0, 1040.0, 3740.0, 120.0, 4],
]

## Main route: straight down the tracheal lumen into the carina, with a gentle
## side-to-side meander so the windpipe does not read as a rectangular corridor.
const ROUTE := [
	Vector2(0.0, -3350.0),
	Vector2(0.0, -3050.0),
	Vector2(30.0, -2800.0),
	Vector2(-30.0, -2500.0),
	Vector2(35.0, -2050.0),
	Vector2(-25.0, -1550.0),
	Vector2(30.0, -1050.0),
	Vector2(-30.0, -550.0),
	Vector2(30.0, -50.0),
	Vector2(-25.0, 450.0),
	Vector2(30.0, 950.0),
	Vector2(-20.0, 1450.0),
	Vector2(20.0, 1950.0),
	Vector2(0.0, 2400.0),
	Vector2(0.0, 2680.0),
	Vector2(0.0, 2900.0),
]

const REGION_NAMES := ["Upper trachea", "Mid trachea", "Lower trachea", "Carina", "Distal bronchioles"]

## The posterior membranous wall occupies this fraction of the lumen width on
## the +x side. The C-shaped cartilage rings stop here and leave the gap that
## the trachealis muscle bridges.
const POSTERIOR_INNER := 0.56
const POSTERIOR_OUTER := 0.96

const RING_COUNT := 12
const RING_THICKNESS := 17.0
const RING_BOW := 15.0

const TOP := -3760.0
const BOTTOM := 3450.0

static var _bounds := Rect2()
static var _wall_segments := PackedVector2Array()
static var _boundary_samples := PackedVector2Array()


# --------------------------------------------------------------------------
# Chamber / corridor accessors
# --------------------------------------------------------------------------

static func chamber_count() -> int:
	return CHAMBERS.size()


static func chamber_name(i: int) -> String:
	return str(CHAMBERS[i][0])


static func chamber_center(i: int) -> Vector2:
	var c: Array = CHAMBERS[i]
	return Vector2(float(c[1]), float(c[2]))


static func chamber_radii(i: int) -> Vector2:
	var c: Array = CHAMBERS[i]
	return Vector2(float(c[3]), float(c[4]))


static func chamber_region(i: int) -> int:
	return int(CHAMBERS[i][5])


static func corridor_count() -> int:
	return CORRIDORS.size()


static func corridor_a(i: int) -> Vector2:
	var c: Array = CORRIDORS[i]
	return Vector2(float(c[0]), float(c[1]))


static func corridor_b(i: int) -> Vector2:
	var c: Array = CORRIDORS[i]
	return Vector2(float(c[2]), float(c[3]))


static func corridor_width(i: int) -> float:
	return float(CORRIDORS[i][4])


static func region_name(r: int) -> String:
	return REGION_NAMES[clampi(r, 0, REGION_NAMES.size() - 1)]


# --------------------------------------------------------------------------
# Distance field
# --------------------------------------------------------------------------

static func _ellipse_distance(p: Vector2, i: int) -> float:
	var r := chamber_radii(i)
	var c := chamber_center(i)
	var q := Vector2((p.x - c.x) / maxf(r.x, 1.0), (p.y - c.y) / maxf(r.y, 1.0))
	return (q.length() - 1.0) * minf(r.x, r.y)


static func _capsule_distance(p: Vector2, i: int) -> float:
	var a := corridor_a(i)
	var b := corridor_b(i)
	var w := corridor_width(i)
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(ba.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ba * h) - w


## Signed distance to the walkable cavity: negative inside, positive in tissue.
static func cavity_sdf(p: Vector2) -> float:
	var d := 1.0e9
	for i in range(chamber_count()):
		d = minf(d, _ellipse_distance(p, i))
	for i in range(corridor_count()):
		d = minf(d, _capsule_distance(p, i))
	return d


static func contains(p: Vector2, clearance: float = 0.0) -> bool:
	return cavity_sdf(p) < -clearance


## True where a body of the given radius can move.
static func walkable(p: Vector2, clearance: float = 24.0) -> bool:
	return cavity_sdf(p) < -clearance


static func nearest_chamber(p: Vector2) -> int:
	var best := INF
	var best_index := 0
	for i in range(chamber_count()):
		var c := chamber_center(i)
		var r := chamber_radii(i)
		var q := Vector2((p.x - c.x) / maxf(r.x, 1.0), (p.y - c.y) / maxf(r.y, 1.0))
		if q.length() < best:
			best = q.length()
			best_index = i
	return best_index


static func region_at(p: Vector2) -> int:
	return chamber_region(nearest_chamber(p))


# --------------------------------------------------------------------------
# Cartilage rings and posterior membranous wall
# --------------------------------------------------------------------------

## One C-shaped hyaline ring per tube segment, at the widest point of the bulge.
static func ring_y(i: int) -> float:
	return chamber_center(clampi(i, 0, RING_COUNT - 1)).y


static func ring_center_x(i: int) -> float:
	return chamber_center(clampi(i, 0, RING_COUNT - 1)).x


static func ring_half_width(i: int) -> float:
	return chamber_radii(clampi(i, 0, RING_COUNT - 1)).x * 0.985


## The x coordinate where the cartilage stops on the posterior side.
static func ring_gap_x(i: int) -> float:
	return ring_center_x(i) + ring_half_width(i) * POSTERIOR_INNER


static func posterior_inner_x(i: int) -> float:
	return ring_center_x(i) + ring_half_width(i) * POSTERIOR_INNER


static func posterior_outer_x(i: int) -> float:
	return ring_center_x(i) + ring_half_width(i) * POSTERIOR_OUTER


## Closed ribbon covering the posterior membranous wall, from the first ring to
## the last. The trachealis muscle fibres are drawn inside this band.
static func posterior_band() -> PackedVector2Array:
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	for i in range(RING_COUNT):
		var y := ring_y(i)
		inner.append(Vector2(posterior_inner_x(i), y))
		outer.append(Vector2(posterior_outer_x(i), y))

	# Extend the band half a segment above the first ring and below the last so
	# it reaches the carina and the laryngeal inlet instead of stopping short.
	var first_dir := (inner[1] - inner[0]).normalized()
	var last_dir := (inner[inner.size() - 1] - inner[inner.size() - 2]).normalized()
	inner.insert(0, inner[0] - first_dir * 250.0)
	outer.insert(0, outer[0] - first_dir * 250.0)
	inner.append(inner[inner.size() - 1] + last_dir * 250.0)
	outer.append(outer[outer.size() - 1] + last_dir * 250.0)

	var poly := PackedVector2Array()
	poly.append_array(inner)
	for i in range(outer.size() - 1, -1, -1):
		poly.append(outer[i])
	return poly


## Centre line of the posterior wall, used for the muscle fibres.
static func posterior_spine(i: int) -> Vector2:
	return Vector2(
		(ring_center_x(i) + ring_half_width(i) * 0.76),
		ring_y(i)
	)


static func carina_chamber() -> int:
	return 12


# --------------------------------------------------------------------------
# Cavity outline (same union-of-rings model as Levels 2 and 3)
# --------------------------------------------------------------------------

const ELLIPSE_SEGMENTS := 128
const CAP_SEGMENTS := 24
const HIDDEN_EPSILON := 0.75
const CLIP_OVERLAP := 1.5


static func _ellipse_polygon(c: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _capsule_polygon(a: Vector2, b: Vector2, w: float, cap_segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var dir := (b - a)
	if dir.length() < 0.0001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var n := Vector2(-dir.y, dir.x)

	pts.append(a + n * w)
	for i in range(cap_segments + 1):
		var t := PI * float(i) / float(cap_segments)
		pts.append(b + (n * cos(t) + dir * sin(t)) * w)
	for i in range(cap_segments + 1):
		var t := PI * float(i) / float(cap_segments)
		pts.append(a - (n * cos(t) + dir * sin(t)) * w)
	pts.remove_at(pts.size() - 1)
	return pts


static func _chamber_ring(i: int) -> PackedVector2Array:
	var r := chamber_radii(i)
	return _ellipse_polygon(chamber_center(i), r.x, r.y, ELLIPSE_SEGMENTS)


static func _corridor_ring(i: int) -> PackedVector2Array:
	return _capsule_polygon(
		corridor_a(i), corridor_b(i), corridor_width(i), CAP_SEGMENTS
	)


static func _interior_to_other(p: Vector2, skip_kind: int, skip_index: int) -> bool:
	for i in range(chamber_count()):
		if skip_kind == 0 and i == skip_index:
			continue
		if _ellipse_distance(p, i) < -HIDDEN_EPSILON:
			return true
	for i in range(corridor_count()):
		if skip_kind == 1 and i == skip_index:
			continue
		if _capsule_distance(p, i) < -HIDDEN_EPSILON:
			return true
	return false


static func _build_outline() -> void:
	_wall_segments = PackedVector2Array()
	_boundary_samples = PackedVector2Array()
	for i in range(chamber_count()):
		_emit_ring(_chamber_ring(i), 0, i)
	for i in range(corridor_count()):
		_emit_ring(_corridor_ring(i), 1, i)


static func _emit_ring(ring: PackedVector2Array, kind: int, index: int) -> void:
	var n := ring.size()
	var hidden := PackedByteArray()
	hidden.resize(n)
	var hidden_count := 0
	for i in range(n):
		if _interior_to_other(ring[i], kind, index):
			hidden[i] = 1
			hidden_count += 1
		else:
			_boundary_samples.append(ring[i])

	if hidden_count == 0:
		for i in range(n):
			_add_segment(ring[i], ring[(i + 1) % n])
		return
	if hidden_count == n:
		return

	var runs: Array[PackedInt32Array] = []
	var current := PackedInt32Array()
	for i in range(n):
		if hidden[i] == 1:
			if not current.is_empty():
				runs.append(current)
				current = PackedInt32Array()
		else:
			current.append(i)
	if not current.is_empty():
		runs.append(current)

	if runs.size() > 1 and hidden[0] == 0 and hidden[n - 1] == 0:
		var merged: PackedInt32Array = runs[runs.size() - 1]
		merged.append_array(runs[0])
		runs.remove_at(0)
		runs[runs.size() - 1] = merged

	for run in runs:
		var first := run[0]
		var last := run[run.size() - 1]
		var pts := PackedVector2Array()
		pts.append(_clip_to_neighbour(ring[(first - 1 + n) % n], ring[first], kind, index))
		for idx in run:
			pts.append(ring[idx])
		pts.append(_clip_to_neighbour(ring[(last + 1) % n], ring[last], kind, index))
		_emit_run(pts)


static func _clip_to_neighbour(inner: Vector2, outer: Vector2, kind: int, index: int) -> Vector2:
	if not _interior_to_other(inner, kind, index):
		return inner
	var lo := outer
	var hi := inner
	for _step in range(18):
		var mid := lo.lerp(hi, 0.5)
		if _interior_to_other(mid, kind, index):
			hi = mid
		else:
			lo = mid
	return lo.lerp(hi, 0.5) + (inner - outer).normalized() * CLIP_OVERLAP


static func _emit_run(run: PackedVector2Array) -> void:
	for i in range(run.size() - 1):
		_add_segment(run[i], run[i + 1])


static func _add_segment(a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) <= 0.05:
		return
	_wall_segments.append(a)
	_wall_segments.append(b)


## Wall segment pairs (p0, p1, p2, p3, ...) for a ConcavePolygonShape2D.
static func wall_segments() -> PackedVector2Array:
	if _wall_segments.is_empty():
		_build_outline()
	return _wall_segments


## Points on the visible cavity boundary, used by the cilia and by the
## headless self check.
static func boundary_samples() -> PackedVector2Array:
	if _boundary_samples.is_empty():
		_build_outline()
	return _boundary_samples


static func bounds() -> Rect2:
	if _bounds.size == Vector2.ZERO:
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for i in range(chamber_count()):
			var c := chamber_center(i)
			var r := chamber_radii(i)
			mn = mn.min(c - r)
			mx = mx.max(c + r)
		for i in range(corridor_count()):
			var w := corridor_width(i)
			var a := corridor_a(i)
			var b := corridor_b(i)
			mn = mn.min(a - Vector2(w, w))
			mn = mn.min(b - Vector2(w, w))
			mx = mx.max(a + Vector2(w, w))
			mx = mx.max(b + Vector2(w, w))
		_bounds = Rect2(mn, mx - mn)
	return _bounds


static func route_length() -> float:
	return _polyline_length(ROUTE)


static func route_seconds() -> float:
	return route_length() / PLAYER_SPEED


static func _polyline_length(points: Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += (points[i - 1] as Vector2).distance_to(points[i] as Vector2)
	return total


static func spawn_point() -> Vector2:
	return ROUTE[0]


static func route_end() -> Vector2:
	return ROUTE[ROUTE.size() - 1]


## Tapered ribbon around a centre line (folds, muscle bands, rings).
static func ribbon(path: PackedVector2Array, half_widths: PackedFloat32Array) -> PackedVector2Array:
	var n := path.size()
	var out := PackedVector2Array()
	if n < 2:
		return out
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(n):
		var prev := path[maxi(i - 1, 0)]
		var next := path[mini(i + 1, n - 1)]
		var tangent := next - prev
		if tangent.length() < 0.0001:
			tangent = Vector2.RIGHT
		tangent = tangent.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var h := half_widths[i]
		left.append(path[i] + normal * h)
		right.append(path[i] - normal * h)
	out.append_array(left)
	for i in range(n - 1, -1, -1):
		out.append(right[i])
	return out
