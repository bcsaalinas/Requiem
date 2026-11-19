extends Node
## The one script that changes the mix.
##
## It never moves a bus volume: those belong to the player's volume sliders (Preferences) and to
## the pause menu. It owns one gain stage ("MixGain") and, on the buses that may be muffled, one
## low-pass ("MixMuffle"), and everything a moment asks of the mix goes through them.
##
## Other scripts ask by name: duck() or focus() to move a bus level, muffle() to dull a bus,
## release() when the moment is over. Each request has a priority. On every bus the request with
## the highest priority decides; when it ends, the next one down takes over. Changes are faded.
##
## Muffling is only ever applied to Music, Ambience and World (AudioBus.MUFFLEABLE): never to
## the entity, never to Viv's body.

## Who wins when two moments want the same bus. Higher wins.
enum Priority { THREAT = 10, PRAYER = 20, BREATH = 30, SCREAM = 40 }

const GAIN_NAME := "MixGain"
const MUFFLE_NAME := "MixMuffle"

## name -> { priority, order, gains: {bus: dB}, cutoffs: {bus: Hz}, holder: weakref or null }
var _requests := {}
## "gain/Music", "cutoff/World"... -> { now, from, to, time, length }
var _moves := {}
var _gains := {}
var _muffles := {}
var _order := 0
var _set_up := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()


## Makes sure every bus and every effect of the layout exists (default_bus_layout.tres has
## them; this is the safety net), and sets the effects from sound_settings.tres, which is where
## their numbers live. Safe to call more than once and before _ready.
func ensure_buses() -> void:
	if _set_up:
		return
	var settings := SoundSettings.current()
	var added := false
	for bus_name in AudioBus.ALL:
		if AudioServer.get_bus_index(bus_name) < 0:
			var index := AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, AudioBus.MASTER)
			added = true
	if added:
		# A bus made here has to pick up the player's volume sliders; those are not ours to set.
		Preferences.apply_volumes()
	var limiter := _effect(AudioBus.MASTER, "AudioEffectHardLimiter") as AudioEffectHardLimiter
	limiter.ceiling_db = settings.limiter_ceiling_db
	_room(AudioBus.ENTITY, settings.entity_reverb_room, settings.entity_reverb_damping, settings.entity_reverb_wet)
	var far := _effect(AudioBus.ENTITY_FAR, "AudioEffectLowPassFilter") as AudioEffectLowPassFilter
	far.cutoff_hz = settings.far_cutoff_hz
	_room(AudioBus.ENTITY_FAR, settings.far_reverb_room, settings.far_reverb_damping, settings.far_reverb_wet)
	for bus_name in AudioBus.MIXABLE:
		_gains[bus_name] = _effect(bus_name, "AudioEffectAmplify", GAIN_NAME)
	for bus_name in AudioBus.MUFFLEABLE:
		_muffles[bus_name] = _effect(bus_name, "AudioEffectLowPassFilter", MUFFLE_NAME)
		(_muffles[bus_name] as AudioEffectLowPassFilter).cutoff_hz = settings.open_hz
	_set_up = true


## Lowers (or raises) bus levels: gains_db is { bus name: dB }. Calling it again with the same
## name changes the request. `holder`, if given, is the node the request belongs to: the request ends when it leaves the scene.
func duck(request: StringName, priority: int, gains_db: Dictionary, fade := 0.0, holder: Node = null) -> void:
	_ask(request, priority, gains_db, {}, fade, holder)


## Brings bus levels forward. The same as duck(), named for what it is used for.
func focus(request: StringName, priority: int, gains_db: Dictionary, fade := 0.0, holder: Node = null) -> void:
	_ask(request, priority, gains_db, {}, fade, holder)


## Dulls buses: cutoffs_hz is { bus name: Hz }. Buses that may not be muffled are left out;
## returns false if any was asked for.
func muffle(request: StringName, priority: int, cutoffs_hz: Dictionary, fade := 0.0, holder: Node = null) -> bool:
	var allowed := {}
	for bus_name in cutoffs_hz:
		if AudioBus.MUFFLEABLE.has(StringName(bus_name)):
			allowed[StringName(bus_name)] = float(cutoffs_hz[bus_name])
	_ask(request, priority, {}, allowed, fade, holder)
	return allowed.size() == cutoffs_hz.size()


## Ends a request. What it held goes to the next request down, or back to rest, over `fade`.
func release(request: StringName, fade := 0.0) -> void:
	if not _requests.has(request):
		return
	var old: Dictionary = _requests[request]
	_requests.erase(request)
	_retarget(old.gains.keys(), old.cutoffs.keys(), fade)


func is_active(request: StringName) -> bool:
	return _requests.has(request)


## The level the mix adds to a bus right now, in dB (0 at rest).
func gain_db(bus_name: StringName) -> float:
	var key := "gain/%s" % bus_name
	return _moves[key].now if _moves.has(key) else 0.0


## The cutoff of a bus right now, in Hz (open_hz at rest; buses that are never muffled too).
func cutoff_hz(bus_name: StringName) -> float:
	var key := "cutoff/%s" % bus_name
	return pow(2.0, _moves[key].now) if _moves.has(key) else SoundSettings.current().open_hz


