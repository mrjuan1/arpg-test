extends Label

func _ready() -> void:
	_on_fps_timer_timeout()

func _on_fps_timer_timeout() -> void:
	var fps: float = Engine.get_frames_per_second()
	text = "FPS: %.0f" % fps
