extends Node2D

const Map := preload("res://scenes/pharynx_map.gd")
const LevelGameplay := preload("res://scenes/pharynx_level.gd")

# Optional local test autopilot. Loaded lazily so a published build never
# depends on the temporary test scaffolding being present.
const WALK_TEST_PATH := "res://scenes/_walk_test.gd"

# Pharynx Level 2 - Exploration Environment
# Manages the anatomical camera framing, chamber/region reporting,
# and keeps the shared HUD free of enemy objective panels.

const CAMERA_MARGIN := 200.0

var _player: Node2D = null
var _region: int = -1
var _chamber: int = -1
var _walk_cache := PackedByteArray()


func _ready() -> void:
	add_to_group("level_manager")
	_player = get_node_or_null("Player") as Node2D
	if _player != null:
		_player.global_position = Map.spawn_point()
	_configure_camera()
	_configure_hud()
	print(
		"[Pharynx] Level 2 ready - %d chambers, %d passages, %d folds, %.0f px main route (%.1f s), %.0f px side routes (%.1f s)."
		% [
			Map.chamber_count(), Map.corridor_count(), Map.barrier_count(),
			Map.route_length(), Map.route_seconds(),
			Map.branch_length(), Map.branch_length() / Map.PLAYER_SPEED,
		]
	)
	if _player != null:
		_report(_player.global_position)

	# Level 2 gameplay: host cells, immune cells, objective tracking and exit.
	var gameplay := LevelGameplay.new()
	gameplay.name = "LevelGameplay"
	add_child(gameplay)


func _configure_camera() -> void:
	var cam := get_node_or_null("Player/Camera2D") as Camera2D
	if cam == null:
		push_warning("[Pharynx] Player camera not found; keeping defaults.")
		return
	var box := Map.bounds()
	cam.limit_left = int(box.position.x - CAMERA_MARGIN)
	cam.limit_right = int(box.end.x + CAMERA_MARGIN)
	cam.limit_top = int(box.position.y - CAMERA_MARGIN)
	cam.limit_bottom = int(box.end.y + CAMERA_MARGIN)
	cam.reset_smoothing()


func _configure_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var panel: Variant = hud.get("objective_panel")
	if panel is Control:
		(panel as Control).visible = true


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_node_or_null("Player") as Node2D
		if _player == null:
			return
	_report(_player.global_position)


func _report(p: Vector2) -> void:
	var region := Map.region_at(p)
	if region != _region:
		_region = region
		print("[Pharynx] Entered region: ", Map.region_name(region))
	var chamber := Map.nearest_chamber(p)
	if chamber != _chamber:
		_chamber = chamber
		print(
			"[Pharynx] Entered chamber: ", Map.chamber_name(chamber),
			" (", Map.region_name(Map.chamber_region(chamber)), ")"
		)


# --------------------------------------------------------------------------
# Runtime verification
# --------------------------------------------------------------------------

