extends CharacterBody3D

enum CharacterType { NONE, PLAYER, ENEMY }
enum DoubleJumpState { RESET, READY, DONE }
enum BehaviourAction {
	NONE = 0,
	MOVE = 1,
	PURSUE,
	PREPARE_ATTACK,
	PERFORM_ATTACK
}

#region exports
@export var character_type: CharacterType = CharacterType.NONE

@export_group("Stats")
@export_subgroup("HP")
@export var hp: float = 5.0
@export var max_hp: float = 5.0
@export_subgroup("Stamina")
@export var stamina: float = 3.0
@export var max_stamina: float = 3.0
@export var stamina_refill_rate: float = 2.0
@export_subgroup("Combat")
@export var strength: float = 2.0
@export var defence: float = 1.0
@export_subgroup("EXP")
@export var experience: float = 0.0
@export var next_exp: float = 100.0
@export var level: int = 1
@export_subgroup("Stats FX")
@export var mesh: MeshInstance3D
@export var albedo_lerp_speed: float = 5.0
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
@export var rotation_lerp_speed: float = 10.0
@export var gravity_multiplier: float = 2.0
@export var air_movement_dampening: float = 0.1
@export var air_rotation_dampening: float = 0.5
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

@export_group("Behaviour (non-player)")
@export var behaviour_timer: Timer
@export var detection_area: Area3D
@export var navigation_agent: NavigationAgent3D
@export var ray: RayCast3D
#endregion exports

#region variables
const HALF_PI: float = PI / 2.0
# TODO: Move below to exports?
const MIN_DODGE_VELOCITY: float = 0.1
const MAX_DODGE_VELOCITY_OFFSET: float = 1.0

var input_vec: Vector2 = Vector2.ZERO
var double_jump_state: DoubleJumpState = DoubleJumpState.RESET
var last_y_velocity: float = 0.0
var camera_offset_pos: Vector3 = Vector3.ZERO
var last_floor_y: float = 0.0
var behaviour_action: BehaviourAction = BehaviourAction.NONE
var target_last_position: Vector3 = Vector3.ZERO
var attack_velocity: Vector3 = Vector3.ZERO
var has_attacked: bool = false

var target_character: CharacterBody3D
var detection_debug_material: StandardMaterial3D
var detection_debug_target_colour: Color

@onready var gravity: float = ProjectSettings.get("physics/3d/default_gravity")
@onready var target_y_rotation: float = rotation.y
@onready var material: StandardMaterial3D = (mesh.mesh as PrimitiveMesh).material
@onready var original_albedo: Color = material.albedo_color
# TODO: Remove one day, temporary for kill function lower down
@onready var rigid_capsule_res: PackedScene = preload("res://RigidCapsule.tscn")
#endregion variables

func _ready() -> void:
	update_stat_labels()
	if camera:
		camera_offset_pos = camera.position

	if character_type != CharacterType.PLAYER:
		behaviour_action = randi_range(BehaviourAction.NONE, BehaviourAction.MOVE) as BehaviourAction

		if behaviour_timer:
			# TODO: Move wait time range to exports
			behaviour_timer.wait_time = randf_range(2.0, 4.0)
			behaviour_timer.connect("timeout", _on_behaviour_timer_timeout)
			behaviour_timer.start()

		if detection_area:
			detection_area.connect("body_entered", _on_detection_area_body_entered)
			detection_area.connect("body_exited", _on_detection_area_body_exited)

			var detection_area_children: Array[Node] = detection_area.get_children()
			for child: Node in detection_area_children:
				if child is MeshInstance3D:
					var detection_mesh: PrimitiveMesh = (child as MeshInstance3D).mesh
					detection_debug_material = detection_mesh.material
					detection_debug_target_colour = detection_debug_material.albedo_color

			set_detection_debug_colour()

		if navigation_agent:
			navigation_agent.connect("target_reached", _on_navigation_agent_target_reached)

