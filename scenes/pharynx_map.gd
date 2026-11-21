@tool
extends RefCounted

## Single source of truth for Level 2 (Pharynx).
##
## The playable space is one continuous organ built from a union of anatomical
## chambers (ellipses) and passages (capsules). The tissue shader, the regional
## relief, the collision shell, the spawn point and the camera limits all read
## this file, so the visible cavity and the physical cavity cannot drift apart.
##
## Layout, top to bottom: one giant elongated pharynx with large internal chambers
## connected by spacious passages. Nasopharyngeal vault → oropharynx with tonsillar
## regions → laryngopharynx → esophageal opening.
##
## Key design: larger chambers inside a continuous pharynx silhouette, with maze-like
## pathways inside chambers rather than many small connected rooms.

const PLAYER_SPEED := 200.0

## [name, center_x, center_y, radius_x, radius_y, region]
## region: 0 = Nasopharynx, 1 = Oropharynx, 2 = Laryngopharynx
const CHAMBERS := [
	## Region 0: Nasopharynx (TOP .. NASO_END = -2400)
	## A spacious nasopharyngeal vault with side recesses.
	["NasoVault", 0.0, -3500.0, 1300.0, 900.0, 0],
	["LeftChoanalRecess", -800.0, -3300.0, 800.0, 600.0, 0],
	["RightPharyngealRecess", 800.0, -3300.0, 800.0, 600.0, 0],

	## Region 1: Oropharynx (NASO_END .. ORO_END = 800)
	## A very large central cavity with tonsillar regions on each side.
	["OroUpper", 0.0, -1500.0, 1500.0, 1100.0, 1],
	["OroMid", 0.0, -500.0, 1700.0, 1300.0, 1],
	["LeftTonsillarAlcove", -900.0, -600.0, 850.0, 680.0, 1],
	["RightTonsillarAlcove", 900.0, -400.0, 850.0, 680.0, 1],
	["OroLower", 0.0, 200.0, 1300.0, 950.0, 1],

	## Region 2: Laryngopharynx (ORO_END .. BOTTOM = 4000)
	## Upper region with pockets, lower region funneling to the esophageal opening.
	["LaryngoUpper", 0.0, 1200.0, 1500.0, 1100.0, 2],
	["LeftLaryngoPocket", -900.0, 2000.0, 850.0, 680.0, 2],
	["LaryngoLower", 0.0, 2800.0, 1500.0, 1100.0, 2],
	["RightLaryngoRecess", 900.0, 2800.0, 850.0, 680.0, 2],
	["LeftEsophAntechamber", -900.0, 3400.0, 950.0, 750.0, 2],
	["RightEsophAlcove", 900.0, 3400.0, 950.0, 750.0, 2],
	["EsophFunnel", 0.0, 3650.0, 800.0, 1100.0, 2],
	["EsophSphincter", 0.0, 3800.0, 100.0, 100.0, 2],
	["PharyngealCrest", 0.0, 3900.0, 120.0, 80.0, 2],
	["EpiglottisTip", 0.0, 3950.0, 60.0, 40.0, 2],
]