func run_self_check() -> Dictionary:
	var failures: Array[String] = []
	var samples := Map.boundary_samples()
	if samples.size() < 100:
		failures.append("cavity boundary is degenerate (%d samples)" % samples.size())

	var space := get_world_2d().direct_space_state
	var probe := CircleShape2D.new()
	probe.radius = 16.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if _player is CollisionObject2D:
		# The player itself is on the wall mask; it must not count as a blocker.
		query.exclude = [(_player as CollisionObject2D).get_rid()]

	var box := Map.bounds()

	# Every chamber centre, passage midline and route segment must be open.
	var blocked := 0
	for i in range(Map.chamber_count()):
		if _hits(space, query, Map.chamber_center(i)):
			blocked += 1
			failures.append(
				"chamber centre blocked: %s by %s"
				% [Map.chamber_name(i), _blocker(space, query, Map.chamber_center(i))]
			)
	for i in range(Map.corridor_count()):
		var a := Map.corridor_a(i)
		var b := Map.corridor_b(i)
		for s in range(5):
			var p := a.lerp(b, 0.1 + 0.2 * float(s))
			if _hits(space, query, p):
				blocked += 1
				failures.append(
					"passage blocked: corridor %d at %.1f by %s"
					% [i, 0.1 + 0.2 * s, _blocker(space, query, p)]
				)
				break
	var route_blocked := 0
	for i in range(1, Map.ROUTE.size()):
		var a: Vector2 = Map.ROUTE[i - 1]
		var b: Vector2 = Map.ROUTE[i]
		for s in range(7):
			var p := a.lerp(b, float(s) / 6.0)
			if _hits(space, query, p):
				route_blocked += 1
				failures.append(
					"main route blocked near waypoint %d by %s"
					% [i, _blocker(space, query, p)]
				)
				break

	# The wall must exist all along the visible boundary, and it must not stray
	# into the open cavity. Each sample is a point on the analytic contour, so a
	# hit there proves the wall is present; a probe 34 px to the inside proves
	# the passage is still clear just next to it.
	var boundary_tested := 0
	var boundary_hits := 0
	var interior_blocked := 0
	var stride := maxi(1, samples.size() / 80)
	var edge_index := 0
	while edge_index < samples.size():
		var p := samples[edge_index]
		boundary_tested += 1
		if _hits(space, query, p):
			boundary_hits += 1
		var inward := _inward(p)
		if _hits(space, query, p + inward * 34.0):
			interior_blocked += 1
		edge_index += stride
	if boundary_tested > 0 and boundary_hits < boundary_tested - 2:
		failures.append(
			"wall missing on %d of %d boundary probes"
			% [boundary_tested - boundary_hits, boundary_tested]
		)
	if boundary_tested > 0 and interior_blocked > boundary_tested / 5:
		failures.append(
			"collision intrudes into open cavity at %d of %d boundary probes"
			% [interior_blocked, boundary_tested]
		)

	# Connectivity of the walkable space, folds included.
	var grid := _flood_fill()
	var reachable: PackedByteArray = grid["seen"]
	var cols: int = grid["cols"]
	var rows: int = grid["rows"]
	var step: float = grid["step"]
	var origin: Vector2 = grid["origin"]
	var reachable_count: int = grid["count"]

	var unreachable: Array[String] = []
	for i in range(Map.chamber_count()):
		if not _point_reached(Map.chamber_center(i), reachable, cols, rows, step, origin):
			unreachable.append(Map.chamber_name(i))
	if not unreachable.is_empty():
		failures.append("unreachable chambers: %s" % ", ".join(unreachable))

	for i in range(Map.BRANCHES.size()):
		var branch: Array = Map.BRANCHES[i]
		var end: Vector2 = branch[branch.size() - 1]
		if not _point_reached(end, reachable, cols, rows, step, origin):
			failures.append("unreachable side route %d" % i)

	var cam := get_node_or_null("Player/Camera2D") as Camera2D
	var camera_ok := cam != null \
		and cam.limit_left == int(box.position.x - CAMERA_MARGIN) \
		and cam.limit_right == int(box.end.x + CAMERA_MARGIN) \
		and cam.limit_top == int(box.position.y - CAMERA_MARGIN) \
		and cam.limit_bottom == int(box.end.y + CAMERA_MARGIN)
	if not camera_ok:
		failures.append("camera limits do not match the map bounds")

	return {
		"ok": failures.is_empty(),
		"chambers": Map.chamber_count(),
		"passages": Map.corridor_count(),
		"folds": Map.barrier_count(),
		"route_px": roundf(Map.route_length()),
		"route_s": snappedf(Map.route_seconds(), 0.1),
		"branches_px": roundf(Map.branch_length()),
		"branches_s": snappedf(Map.branch_length() / Map.PLAYER_SPEED, 0.1),
		"contour_points": samples.size(),
		"walkable_cells": reachable_count,
		"blocked_probes": blocked,
		"route_blocked": route_blocked,
		"wall_probes": boundary_hits,
		"wall_probes_total": boundary_tested,
		"interior_blocked": interior_blocked,
		"camera_ok": camera_ok,
		"failures": failures,
	}