func _process(delta: float) -> void:
	#region inputs
	if character_type == CharacterType.PLAYER:
		input_vec = Input.get_vector("left", "right", "up", "down")
		if input_vec:
			target_y_rotation = -input_vec.angle() + HALF_PI

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
			var abs_vel_x: float = absf(velocity.x)
			var abs_vel_z: float = absf(velocity.z)
			var increased_speed: float = movement_speed + MAX_DODGE_VELOCITY_OFFSET
			if (abs_vel_x > MIN_DODGE_VELOCITY and abs_vel_x < increased_speed) or (abs_vel_z > MIN_DODGE_VELOCITY and abs_vel_z < increased_speed):
				if is_on_floor():
					velocity.x *= dodge_floor_speed
					velocity.z *= dodge_floor_speed
				else:
					velocity.x *= dodge_air_speed
					velocity.z *= dodge_air_speed
					velocity.y = 0.0
				stamina -= dodge_stamina
				update_stamina_label()
		elif Input.is_action_just_pressed("attack"):
			pass
	#endregion inputs
	else:
		if target_character and behaviour_action < BehaviourAction.PURSUE:
			var target_velocity: Vector3 = target_character.velocity.abs()
			# TODO: Move min detection velocity to exports
			if target_velocity.x > 0.1 or target_velocity.z > 0.1:
				behaviour_timer.stop()
				behaviour_action = BehaviourAction.PURSUE
				input_vec = Vector2.ZERO

				set_detection_debug_colour()

		match behaviour_action:
			BehaviourAction.NONE:
				input_vec = Vector2.ZERO
			BehaviourAction.MOVE:
				input_vec = Vector2.from_angle(-target_y_rotation + HALF_PI)
			BehaviourAction.PURSUE:
				pursue_target()
			BehaviourAction.PREPARE_ATTACK:
				# TODO: Export prepare attack velocity reverse factor
				input_vec = -Vector2(attack_velocity.x, attack_velocity.z) * 0.5
			BehaviourAction.PERFORM_ATTACK:
				if not has_attacked and ray and ray.is_colliding():
					var chartype_prop: Variant = ray.get_collider().get("character_type")
					var char_type: CharacterType = chartype_prop
					if char_type == CharacterType.PLAYER:
						var damage: float = strength - target_character.defence
						if damage > 0.0:
							target_character.change_hp(-damage)
							has_attacked = true

	if stamina < max_stamina:
		stamina += stamina_refill_rate * delta
		if stamina > max_stamina:
			stamina = max_stamina
		update_stamina_label()

func _physics_process(delta: float) -> void:
	var mov_lerp_speed: float = movement_lerp_speed * delta
	var rot_lerp_speed: float = rotation_lerp_speed * delta

	if is_on_floor():
		double_jump_state = DoubleJumpState.RESET
		if last_y_velocity != 0.0:
			if last_y_velocity < fall_damage_velocity:
				var damage: float = last_y_velocity / fall_damage_divisor
				if damage < fall_damage_threshold:
					damage = floorf(damage)
					change_hp(damage)
			last_y_velocity = 0.0
	else:
		mov_lerp_speed *= air_movement_dampening
		rot_lerp_speed *= air_rotation_dampening

		velocity.y -= gravity * gravity_multiplier * delta
		if double_jump_state == DoubleJumpState.RESET and absf(velocity.y) < velocity_for_double_jump:
			double_jump_state = DoubleJumpState.READY

	rotation.y = lerp_angle(rotation.y, target_y_rotation, rot_lerp_speed)

	if input_vec:
		var movement: Vector2 = input_vec * movement_speed
		velocity.x = lerpf(velocity.x, movement.x, mov_lerp_speed)
		velocity.z = lerpf(velocity.z, movement.y, mov_lerp_speed)
	else:
		velocity.x = lerpf(velocity.x, 0.0, mov_lerp_speed)
		velocity.z = lerpf(velocity.z, 0.0, mov_lerp_speed)

	if position.y < reset_at_y:
		position = Vector3.ZERO
	last_y_velocity = velocity.y

	material.albedo_color = lerp(material.albedo_color, original_albedo, albedo_lerp_speed * delta)
	if detection_debug_material:
		# TODO: Export detection colour lerp speed?
		detection_debug_material.albedo_color = lerp(detection_debug_material.albedo_color, detection_debug_target_colour, 5.0 * delta)

	move_and_slide()
	update_camera(delta)