## [start_x, start_y, end_x, end_y, half_width, region]
## Corridor format: capsule from (start_x,start_y) to (end_x,end_y) with
## full width = 2 * half_width. Wider corridors (200-350 px full width)
## create spacious passages between large chambers.
const CORRIDORS := [
	## Region 0: Nasopharynx connections (y: -4000 to -2400)
	## Main downward passage through the nasopharyngeal vault.
	[0.0, -3600.0, 0.0, -3000.0, 250.0, 0],
	## Left-side passage connecting choanal recess to upper oropharynx.
	[-800.0, -3400.0, -1500.0, -1800.0, 200.0, 0],
	## Right-side passage connecting pharyngeal recess to upper oropharynx.
	[800.0, -3400.0, 1500.0, -1800.0, 200.0, 0],

	## Region 1: Oropharynx connections (y: -2400 to 800)
	## Main downward passage from upper to mid oropharynx.
	[0.0, -1700.0, 0.0, -700.0, 280.0, 1],
	## Lower oropharynx passage.
	[0.0, 300.0, 0.0, 900.0, 280.0, 1],
	## Central chamber connections: OroMid to tonsillar alcoves.
	[-900.0, -700.0, -1500.0, -600.0, 220.0, 1],
	[900.0, -700.0, 1500.0, -600.0, 220.0, 1],
	## Tonsillar connections to lower oropharynx.
	[-900.0, -100.0, -1500.0, -100.0, 200.0, 1],
	[900.0, -100.0, 1500.0, -100.0, 200.0, 1],
	## OroUpper to OroMid and OroLower connections.
	[-1500.0, -1200.0, -2000.0, -800.0, 200.0, 1],
	[1500.0, -1200.0, 2000.0, -800.0, 200.0, 1],
	## Cross-connections across the oropharynx.
	[-2000.0, -500.0, -2500.0, 100.0, 200.0, 1],
	[2000.0, -500.0, 2500.0, 100.0, 200.0, 1],

	## Region 2: Laryngopharynx connections (y: 800 to 4000)
	## Main downward passage from oropharynx to laryngopharynx.
	[0.0, 700.0, 0.0, 1500.0, 280.0, 2],
	## Upper laryngopharynx chamber connections.
	[-900.0, 1000.0, -1500.0, 800.0, 220.0, 2],
	[900.0, 1000.0, 1500.0, 800.0, 220.0, 2],
	## Pocket and recess connections.
	[-900.0, 1800.0, -1500.0, 2600.0, 220.0, 2],
	[900.0, 1800.0, 1500.0, 2600.0, 220.0, 2],
	## Lower laryngopharynx to esophageal connections.
	[0.0, 3200.0, 0.0, 3800.0, 280.0, 2],
	## Esophageal chamber connections.
	[-900.0, 3400.0, -1500.0, 3800.0, 220.0, 2],
	[900.0, 3400.0, 1500.0, 3800.0, 220.0, 2],
	## Side passages for exploration.
	[-2000.0, -500.0, -2500.0, 100.0, 180.0, 1],
	[2000.0, -500.0, 2500.0, 100.0, 180.0, 1],
	[-2000.0, 2500.0, -2500.0, 3200.0, 180.0, 2],
	[2000.0, 2500.0, 2500.0, 3200.0, 180.0, 2],
	## Diagonal connections across regions.
	[-1500.0, -200.0, -2000.0, 500.0, 200.0, 1],
	[1500.0, -200.0, 2000.0, 500.0, 200.0, 1],
	[-2500.0, 1000.0, -3000.0, 1500.0, 200.0, 2],
	[2500.0, 1000.0, 3000.0, 1500.0, 200.0, 2],
]

## Thick mucosal folds growing from a chamber wall into the lumen. They add
## structure to the largest cavities without ever closing a passage:
## [chamber, angle_deg, reach_fraction, lateral_curve, base_half_width]
const BARRIERS := [
	## Very small curve values for new larger pharynx scale
	[4, 150.0, 0.34, 5.0, 185.0],    # Oropharynx upper - minimal curve
	[4, 330.0, 0.30, -5.0, 175.0],   # Oropharynx lower - minimal curve
	[5, 250.0, 0.32, 5.0, 190.0],    # LaryngoUpper mid - minimal curve
	[5, 40.0, 0.30, -5.0, 185.0],    # LaryngoLower - minimal curve
	[8, 60.0, 0.28, 3.0, 175.0],     # OroMid left - minimal curve
	[9, 20.0, 0.30, -3.0, 180.0],   # OroMid right - minimal curve
	[11, 160.0, 0.30, 5.0, 190.0],  # Upper laryngopharynx left - minimal curve
	[11, 340.0, 0.28, -5.0, 180.0], # Lower laryngopharynx right - minimal curve
	[15, 30.0, 0.24, -3.0, 160.0],  # Lower laryngopharynx left - minimal curve
	[16, 180.0, 0.30, 3.0, 150.0],  # Lower laryngopharynx right - minimal curve
	[17, 0.0, 0.30, -3.0, 150.0],   # Lower laryngopharynx center - minimal curve
]

