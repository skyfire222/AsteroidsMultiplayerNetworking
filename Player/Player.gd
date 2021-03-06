extends KinematicBody2D

var death_scene = preload("res://Player_Death/Player_Death.tscn")


onready var screen_size = get_viewport_rect().size
puppet var pos: Vector2 
puppet var rot = 0
var rot_speed = 10
var engine_speed = 400
var throw_speed = 600
var current_momentum = Vector2(0,0)
var player_color = Color.white
var has_asteroid = false
var throw_recoil = 25
var old_positon = 0
var last_delta = 0.02


# inputs:
remotesync var rot_right_input = 0
remotesync var rot_left_input = 0
remotesync var engine_input = 0
remotesync var grab_input = false




func _ready():
	self.modulate = player_color
	$rect.hide()
	
func _process(delta):
	old_positon = global_position
	if (name == String(get_tree().get_network_unique_id())):
		var right = int(Input.is_action_pressed("game_right"))
		var left =  int(Input.is_action_pressed("game_left"))
		var up = int(Input.is_action_pressed("game_up"))
		var space = Input.is_action_pressed("game_grab")

		
		rset_id(get_network_master(),"rot_right_input", right)
		rset_id(get_network_master(),"rot_left_input", left)
		rset_id(get_network_master(),"engine_input", up)
		rset_id(get_network_master(),"grab_input", space)
	if !is_network_master():
		position = pos
		rotation = rot
	last_delta = delta


func _physics_process(delta):
	if grab_input:
		$rect.show()
	else:
		$rect.hide()
	$Particles2D.emitting = bool(engine_input)
	if (is_network_master()):
		process_input(delta)

func process_input(delta):

	# manage rotation of self and asteroids
	$Asteroid_Holding_Position.rotation = rotation
	if rot_right_input:
		rotation += rot_speed * delta 
	if rot_left_input:
		rotation -= rot_speed * delta
	rset_unreliable("rot", rotation)

	# manage engines and thrust
	if (engine_speed < 0): # if recoil has been caused by throwing an asteroid.
		var current_movement = Vector2(0, -1)
		current_movement = current_movement.rotated(rotation).normalized() # create a rotation vector
		current_movement *= engine_speed * delta * throw_recoil # make the vector the right speed
		engine_speed = -engine_speed # don't go backward anymore
		current_momentum += current_movement * delta # add movement to current movement
	else:
		var current_movement = Vector2(0, -engine_input) 
		current_movement = current_movement.rotated(rotation).normalized()
		current_movement *= engine_speed * delta
		current_momentum += current_movement * delta # create movement vector
	# apply movement
	var collision = move_and_collide(current_momentum)
	if collision:
		process_collision(collision)
	screen_wrap()
	rset_unreliable("pos", position)
	
	# manage grabbing asteroids                        
	if grab_input and !has_asteroid: # bool flag has_asteroid prevents checking tons of times
		# raycast in front to grab asteroid
		var space_state = get_world_2d().direct_space_state
		var result = space_state.intersect_ray(self.position, self.position + $Laser_End.position.rotated(self.rotation), [self])
		if !result.empty():
			link_asteroid(result)
	elif has_asteroid and !grab_input:
		signal_emitter.emit_signal("not_grabbing", name, rotation, throw_speed) # release asteroid otherwise
		has_asteroid = false

func screen_wrap():
	position.x = wrapf(position.x, -50, screen_size.x+50)
	position.y = wrapf(position.y, -50, screen_size.y+50)


func link_asteroid(result):
	var collision = result["collider"]
	if(collision.is_in_group("throwable")):
		collision.grabbing_player_name = name
		collision.color = player_color
		has_asteroid = true


remotesync func _on_death():
	var death = death_scene.instance()
	death.dead_player = name
	death.position = position
	death.dead_color = player_color
	get_parent().add_child(death)
	queue_free()
	



func process_collision(collision):
	if (collision.collider.is_in_group("asteroid")):
		signal_emitter.emit_signal("not_grabbing", name, (global_position-old_positon).angle()  + PI/2, (global_position-old_positon).length() / last_delta)
		rpc("_on_death")
	else:
		current_momentum = current_momentum.slide(collision.normal)
	