# --------------------------------------------------------------------------
# Unit vector pointing into the cavity at a point on the boundary, obtained from
# the distance field gradient (which points outward).
# --------------------------------------------------------------------------

func start_walk(kind: String, index: int = 0, seconds: float = 3.0) -> Node:
	var node := get_node_or_null("WalkTest")
	if node == null:
		node = _new_walk_test()
		if node == null:
			return null
		add_child(node)
	match kind:
		"branch":
			node.start_branch(index)
		"push":
			node.start_push(float(index), seconds)
		_:
			node.start_route()
	return node


# Test-only bridge: current autopilot report.
func walk_report() -> Dictionary:
	var node := get_node_or_null("WalkTest")
	if node == null:
		return {"error": "no walk test"}
	return node.report()


# Test-only bridge: find a route through cells that are walkable with real
# body clearance, then drive the player along it. This is how the side chambers
# are proven reachable by walking, not just by the coarse flood fill.
func start_walk_to(from: Vector2, to: Vector2, path_label: String) -> Node:
	var points := walkable_path(from, to)
	var node := _walk_node()
	if node == null:
		return null
	node.start_path(points, path_label)
	return node


func _walk_node() -> Node:
	var node := get_node_or_null("WalkTest")
	if node == null:
		node = _new_walk_test()
		if node == null:
			return null
		add_child(node)
	return node


func _new_walk_test() -> Node:
	if not ResourceLoader.exists(WALK_TEST_PATH):
		push_warning("[Pharynx] Test walk helper is not present in this build.")
		return null
	var script := load(WALK_TEST_PATH) as Script
	if script == null:
		push_warning("[Pharynx] Test walk helper failed to load.")
		return null
	return script.new()


# Breadth-first route over the walkable grid (body clearance 26 px) between two
# points, simplified with a line-of-sight pass so the player only has to steer
# through a handful of waypoints.
func walkable_path(from: Vector2, to: Vector2) -> Array:
	var step := 56.0
	var box := Map.bounds().grow(step * 2.0)
	var cols := int(ceil(box.size.x / step)) + 1
	var rows := int(ceil(box.size.y / step)) + 1
	_walk_cache = PackedByteArray()
	_walk_cache.resize(cols * rows)
	var start := _nearest_walkable(_cell_of(from, box.position, step, cols, rows), box, step, cols)
	var goal := _nearest_walkable(_cell_of(to, box.position, step, cols, rows), box, step, cols)
	if start.x < 0 or goal.x < 0:
		return []
	var si := start.y * cols + start.x
	var gi := goal.y * cols + goal.x
	var prev := PackedInt32Array()
	prev.resize(cols * rows)
	prev.fill(-1)
	prev[si] = si
	var queue := PackedInt32Array([si])
	var head := 0
	var reached := si == gi
	while head < queue.size() and not reached:
		var index := queue[head]
		head += 1
		var ix := index % cols
		var iy := index / cols
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = ix + offset.x
			var ny: int = iy + offset.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var ni: int = ny * cols + nx
			if prev[ni] != -1:
				continue
			if not _cell_walkable(nx, ny, box.position, step, cols):
				continue
			prev[ni] = index
			if ni == gi:
				reached = true
				break
			queue.append(ni)
	if not reached:
		return []

	var cells := PackedVector2Array()
	var cursor := gi
	while cursor != si:
		cells.append(box.position + Vector2(cursor % cols * step, (cursor / cols) * step))
		cursor = prev[cursor]
	cells.append(box.position + Vector2(si % cols * step, (si / cols) * step))
	cells.reverse()
	var raw := PackedVector2Array([from])
	for p in cells:
		raw.append(p)
	raw.append(to)
	return _sight_simplify(raw)


func _nearest_walkable(
	cell: Vector2i, box: Rect2, step: float, cols: int
) -> Vector2i:
	for r in range(0, 6):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var ix := cell.x + dx
				var iy := cell.y + dy
				if ix < 0 or iy < 0:
					continue
				if _cell_walkable(ix, iy, box.position, step, cols):
					return Vector2i(ix, iy)
	return Vector2i(-1, -1)