func _on_behaviour_timer_timeout() -> void:
	if behaviour_action < BehaviourAction.PURSUE:
		var last_action: BehaviourAction = behaviour_action
		while behaviour_action == last_action:
			behaviour_action = randi_range(BehaviourAction.NONE, BehaviourAction.MOVE) as BehaviourAction

		if behaviour_action == BehaviourAction.MOVE:
			target_y_rotation = randf_range(0.0, TAU)

		# TODO: Integrate exported wait range here too
		behaviour_timer.wait_time = randf_range(2.0, 4.0)
	elif behaviour_action == BehaviourAction.PREPARE_ATTACK:
		# TODO: Export attack lunge speed?
		velocity = attack_velocity * 20.0
		behaviour_action = BehaviourAction.PERFORM_ATTACK
	elif behaviour_action == BehaviourAction.PERFORM_ATTACK:
		if target_character:
			var last_rotation: Vector3 = rotation
			look_at(target_character.position)
			target_y_rotation = rotation.y + PI
			rotation = last_rotation
			attack_velocity = (target_character.position - position).normalized()
			attack_velocity.y = 0.0
			behaviour_action = BehaviourAction.PREPARE_ATTACK
		else:
			# TODO: Change to observe behaviour and wait a bit once implemented
			behaviour_action = BehaviourAction.NONE
		has_attacked = false

	set_detection_debug_colour()

func _on_detection_area_body_entered(body: Node3D) -> void:
	if character_type == CharacterType.ENEMY and not target_character:
		var chartype_prop: Variant = body.get("character_type")
		if chartype_prop:
			var char_type: CharacterType = chartype_prop
			if char_type == CharacterType.PLAYER:
				target_character = body

func _on_detection_area_body_exited(_body: Node3D) -> void:
	if character_type == CharacterType.ENEMY and target_character:
		target_character = null

func _on_navigation_agent_target_reached() -> void:
	input_vec = Vector2.ZERO
	target_last_position = Vector3.ZERO

	if target_character and behaviour_action == BehaviourAction.PURSUE:
		behaviour_action = BehaviourAction.PREPARE_ATTACK
		attack_velocity = (target_character.position - position).normalized()
		attack_velocity.y = 0.0
		# TODO: Export prepare attack time
		behaviour_timer.wait_time = 0.5
	else:
		# TODO: Change to observe behaviour and wait a bit once implemented
		behaviour_action = BehaviourAction.NONE
	behaviour_timer.start()

	set_detection_debug_colour()

# TODO: Replace kill function with proper game-over one day
func kill() -> void:
	velocity = Vector3.ZERO
	character_type = CharacterType.NONE
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
func change_hp(amount: float) -> void:
	var last_hp: float = hp
	hp += amount
	check_hp()

	# TODO: Replace damage effect one day
	if hp < last_hp:
		material.albedo_color = Color(1.0, 0.0, 0.0)

func check_hp() -> void:
	if hp > max_hp:
		hp = max_hp
	elif hp < 0.0:
		hp = 0.0

	if hp_label:
		hp_label.text = "HP: %.0f/%.0f" % [roundf(hp), roundf(max_hp)]

	if hp == 0.0:
		kill()

func update_stamina_label() -> void:
	if stamina_label:
		stamina_label.text = "Stamina: %.1f/%.0f" % [stamina, roundf(max_stamina)]
		stamina_label.text = stamina_label.text.replace(".0", "")

func update_stat_labels() -> void:
	check_hp()
	update_stamina_label()

	if str_label:
		str_label.text = "STR: %.0f" % roundf(strength)

	if def_label:
		def_label.text = "DEF: %.0f" % roundf(defence)

	if exp_label:
		exp_label.text = "EXP: %.0f/%.0f" % [roundf(experience), roundf(next_exp)]

	if level_label:
		level_label.text = "Level: %d" % level
#endregion stat functions

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

func pursue_target() -> void:
	if target_character:
		target_last_position = target_character.position

	if target_last_position:
		navigation_agent.target_position = target_last_position
		var next_pos: Vector3 = navigation_agent.get_next_path_position()
		var last_rotation: Vector3 = rotation
		look_at(next_pos)
		target_y_rotation = rotation.y + PI
		rotation = last_rotation
		input_vec = Vector2.from_angle(-target_y_rotation + HALF_PI).normalized()

func set_detection_debug_colour() -> void:
	if detection_debug_material:
		match behaviour_action:
			BehaviourAction.NONE:
				detection_debug_target_colour = Color.WHITE
			BehaviourAction.MOVE:
				detection_debug_target_colour = Color.AQUAMARINE
			BehaviourAction.PURSUE:
				detection_debug_target_colour = Color.ORANGE
			BehaviourAction.PREPARE_ATTACK:
				detection_debug_target_colour = Color.DEEP_PINK
			BehaviourAction.PERFORM_ATTACK:
				detection_debug_target_colour = Color.RED
		detection_debug_target_colour.a = 0.25
