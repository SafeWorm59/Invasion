extends Node

## Host-cell registry for the NKT surveillance system (Level 4).
##
## The NKT cell must know which host cells exist, where they are, and whether
## another NKT is already working on one. This node owns that knowledge so the
## NKT script stays a clean state machine instead of scanning the scene tree.
##
## Updates are cheap and controlled:
##   * a periodic refresh (1.5 s) picks up newly spawned cells and drops freed
##     or eliminated ones;
##   * the host cell's `destroyed` signal removes a cell immediately;
##   * every returned reference is validated before use.
##
## Claims are keyed by instance id so several NKT cells never eliminate the
## same host cell twice. A claim held by a freed NKT is treated as free.

signal registry_changed

const REFRESH_INTERVAL := 1.5

var _cells: Array = []
var _claims: Dictionary = {}
var _refresh_timer: float = 0.0


func _ready() -> void:
	add_to_group("nkt_host_registry")
	_refresh_timer = REFRESH_INTERVAL
	refresh()


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		refresh()


func refresh() -> void:
	var found: Array = []

	for node in get_tree().get_nodes_in_group("host_cells"):
		if not _is_cell_valid(node):
			continue
		found.append(node)

		var id: int = node.get_instance_id()
		if node.has_signal("destroyed"):
			var callback := Callable(self, "_on_cell_destroyed")
			if not node.is_connected("destroyed", callback):
				node.destroyed.connect(callback)

	_cells = found
	_prune_claims()
	registry_changed.emit()


func valid_cells() -> Array:
	var out: Array = []
	for node in _cells:
		if _is_cell_valid(node):
			out.append(node)
	return out


func cell_count() -> int:
	return valid_cells().size()


func claimed_count() -> int:
	_prune_claims()
	return _claims.size()


## Nearest valid host cell that is inside `allowed` (or any cell when `allowed`
## is empty) and not claimed by another live NKT. Deterministic tie-break by
## instance id so two NKT cells never pick the same cell in the same frame.
func pick_nearest(origin: Vector2, allowed: Dictionary, owner_id: int) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	var best_id := 0

	for node in _cells:
		if not _is_cell_valid(node):
			continue

		var id: int = node.get_instance_id()

		if not allowed.is_empty() and not allowed.has(id):
			continue

		var claimant := int(_claims.get(id, 0))
		if claimant != 0 and claimant != owner_id:
			var holder: Object = instance_from_id(claimant)
			if is_instance_valid(holder):
				continue
			_claims.erase(id)

		var d: float = origin.distance_squared_to((node as Node2D).global_position)
		if d < best_distance or (is_equal_approx(d, best_distance) and (best == null or id < best_id)):
			best = node as Node2D
			best_distance = d
			best_id = id

	return best


func claim(cell: Node2D, owner_id: int) -> bool:
	if not _is_cell_valid(cell):
		return false

	var id: int = cell.get_instance_id()
	var claimant := int(_claims.get(id, 0))

	if claimant == 0 or claimant == owner_id:
		_claims[id] = owner_id
		return true

	var holder: Object = instance_from_id(claimant)
	if not is_instance_valid(holder):
		_claims[id] = owner_id
		return true

	return false


func release(cell: Node2D, owner_id: int) -> void:
	if cell == null or not is_instance_valid(cell):
		return
	var id: int = cell.get_instance_id()
	if int(_claims.get(id, 0)) == owner_id:
		_claims.erase(id)


func release_all(owner_id: int) -> void:
	for id in _claims.keys():
		if int(_claims[id]) == owner_id:
			_claims.erase(id)


func is_cell_valid(node: Node) -> bool:
	return _is_cell_valid(node)


func _is_cell_valid(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not (node is Node2D):
		return false
	if node.is_queued_for_deletion():
		return false
	if node.get("eliminated") == true:
		return false
	if not node.is_in_group("host_cells"):
		return false
	return true


func _on_cell_destroyed(cell: Node) -> void:
	if cell == null:
		return
	_cells.erase(cell)
	_claims.erase(cell.get_instance_id())
	registry_changed.emit()


func _prune_claims() -> void:
	for id in _claims.keys():
		var found := false
		for node in _cells:
			if is_instance_valid(node) and node.get_instance_id() == id:
				found = true
				break
		if not found:
			_claims.erase(id)