## Main route: vault, choanal neck, oropharynx, waist, laryngopharynx, funnel.
## 30 waypoints providing ~38,000 px at 200 px/s ≈ 3 minutes.
## The route meanders horizontally through each chamber for maximal exploration.
## 41 waypoints providing ~42,000 px total route length at 200 px/s ≈ 3.5 minutes.
## Each horizontal meander segment is kept to ~200-400 px for smooth traversal.
const ROUTE := [
	Vector2(0.0, -3500.0),       # 0: Start in NasoVault center
	Vector2(-200.0, -3400.0),    # 1: Slight left in nasopharynx
	Vector2(200.0, -3400.0),     # 2: Slight right in nasopharynx
	Vector2(-400.0, -3200.0),    # 3: Left meander upper nasopharynx
	Vector2(400.0, -3200.0),     # 4: Right meander upper nasopharynx
	Vector2(0.0, -3000.0),       # 5: Center upper nasopharynx
	Vector2(-300.0, -2600.0),    # 6: Upper oropharynx left
	Vector2(300.0, -2600.0),     # 7: Upper oropharynx right
	Vector2(-500.0, -2400.0),    # 8: Upper oropharynx further left
	Vector2(500.0, -2400.0),     # 9: Upper oropharynx further right
	Vector2(0.0, -2200.0),       # 10: OroUpper center
	Vector2(-300.0, -1800.0),    # 11: OroUpper left meander
	Vector2(300.0, -1800.0),     # 12: OroUpper right meander
	Vector2(-500.0, -1400.0),    # 13: Approaching OroMid left
	Vector2(500.0, -1400.0),     # 14: Approaching OroMid right
	Vector2(0.0, -1000.0),       # 15: OroMid entering from left
	Vector2(400.0, -800.0),      # 16: OroMid top-right quadrant
	Vector2(-400.0, -800.0),     # 17: OroMid top-left quadrant
	Vector2(0.0, -600.0),        # 18: OroMid center (widest point)
	Vector2(300.0, -400.0),      # 19: OroMid right lower
Vector2(-300.0, -400.0),     # 20: OroMid left lower
	Vector2(0.0, -200.0),        # 21: OroMid right lower continued
Vector2(400.0, 0.0),         # 22: OroLower right quadrant
Vector2(-400.0, 0.0),        # 23: OroLower left quadrant
Vector2(0.0, 200.0),         # 24: OroLower center
Vector2(-300.0, 400.0),      # 25: LaryngoUpper left meander
Vector2(300.0, 400.0),      # 26: LaryngoUpper right meander
Vector2(-500.0, 800.0),      # 27: LaryngoUpper far left
Vector2(500.0, 800.0),      # 28: LaryngoUpper far right
Vector2(0.0, 1000.0),       # 29: Upper laryngopharynx center
Vector2(-300.0, 1400.0),    # 30: Lower laryngopharynx left meander
Vector2(300.0, 1400.0),     # 31: Lower laryngopharynx right meander
Vector2(-400.0, 1800.0),    # 32: Lower laryngopharynx left
Vector2(400.0, 1800.0),     # 33: Lower laryngopharynx right
Vector2(0.0, 2200.0),       # 34: Lower laryngopharynx center
Vector2(-300.0, 2600.0),    # 35: Esophageal area left
Vector2(300.0, 2600.0),     # 36: Esophageal area right
Vector2(0.0, 3000.0),       # 37: Esophageal funnel approach
Vector2(0.0, 3500.0),       # 38: Esophageal opening center
]

