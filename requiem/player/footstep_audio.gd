extends Node
## Audible one-shots follow resolved foot plants. FootstepNoise independently
## owns the established AI-hearing cadence and never calls this presentation.
##
## What her steps sound like depends on what she walks on (`surface`). Each surface has its
## own sound set, the folder assets/audio/viv/steps_<surface>/. While that folder has no
## files, or no surface is known, the steps are the concrete bank set on FootstepNoise.

signal step_played(side: String, at: Vector2, mode: String, clip: AudioStream, pitch: float, gain_db: float)

## The sound set of a surface: "wood" is the folder assets/audio/viv/steps_wood/.
const STEP_SET := "viv/steps_%s"

@export var enabled := true
@export var sprint_gain_db := 2.5
@export var held_gain_db := -8.0
@export_range(0.0, 2.0) var gain_variation_db := 0.7

@onready var player: CharacterBody2D = get_parent()
@onready var appearance: Node2D = player.get_node("Appearance")
@onready var motion: Node = player.get_node("PlayerMotion")
@onready var footsteps: Node = player.get_node("FootstepNoise")
@onready var actions: Node = player.get_node("ActionState")

## What she is walking on (&"wood", &"forest"...). The level sets it; nothing here knows the
## levels. Empty: no surface known, the concrete bank.
var surface: StringName = &""
var played_steps := 0
## The set the last step came from ("viv/steps_wood"), or "" when it was the concrete bank.
var last_step_set := ""
var _voices: Array[AudioStreamPlayer2D] = []
var _voice_index := 0
var _previous_position := Vector2.ZERO
var _previous_contacts := {"left": false, "right": false}
var _last_clip: AudioStream
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 30
	_random.randomize()
	for index in range(3):
		var voice := AudioStreamPlayer2D.new()
		voice.name = "FootstepVoice%d" % index
		voice.bus = AudioBus.BODY
		add_child(voice)
		voice.set_as_top_level(true)
		_voices.append(voice)
	GameState.state_reset.connect(reset_audio)
	GameState.player_died.connect(reset_audio)
	reset_audio()


func reset_audio() -> void:
	for voice in _voices:
		voice.stop()
	_previous_position = player.global_position
	_remember_contacts(appearance.get_actor_lower_pose().get("contacts", {}))


func _physics_process(delta: float) -> void:
	var displacement := player.global_position - _previous_position
	_previous_position = player.global_position
	if not enabled or not actions.can_move() \
			or displacement.length() > Units.to_px(motion.teleport_reset_distance_u):
		reset_audio()
		return
	var lower: Dictionary = appearance.get_actor_lower_pose()
	var contacts: Dictionary = lower.get("contacts", {})
	var boots: Dictionary = lower.get("boots", {})
	var moving: bool = delta > 0.0 and displacement.length() > Units.to_px(footsteps.moving_threshold_u) * delta
	if moving and motion.enabled and motion.mode != "Idle":
		for side in ["left", "right"]:
			if bool(contacts.get(side, false)) and not bool(_previous_contacts[side]) and boots.has(side):
				_play_step(side, Vector2(boots[side]), motion.mode)
	# Normal stopping lets a short impact finish; gathering/pivots never add steps.
	_remember_contacts(contacts)


func _remember_contacts(contacts: Dictionary) -> void:
	for side in ["left", "right"]:
		_previous_contacts[side] = bool(contacts.get(side, false))


func _play_step(side: String, at: Vector2, mode: String) -> void:
	var clips: Array[AudioStream] = footsteps.sprint_clips if mode == "Sprint" else footsteps.walk_clips
	# A configured walk bank also supplies sprint until a dedicated bank is set.
	if clips.is_empty() and mode == "Sprint":
		clips = footsteps.walk_clips
	# The surface's own set replaces the bank in every gait, once its folder has files. An
	# empty bank means her steps are switched off (automated runs do this): they stay off.
	var step_set := ""
	if surface != &"" and not clips.is_empty():
		var surface_set := STEP_SET % surface
		var surface_clips := SoundLibrary.files(surface_set)
		if not surface_clips.is_empty():
			clips = surface_clips
			step_set = surface_set
	var candidates: Array[AudioStream] = []
	for clip in clips:
		if clip != null and clip != _last_clip:
			candidates.append(clip)
	if candidates.is_empty():
		for clip in clips:
			if clip != null: candidates.append(clip)
	if candidates.is_empty(): return
	var selected: AudioStream = candidates[_random.randi_range(0, candidates.size() - 1)]
	var voice := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	voice.stop()
	voice.global_position = at
	voice.stream = selected
	voice.pitch_scale = 1.0 + _random.randf_range(-footsteps.pitch_variation, footsteps.pitch_variation)
	var mode_gain := held_gain_db if mode == "Held breath" else (sprint_gain_db if mode == "Sprint" else 0.0)
	# A surface set can be trimmed like any other set (set_gain_db in the sound settings).
	var set_gain := SoundLibrary.gain_db(step_set) if step_set != "" else 0.0
	voice.volume_db = footsteps.volume_db + mode_gain + set_gain + _random.randf_range(-gain_variation_db, gain_variation_db)
	voice.play()
	_last_clip = selected
	last_step_set = step_set
	played_steps += 1
	step_played.emit(side, at, mode, selected, voice.pitch_scale, voice.volume_db)
