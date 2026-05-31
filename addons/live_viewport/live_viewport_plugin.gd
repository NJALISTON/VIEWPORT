@tool
extends EditorPlugin

var panel_instance: Control

func _enter_tree() -> void:
	# Cargar la escena del panel ignorando la caché para forzar la recarga del archivo en disco
	var panel_scene = ResourceLoader.load("res://addons/live_viewport/live_viewport_panel.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if panel_scene:
		panel_instance = panel_scene.instantiate()
		# Asignar un nombre al nodo para que sirva de título en la pestaña del Dock
		panel_instance.name = "Live View 2D"
		# Añadirlo como panel acoplable (Dock) en la parte superior derecha por defecto
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, panel_instance)

func _exit_tree() -> void:
	if panel_instance:
		# Removerlo de los docks para limpiar
		remove_control_from_docks(panel_instance)
		panel_instance.queue_free()
