extends Control

# Procedural biological sci-fi background with organic cells and ambient fluid particles

class Particle:
	var position: Vector2
	var velocity: Vector2
	var radius: float
	var color: Color
	var pulse_speed: float
	var pulse_offset: float
	var type: int # 0: erythrocyte/disc, 1: virion/spiked, 2: micro-droplet

var particles: Array[Particle] = []
var time: float = 0.0
const PARTICLE_COUNT: int = 45


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	init_particles()


func _on_resized() -> void:
	init_particles()
	queue_redraw()


func init_particles() -> void:
	particles.clear()
	var vp_size := size
	if vp_size == Vector2.ZERO:
		vp_size = Vector2(1280, 720)

	for i in range(PARTICLE_COUNT):
		var p := Particle.new()
		p.position = Vector2(randf() * vp_size.x, randf() * vp_size.y)
		p.velocity = Vector2(randf_range(-15.0, 15.0), randf_range(-25.0, -8.0))
		p.type = randi() % 3
		p.pulse_speed = randf_range(1.5, 3.5)
		p.pulse_offset = randf_range(0.0, TAU)

		match p.type:
			0: # Erythrocyte / red blood cell disc
				p.radius = randf_range(9.0, 18.0)
				p.color = Color(0.65, 0.12, 0.20, randf_range(0.18, 0.35))
			1: # Small virion
				p.radius = randf_range(5.0, 9.0)
				p.color = Color(0.85, 0.25, 0.38, randf_range(0.25, 0.45))
			2: # Micro-droplet
				p.radius = randf_range(2.0, 5.0)
				p.color = Color(0.95, 0.40, 0.50, randf_range(0.15, 0.30))

		particles.append(p)


func _process(delta: float) -> void:
	time += delta
	var vp_size := size
	if vp_size == Vector2.ZERO:
		vp_size = Vector2(1280, 720)

	for p in particles:
		p.position += p.velocity * delta
		# Add gentle sinusoidal horizontal wave
		p.position.x += sin(time * 0.8 + p.pulse_offset) * 12.0 * delta

		# Wrap around screen
		if p.position.y < -30:
			p.position.y = vp_size.y + 30
			p.position.x = randf() * vp_size.x
		elif p.position.y > vp_size.y + 30:
			p.position.y = -30
		if p.position.x < -30:
			p.position.x = vp_size.x + 30
		elif p.position.x > vp_size.x + 30:
			p.position.x = -30

	queue_redraw()


func _draw() -> void:
	var rect_size := size
	if rect_size == Vector2.ZERO:
		rect_size = Vector2(1280, 720)

	# Deep biological gradient: dark maroon/crimson to abyssal black
	var top_color := Color(0.15, 0.04, 0.07, 1.0)
	var bottom_color := Color(0.05, 0.01, 0.02, 1.0)
	draw_rect(Rect2(Vector2.ZERO, rect_size), bottom_color)

	# Soft ambient organic radial glow in the center-top
	var center := Vector2(rect_size.x * 0.5, rect_size.y * 0.4)
	draw_circle(center, rect_size.x * 0.6, Color(0.35, 0.06, 0.12, 0.20))
	draw_circle(center, rect_size.x * 0.35, Color(0.50, 0.08, 0.16, 0.15))

	# Draw particles
	for p in particles:
		var alpha_pulse := 0.8 + 0.2 * sin(time * p.pulse_speed + p.pulse_offset)
		var c := p.color
		c.a *= alpha_pulse

		match p.type:
			0: # Erythrocyte / disc
				draw_circle(p.position, p.radius, c)
				# Dimple in center
				var inner_color := Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, c.a * 0.9)
				draw_circle(p.position, p.radius * 0.45, inner_color)
			1: # Small virion with tiny spikes
				draw_circle(p.position, p.radius, c)
				for k in range(6):
					var ang := k * TAU / 6.0 + time * 0.5
					var p1 := p.position + Vector2(cos(ang), sin(ang)) * p.radius
					var p2 := p.position + Vector2(cos(ang), sin(ang)) * (p.radius + 3.5)
					draw_line(p1, p2, c, 1.5)
			2: # Micro-droplet
				draw_circle(p.position, p.radius, c)

	# Vignette border darkness
	draw_rect(Rect2(0, 0, rect_size.x, 80), Color(0.02, 0.0, 0.01, 0.4))
	draw_rect(Rect2(0, rect_size.y - 80, rect_size.x, 80), Color(0.02, 0.0, 0.01, 0.6))