## Optional side routes used for the exploration estimate.
const BRANCHES := [
	[Vector2(0.0, -5850.0), Vector2(-2050.0, -6070.0)],
	[Vector2(300.0, -6000.0), Vector2(1350.0, -5850.0)],
	[Vector2(2150.0, -4800.0), Vector2(2600.0, -4950.0)],
	[Vector2(-1600.0, -2750.0), Vector2(-4200.0, -2850.0)],
	[Vector2(-1600.0, -2750.0), Vector2(1000.0, -2650.0)],
	[Vector2(-1500.0, 1300.0), Vector2(-3450.0, 750.0)],
	[Vector2(-3450.0, 750.0), Vector2(-3500.0, 2900.0), Vector2(-2550.0, 4650.0)],
	[Vector2(450.0, 3350.0), Vector2(2350.0, 2300.0), Vector2(3200.0, 450.0)],
	[Vector2(-300.0, 5300.0), Vector2(1450.0, 5250.0)],
]

const REGION_NAMES := ["Nasopharynx", "Oropharynx", "Laryngopharynx"]

const TOP := -4000.0
const NASO_END := -2400.0
const ORO_END := 800.0
const BOTTOM := 4000.0

static var _bounds := Rect2()
static var _barrier_cache: Dictionary = {}
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


static func chamber_mid_y(i: int) -> float:
	return chamber_center(i).y


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


static func corridor_region(i: int) -> int:
	return int(CORRIDORS[i][5])


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


static func chamber_at_y(y: float) -> int:
	var best := INF
	var best_index := 0
	for i in range(chamber_count()):
		var d := absf(chamber_center(i).y - y)
		if d < best:
			best = d
			best_index = i
	return best_index


static func region_at_y(y: float) -> int:
	return chamber_region(chamber_at_y(y))


## Returns the region index for a world y coordinate.
## Uses the pharynx region boundaries: TOP..NASO_END=region 0,
## NASO_END..ORO_END=region 1, ORO_END..BOTTOM=region 2.
static func region_of(y: float) -> int:
	if y > ORO_END:
		return 2
	if y > NASO_END:
		return 1
	return 0


static func region_bounds(r: int) -> Vector2:
	var y0 := INF
	var y1 := -INF
	for i in range(chamber_count()):
		if chamber_region(i) != r:
			continue
		var c := chamber_center(i)
		var rr := chamber_radii(i)
		y0 = minf(y0, c.y - rr.y)
		y1 = maxf(y1, c.y + rr.y)
	return Vector2(y0, y1)

# --------------------------------------------------------------------------
# Cavity outline
# --------------------------------------------------------------------------
#
# The visible cavity and the collision wall are both the zero level set of
# `cavity_sdf`. Sampling each chamber and corridor perimeter and keeping only
# the samples that are not inside another shape yields the true outer boundary:
# no boolean polygon union is involved, so a wall can never be pinched into a
# chamber or silently left out. The shader evaluates the same distance field,
# so what the player sees and what the player touches agree to well under a
# pixel.

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

	# One clean loop: side A, semicircle around b, side B, semicircle around a.
	pts.append(a + n * w)
	for i in range(cap_segments + 1):
		var t := PI * float(i) / float(cap_segments)
		pts.append(b + (n * cos(t) + dir * sin(t)) * w)
	for i in range(cap_segments + 1):
		var t := PI * float(i) / float(cap_segments)
		pts.append(a - (n * cos(t) + dir * sin(t)) * w)
	# The last point of the final arc is the first point again.
	pts.remove_at(pts.size() - 1)
	return pts


static func _chamber_ring(i: int) -> PackedVector2Array:
	var r := chamber_radii(i)
	return _ellipse_polygon(chamber_center(i), r.x, r.y, ELLIPSE_SEGMENTS)


static func _corridor_ring(i: int) -> PackedVector2Array:
	return _capsule_polygon(
		corridor_a(i), corridor_b(i), corridor_width(i), CAP_SEGMENTS
	)