func _sight_simplify(points: PackedVector2Array) -> Array:
	var out: Array = []
	if points.size() < 2:
		return out
	out.append(points[0])
	var anchor := 0
	while anchor < points.size() - 1:
		var next := points.size() - 1
		while next > anchor + 1 and not _line_clear(points[anchor], points[next]):
			next -= 1
		out.append(points[next])
		anchor = next
	return out


func _line_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(2, int(ceil(a.distance_to(b) / 16.0)))
	for i in range(steps + 1):
		if not Map.walkable(a.lerp(b, float(i) / float(steps)), 22.0):
			return false
	return true


func _inward(p: Vector2) -> Vector2:
	var e := 3.0
	var gx := Map.cavity_sdf(p + Vector2(e, 0.0)) - Map.cavity_sdf(p - Vector2(e, 0.0))
	var gy := Map.cavity_sdf(p + Vector2(0.0, e)) - Map.cavity_sdf(p - Vector2(0.0, e))
	var outward := Vector2(gx, gy)
	if outward.length() < 0.0001:
		return Vector2.ZERO
	return -outward.normalized()


# --------------------------------------------------------------------------
# Diagnostic: walk each main-route segment in 6 px steps and report every probe
# that collides, with its distance field, the blocker and the nearest wall
# segment. Used to locate a passage pinch; not part of the level runtime.
# --------------------------------------------------------------------------

func route_scan() -> Dictionary:
	var space := get_world_2d().direct_space_state
	var probe := CircleShape2D.new()
	probe.radius = 16.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if _player is CollisionObject2D:
		query.exclude = [(_player as CollisionObject2D).get_rid()]

	var hits: Array = []
	for i in range(1, Map.ROUTE.size()):
		var a: Vector2 = Map.ROUTE[i - 1]
		var b: Vector2 = Map.ROUTE[i]
		var steps := maxi(2, int(ceil(a.distance_to(b) / 6.0)))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			if not _hits(space, query, p):
				continue
			hits.append(
				{
					"waypoint": i,
					"p": str(p.round()),
					"sdf": snappedf(Map.cavity_sdf(p), 0.1),
					"blocker": _blocker(space, query, p),
					"nearest_wall": _nearest_wall(p),
				}
			)
			break
	return {"hits": hits, "segments": Map.ROUTE.size() - 1}


# --------------------------------------------------------------------------
# Nearest wall segment to `p`, as "distance (@a -> @b)".
# --------------------------------------------------------------------------

func _nearest_wall(p: Vector2) -> String:
	var segs := Map.wall_segments()
	var best := 1e99
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	var i := 0
	while i < segs.size() - 1:
		var a := segs[i]
		var b := segs[i + 1]
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(closest)
		if d < best:
			best = d
			best_a = a
			best_b = b
		i += 2
	return "%s (@%s -> @%s)" % [snappedf(best, 0.1), str(best_a.round()), str(best_b.round())]


# --------------------------------------------------------------------------
# Physics query helpers
# --------------------------------------------------------------------------

func _hits(space: PhysicsDirectSpaceState2D, query: PhysicsShapeQueryParameters2D, p: Vector2) -> bool:
	query.transform = Transform2D(0.0, p)
	return not space.intersect_shape(query, 1).is_empty()


func _blocker(space: PhysicsDirectSpaceState2D, query: PhysicsShapeQueryParameters2D, p: Vector2) -> String:
	query.transform = Transform2D(0.0, p)
	for hit in space.intersect_shape(query, 4):
		var collider: Variant = hit.get("collider")
		if collider is Node:
			return str((collider as Node).name)
	return "unknown"


# --------------------------------------------------------------------------
# Flood fill / walkable space analysis
# --------------------------------------------------------------------------

