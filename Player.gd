extends CharacterBody3D

enum DoubleJumpState { RESET, READY, DONE }

#region exports
@export var can_control: bool = false

@export_group("Stats")
@export_subgroup("HP")
@export var hp: float = 5.0
@export var max_hp: float = 5.0
@export_subgroup("Stamina")
@export var stamina: float = 3.0
@export var max_stamina: float = 3.0
@export var stamina_refill_rate: float = 2.0
@export_subgroup("Combat")
@export var strength: float = 1.0
@export var defence: float = 1.0
@export_subgroup("EXP")
@export var experience: float = 0.0
@export var next_exp: float = 100.0
@export var level: int = 1
@export_subgroup("Stats UI")
@export var hp_label: Label
@export var stamina_label: Label
@export var str_label: Label
@export var def_label: Label
@export var exp_label: Label
@export var level_label: Label

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
@export_subgroup("Stats")
@export var jump_stamina: float = 1.0
@export var double_jump_stamina: float = 2.0

@export_group("Dodging")
@export var dodge_floor_speed: float = 5.0
@export var dodge_air_speed: float = 2.0
@export_subgroup("Stats")
@export var dodge_stamina: float = 2.0

@export_group("Fall damage")
@export var fall_damage_velocity: float = -15.0
@export var fall_damage_divisor: float = 20.0
@export var fall_damage_threshold: float = -0.5

@export_group("Camera")
@export var camera: Camera3D
@export var camera_lerp_speed: float = 5.0
@export var camera_y_follow_distance: float = 2.0
@export var camera_y_lerp_factor: float = 0.5
#endregion

var input_vec: Vector2 = Vector2.ZERO
var double_jump_state: DoubleJumpState = DoubleJumpState.RESET
var last_y_velocity: float = 0.0
var camera_offset_pos: Vector3 = Vector3.ZERO
var last_floor_y: float = 0.0

@onready var gravity: float = ProjectSettings.get("physics/3d/default_gravity")
@onready var rigid_capsule_res: PackedScene = preload("res://RigidCapsule.tscn")

func _ready() -> void:
	update_stat_labels()
	if camera:
		camera_offset_pos = camera.position

func _process(delta: float) -> void:
	#region inputs
	if can_control:
		input_vec = Input.get_vector("left", "right", "up", "down")

		if Input.is_action_just_pressed("jump") and stamina >= jump_stamina:
			if is_on_floor():
				velocity.y = jump_height
				stamina -= jump_stamina
			elif double_jump_state == DoubleJumpState.READY and stamina >= double_jump_stamina:
				velocity.y = jump_height * double_jump_reduction_factor
				double_jump_state = DoubleJumpState.DONE
				stamina -= double_jump_stamina
			update_stamina_label()
		elif Input.is_action_just_pressed("dodge") and stamina >= dodge_stamina:
			var increased_speed: float = movement_speed + 1.0
			if absf(velocity.x) < increased_speed and absf(velocity.z) < increased_speed:
				if is_on_floor():
					velocity.x *= dodge_floor_speed
					velocity.z *= dodge_floor_speed
				else:
					velocity.x *= dodge_air_speed
					velocity.z *= dodge_air_speed
				stamina -= dodge_stamina
				update_stamina_label()
	#endregion inputs

	if stamina < max_stamina:
		stamina += stamina_refill_rate * delta
		if stamina > max_stamina:
			stamina = max_stamina
		update_stamina_label()

func _physics_process(delta: float) -> void:
	var lerp_speed: float = movement_lerp_speed * delta

	if is_on_floor():
		double_jump_state = DoubleJumpState.RESET
		if last_y_velocity != 0.0:
			if last_y_velocity < fall_damage_velocity:
				var damage: float = last_y_velocity / fall_damage_divisor
				if damage < fall_damage_threshold:
					damage = floorf(damage)
					hp += damage
					check_hp()
			last_y_velocity = 0.0
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

	if position.y < reset_at_y:
		position = Vector3.ZERO

	last_y_velocity = velocity.y
	move_and_slide()

	update_camera(delta)

# TODO: Replace kill function with proper game-over one day
func kill() -> void:
	velocity = Vector3.ZERO
	can_control = false
	visible = false
	gravity = 0.0
	set_collision_mask_value(1, false)
	set_collision_layer_value(1, false)

	var rigid_capsule: RigidBody3D = rigid_capsule_res.instantiate()
	rigid_capsule.position = position
	rigid_capsule.position.y += 1.7 / 2.0
	rigid_capsule.linear_velocity.y = randf_range(2.0, 6.0)
	rigid_capsule.angular_velocity = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
	get_parent_node_3d().add_child(rigid_capsule)

#region stat functions
func check_hp() -> void:
	if hp > max_hp:
		hp = max_hp
	elif hp < 0.0:
		hp = 0.0

	hp_label.text = "HP: %.0f/%.0f" % [roundf(hp), roundf(max_hp)]

	if hp == 0.0:
		kill()

func update_stamina_label() -> void:
	stamina_label.text = "Stamina: %.1f/%.0f" % [stamina, roundf(max_stamina)]
	stamina_label.text = stamina_label.text.replace(".0", "")

func update_stat_labels() -> void:
	check_hp()
	update_stamina_label()
	str_label.text = "STR: %.0f" % roundf(strength)
	def_label.text = "DEF: %.0f" % roundf(defence)
	exp_label.text = "EXP: %.0f/%.0f" % [roundf(experience), roundf(next_exp)]
	level_label.text = "Level: %d" % level
#endregion

func update_camera(delta: float) -> void:
	if camera:
		var lerp_speed: float = camera_lerp_speed * delta
		camera.position.x = lerpf(camera.position.x, position.x + camera_offset_pos.x, lerp_speed)
		camera.position.z = lerpf(camera.position.z, position.z + camera_offset_pos.z, lerp_speed)

		var cam_y_pos: float = camera.position.y - camera_offset_pos.y
		var cam_y_diff: float = absf(cam_y_pos - position.y)
		if is_on_floor() or cam_y_diff > camera_y_follow_distance or velocity.y < -jump_height:
			last_floor_y = position.y

		camera.position.y = lerpf(camera.position.y, last_floor_y + camera_offset_pos.y, lerp_speed * camera_y_lerp_factor)
