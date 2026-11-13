extends Node2D
## Draws La Amortajada with the entity-lab sprite sheets (tutorial/assets/art/entity, copied from
## entity-lab/art_drop/entity with the same folder layout), driven by the AI of its parent
## (tutorial/entity.gd). Frame numbers, timings, joins and head rules follow each clip's NOTES.md
## in entity-lab. Body and head are drawn only where a light lands (lit_material, light layer 3);
## the scream and ear effects ignore lighting, so the player feels them in the dark.
##
## AI state -> clip: PATROL moving = walk, PATROL still = idle, listening = listen,
## scream hold = hunt_start, HUNT moving = pursuit, HUNT/SEARCH still = feel,
## SEARCH moving = scuttle, caught = catch (play_catch).

## Placeholder sound names from the clip JSONs, at the moment they should play.
signal cue(sound_name: String)
## Catch: the hands are under the cloth (catch.json hide_player).
signal hide_player

const COLS := ["l70", "l55", "l35", "l15", "c0", "r15", "r35", "r55", "r70"]
const EAR_ROW := {"c0": 0, "r35": 1, "r15": 2, "l35": 3, "l15": 4}
## Sheet key -> [file under ART_DIR, hframes, vframes].
const SHEETS := {
	"idle": ["idle/idle_sheet.png", 12, 1],
	"idle_twist_left": ["idle/idle_twist_left_sheet.png", 12, 1],
	"idle_twist_right": ["idle/idle_twist_right_sheet.png", 12, 1],
	"walk": ["walk/walk_sheet.png", 13, 4],
	"listen": ["listen_v2/listen_sheet.png", 9, 6],
	"hunt_start": ["hunt_start/hunt_start_sheet.png", 13, 2],
	"pursuit": ["pursuit/pursuit_sheet.png", 13, 2],
	"scuttle": ["scuttle/scuttle_sheet.png", 13, 4],
	"feel": ["feel/feel_sheet.png", 13, 5],
	"joins": ["feel/joins_sheet.png", 13, 5],
	"catch": ["catch/catch_sheet.png", 13, 2],
	"head_zones": ["head_zones/head_sheet.png", 9, 1],
	"head_listen": ["listen_v2/head_listen_sheet.png", 10, 4],
	"head_hunt": ["hunt_start/head_hunt_sheet.png", 9, 5],
	"head_pursuit": ["pursuit/head_pursuit_sheet.png", 9, 2],
	"head_quiet": ["scuttle/head_quiet_sheet.png", 9, 2],
	"scream_back": ["hunt_start/scream_vfx_back_sheet.png", 7, 4],
	"scream_front": ["hunt_start/scream_vfx_front_sheet.png", 7, 4],
	"ear_vfx": ["ear_vfx/ear_vfx_sheet.png", 15, 5],
}
const DATA := {
	"idle": "idle/idle.json",
	"walk": "walk/walk.json",
	"zones": "head_zones/head_zones.json",
	"listen": "listen_v2/listen.json",
	"hunt": "hunt_start/hunt_start.json",
	"pursuit": "pursuit/pursuit.json",
	"scuttle": "scuttle/scuttle.json",
	"feel": "feel/feel.json",
	"catch": "catch/catch.json",
}

## Folder that holds idle/, walk/, listen_v2/... (same layout as entity-lab/art_drop/entity).
const ART_DIR := "res://tutorial/assets/art/entity"

## Light-only material: the entity is drawn only where a light lands on it.
@export var lit_material: Material
## Spring stiffness of the body turn: it eases toward its heading, never at a constant speed.
@export var turn_stiffness := 70.0

var load_errors: PackedStringArray = []
## Clip on screen: idle, walk, listen, hunt_start, pursuit, scuttle, feel, catch.
var mode := ""
## World heading of the body. The art faces down the screen (PI/2).
var heading := PI * 0.5
var body_sheet := ""
var body_frame := 0
var head_sheet := ""
var head_frame := 0
var aim := "c0"

