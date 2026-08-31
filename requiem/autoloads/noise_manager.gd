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
}
# Se dispara cada vez que se emite un ruido en el nivel.
# Cualquier listener (ej. EntityAI) se conecta a esta senal.
signal noise_emitted(noise_position: Vector2, radius: float, source_type: int, duration: float)
func emit_noise(noise_position: Vector2, radius: float, source_type: int, duration: float = 0.0) -> void:
	noise_emitted.emit(noise_position, radius, source_type, duration)
