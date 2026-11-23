@tool
extends RefCounted

## Shared geometry for Level 5. The airway, wall collision, tissue renderer,
## spawn positions, camera bounds, and minimap all read this map.

const PLAYER_SPEED := 200.0

## [name, center_x, center_y, radius_x, radius_y, region]
## Regions: 0 = trachea, 1 = carina/main bronchi, 2 = lobes, 3 = alveoli.
const CHAMBERS := [
	["TrachealInlet", 0.0, -2600.0, 330.0, 470.0, 0],
	["LowerTrachea", 0.0, -2040.0, 350.0, 490.0, 0],
	["Carina", 0.0, -1480.0, 450.0, 330.0, 1],
	["LeftMainBronchus", -520.0, -1160.0, 330.0, 380.0, 1],
	["RightMainBronchus", 520.0, -1160.0, 330.0, 380.0, 1],
	["LeftUpperLobe", -1270.0, -1460.0, 610.0, 480.0, 2],
	["LeftLowerLobe", -1370.0, -350.0, 620.0, 560.0, 2],
	["RightUpperLobe", 1270.0, -1460.0, 610.0, 480.0, 2],
	["RightLowerLobe", 1370.0, -350.0, 620.0, 560.0, 2],
	["LeftApicalAlveoli", -2200.0, -1880.0, 440.0, 360.0, 3],
	["LeftUpperAlveoli", -2460.0, -950.0, 470.0, 350.0, 3],
	["LeftLateralAlveoli", -2380.0, -140.0, 470.0, 360.0, 3],
	["LeftBasalAlveoli", -1700.0, 600.0, 530.0, 320.0, 3],
	["RightApicalAlveoli", 2200.0, -1880.0, 440.0, 360.0, 3],
	["RightUpperAlveoli", 2460.0, -950.0, 470.0, 350.0, 3],
	["RightLateralAlveoli", 2380.0, -140.0, 470.0, 360.0, 3],
	["RightBasalAlveoli", 1700.0, 600.0, 530.0, 320.0, 3],
]

## [start_x, start_y, end_x, end_y, half_width]
const CORRIDORS := [
	[0.0, -2340.0, 0.0, -2050.0, 220.0],
	[0.0, -1760.0, 0.0, -1510.0, 230.0],
	[0.0, -1510.0, -340.0, -1260.0, 210.0],
	[0.0, -1510.0, 340.0, -1260.0, 210.0],
	[-620.0, -1190.0, -1030.0, -1400.0, 175.0],
	[-650.0, -1050.0, -1050.0, -600.0, 175.0],
	[620.0, -1190.0, 1030.0, -1400.0, 175.0],
	[650.0, -1050.0, 1050.0, -600.0, 175.0],
	[-1680.0, -1570.0, -1980.0, -1780.0, 150.0],
	[-1720.0, -1370.0, -2210.0, -1030.0, 155.0],
	[-1780.0, -420.0, -2110.0, -260.0, 155.0],
	[-1570.0, 160.0, -1640.0, 410.0, 150.0],
	[1680.0, -1570.0, 1980.0, -1780.0, 150.0],
	[1720.0, -1370.0, 2210.0, -1030.0, 155.0],
	[1780.0, -420.0, 2110.0, -260.0, 155.0],
	[1570.0, 160.0, 1640.0, 410.0, 150.0],
]

const ROUTE := [
	Vector2(0.0, -2860.0),
	Vector2(0.0, -2440.0),
	Vector2(0.0, -2040.0),
	Vector2(0.0, -1660.0),
	Vector2(-330.0, -1290.0),
	Vector2(-850.0, -1390.0),
	Vector2(-1400.0, -1450.0),
	Vector2(-2180.0, -1860.0),
	Vector2(-1400.0, -1450.0),
	Vector2(-600.0, -1150.0),
	Vector2(0.0, -1480.0),
	Vector2(600.0, -1150.0),
	Vector2(1400.0, -1450.0),
	Vector2(2180.0, -1860.0),
	Vector2(1400.0, -1450.0),
	Vector2(0.0, -1480.0),
	Vector2(0.0, -2440.0),
]