var _ok := false
var _entity
var _tex := {}
var _d := {}
var _zone_index := {}
var _listen_index := {}
var _body: Sprite2D
var _head: Sprite2D
var _scream_back: Sprite2D
var _scream_front: Sprite2D
var _ear: Sprite2D
var _turn_vel := 0.0
var _turn_to := NAN
var _last_pos := Vector2.ZERO
var _moved := 0.0
var _queue: Array = []
var _step_left := 0.0
var _want := ""
var _want_ms := 0.0
## Free clock (ms) for tremble and roll: never reset by a body loop.
var _clock := 0.0
## Time (ms) in the current clip phase, the previous value (for sound crossings) and the loop frame.
var _t := 0.0
var _prev := -1.0
var _i := 0
var _dist := 0.0
var _head_off := Vector2.ZERO
var _head_roll := 0.0
# Idle look / walk glance.
var _look_wait := 0.0
var _look_t := -1.0
var _look_keys: Array = []
# Listen.
var _phase := ""
var _tl: Dictionary = {}
var _pending_aim := ""
var _bridge := ""
# Face column for hunt start and pursuit, with the 50 ms middle pose on two-zone jumps.
var _col := 4
var _col_target := 4
var _col_mid := 0.0
# Feel.
var _feel_clock := 0.0
var _pat_name := ""
var _pat_on := false
var _pat_k := 0
var _pat_t := 0.0
var _pat_wait := 0.0
# Effects.
var _scream_t := -1.0
var _ear_t := -1.0
var _ear_first := 0
var _ear_count := 0


func _ready() -> void:
	_entity = get_parent()
	scale = Vector2(0.5, 0.5)
	z_index = 1
	_scream_back = _sprite("ScreamBack", true)
	_body = _sprite("Body", false)
	_head = _sprite("Head", false)
	_ear = _sprite("EarVfx", true)
	_scream_front = _sprite("ScreamFront", true)
	for sprite in [_body, _head]:
		sprite.material = lit_material
		sprite.light_mask = 4
	_ok = _load_art()
	if not _ok:
		for line in load_errors:
			push_error("[EntitySpriteRig] " + line)
		return
	_set_sheet(_scream_back, "scream_back")
	_set_sheet(_scream_front, "scream_front")
	_set_sheet(_ear, "ear_vfx")
	_entity.heard_noise.connect(_on_heard)
	reset()


func is_ready() -> bool:
	return _ok


func reset() -> void:
	if not _ok:
		return
	_queue.clear()
	_step_left = 0.0
	heading = PI * 0.5
	_turn_vel = 0.0
	_turn_to = NAN
	_last_pos = _entity.global_position
	_scream_t = -1.0
	_ear_t = -1.0
	_scream_back.hide()
	_scream_front.hide()
	_ear.hide()
	_want = ""
	_begin("idle", "")
	_tick_idle(0.0)
	rotation = heading - PI * 0.5


## Review only: false draws body and head unlit (true sprite colours, no light needed).
func set_lit(on: bool) -> void:
	for sprite in [_body, _head]:
		sprite.material = lit_material if on else null
		sprite.light_mask = 4 if on else 1


func play_catch(target: Vector2) -> void:
	if not _ok:
		return
	_queue.clear()
	_step_left = 0.0
	mode = "catch"
	_t = 0.0
	_prev = -1.0
	# The one turn outside Scuttle: face the player on the first key; the 40 ms burst hides it.
	var to: Vector2 = target - _entity.global_position
	if to.length() > 1.0:
		heading = to.angle()
	_turn_vel = 0.0
	rotation = heading - PI * 0.5
	_scream_t = -1.0
	_ear_t = -1.0
	_scream_back.hide()
	_scream_front.hide()
	_ear.hide()
	_tick_catch(0.0)


func describe() -> String:
	return "clip %s · body %s #%d · head %s #%d · aim %s" % [mode, body_sheet, body_frame, head_sheet, head_frame, aim]


# ------------------------------------------------------------------ loading ---

func _load_art() -> bool:
	for key in SHEETS:
		var path: String = ART_DIR.path_join(SHEETS[key][0])
		var texture := load(path) as Texture2D
		if texture == null:
			load_errors.append("missing sheet " + path)
			continue
		_tex[key] = texture
	for key in DATA:
		var path: String = ART_DIR.path_join(DATA[key])
		var json := load(path) as JSON
		if json == null or not json.data is Dictionary:
			load_errors.append("missing or broken " + path)
			continue
		_d[key] = json.data
	if not load_errors.is_empty():
		return false
	for pose in _d.zones.poses:
		_zone_index[pose.name] = int(pose.index)
	for pose in _d.listen.head_poses:
		_listen_index[pose.name] = int(pose.index)
	return true


