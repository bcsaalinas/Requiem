extends Node
## The one script that changes the mix.
##
## It never moves a bus volume: those belong to the player's volume sliders (Preferences) and to
## the pause menu. It owns one gain stage ("MixGain") and, on the buses that may be muffled, one
## low-pass ("MixMuffle"), and everything a moment asks of the mix goes through them.
##
## Other scripts ask by name: duck() or focus() to move a bus level, muffle() to dull a bus,
## follow() for a level that drifts all the time, release() when the moment is over. Each request has a priority. On every bus the request with
## the highest priority decides; when it ends, the next one down takes over. Changes are faded.
##
## Muffling is only ever applied to Music, Ambience and World (AudioBus.MUFFLEABLE): never to
## the entity, never to Viv's body.
##
## Two requests are its own. The mood of the house (Dread.threat, and Dread.presence for an
## entity that is near without knowing): as it rises, Ambience and World pull back and Viv's
## body comes forward, so she hears herself. And death: on the game
## over screen Music, Ambience and World fall silent.

## Who wins when two moments want the same bus. Higher wins.
## LISTEN is the soft low-pass of holding her breath; BREATH (running out of air) takes it
## further on the buses it muffles.
enum Priority { THREAT = 10, PRAYER = 20, LISTEN = 25, BREATH = 30, SCREAM = 40, DEATH = 50 }

const GAIN_NAME := "MixGain"
const MUFFLE_NAME := "MixMuffle"
## The request that follows the mood of the house.
const THREAT_MIX := &"threat"
## The request that silences the house on the game over screen.
const DEATH_MIX := &"death"

## name -> { priority, order, gains: {bus: dB}, cutoffs: {bus: Hz}, holder: weakref or null,
##           drifting: true for a follow() request }
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
	Dread.threat_changed.connect(_on_mood_changed)
	Dread.presence_changed.connect(_on_mood_changed)
	GameState.player_died.connect(_on_player_died)
	GameState.state_reset.connect(_on_state_reset)


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


## A level that drifts all the time (the mood of the house): call it every time the value moves.
## The bus goes straight to the new value, unless a fade is already bringing the bus to this
## request (a stronger one just ended, say): then that fade is kept, never cut short.
func follow(request: StringName, priority: int, gains_db: Dictionary) -> void:
	_ask(request, priority, gains_db, {}, 0.0, null, true)


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


## The level a bus is heading for, in dB: where gain_db() will be once its fade is over.
func target_db(bus_name: StringName) -> float:
	var key := "gain/%s" % bus_name
	return _moves[key].to if _moves.has(key) else 0.0


## The cutoff of a bus right now, in Hz (open_hz at rest; buses that are never muffled too).
func cutoff_hz(bus_name: StringName) -> float:
	var key := "cutoff/%s" % bus_name
	return pow(2.0, _moves[key].now) if _moves.has(key) else SoundSettings.current().open_hz


## The low-pass this director drives on a bus (null for buses that are never muffled).
## For tests and read-outs: nothing else may change it.
func muffle_filter(bus_name: StringName) -> AudioEffectLowPassFilter:
	ensure_buses()
	return _muffles.get(bus_name)


## How far the world has receded (0..1): the stronger of what it knows (threat) and how near
## it is (presence, at a share of its full effect).
func recede() -> float:
	return maxf(Dread.threat, Dread.presence * SoundSettings.current().presence_world_share)


## The mood of the house: Ambience and World recede with it, Viv's body comes forward.
func _on_mood_changed(_value := 0.0) -> void:
	var amount := recede()
	if amount <= 0.0:
		release(THREAT_MIX)
		return
	var settings := SoundSettings.current()
	var world: float = settings.threat_world_db * amount
	follow(THREAT_MIX, Priority.THREAT, {AudioBus.AMBIENCE: world, AudioBus.WORLD: world,
		AudioBus.BODY: settings.threat_body_db * amount})


