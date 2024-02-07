extends CharacterBody3D

enum DoubleJumpState { RESET, READY, DONE }

@export_group("Movement")
@export var movement_speed: float = 5.0
@export var movement_lerp_speed: float = 10.0
@export var gravity_multiplier: float = 2.0
@export var air_movement_dampening: float = 0.1
@export var reset_at_y: float = -50.0

@export_group("Jumping")
@export var jump_height: float = 8.0
@export var velocity_for_double_jump: float = 3.0
@export var double_jump_reduction_factor: float = 0.75

@export_group("Camera")
@export var camera_lerp_speed: float = 5.0
@export var camera_y_follow_distance: float = 2.0
@export var camera_y_lerp_factor: float = 0.5

var input_vec: Vector2 = Vector2.ZERO
var double_jump_state: DoubleJumpState = DoubleJumpState.RESET
var last_floor_y: float = 0.0

@onready var gravity: float = ProjectSettings.get("physics/3d/default_gravity")
@onready var camera: Camera3D = %Camera
@onready var camera_offset_pos: Vector3 = camera.position
@onready var camera_offset_rot: Vector3 = camera.rotation_degrees

func _process(_delta: float) -> void:
	input_vec = Input.get_vector("left", "right", "up", "down")

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_height
		elif double_jump_state == DoubleJumpState.READY:
			velocity.y = jump_height * double_jump_reduction_factor
			double_jump_state = DoubleJumpState.DONE

func _physics_process(delta: float) -> void:
	var lerp_speed: float = movement_lerp_speed * delta
	if is_on_floor():
		double_jump_state = DoubleJumpState.RESET
	else:
		lerp_speed *= air_movement_dampening
		velocity.y -= gravity * gravity_multiplier * delta
		if double_jump_state == DoubleJumpState.RESET and absf(velocity.y) < velocity_for_double_jump:
			double_jump_state = DoubleJumpState.READY

	if input_vec:
		var input_dir: Vector3 = Vector3(input_vec.x, 0.0, input_vec.y)
		var movement: Vector3 = (transform.basis * input_dir).normalized() * movement_speed
		velocity.x = lerpf(velocity.x, movement.x, lerp_speed)
		velocity.z = lerpf(velocity.z, movement.z, lerp_speed)
	else:
		velocity.x = lerpf(velocity.x, 0.0, lerp_speed)
		velocity.z = lerpf(velocity.z, 0.0, lerp_speed)

	move_and_slide()

	if position.y < reset_at_y:
		position = Vector3.ZERO

	lerp_speed = camera_lerp_speed * delta
	camera.position.x = lerpf(camera.position.x, position.x + camera_offset_pos.x, lerp_speed)
	camera.position.z = lerpf(camera.position.z, position.z + camera_offset_pos.z, lerp_speed)

	var cam_y_pos: float = camera.position.y - camera_offset_pos.y
	var cam_y_diff: float = absf(cam_y_pos - position.y)
	if is_on_floor() or cam_y_diff > camera_y_follow_distance or velocity.y < -jump_height:
		last_floor_y = position.y

	camera.position.y = lerpf(camera.position.y, last_floor_y + camera_offset_pos.y, lerp_speed * camera_y_lerp_factor)