## The low-pass this director drives on a bus (null for buses that are never muffled).
## For tests and read-outs: nothing else may change it.
func muffle_filter(bus_name: StringName) -> AudioEffectLowPassFilter:
	ensure_buses()
	return _muffles.get(bus_name)


func _process(delta: float) -> void:
	for request in _requests.keys():
		var holder: WeakRef = _requests[request].holder
		if holder != null and holder.get_ref() == null:
			release(request, SoundSettings.current().orphan_fade)
	for key in _moves:
		var move: Dictionary = _moves[key]
		if move.now == move.to:
			continue
		move.time += delta
		var t := clampf(move.time / move.length, 0.0, 1.0) if move.length > 0.0 else 1.0
		move.now = move.to if t >= 1.0 else lerpf(move.from, move.to, t)
		_apply(key, move.now)


func _ask(request: StringName, priority: int, gains: Dictionary, cutoffs: Dictionary, fade: float, holder: Node) -> void:
	ensure_buses()
	var touched_gains := gains.keys()
	var touched_cutoffs := cutoffs.keys()
	var order := _order + 1
	if _requests.has(request):
		# Asking again changes the request; it keeps its place among requests of equal priority.
		touched_gains.append_array(_requests[request].gains.keys())
		touched_cutoffs.append_array(_requests[request].cutoffs.keys())
		order = _requests[request].order
	_order = maxi(_order, order)
	var kept := {}
	for bus_name in gains:
		if AudioBus.MIXABLE.has(StringName(bus_name)):
			kept[StringName(bus_name)] = float(gains[bus_name])
	_requests[request] = {"priority": priority, "order": order, "gains": kept, "cutoffs": cutoffs,
		"holder": weakref(holder) if holder != null else null}
	_retarget(touched_gains, touched_cutoffs, fade)


## Works out what each touched bus should be now and starts moving there.
func _retarget(gain_buses: Array, cutoff_buses: Array, fade: float) -> void:
	for bus_name in gain_buses:
		_move_to("gain/%s" % bus_name, _winner("gains", bus_name, 0.0), fade)
	for bus_name in cutoff_buses:
		# Cutoffs move in octaves, so a fade sounds even from open to shut.
		_move_to("cutoff/%s" % bus_name, _winner("cutoffs", bus_name, SoundSettings.current().open_hz), fade)


func _winner(what: String, bus_name: StringName, rest: float) -> float:
	var best: Dictionary = {}
	for request in _requests.values():
		if request[what].has(bus_name) and (best.is_empty() or request.priority > best.priority \
				or (request.priority == best.priority and request.order > best.order)):
			best = request
	return best[what][bus_name] if not best.is_empty() else rest


func _move_to(key: String, target: float, fade: float) -> void:
	var cutoff := key.begins_with("cutoff/")
	if not _moves.has(key):
		var rest := _scale(SoundSettings.current().open_hz, true) if cutoff else 0.0
		_moves[key] = {"now": rest, "from": rest, "to": rest, "time": 0.0, "length": 0.0}
	var move: Dictionary = _moves[key]
	var to := _scale(target, cutoff)
	# Already on its way there: only a faster fade changes anything.
	if is_equal_approx(move.to, to) and fade >= move.length - move.time:
		return
	move.from = move.now
	move.to = to
	move.time = 0.0
	move.length = maxf(fade, 0.0)
	if fade <= 0.0:
		move.now = to
		_apply(key, to)


func _apply(key: String, value: float) -> void:
	var bus_name := StringName(key.get_slice("/", 1))
	if key.begins_with("cutoff/"):
		(_muffles[bus_name] as AudioEffectLowPassFilter).cutoff_hz = pow(2.0, value)
	else:
		(_gains[bus_name] as AudioEffectAmplify).volume_db = value


func _scale(value: float, cutoff: bool) -> float:
	return log(value) / log(2.0) if cutoff else value


## The effect of a class on a bus (and with a given name, if any); added when it is missing.
func _effect(bus_name: StringName, effect_class: String, effect_name := "") -> AudioEffect:
	var bus := AudioServer.get_bus_index(bus_name)
	for slot in AudioServer.get_bus_effect_count(bus):
		var found := AudioServer.get_bus_effect(bus, slot)
		if found.is_class(effect_class) and found.resource_name == effect_name:
			return found
	var effect: AudioEffect = ClassDB.instantiate(effect_class)
	effect.resource_name = effect_name
	AudioServer.add_bus_effect(bus, effect)
	return effect


func _room(bus_name: StringName, room: float, damping: float, wet: float) -> void:
	var settings := SoundSettings.current()
	var reverb := _effect(bus_name, "AudioEffectReverb") as AudioEffectReverb
	reverb.room_size = room
	reverb.damping = damping
	reverb.wet = wet
	reverb.dry = 1.0
	reverb.predelay_msec = settings.reverb_predelay_ms
	reverb.predelay_feedback = 0.0
	reverb.spread = settings.reverb_spread
	reverb.hipass = settings.reverb_hipass