const REGION_NAMES := ["Trachea", "Carina and main bronchi", "Lung lobes", "Alveoli"]
const ELLIPSE_SEGMENTS := 128
const CAP_SEGMENTS := 24
const HIDDEN_EPSILON := 0.75
const CLIP_OVERLAP := 1.5

static var _bounds := Rect2()
static var _wall_segments := PackedVector2Array()
static var _boundary_samples := PackedVector2Array()


static func chamber_count() -> int:
	return CHAMBERS.size()


static func chamber_name(i: int) -> String:
	return str(CHAMBERS[i][0])


static func chamber_center(i: int) -> Vector2:
	var chamber: Array = CHAMBERS[i]
	return Vector2(float(chamber[1]), float(chamber[2]))


static func chamber_radii(i: int) -> Vector2:
	var chamber: Array = CHAMBERS[i]
	return Vector2(float(chamber[3]), float(chamber[4]))


static func chamber_region(i: int) -> int:
	return int(CHAMBERS[i][5])


static func corridor_count() -> int:
	return CORRIDORS.size()


static func corridor_a(i: int) -> Vector2:
	var corridor: Array = CORRIDORS[i]
	return Vector2(float(corridor[0]), float(corridor[1]))


static func corridor_b(i: int) -> Vector2:
	var corridor: Array = CORRIDORS[i]
	return Vector2(float(corridor[2]), float(corridor[3]))


static func corridor_width(i: int) -> float:
	return float(CORRIDORS[i][4])


static func region_name(region: int) -> String:
	return REGION_NAMES[clampi(region, 0, REGION_NAMES.size() - 1)]


static func _ellipse_distance(point: Vector2, index: int) -> float:
	var radii := chamber_radii(index)
	var center := chamber_center(index)
	var q := Vector2(
		(point.x - center.x) / maxf(radii.x, 1.0),
		(point.y - center.y) / maxf(radii.y, 1.0)
	)
	return (q.length() - 1.0) * minf(radii.x, radii.y)