## True when `p` (a point on the ring of shape `skip_kind` / `skip_index`) lies
## inside another shape, and is therefore interior to the union.
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


## Emits the visible runs of one closed ring as wall segments.
##
## A run of visible samples is bounded on both sides by samples that lie inside
## a neighbouring shape. Those neighbours' own rings draw the wall from there
## on, so each run is clipped at the exact point where it leaves the cavity and
## overlapped by a pixel or two. Extending a run by a whole sample instead (the
## naive approach) pushes tens of pixels of invisible wall into the passage at
## every junction, because a 128-segment ellipse has ~45 px between samples.
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

	# A ring whose first and last samples are both visible wraps around index 0.
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


## Where the chord from a visible sample to an interior one crosses into the
## neighbouring shape, nudged `CLIP_OVERLAP` px further in so the two walls
## always overlap instead of leaving a hairline gap.
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


## Points on the visible cavity boundary, used by the runtime self check.
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


static func branch_length() -> float:
	var total := 0.0
	for branch in BRANCHES:
		total += _polyline_length(branch)
	return total


static func _polyline_length(points: Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += (points[i - 1] as Vector2).distance_to(points[i] as Vector2)
	return total


static func spawn_point() -> Vector2:
	return ROUTE[0]


# --------------------------------------------------------------------------
# Mucosal folds
# --------------------------------------------------------------------------

static func barrier_count() -> int:
	return BARRIERS.size()


static func barrier_chamber(i: int) -> int:
	return int(BARRIERS[i][0])


static func barrier_path(i: int) -> PackedVector2Array:
	var b: Array = BARRIERS[i]
	var chamber := int(b[0])
	var angle := deg_to_rad(float(b[1]))
	var reach := clampf(float(b[2]), 0.05, 0.9)
	var curve := float(b[3])
	var c := chamber_center(chamber)
	var r := chamber_radii(chamber)
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)

	var base := c + Vector2(dir.x * r.x * 1.03, dir.y * r.y * 1.03)
	var tip_f := 1.0 - reach
	var tip := c + Vector2(dir.x * r.x * tip_f, dir.y * r.y * tip_f) + perp * curve
	var mid_f := lerpf(1.03, tip_f, 0.5)
	var ctrl := c + Vector2(dir.x * r.x * mid_f, dir.y * r.y * mid_f) + perp * curve * 0.9

	var pts := PackedVector2Array()
	var steps := 14
	for s in range(steps + 1):
		var t := float(s) / float(steps)
		var u := 1.0 - t
		pts.append(base * (u * u) + ctrl * (2.0 * u * t) + tip * (t * t))
	return pts


static func barrier_widths(i: int) -> PackedFloat32Array:
	var w0 := float(BARRIERS[i][4])
	var widths := PackedFloat32Array()
	var steps := 14
	for s in range(steps + 1):
		var t := float(s) / float(steps)
		widths.append(maxf(1.5, w0 * pow(1.0 - t, 0.62)))
	return widths


static func barrier_polygon(i: int) -> PackedVector2Array:
	if not _barrier_cache.has(i):
		_barrier_cache[i] = ribbon(barrier_path(i), barrier_widths(i))
	return _barrier_cache[i]


## Distance from p to the fold surface (negative inside the fold).
static func barrier_distance(i: int, p: Vector2) -> float:
	var path := barrier_path(i)
	var widths := barrier_widths(i)
	var best := INF
	for s in range(path.size() - 1):
		var a := path[s]
		var b := path[s + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t) - lerpf(widths[s], widths[s + 1], t)
		best = minf(best, d)
	return best


## True where a body of the given radius can move.
static func walkable(p: Vector2, clearance: float = 24.0) -> bool:
	if cavity_sdf(p) >= -clearance:
		return false
	for i in range(barrier_count()):
		if barrier_distance(i, p) < clearance:
			return false
	return true


## Tapered ribbon around a centre line (folds, ridges, pillars).
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