func _flood_fill() -> Dictionary:
	var step := 56.0
	var box := Map.bounds().grow(step * 2.0)
	var cols := int(ceil(box.size.x / step)) + 1
	var rows := int(ceil(box.size.y / step)) + 1
	var state := PackedByteArray()
	state.resize(cols * rows)  # 0 = unknown, 1 = walkable, 2 = blocked
	_walk_cache = state
	var seen := PackedByteArray()
	seen.resize(cols * rows)

	var start := _cell_of(Map.spawn_point(), box.position, step, cols, rows)
	var start_index := -1
	for r in range(0, 5):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if start_index >= 0:
					continue
				var ix := start.x + dx
				var iy := start.y + dy
				if ix < 0 or iy < 0 or ix >= cols or iy >= rows:
					continue
				if _cell_walkable(ix, iy, box.position, step, cols):
					start_index = iy * cols + ix
	if start_index < 0:
		return {"seen": seen, "cols": cols, "rows": rows, "step": step, "origin": box.position, "count": 0}

	var queue := PackedInt32Array([start_index])
	seen[start_index] = 1
	var count := 0
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		count += 1
		var ix := index % cols
		var iy := index / cols
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = ix + offset.x
			var ny: int = iy + offset.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var ni: int = ny * cols + nx
			if seen[ni] == 1:
				continue
			if not _cell_walkable(nx, ny, box.position, step, cols):
				continue
			seen[ni] = 1
			queue.append(ni)
	return {"seen": seen, "cols": cols, "rows": rows, "step": step, "origin": box.position, "count": count}


func _cell_of(p: Vector2, origin: Vector2, step: float, cols: int, rows: int) -> Vector2i:
	var ix := int(round((p.x - origin.x) / step))
	var iy := int(round((p.y - origin.y) / step))
	return Vector2i(clampi(ix, 0, cols - 1), clampi(iy, 0, rows - 1))


func _cell_walkable(ix: int, iy: int, origin: Vector2, step: float, cols: int) -> bool:
	var index := iy * cols + ix
	if _walk_cache[index] != 0:
		return _walk_cache[index] == 1
	var p := origin + Vector2(ix * step, iy * step)
	var ok := Map.walkable(p, 26.0)
	_walk_cache[index] = 1 if ok else 2
	return ok


func _point_reached(
	p: Vector2, seen: PackedByteArray, cols: int, rows: int, step: float, origin: Vector2
) -> bool:
	var center := _cell_of(p, origin, step, cols, rows)
	for r in range(0, 6):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var ix := center.x + dx
				var iy := center.y + dy
				if ix < 0 or iy < 0 or ix >= cols or iy >= rows:
					continue
				if seen[iy * cols + ix] == 1:
					return true
	return false


# --------------------------------------------------------------------------
# Minimap provider
# --------------------------------------------------------------------------
# The shared minimap asks the level root for its world bounds and a simplified
# outline. Level 2 draws every chamber as an ellipse and every passage as a
# capsule, giving the elongated pharynx silhouette with its internal shape.

func minimap_bounds() -> Rect2:
	return Map.bounds()


func minimap_outline() -> Array:
	var polys: Array = []

	for i in range(Map.chamber_count()):
		polys.append(_ellipse_polygon(Map.chamber_center(i), Map.chamber_radii(i), 24))

	for i in range(Map.corridor_count()):
		polys.append(
			_capsule_polygon(
				Map.corridor_a(i), Map.corridor_b(i), Map.corridor_width(i), 8
			)
		)

	return polys


func _ellipse_polygon(center: Vector2, radii: Vector2, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()

	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))

	return pts


func _capsule_polygon(a: Vector2, b: Vector2, w: float, cap_segments: int) -> PackedVector2Array:
	var dir := b - a
	if dir.length() < 0.0001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var normal := Vector2(-dir.y, dir.x)

	var pts := PackedVector2Array()
	pts.append(a + normal * w)
	for i in range(cap_segments + 1):
		var t := PI * float(i) / float(cap_segments)
		pts.append(b + (normal * cos(t) + dir * sin(t)) * w)
	for i in range(cap_segments + 1):
		var t := PI * float(i) / float(cap_segments)
		pts.append(a - (normal * cos(t) + dir * sin(t)) * w)
	pts.remove_at(pts.size() - 1)

	return pts