static func _capsule_distance(point: Vector2, index: int) -> float:
	var a := corridor_a(index)
	var b := corridor_b(index)
	var pa := point - a
	var ba := b - a
	var t := clampf(pa.dot(ba) / maxf(ba.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + ba * t) - corridor_width(index)


static func cavity_sdf(point: Vector2) -> float:
	var distance := 1.0e9
	for i in range(chamber_count()):
		distance = minf(distance, _ellipse_distance(point, i))
	for i in range(corridor_count()):
		distance = minf(distance, _capsule_distance(point, i))
	return distance


static func contains(point: Vector2, clearance: float = 0.0) -> bool:
	return cavity_sdf(point) < -clearance


static func walkable(point: Vector2, clearance: float = 24.0) -> bool:
	return cavity_sdf(point) < -clearance


static func nearest_chamber(point: Vector2) -> int:
	var best_distance := INF
	var best_index := 0
	for i in range(chamber_count()):
		var center := chamber_center(i)
		var radii := chamber_radii(i)
		var q := Vector2(
			(point.x - center.x) / maxf(radii.x, 1.0),
			(point.y - center.y) / maxf(radii.y, 1.0)
		)
		if q.length() < best_distance:
			best_distance = q.length()
			best_index = i
	return best_index


static func region_at(point: Vector2) -> int:
	return chamber_region(nearest_chamber(point))


static func bounds() -> Rect2:
	if _bounds.size == Vector2.ZERO:
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for i in range(chamber_count()):
			var center := chamber_center(i)
			var radii := chamber_radii(i)
			minimum = minimum.min(center - radii)
			maximum = maximum.max(center + radii)
		for i in range(corridor_count()):
			var width := corridor_width(i)
			var a := corridor_a(i)
			var b := corridor_b(i)
			minimum = minimum.min(a - Vector2(width, width))
			minimum = minimum.min(b - Vector2(width, width))
			maximum = maximum.max(a + Vector2(width, width))
			maximum = maximum.max(b + Vector2(width, width))
		_bounds = Rect2(minimum, maximum - minimum)
	return _bounds


static func spawn_point() -> Vector2:
	return ROUTE[0]


static func route_end() -> Vector2:
	return ROUTE[ROUTE.size() - 1]


static func route_length() -> float:
	var total := 0.0
	for i in range(1, ROUTE.size()):
		total += ROUTE[i - 1].distance_to(ROUTE[i])
	return total


static func route_seconds() -> float:
	return route_length() / PLAYER_SPEED


static func _ellipse_polygon(center: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points


static func _capsule_polygon(a: Vector2, b: Vector2, width: float, cap_segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var direction := b - a
	if direction.length() < 0.0001:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var normal := Vector2(-direction.y, direction.x)
	points.append(a + normal * width)
	for i in range(cap_segments + 1):
		var angle := PI * float(i) / float(cap_segments)
		points.append(b + (normal * cos(angle) + direction * sin(angle)) * width)
	for i in range(cap_segments + 1):
		var angle := PI * float(i) / float(cap_segments)
		points.append(a - (normal * cos(angle) + direction * sin(angle)) * width)
	points.remove_at(points.size() - 1)
	return points


static func _chamber_ring(index: int) -> PackedVector2Array:
	var radii := chamber_radii(index)
	return _ellipse_polygon(chamber_center(index), radii.x, radii.y, ELLIPSE_SEGMENTS)


static func _corridor_ring(index: int) -> PackedVector2Array:
	return _capsule_polygon(
		corridor_a(index),
		corridor_b(index),
		corridor_width(index),
		CAP_SEGMENTS
	)


static func _interior_to_other(point: Vector2, skip_kind: int, skip_index: int) -> bool:
	for i in range(chamber_count()):
		if skip_kind == 0 and i == skip_index:
			continue
		if _ellipse_distance(point, i) < -HIDDEN_EPSILON:
			return true
	for i in range(corridor_count()):
		if skip_kind == 1 and i == skip_index:
			continue
		if _capsule_distance(point, i) < -HIDDEN_EPSILON:
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
	var count := ring.size()
	var hidden := PackedByteArray()
	hidden.resize(count)
	var hidden_count := 0
	for i in range(count):
		if _interior_to_other(ring[i], kind, index):
			hidden[i] = 1
			hidden_count += 1
		else:
			_boundary_samples.append(ring[i])

	if hidden_count == 0:
		for i in range(count):
			_add_segment(ring[i], ring[(i + 1) % count])
		return
	if hidden_count == count:
		return

	var runs: Array[PackedInt32Array] = []
	var current := PackedInt32Array()
	for i in range(count):
		if hidden[i] == 1:
			if not current.is_empty():
				runs.append(current)
				current = PackedInt32Array()
		else:
			current.append(i)
	if not current.is_empty():
		runs.append(current)

	if runs.size() > 1 and hidden[0] == 0 and hidden[count - 1] == 0:
		var merged: PackedInt32Array = runs[runs.size() - 1]
		merged.append_array(runs[0])
		runs.remove_at(0)
		runs[runs.size() - 1] = merged

	for run in runs:
		var first := run[0]
		var last := run[run.size() - 1]
		var points := PackedVector2Array()
		points.append(_clip_to_neighbour(ring[(first - 1 + count) % count], ring[first], kind, index))
		for point_index in run:
			points.append(ring[point_index])
		points.append(_clip_to_neighbour(ring[(last + 1) % count], ring[last], kind, index))
		_emit_run(points)


static func _clip_to_neighbour(inner: Vector2, outer: Vector2, kind: int, index: int) -> Vector2:
	if not _interior_to_other(inner, kind, index):
		return inner
	var low := outer
	var high := inner
	for _step in range(18):
		var middle := low.lerp(high, 0.5)
		if _interior_to_other(middle, kind, index):
			high = middle
		else:
			low = middle
	return low.lerp(high, 0.5) + (inner - outer).normalized() * CLIP_OVERLAP


static func _emit_run(run: PackedVector2Array) -> void:
	for i in range(run.size() - 1):
		_add_segment(run[i], run[i + 1])


static func _add_segment(a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) > 0.05:
		_wall_segments.append(a)
		_wall_segments.append(b)


static func wall_segments() -> PackedVector2Array:
	if _wall_segments.is_empty():
		_build_outline()
	return _wall_segments


static func boundary_samples() -> PackedVector2Array:
	if _boundary_samples.is_empty():
		_build_outline()
	return _boundary_samples
