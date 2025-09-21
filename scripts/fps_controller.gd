extends CharacterBody3D

@export var look_sensitivity: float = 0.002
@export var jump_velocity: float = 6.0
@export var auto_bhop: bool = true
@export var walk_speed: float = 7.0
@export var sprint_speed: float = 8.5

const HEADBOB_MOVE_AMOUNT: float = 0.06
const HEADBOB_FREQUENCY: float = 2.4
var headbob_time: float = 0.0

var wish_direction: Vector3 = Vector3.ZERO


func get_move_speed() -> float:
	return sprint_speed if Input.is_action_pressed("sprint") else walk_speed


func _ready() -> void:
	for child in %WorldModel.find_children("*", "VisualInstance3D"):
		child.set_layer_mask_value(1, false)
		child.set_layer_mask_value(2, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * look_sensitivity)
			%Camera3D.rotate_x(-event.relative.y * look_sensitivity)
			%Camera3D.rotation.x = clamp(%Camera3D.rotation.x, deg_to_rad(-90), deg_to_rad(90))


func _headbob_effect(delta):
	pass


func _process(delta: float) -> void:
	pass


func _handle_air_physics(delta: float) -> void:
	self.velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta


func _handle_ground_physics(delta: float) -> void:
	self.velocity.x = wish_direction.x * get_move_speed()
	self.velocity.z = wish_direction.z * get_move_speed()


func _physics_process(delta: float) -> void:
	var input_direction: Vector2 = (
		Input.get_vector("move_left", "move_right", "move_forward", "move_backward").normalized()
	)

	wish_direction = (
		self.global_transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)
	)

	if is_on_floor():
		if Input.is_action_pressed("jump"):
			self.velocity.y = jump_velocity

		_handle_ground_physics(delta)
	else:
		_handle_air_physics(delta)

	move_and_slide()