## The game over screen: the house falls silent. What the entity is still sounding is left to
## ring out.
func _on_player_died() -> void:
	var settings := SoundSettings.current()
	_ask(DEATH_MIX, Priority.DEATH, {AudioBus.MUSIC: settings.death_duck_db, AudioBus.AMBIENCE: settings.death_duck_db,
		AudioBus.WORLD: settings.death_duck_db}, {}, settings.death_fade, null)


func _on_state_reset() -> void:
	release(DEATH_MIX, SoundSettings.current().death_release)


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


func _ask(request: StringName, priority: int, gains: Dictionary, cutoffs: Dictionary, fade: float, holder: Node,
		drifting := false) -> void:
	ensure_buses()
	var touched_gains := gains.keys()
	var touched_cutoffs := cutoffs.keys()
	var order := _order + 1
	if _requests.has(request):
		# Asking again changes the request; it keeps its place among requests of equal priority.
		# Buses it no longer asks for are handed back.
		for bus_name in _requests[request].gains:
			if not touched_gains.has(bus_name):
				touched_gains.append(bus_name)
		for bus_name in _requests[request].cutoffs:
			if not touched_cutoffs.has(bus_name):
				touched_cutoffs.append(bus_name)
		order = _requests[request].order
	_order = maxi(_order, order)
	var kept := {}
	for bus_name in gains:
		if AudioBus.MIXABLE.has(StringName(bus_name)):
			kept[StringName(bus_name)] = float(gains[bus_name])
	_requests[request] = {"priority": priority, "order": order, "gains": kept, "cutoffs": cutoffs,
		"holder": weakref(holder) if holder != null else null, "drifting": drifting}
	_retarget(touched_gains, touched_cutoffs, fade, request)


## Works out what each touched bus should be now and starts moving there. `asker` is the
## request that just changed (none when one ended).
func _retarget(gain_buses: Array, cutoff_buses: Array, fade: float, asker := &"") -> void:
	for bus_name in gain_buses:
		_move_to("gains", bus_name, fade, asker)
	for bus_name in cutoff_buses:
		_move_to("cutoffs", bus_name, fade, asker)


## The name of the request that decides a bus (&"" when no request wants it).
func _winner(what: String, bus_name: StringName) -> StringName:
	var best := &""
	for request: StringName in _requests:
		var candidate: Dictionary = _requests[request]
		if not candidate[what].has(bus_name):
			continue
		var held: Dictionary = _requests[best] if best != &"" else {}
		if best == &"" or candidate.priority > held.priority \
				or (candidate.priority == held.priority and candidate.order > held.order):
			best = request
	return best


## Starts moving a bus to what its winning request asks for (or to rest, with none).
func _move_to(what: String, bus_name: StringName, fade: float, asker: StringName) -> void:
	var cutoff := what == "cutoffs"
	var key := ("cutoff/%s" if cutoff else "gain/%s") % bus_name
	# Cutoffs move in octaves, so a fade sounds even from open to shut.
	var rest := _scale(SoundSettings.current().open_hz, true) if cutoff else 0.0
	if not _moves.has(key):
		_moves[key] = {"now": rest, "from": rest, "to": rest, "time": 0.0, "length": 0.0}
	var move: Dictionary = _moves[key]
	var owner := _winner(what, bus_name)
	var to: float = _scale(_requests[owner][what][bus_name], cutoff) if owner != &"" else rest
	var left: float = maxf(move.length - move.time, 0.0) if move.now != move.to else 0.0
	# A drifting request that decides this bus and has just moved its own value (follow()).
	var drifting: bool = asker != &"" and asker == owner and _requests[owner].drifting
	if is_equal_approx(move.to, to):
		# Already on its way there. A request that does not decide this bus changes nothing,
		# nor does a drifting one; otherwise only a faster fade changes anything.
		if (asker != &"" and asker != owner) or drifting or fade >= left:
			return
	elif drifting:
		# The value moved a little: the fade that is bringing the bus to it goes on, to the
		# new value, and is never cut short.
		fade = maxf(fade, left)
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
