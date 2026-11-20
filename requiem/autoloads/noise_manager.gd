extends Node
# NoiseManager (Autoload / Singleton global)
#
# Al registrarlo como Autoload en Project Settings, cualquier script
# puede llamarlo directo escribiendo "NoiseManager.emit_noise(...)"
# sin buscar instancia ni checar null.
#
# Este script SOLO avisa que hubo un ruido (posicion, radio, tipo).
# No reproduce audio el mismo: cada mecanica (pasos, respiracion,
# rezar) es responsable de reproducir su propio sonido real ademas
# de llamar a emit_noise(), para que la entidad pueda "escucharlo".
enum SourceType {
	FOOTSTEP,
	SPRINT,
	CROUCH,
	BREATH,
	PRAY,
	THROW,
	CANDLE,
	ENVIRONMENT,
	DOOR,
	FLASHLIGHT,
}
# Se dispara cada vez que se emite un ruido en el nivel.
# Cualquier listener (ej. EntityAI) se conecta a esta senal.
signal noise_emitted(noise_position: Vector2, radius: float, source_type: int, duration: float)

## Who made the noise that is being sent right now (null: Viv or the world). Only valid inside
## a noise_emitted callback. A listener that made the noise itself ignores it: the entity never
## hears its own doors, or anything else it sets off.
var current_emitter: Node = null


## `emitter`: the node that made the noise, when it is something that also listens (the entity).
## The signal keeps its four arguments, so no listener has to change.
func emit_noise(noise_position: Vector2, radius: float, source_type: int, duration: float = 0.0, emitter: Node = null) -> void:
	var outer := current_emitter
	current_emitter = emitter
	noise_emitted.emit(noise_position, radius, source_type, duration)
	current_emitter = outer