func _sprite(node_name: String, unshaded: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	if unshaded:
		# Effects ignore lighting, so the player feels them even when the entity is unseen.
		var unshaded_material := CanvasItemMaterial.new()
		unshaded_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite.material = unshaded_material
		sprite.hide()
	add_child(sprite)
	return sprite


func _set_sheet(sprite: Sprite2D, key: String) -> void:
	sprite.frame = 0
	sprite.texture = _tex[key]
	sprite.hframes = SHEETS[key][1]
	sprite.vframes = SHEETS[key][2]


func _show_body(sheet: String, frame: int) -> void:
	if sheet != body_sheet:
		body_sheet = sheet
		_set_sheet(_body, sheet)
	body_frame = frame
	_body.frame = frame


func _show_head(sheet: String, frame: int, offset := Vector2.ZERO, roll_deg := 0.0) -> void:
	if sheet != head_sheet:
		head_sheet = sheet
		_set_sheet(_head, sheet)
	head_frame = frame
	_head.frame = frame
	# Offsets are art pixels; the rig is scaled 0.5, so its local space is art pixels.
	_head.position = offset
	_head.rotation_degrees = roll_deg


# --------------------------------------------------------------------- loop ---

func _process(delta: float) -> void:
	if not _ok:
		return
	if not is_visible_in_tree():
		_last_pos = _entity.global_position
		return
	var ms := delta * 1000.0
	_clock += ms
	_moved = _entity.global_position.distance_to(_last_pos)
	_last_pos = _entity.global_position
	if _moved > 64.0:
		_moved = 0.0
	_tick_effects(ms)
	_update_heading(delta)
	if mode == "catch":
		_tick_catch(ms)
		return
	var want := _wanted()
	if want != _want:
		_want = want
		_want_ms = 0.0
	else:
		_want_ms += ms
	# Reacting always wins: a sound cuts a locomotion start short.
	if want == "listen" and mode != "listen" and not _queue.is_empty():
		_queue.clear()
		_step_left = 0.0
	if _run_queue(ms):
		return
	if want != mode and (_want_ms >= 80.0 or want == "listen" or want == "hunt_start"):
		_transition(mode, want)
		if _run_queue(0.0):
			return
	match mode:
		"idle": _tick_idle(ms)
		"walk": _tick_walk(ms)
		"listen": _tick_listen(ms)
		"hunt_start": _tick_hunt(ms)
		"pursuit": _tick_pursuit(ms)
		"scuttle": _tick_scuttle(ms)
		"feel": _tick_feel(ms)


func _wanted() -> String:
	if _entity.is_screaming():
		return "hunt_start"
	if _entity.is_listening():
		return "listen"
	var moving: bool = _entity.velocity.length() > 4.0
	match _entity.get_state_name():
		"HUNT":
			return "pursuit" if moving else "feel"
		"SEARCH", "INVESTIGATE":
			return "scuttle" if moving else "feel"
	return "walk" if moving else "idle"


## The body turns only while it moves (and toward a sound behind it while it listens or screams);
## never during Idle or Feel, where the planted feet would spin on the floor.
func _update_heading(delta: float) -> void:
	var target := heading
	match mode:
		"walk", "pursuit", "scuttle":
			if _entity.velocity.length() > 4.0:
				target = _entity.velocity.angle()
		"listen", "hunt_start":
			if not is_nan(_turn_to):
				target = _turn_to
	var error := angle_difference(heading, target)
	_turn_vel += (turn_stiffness * error - 2.0 * sqrt(turn_stiffness) * _turn_vel) * delta
	heading = wrapf(heading + _turn_vel * delta, -PI, PI)
	rotation = heading - PI * 0.5


# --------------------------------------------------------------- transitions ---

func _step(sheet: String, frame: int, ms: float, h_sheet := "", h_frame := 0, h_off := Vector2.ZERO, h_roll := 0.0, sound := "") -> void:
	_queue.append({"s": sheet, "f": frame, "ms": ms, "hs": h_sheet, "hf": h_frame, "ho": h_off, "hr": h_roll, "cue": sound})


func _run_queue(ms: float) -> bool:
	_step_left -= ms
	while _step_left <= 0.0:
		if _queue.is_empty():
			_step_left = 0.0
			return false
		var step: Dictionary = _queue.pop_front()
		if step.s != "":
			_show_body(step.s, step.f)
		if step.hs != "":
			_show_head(step.hs, step.hf, step.ho, step.hr)
		if step.cue != "":
			cue.emit(step.cue)
		_step_left += step.ms
	return true


## Leave the current clip through its own exit (a halt, a join), reach a hub pose (rest = idle_00,
## crouch = feel loop 0), then enter the next clip through its entry. All from the NOTES.
func _transition(from: String, to: String) -> void:
	_queue.clear()
	_step_left = 0.0
	if from == "listen":
		_ear_t = -1.0
		_ear.hide()
	var alert := to in ["listen", "hunt_start", "pursuit"]
	var hub := "rest"
	match from:
		"walk":
			_walk_halt(alert)
		"scuttle":
			if to == "feel":
				_scuttle_settle()
				hub = "crouch"
			else:
				_scuttle_halt()
		"pursuit":
			if to in ["feel", "scuttle"]:
				_pursuit_crouch(_i)
				hub = "crouch"
			else:
				_pursuit_halt()
		"hunt_start":
			if to == "pursuit":
				hub = "launch"
			else:
				# Launched but nowhere to run (it was already on the sound): lunge, then feel.
				_pursuit_start()
				_pursuit_crouch(int(_d.pursuit.start.next_loop_frame))
				hub = "crouch"
		"listen":
			if to == "hunt_start":
				hub = "listen"
			else:
				_listen_release()
		"feel":
			if _i == 0 and not _pat_on and to == "scuttle":
				hub = "crouch"
			elif _i == 0 and not _pat_on and to in ["idle", "walk"]:
				_feel_rise()
			else:
				_feel_startle(_pat_f())
	match to:
		"idle":
			if hub == "crouch":
				_feel_rise()
		"walk":
			if hub == "crouch":
				_feel_rise()
			_walk_start()
		"scuttle":
			if hub == "crouch":
				_feel_to_scuttle()
			else:
				_scuttle_start()
		"pursuit":
			if hub == "crouch":
				_feel_startle(0)
			_pursuit_start()
		"listen":
			if hub == "crouch":
				_feel_startle(0)
			elif from in ["idle", ""]:
				# Reaction delay (50-100 ms); walk and scuttle use their halt instead.
				_step(body_sheet, body_frame, randf_range(50.0, 100.0))
		"hunt_start":
			if hub == "crouch":
				_feel_startle(0)
	_begin(to, from)


func _begin(to: String, from: String) -> void:
	mode = to
	_t = 0.0
	_prev = -1.0
	_i = 0
	_dist = 0.0
	_turn_to = NAN
	match to:
		"idle":
			_look_t = -1.0
			_look_wait = randf_range(1500.0, 4000.0)
		"walk":
			_i = int(_d.walk.start.then_loop_frame)
			_look_t = -1.0
			_look_wait = randf_range(3000.0, 6000.0)
		"scuttle":
			_i = int(_d.scuttle.start_from_rest.next_loop_frame)
		"pursuit":
			_i = int(_d.pursuit.start.next_loop_frame)
			_col_target = _face_col()
		"feel":
			_pat_name = ""
			_pat_on = false
			_pat_wait = randf_range(2500.0, 5000.0)
		"listen":
			aim = _aim_now()
			_phase = "enter"
			_tl = _d.listen.enter[aim]
			_pending_aim = ""
			_ear_play(aim, false)
		"hunt_start":
			_bridge = ""
			if from == "listen":
				_bridge = "front" if aim == "c0" else ("left" if aim.begins_with("r") else "right")
			_col_target = _face_col()
			_col = _col_target
			_col_mid = 0.0


func _walk_halt(alert: bool) -> void:
	var halt: Array = _d.walk.halt.frames_from_loop_frame[str(_i)]
	var ms: float = _d.walk.halt.ms_alert if alert else _d.walk.halt.ms_calm
	for frame in halt:
		_step("walk", int(frame), ms, "head_zones", _zone_index["c0"])


func _walk_start() -> void:
	for key in _d.walk.start.frames:
		_step("walk", int(key.index), key.ms, "head_zones", _zone_index["c0"])


func _scuttle_start() -> void:
	for key in _d.scuttle.start_from_rest.keys:
		_step("scuttle", int(key.body), key.ms, "head_quiet", int(key.head_row) * 9 + 4, _vec(key.head_offset))


func _scuttle_halt() -> void:
	var halt: Array = _d.scuttle.halt_to_rest.from_loop_frame[str(_i)]
	var offsets := [Vector2(0, 3), Vector2(0, 1)]
	for n in halt.size():
		_step("scuttle", int(halt[n]), _d.scuttle.halt_to_rest.ms, "head_quiet", 4, offsets[n])


func _scuttle_settle() -> void:
	for frame in [26 + 2 * _i, 27 + 2 * _i]:
		_step("feel", frame, 60.0, "head_quiet", 4, Vector2(0, 7))


func _pursuit_start() -> void:
	for key in _d.pursuit.start.keys:
		var sheet := "head_hunt" if str(key.head_sheet).begins_with("head_hunt") else "head_pursuit"
		_step("pursuit", int(key.body), key.ms, sheet, int(key.head_row) * 9 + _col, _vec(key.head_offset), key.head_roll_deg)


func _pursuit_halt() -> void:
	var halt: Array = _d.pursuit.halt.from_loop_frame[str(_i)]
	var ms: float = _d.pursuit.halt.ms
	_step("pursuit", int(halt[0]), ms, "head_pursuit", _col, (_head_off * 0.5).round(), roundf(_head_roll / 6.0) * 3.0)
	_step("pursuit", int(halt[1]), ms, "head_hunt", _col)


func _pursuit_crouch(loop_frame: int) -> void:
	_step("joins", 3 * loop_frame, 60.0, "head_pursuit", _col, (_head_off * 0.5).round(), roundf(_head_roll / 6.0) * 3.0)
	_step("joins", 3 * loop_frame + 1, 60.0, "head_quiet", 4, Vector2(0, 5))
	_step("joins", 3 * loop_frame + 2, 60.0, "head_quiet", 4, Vector2(0, 7))


func _feel_startle(loop_frame: int) -> void:
	_step("joins", 33 + 2 * loop_frame, 60.0, "head_quiet", 4, Vector2(0, 3))
	_step("joins", 34 + 2 * loop_frame, 60.0, "head_quiet", 4, Vector2(0, 1))


func _feel_rise() -> void:
	var rise: Dictionary = _d.feel.feel.rise_to_rest
	for n in rise.frames.size():
		_step("feel", int(rise.frames[n]), rise.ms, "head_quiet", 4, _vec(rise.head_offsets[n]), 0.0, "exhale" if n == 0 else "")


func _feel_to_scuttle() -> void:
	var join: Dictionary = _d.feel.feel.to_scuttle
	for frame in join.frames:
		_step("feel", int(frame), join.ms, "head_quiet", 4, Vector2(0, 7))


func _listen_release() -> void:
	var tl: Dictionary = _d.listen.release[aim]
	var keys: Array = tl.keys
	for n in keys.size():
		var end: float = keys[n + 1].t_ms if n + 1 < keys.size() else tl.length_ms
		_step("listen", int(keys[n].body), end - keys[n].t_ms, "head_listen", _listen_index.get(keys[n].head, 0), Vector2.ZERO, 0.0, "exhale" if n == 0 else "")


## A pat replaces loop frame 0 (left) or 6 (right); a startle during a pat uses that frame.
func _pat_f() -> int:
	if _pat_on:
		return int(_d.feel.feel[_pat_name].replaces_loop_frame)
	return _i


# --------------------------------------------------------------------- clips ---

func _tick_idle(ms: float) -> void:
	var idle: Dictionary = _d.idle
	var frames: Array = idle.frames
	_t += ms
	while _t >= frames[_i].ms:
		_t -= frames[_i].ms
		_i = (_i + 1) % frames.size()
		for sound in idle.sound_frames:
			if int(sound.index) == _i:
				cue.emit(sound.name)
	var pose := "c0"
	var body_set := "idle"
	var look: Dictionary = idle.head_look
	var key = _look_tick(ms, look.keys, look.length_ms, 1500.0, 4000.0)
	if key != null:
		pose = key.pose
		body_set = key.body
	# Swap body sets at the same frame index; the clock keeps running.
	_show_body(body_set, _i)
	_show_head("head_zones", _zone_index[pose])


func _tick_walk(ms: float) -> void:
	var walk: Dictionary = _d.walk
	# Feet stay planted: the loop advances with the distance travelled, not with time.
	_dist += _moved
	var px: float = walk.ground_art_px_per_frame * scale.x
	while _dist >= px:
		_dist -= px
		_i = (_i + 1) % walk.loop.frames.size()
		for sound in walk.sound_frames:
			if int(sound.index) == _i:
				cue.emit(sound.name)
	var pose := "c0"
	var body_set := "walk"
	var glance: Dictionary = walk.head_glance
	if _look_t < 0.0 and _look_keys.is_empty():
		_look_keys = glance.right if randf() < 0.5 else glance.left
	var key = _look_tick(ms, _look_keys, glance.length_ms, 3000.0, 6000.0)
	if key != null:
		pose = key.pose
		body_set = key.body
	elif _look_t < 0.0:
		_look_keys = []
	_show_body("walk", _i + int(walk.loop.set_offset[body_set]))
	_show_head("head_zones", _zone_index[pose])


## Random look/glance timeline: wait, play the keys, wait again. Returns the current key or null.
func _look_tick(ms: float, keys: Array, length: float, wait_min: float, wait_max: float):
	if _look_t < 0.0:
		_look_wait -= ms
		if _look_wait > 0.0:
			return null
		_look_t = 0.0
	else:
		_look_t += ms
	if _look_t >= length:
		_look_t = -1.0
		_look_wait = randf_range(wait_min, wait_max)
		return null
	return _key_at(keys, _look_t)


func _tick_listen(ms: float) -> void:
	var from_t := _prev
	_t += ms
	_prev = _t
	if _phase == "hold":
		var hold: Dictionary = _d.listen.hold[aim]
		var every: float = hold.twitch_every_ms
		var head_name: String = hold.head
		if _t >= every and fmod(_t, every) < hold.twitch_ms:
			head_name = hold.twitch_head
		if from_t >= 0.0 and int(from_t / every) != int(_t / every):
			_ear_play(aim, true)
		_show_body("listen", int(hold.body))
		_show_head("head_listen", _listen_index.get(head_name, 0))
		return
	var key := _key_at(_tl.keys, _t)
	_show_body("listen", int(key.body))
	_show_head("head_listen", _listen_index.get(key.head, 0))
	_cues(_tl.get("sounds", []), from_t, _t)
	if _t >= _tl.length_ms:
		if _pending_aim != "" and _pending_aim != aim:
			_reaim(_pending_aim)
		else:
			_phase = "hold"
			_t = 0.0
			_prev = 0.0


func _reaim(new_aim: String) -> void:
	var timeline := "%s>%s" % [aim, new_aim]
	_pending_aim = ""
	aim = new_aim
	_t = 0.0
	_prev = -1.0
	if _d.listen.reaim.has(timeline):
		_tl = _d.listen.reaim[timeline]
		_phase = "reaim"
	else:
		_phase = "hold"


func _tick_hunt(ms: float) -> void:
	var hunt: Dictionary = _d.hunt
	var from_t := _prev
	_t += ms
	_prev = _t
	var frames: Array = hunt.frames
	var current: Dictionary = frames[frames.size() - 1]
	for frame in frames:
		if frame.t_ms <= _t:
			current = frame
		else:
			break
	var body := int(current.index)
	if _bridge != "" and body < 2:
		body = int(hunt.bridge_from_listen[_bridge][body])
	_show_body("hunt_start", body)
	_tick_col(ms)
	_show_head("head_hunt", int(current.head_row) * 9 + _col)
	_cues(hunt.sounds, from_t, _t)
	var vfx_at: float = hunt.vfx.starts_at_ms
	if from_t < vfx_at and _t >= vfx_at:
		_scream_t = 0.0
		var degrees := (4 - _col) * 17.5
		_scream_back.rotation_degrees = degrees
		_scream_front.rotation_degrees = degrees


func _tick_pursuit(ms: float) -> void:
	var run: Dictionary = _d.pursuit
	_dist += _moved
	var px: float = run.speed.art_px_per_frame * scale.x
	while _dist >= px:
		_dist -= px
		_i = (_i + 1) % run.loop.frames.size()
		for sound in run.loop.sounds:
			if int(sound.frame) == _i:
				cue.emit(sound.name)
	_show_body("pursuit", _i)
	# The face keeps facing the sound while the body comes round to it (it ends on c0 when the
	# body runs straight at the sound). 5 degrees of hysteresis stop flicker on path corners.
	_col_target = _face_col_sticky()
	_tick_col(ms)
	var motion: Dictionary = run.head_motion
	var row := int(_clock / motion.tremble_every_ms) % 2
	var rolls: Array = motion.roll_deg
	_head_off = _vec(motion.offset_px_by_loop_frame[str(_i)])
	_head_roll = rolls[int(_clock / motion.roll_every_ms) % rolls.size()]
	_show_head("head_pursuit", row * 9 + _col, _head_off, _head_roll)


func _tick_scuttle(ms: float) -> void:
	var run: Dictionary = _d.scuttle
	_dist += _moved
	var px: float = run.speed.art_px_per_frame * scale.x
	while _dist >= px:
		_dist -= px
		_i = (_i + 1) % run.loop.frames.size()
		for sound in run.loop.sounds:
			if int(sound.frame) == _i:
				cue.emit(sound.name)
	_show_body("scuttle", _i)
	var motion: Dictionary = run.head_motion
	var step := int(_clock / run.loop.ms)
	var scan: Array = motion.search_scan
	var rolls: Array = motion.roll_deg
	var col_name: String = scan[step % scan.size()] if _entity.get_state_name() == "SEARCH" else "c0"
	var row := int(_i / 2.0) % 2
	_show_head("head_quiet", row * 9 + COLS.find(col_name), _vec(motion.offset_px_by_loop_frame[str(_i)]), rolls[step % rolls.size()])


func _tick_feel(ms: float) -> void:
	var feel: Dictionary = _d.feel.feel
	var loop: Dictionary = feel.loop
	_feel_clock += ms
	if _pat_on:
		var pat: Dictionary = feel[_pat_name]
		_pat_t += ms
		while _pat_on and _pat_t >= pat.ms[_pat_k]:
			_pat_t -= pat.ms[_pat_k]
			_pat_k += 1
			if _pat_k >= pat.frames.size():
				_pat_on = false
				_pat_name = ""
				_i = int(pat.then_loop_frame)
				_t = 0.0
				_pat_wait = randf_range(3000.0, 6000.0)
			else:
				_pat_cues(pat)
		if _pat_on:
			_show_body("feel", int(pat.frames[_pat_k]))
			# The ear goes to the hand: hold the pat's head, no roll. The clock keeps running.
			_show_head("head_quiet", _tremble(130.0) * 9 + COLS.find(pat.head), Vector2(0, 7))
			return
	_t += ms
	while _t >= loop.ms:
		_t -= loop.ms
		_i = (_i + 1) % loop.frames.size()
		for sound in loop.sounds:
			if int(sound.frame) == _i:
				cue.emit(sound.name)
		if _pat_name != "" and _i == int(feel[_pat_name].replaces_loop_frame):
			_pat_on = true
			_pat_k = 0
			_pat_t = 0.0
			_pat_cues(feel[_pat_name])
			_tick_feel(0.0)
			return
	if _pat_name == "":
		_pat_wait -= ms
		if _pat_wait <= 0.0:
			_pat_name = "pat_left" if randf() < 0.5 else "pat_right"
	_show_body("feel", _i)
	var clock: Array = _d.feel.head_motion.clock
	var total := 0.0
	for entry in clock:
		total += entry.ms
	var at := fmod(_feel_clock, total)
	var current: Dictionary = clock[0]
	for entry in clock:
		current = entry
		if at < entry.ms:
			break
		at -= entry.ms
	_show_head("head_quiet", _tremble(130.0) * 9 + COLS.find(current.pose), _vec(_d.feel.head_motion.offset), current.roll_deg)


func _pat_cues(pat: Dictionary) -> void:
	for sound in pat.sounds:
		if int(sound.frame) == int(pat.frames[_pat_k]):
			cue.emit(sound.name)


func _tick_catch(ms: float) -> void:
	var catch_data: Dictionary = _d.catch
	var from_t := _prev
	_t += ms
	_prev = _t
	var length: float = catch_data.length_ms
	if _t < length:
		var key := _key_at(catch_data.keys, _t)
		_show_body("catch", int(key.body))
		_show_head("head_pursuit", int(key.head_row) * 9 + 4, _vec(key.head_offset))
	else:
		# Stillness: the body holds, only the head sinks and tilts. Stay on the last step.
		var still: Dictionary = catch_data.stillness
		var at := _t - length
		var current: Dictionary = still.keys[still.keys.size() - 1]
		for key in still.keys:
			if at < key.ms:
				current = key
				break
			at -= key.ms
		_show_body("catch", int(still.body))
		_show_head("head_pursuit", int(current.head_row) * 9 + 4, _vec(current.head_offset), current.head_roll_deg)
	_cues(catch_data.sounds, from_t, _t)
	var hide_at: float = catch_data.hide_player.t_ms
	if from_t < hide_at and _t >= hide_at:
		hide_player.emit()


# --------------------------------------------------------------------- heads ---

## Signed angle (degrees) from the body facing to the last sound. Positive is clockwise in Godot,
## which for a creature drawn facing down is screen left: the "l" poses (head_zones/NOTES.md).
func _sound_diff() -> float:
	var to: Vector2 = _entity.last_heard_position - _entity.global_position
	if to.length() < 2.0:
		return 0.0
	return rad_to_deg(angle_difference(heading, to.angle()))


## 0 centre, 1 the 35 zone, 2 the 70 zone, signed (+ = l side); 99 behind (over 110 degrees).
func _zone() -> int:
	var diff := _sound_diff()
	var size := absf(diff)
	if size >= 110.0:
		return 99
	var zone := 0 if size < 20.0 else (1 if size < 55.0 else 2)
	return zone if diff >= 0.0 else -zone


func _turn_to_sound() -> void:
	_turn_to = (_entity.last_heard_position - _entity.global_position).angle()


## Face column (hunt start, pursuit): the face turns TO the sound.
func _face_col() -> int:
	var zone := _zone()
	if zone == 99:
		_turn_to_sound()
		return 4
	return 4 - 2 * zone


## Like _face_col, but keeps the current zone until the sound is 5 degrees past its edge.
func _face_col_sticky() -> int:
	var diff := _sound_diff()
	var zone := int((4 - _col_target) / 2.0)
	var edges: Array = [[-20.0, 20.0], [20.0, 55.0], [55.0, 110.0]][absi(zone)]
	var along := diff if zone >= 0 else -diff
	if zone == 0 and absf(diff) < 25.0:
		return _col_target
	if zone != 0 and along > edges[0] - 5.0 and along < edges[1] + 5.0:
		return _col_target
	return _face_col()


## Listen aim: the ear turns to the sound, so the head turns AWAY from it (listen/NOTES.md).
func _aim_now() -> String:
	var zone := _zone()
	if zone == 99:
		_turn_to_sound()
		return "c0"
	match zone:
		1: return "r35"
		2: return "r15"
		-1: return "l35"
		-2: return "l15"
	return "c0"


func _tick_col(ms: float) -> void:
	if _col == _col_target:
		return
	if _col_mid > 0.0:
		_col_mid -= ms
		if _col_mid <= 0.0:
			_col = _col_target
		return
	if absi(_col_target - _col) >= 4:
		_col = int((_col + _col_target) / 2.0)
		_col_mid = 50.0
	else:
		_col = _col_target


func _on_heard(_at: Vector2, _source: int) -> void:
	match mode:
		"listen":
			var new_aim := _aim_now()
			_ear_play(new_aim, false)
			if new_aim == aim:
				if _phase == "hold":
					_t = 0.0
					_prev = 0.0
			elif _phase == "hold":
				_reaim(new_aim)
			else:
				_pending_aim = new_aim
		"hunt_start", "pursuit":
			_col_target = _face_col()


func _tremble(every_ms: float) -> int:
	return int(_clock / every_ms) % 2


# ------------------------------------------------------------------- effects ---

func _ear_play(ear_aim: String, pulse: bool) -> void:
	_ear_t = 0.0
	_ear_first = int(EAR_ROW.get(ear_aim, 0)) * 15 + (10 if pulse else 0)
	_ear_count = 5 if pulse else 10


func _tick_effects(ms: float) -> void:
	if _scream_t >= 0.0:
		var frame := int(_scream_t / 50.0)
		if frame >= 26:
			_scream_t = -1.0
			_scream_back.hide()
			_scream_front.hide()
		else:
			_scream_back.frame = frame
			_scream_front.frame = frame
			_scream_back.show()
			_scream_front.show()
			_scream_t += ms
	if _ear_t >= 0.0:
		var frame := int(_ear_t / 50.0)
		if frame >= _ear_count:
			_ear_t = -1.0
			_ear.hide()
		else:
			_ear.frame = _ear_first + frame
			_ear.show()
			_ear_t += ms


# ------------------------------------------------------------------- helpers ---

func _key_at(keys: Array, t: float) -> Dictionary:
	var found: Dictionary = keys[0]
	for key in keys:
		if key.t_ms <= t:
			found = key
		else:
			break
	return found


func _cues(sounds: Array, from_t: float, to_t: float) -> void:
	for sound in sounds:
		if sound.t_ms > from_t and sound.t_ms <= to_t:
			cue.emit(sound.name)


func _vec(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])
