@tool
extends VBoxContainer

@onready var play_button: Button = %PlayButton
@onready var stop_button: Button = %StopButton
@onready var reset_button: Button = %ResetButton
@onready var status_label: Label = %StatusLabel
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var viewport: SubViewport = %Viewport

# Controles Premium de Zoom e Interruptores
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_label: Label = %ZoomLabel
@onready var scene_mode_button: Button = %SceneModeButton
@onready var grid_button: Button = %GridButton
@onready var coords_label: Label = %CoordsLabel
@onready var info_label: Label = %InfoLabel

# Nuevos Controles Científicos 2D/3D (Rulers, Fit, Capture)
@onready var fit_button: Button = %FitButton
@onready var screenshot_button: Button = %ScreenshotButton
@onready var left_ruler: Control = %LeftRuler
@onready var top_ruler: Control = %TopRuler

# Selector de Cámara de la Escena
@onready var camera_selector: OptionButton = %CameraSelector

@onready var aspect_ratio_container: AspectRatioContainer = %AspectRatioContainer
@onready var aspect_button: Button = %AspectButton

var active_scene_instance: Node = null
var watched_scene_root: Node = null
var debounce_timer: Timer = null
var plugin_instance: EditorPlugin = null

func set_plugin_instance(p_plugin: EditorPlugin) -> void:
	plugin_instance = p_plugin

# Estado Unificado 2D / 3D
var is_3d: bool = false

# ----------------- CONFIGURACIÓN DE MODO 2D -----------------
var debug_camera: Camera2D = null
var grid_overlay: Node2D = null

# ----------------- CONFIGURACIÓN DE MODO 3D -----------------
var debug_camera3d: Camera3D = null
var debug_light: DirectionalLight3D = null

# Coordenadas esféricas para cámara Orbital 3D
var rot_x: float = -0.5 # Pitch (Latitud)
var rot_y: float = 0.7  # Yaw (Longitud)
var distance: float = 8.0 # Radio (Distancia al pivot)
var pivot_pos: Vector3 = Vector3.ZERO # Centro del Foco de Órbita

var target_rot_x: float = -0.5
var target_rot_y: float = 0.7
var target_distance: float = 8.0
var target_pivot_pos: Vector3 = Vector3.ZERO

# ----------------- CONFIGURACIÓN DE CONTROL COMÚN -----------------
var is_dragging: bool = false
var last_mouse_pos: Vector2
var target_camera_pos: Vector2 = Vector2.ZERO
var target_camera_zoom: Vector2 = Vector2.ONE

# Clase interna para dibujar la cuadrícula técnica 2D de manera dinámica
class TechnicalGrid2D extends Node2D:
	var camera: Camera2D
	var show_grid: bool = true
	
	func _process(_delta: float) -> void:
		queue_redraw()
		
	func _draw() -> void:
		if not show_grid or not camera or not is_instance_valid(camera):
			return
			
		var cam_pos = camera.position
		var cam_zoom = camera.zoom
		var viewport_size = get_viewport().get_visible_rect().size
		
		# Límites del mundo visibles
		var size_in_world = viewport_size / cam_zoom
		var min_x = cam_pos.x - size_in_world.x / 2.0
		var max_x = cam_pos.x + size_in_world.x / 2.0
		var min_y = cam_pos.y - size_in_world.y / 2.0
		var max_y = cam_pos.y + size_in_world.y / 2.0
		
		# Ajustar el tamaño del grid según el zoom
		var grid_step = 100.0
		if cam_zoom.x < 0.25:
			grid_step = 800.0
		elif cam_zoom.x < 0.6:
			grid_step = 400.0
		elif cam_zoom.x > 3.0:
			grid_step = 25.0
			
		var grid_color := Color(0.4, 0.55, 0.7, 0.12)
		var axis_color_x := Color(0.9, 0.35, 0.35, 0.4) # Eje X Rojo
		var axis_color_y := Color(0.35, 0.85, 0.35, 0.4) # Eje Y Verde
		
		# Dibujar líneas verticales de la cuadrícula
		var start_x = floor(min_x / grid_step) * grid_step
		var end_x = ceil(max_x / grid_step) * grid_step
		for x in range(int(start_x), int(end_x) + 1, int(grid_step)):
			draw_line(Vector2(x, min_y), Vector2(x, max_y), grid_color, 1.0)
			
		# Dibujar líneas horizontales de la cuadrícula
		var start_y = floor(min_y / grid_step) * grid_step
		var end_y = ceil(max_y / grid_step) * grid_step
		for y in range(int(start_y), int(end_y) + 1, int(grid_step)):
			draw_line(Vector2(min_x, y), Vector2(max_x, y), grid_color, 1.0)
			
		# Dibujar ejes cartesianos principales
		draw_line(Vector2(-100000, 0), Vector2(100000, 0), axis_color_x, 1.5)
		draw_line(Vector2(0, -100000), Vector2(0, 100000), axis_color_y, 1.5)
		
		# Mira en el origen (0,0)
		draw_arc(Vector2.ZERO, 10.0 / cam_zoom.x, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.15), 1.0)

func _ready() -> void:
	# Activar bucle de procesamiento para interpolación suave de cámara
	set_process(true)
	
	if not play_button or not stop_button or not reset_button:
		return
		
	# Inicializar la UI con iconos nativos elegantes de Godot
	_setup_editor_icons()
	
	# Conexiones seguras de señales generales
	if play_button: _connect_signal_safe(play_button.pressed, _on_play_pressed)
	if stop_button: _connect_signal_safe(stop_button.pressed, _on_stop_pressed)
	if reset_button: _connect_signal_safe(reset_button.pressed, _on_reset_pressed)
	if zoom_in_button: _connect_signal_safe(zoom_in_button.pressed, _on_zoom_in_pressed)
	if zoom_out_button: _connect_signal_safe(zoom_out_button.pressed, _on_zoom_out_pressed)
	if grid_button: _connect_signal_safe(grid_button.toggled, _on_grid_toggled)
	if scene_mode_button: _connect_signal_safe(scene_mode_button.toggled, _on_scene_mode_toggled)
	if viewport_container: _connect_signal_safe(viewport_container.gui_input, _on_viewport_gui_input)
	
	# Conexiones de las nuevas herramientas científicas
	if fit_button: _connect_signal_safe(fit_button.pressed, _on_fit_pressed)
	if screenshot_button: _connect_signal_safe(screenshot_button.pressed, _on_screenshot_pressed)
	if left_ruler: _connect_signal_safe(left_ruler.draw, _on_left_ruler_draw)
	if top_ruler: _connect_signal_safe(top_ruler.draw, _on_top_ruler_draw)
	
	# Conexión del selector de cámara
	if camera_selector: _connect_signal_safe(camera_selector.item_selected, _on_camera_selected)
	
	# Conexiones para control de relación de aspecto
	if aspect_button: _connect_signal_safe(aspect_button.toggled, _on_aspect_toggled)
	if aspect_ratio_container: _connect_signal_safe(aspect_ratio_container.resized, _on_aspect_container_resized)
	
	# Conexión de señal de visibilidad para suspender el procesamiento
	_connect_signal_safe(visibility_changed, _on_visibility_changed)
	
	# Configurar estado inicial
	_update_ui_state(false)
	_update_coords_display(Vector2.ZERO, Vector2.ZERO)
	
	# Inicializar temporizador de actualización en caliente (debounce)
	debounce_timer = Timer.new()
	debounce_timer.name = "DebounceTimer"
	debounce_timer.one_shot = true
	debounce_timer.wait_time = 0.5
	add_child(debounce_timer)
	_connect_signal_safe(debounce_timer.timeout, _on_debounce_timeout)

func _process(delta: float) -> void:
	# Asegurar que el grid técnico siga a la cámara 2D activa en todo momento
	if not is_3d and grid_overlay and is_instance_valid(grid_overlay):
		grid_overlay.camera = _get_active_camera_2d()

	# Si usamos una cámara personalizada, actualizamos su telemetría y reglas en vivo
	if _is_using_custom_camera():
		if is_3d:
			var custom_cam = viewport.get_camera_3d()
			if custom_cam and is_instance_valid(custom_cam):
				_update_coords_display(Vector2.ZERO, Vector2.ZERO)
		else:
			var custom_cam = viewport.get_camera_2d()
			if custom_cam and is_instance_valid(custom_cam):
				# Obtener la posición del mouse local para calcular coordenadas del mundo
				var local_mouse = viewport_container.get_local_mouse_position()
				var world_mouse = (local_mouse - viewport.size / 2.0) / custom_cam.zoom + custom_cam.position
				_update_coords_display(custom_cam.position, world_mouse)
				_queue_redraw_rulers()
				# Actualizar dinámicamente el zoom real de la cámara de escena
				if zoom_label:
					var percentage = round(custom_cam.zoom.x * 100)
					zoom_label.text = str(percentage) + "%"
		return
		
	var t = clamp(15.0 * delta, 0.0, 1.0)
	
	if is_3d:
		# ----------------- ANIMACIÓN SUAVE CÁMARA 3D -----------------
		rot_x = lerp(rot_x, target_rot_x, t)
		rot_y = lerp(rot_y, target_rot_y, t)
		distance = lerp(distance, target_distance, t)
		pivot_pos = pivot_pos.lerp(target_pivot_pos, t)
		
		# Convertir de esféricas a cartesianas respecto al pivot
		var offset = Vector3(
			cos(rot_x) * sin(rot_y),
			sin(rot_x),
			cos(rot_x) * cos(rot_y)
		) * distance
		
		if debug_camera3d and is_instance_valid(debug_camera3d):
			debug_camera3d.position = pivot_pos + offset
			debug_camera3d.look_at(pivot_pos, Vector3.UP)
			_update_coords_display(Vector2(debug_camera3d.position.x, debug_camera3d.position.z), Vector2(pivot_pos.x, pivot_pos.z))
	else:
		# ----------------- ANIMACIÓN SUAVE CÁMARA 2D -----------------
		if debug_camera and is_instance_valid(debug_camera):
			var pos_changed = debug_camera.position.distance_to(target_camera_pos) > 0.05
			var zoom_changed = debug_camera.zoom.distance_to(target_camera_zoom) > 0.001
			
			if pos_changed:
				debug_camera.position = debug_camera.position.lerp(target_camera_pos, t)
			if zoom_changed:
				debug_camera.zoom = debug_camera.zoom.lerp(target_camera_zoom, t)
				# Garantía de seguridad absoluta de zoom positivo
				debug_camera.zoom.x = max(debug_camera.zoom.x, 0.05)
				debug_camera.zoom.y = max(debug_camera.zoom.y, 0.05)
				
			if pos_changed or zoom_changed:
				# Redibujar reglas de píxeles laterales y superiores en vivo
				_queue_redraw_rulers()

func _setup_editor_icons() -> void:
	if Engine.is_editor_hint():
		var editor_base = EditorInterface.get_base_control()
		if editor_base:
			if play_button: play_button.icon = editor_base.get_theme_icon("Play", "EditorIcons")
			if stop_button: stop_button.icon = editor_base.get_theme_icon("Stop", "EditorIcons")
			if reset_button: reset_button.icon = editor_base.get_theme_icon("CenterView", "EditorIcons")
			if zoom_out_button: zoom_out_button.icon = editor_base.get_theme_icon("ZoomLess", "EditorIcons")
			if zoom_in_button: zoom_in_button.icon = editor_base.get_theme_icon("ZoomMore", "EditorIcons")
			if grid_button: grid_button.icon = editor_base.get_theme_icon("Grid", "EditorIcons")
			
			# Iconos Premium
			if fit_button: fit_button.icon = editor_base.get_theme_icon("ToolFrameSelection", "EditorIcons")
			if screenshot_button: screenshot_button.icon = editor_base.get_theme_icon("Camera", "EditorIcons")
			if aspect_button: aspect_button.icon = editor_base.get_theme_icon("AspectRatio", "EditorIcons")
			
			# Configurar SceneModeButton con icono según el estado
			_update_scene_mode_button_icon()

func _update_scene_mode_button_icon() -> void:
	if Engine.is_editor_hint():
		var editor_base = EditorInterface.get_base_control()
		if editor_base and scene_mode_button:
			if scene_mode_button.button_pressed:
				scene_mode_button.icon = editor_base.get_theme_icon("Instance", "EditorIcons")
				scene_mode_button.text = "Escena Activa"
			else:
				scene_mode_button.icon = editor_base.get_theme_icon("PackedScene", "EditorIcons")
				scene_mode_button.text = "main.tscn"

func _connect_signal_safe(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
	sig.connect(callable)

func _update_ui_state(is_running: bool) -> void:
	if play_button: play_button.disabled = is_running
	if stop_button: stop_button.disabled = not is_running
	if reset_button: reset_button.disabled = not is_running
	if fit_button: fit_button.disabled = not is_running
	if screenshot_button: screenshot_button.disabled = not is_running
	if zoom_in_button: zoom_in_button.disabled = not is_running
	if zoom_out_button: zoom_out_button.disabled = not is_running
	if camera_selector: camera_selector.disabled = not is_running
	if aspect_button: aspect_button.disabled = not is_running
	
	if status_label:
		if is_running:
			status_label.text = "Ejecutando en Vivo"
		else:
			status_label.text = "Detenido"
	if zoom_label and not is_running:
		zoom_label.text = "100%"
		
	# Forzar redibujo de reglas en estado detenido
	_queue_redraw_rulers()

func _on_scene_mode_toggled(_toggled_on: bool) -> void:
	_update_scene_mode_button_icon()

func _on_play_pressed() -> void:
	_on_stop_pressed() # Limpieza previa obligatoria
	
	if status_label: status_label.text = "Cargando escena..."
	
	# Determinar qué escena cargar
	var scene_path = "res://main.tscn"
	var using_active = false
	
	if scene_mode_button and scene_mode_button.button_pressed:
		if Engine.is_editor_hint():
			var root = EditorInterface.get_edited_scene_root()
			if root and root.scene_file_path != "":
				scene_path = root.scene_file_path
				using_active = true
	
	var loaded_scene = load(scene_path)
	if not loaded_scene:
		if status_label: status_label.text = "Error al cargar la escena: " + scene_path
		return
		
	active_scene_instance = loaded_scene.instantiate()
	viewport.add_child(active_scene_instance)
	
	# Si previsualizamos la escena activa del editor, vigilar cambios globales del historial de edición (UndoRedo)
	if scene_mode_button and scene_mode_button.button_pressed:
		if Engine.is_editor_hint() and plugin_instance:
			var undo_redo = plugin_instance.get_undo_redo()
			if undo_redo:
				_connect_signal_safe(undo_redo.history_changed, _on_watched_scene_changed)
	
	# AUTOMÁTICAMENTE DETECTAR SI LA ESCENA ES 2D O 3D!
	is_3d = active_scene_instance is Node3D
	
	if is_3d:
		# ----------------- CONFIGURAR ENTORNO 3D -----------------
		# Ocultar reglas 2D
		if left_ruler: left_ruler.visible = false
		if top_ruler: top_ruler.visible = false
		
		# Crear Cámara 3D interactiva
		debug_camera3d = Camera3D.new()
		debug_camera3d.name = "DebugCamera3D"
		viewport.add_child(debug_camera3d)
		debug_camera3d.make_current()
		
		# Crear Luz Direccional para que la escena 3D no esté oscura
		debug_light = DirectionalLight3D.new()
		debug_light.name = "DebugDirectionalLight3D"
		debug_light.rotation_degrees = Vector3(-45, -45, 0)
		viewport.add_child(debug_light)
		
		# Configuración esférica inicial para órbita
		rot_x = -0.5
		rot_y = 0.7
		distance = 8.0
		pivot_pos = Vector3.ZERO
		
		target_rot_x = -0.5
		target_rot_y = 0.7
		target_distance = 8.0
		target_pivot_pos = Vector3.ZERO
		
		# Dibujar el visor en 3D
		if status_label:
			if using_active:
				status_label.text = "Visor 3D Activo: " + scene_path.get_file()
			else:
				status_label.text = "Visor 3D Activo"
	else:
		# ----------------- CONFIGURAR ENTORNO 2D -----------------
		# Mostrar reglas 2D
		if left_ruler: left_ruler.visible = true
		if top_ruler: top_ruler.visible = true
		
		# Crear cámara 2D de depuración interactiva
		debug_camera = Camera2D.new()
		debug_camera.name = "DebugCamera2D"
		viewport.add_child(debug_camera)
		debug_camera.make_current()
		
		# Inicializar targets de interpolación suave
		target_camera_pos = Vector2.ZERO
		target_camera_zoom = Vector2.ONE
		
		# Crear el overlay de cuadrícula técnica
		grid_overlay = TechnicalGrid2D.new()
		grid_overlay.name = "TechnicalGridOverlay"
		grid_overlay.camera = debug_camera
		if grid_button:
			grid_overlay.show_grid = grid_button.button_pressed
		viewport.add_child(grid_overlay)
		
		if status_label:
			if using_active:
				status_label.text = "Visor 2D Activo: " + scene_path.get_file()
			else:
				status_label.text = "Ejecutando main.tscn (2D)"
				
	# Inicializar UI comunes
	_update_ui_state(true)
	
	# Escanear y cargar cámaras disponibles en la escena
	_refresh_camera_selector()
	
	_update_zoom_display()
	_update_aspect_ratio_mode()
	_apply_project_rendering_settings()
	_update_coords_display(Vector2.ZERO, Vector2.ZERO)
	_update_viewport_render_mode()

func _on_stop_pressed() -> void:
	is_dragging = false
	
	# Desconectar vigilancia de cambios en vivo
	if Engine.is_editor_hint() and plugin_instance:
		var undo_redo = plugin_instance.get_undo_redo()
		if undo_redo and undo_redo.history_changed.is_connected(_on_watched_scene_changed):
			undo_redo.history_changed.disconnect(_on_watched_scene_changed)
	watched_scene_root = null
	
	if debounce_timer and is_instance_valid(debounce_timer):
		debounce_timer.stop()
	
	# Limpiar 3D
	if debug_camera3d and is_instance_valid(debug_camera3d):
		debug_camera3d.queue_free()
	debug_camera3d = null
	
	if debug_light and is_instance_valid(debug_light):
		debug_light.queue_free()
	debug_light = null
	
	# Limpiar 2D
	if debug_camera and is_instance_valid(debug_camera):
		debug_camera.queue_free()
	debug_camera = null
	
	if aspect_ratio_container:
		aspect_ratio_container.ratio = 1.0
		
	if viewport:
		viewport.size_2d_override = Vector2i.ZERO
		viewport.size_2d_override_stretch = false
	
	if grid_overlay and is_instance_valid(grid_overlay):
		grid_overlay.queue_free()
	grid_overlay = null
	
	# Limpiar la escena de prueba
	if active_scene_instance and is_instance_valid(active_scene_instance):
		active_scene_instance.queue_free()
	active_scene_instance = null
	
	# Limpiar remanentes del viewport
	for child in viewport.get_children():
		child.queue_free()
		
	# Restaurar visibilidad de las reglas al detener
	if left_ruler: left_ruler.visible = true
	if top_ruler: top_ruler.visible = true
	
	if camera_selector:
		camera_selector.clear()
		camera_selector.disabled = true
	
	_update_ui_state(false)
	_update_coords_display(Vector2.ZERO, Vector2.ZERO)
	_update_viewport_render_mode()

func _on_reset_pressed() -> void:
	if _is_using_custom_camera():
		return
		
	if is_3d:
		target_rot_x = -0.5
		target_rot_y = 0.7
		target_distance = 8.0
		target_pivot_pos = Vector3.ZERO
	else:
		target_camera_pos = Vector2.ZERO
		target_camera_zoom = Vector2.ONE
		
	_update_zoom_display()
	_update_coords_display(Vector2.ZERO, Vector2.ZERO)

func _on_fit_pressed() -> void:
	if _is_using_custom_camera() or not active_scene_instance or not is_instance_valid(active_scene_instance):
		return
		
	if is_3d:
		# ----------------- ENCUADRE DE ESCENA EN 3D (AABB) -----------------
		var aabb_accum = [null]
		_calculate_scene_aabb(active_scene_instance, aabb_accum)
		
		var aabb: AABB
		if aabb_accum[0] == null:
			aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
		else:
			aabb = aabb_accum[0]
			
		if aabb.size == Vector3.ZERO:
			aabb.size = Vector3(1.0, 1.0, 1.0)
			
		# Mover el foco del pivot al centro de los límites tridimensionales
		target_pivot_pos = aabb.get_center()
		
		# Ajustar la distancia orbital basándonos en la dimensión máxima de la caja
		var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		target_distance = clamp(max_dim * 1.8, 2.0, 80.0)
		_update_zoom_display()
	else:
		# ----------------- ENCUADRE DE ESCENA EN 2D (RECT2) -----------------
		var rect_accum = [null]
		_calculate_scene_bounds(active_scene_instance, rect_accum)
		
		var bounds: Rect2
		if rect_accum[0] == null:
			bounds = Rect2(-300, -300, 600, 600)
		else:
			bounds = rect_accum[0]
			
		if bounds.size == Vector2.ZERO:
			bounds.size = Vector2(100.0, 100.0)
			
		target_camera_pos = bounds.get_center()
		
		var margin_padding = 1.2
		var zoom_x = viewport.size.x / (bounds.size.x * margin_padding)
		var zoom_y = viewport.size.y / (bounds.size.y * margin_padding)
		var optimal_zoom = min(zoom_x, zoom_y)
		
		optimal_zoom = clamp(optimal_zoom, 0.05, 5.0)
		
		target_camera_zoom = Vector2(optimal_zoom, optimal_zoom)
		_update_zoom_display()

# Función recursiva para calcular los límites acumulados (Bounding Box) de todos los Node2D
func _calculate_scene_bounds(node: Node, rect_accum: Array) -> void:
	if not node or not is_instance_valid(node):
		return
		
	if node is Node2D and not node.name.contains("DebugCamera") and not node.name.contains("Grid") and not node.name.contains("Overlay"):
		var pos = node.global_position
		var size = Vector2(40.0, 40.0)
		
		if node is Sprite2D and node.texture:
			size = node.texture.get_size() * node.scale
			
		var local_rect = Rect2(pos - size / 2.0, size)
		
		if rect_accum[0] == null:
			rect_accum[0] = local_rect
		else:
			rect_accum[0] = rect_accum[0].merge(local_rect)
			
	for child in node.get_children():
		_calculate_scene_bounds(child, rect_accum)

# Función recursiva para calcular los límites acumulados en 3D (AABB) de todos los VisualInstance3D
func _calculate_scene_aabb(node: Node, aabb_accum: Array) -> void:
	if not node or not is_instance_valid(node):
		return
		
	if node is VisualInstance3D and not node.name.contains("Light") and not node.name.contains("Grid") and not node.name.contains("Floor"):
		var local_aabb = node.get_aabb()
		var global_aabb = node.global_transform * local_aabb
		
		if aabb_accum[0] == null:
			aabb_accum[0] = global_aabb
		else:
			aabb_accum[0] = aabb_accum[0].merge(global_aabb)
			
	for child in node.get_children():
		_calculate_scene_aabb(child, aabb_accum)

func _on_screenshot_pressed() -> void:
	if not viewport:
		return
		
	var img = viewport.get_texture().get_image()
	if img:
		var dt = Time.get_datetime_dict_from_system()
		var file_path = "res://captura_viewport_%04d-%02d-%02d_%02d-%02d-%02d.png" % [
			dt.year, dt.month, dt.day,
			dt.hour, dt.minute, dt.second
		]
		
		var err = img.save_png(file_path)
		if err == OK:
			if status_label:
				status_label.text = "¡Captura exportada en " + file_path.get_file() + " con éxito!"
		else:
			if status_label:
				status_label.text = "Fallo al exportar captura de pantalla (Error: " + str(err) + ")"

func _on_zoom_in_pressed() -> void:
	_zoom_camera(1.25)

func _on_zoom_out_pressed() -> void:
	_zoom_camera(0.8)

func _on_grid_toggled(toggled_on: bool) -> void:
	if grid_overlay and is_instance_valid(grid_overlay):
		grid_overlay.show_grid = toggled_on

func _on_viewport_gui_input(event: InputEvent) -> void:
	# Si usamos una cámara de la escena, solo capturamos los movimientos del mouse para actualizar coordenadas
	if _is_using_custom_camera():
		if not is_3d and event is InputEventMouseMotion:
			var custom_cam = viewport.get_camera_2d()
			if custom_cam and is_instance_valid(custom_cam):
				var local_mouse_pos = event.position
				var world_mouse_pos = (local_mouse_pos - viewport.size / 2.0) / custom_cam.zoom + custom_cam.position
				_update_coords_display(custom_cam.position, world_mouse_pos)
		return
		
	if is_3d:
		# ----------------- CONTROLES DE ENTRADA EN MODO 3D -----------------
		if debug_camera3d == null or not is_instance_valid(debug_camera3d):
			return
			
		if event is InputEventMouseMotion:
			if is_dragging:
				var diff = event.relative
				
				# Comprobar si se hace paneo (desplazar Pivot) usando SHIFT + Drag o Botón Central del mouse
				var is_panning = event.shift_pressed or event.button_mask == MOUSE_BUTTON_MASK_MIDDLE
				
				if is_panning:
					var right = debug_camera3d.global_transform.basis.x
					var up = debug_camera3d.global_transform.basis.y
					var speed = 0.0015 * target_distance
					target_pivot_pos += (right * -diff.x + up * diff.y) * speed
				else:
					# Rotación Orbital Estándar
					target_rot_y -= diff.x * 0.005
					# Limitar pitch (rotación vertical) para evitar voltear la cámara de cabeza
					target_rot_x = clamp(target_rot_x - diff.y * 0.005, -1.4, 1.4)
					
				viewport_container.accept_event()
				
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
				is_dragging = event.pressed
				viewport_container.accept_event()
				
			# Zoom orbital con rueda
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_camera(0.9)
					viewport_container.accept_event()
					
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_camera(1.1)
					viewport_container.accept_event()
	else:
		# ----------------- CONTROLES DE ENTRADA EN MODO 2D -----------------
		if debug_camera == null or not is_instance_valid(debug_camera):
			return
			
		if event is InputEventMouseMotion:
			var local_mouse_pos = event.position
			var world_mouse_pos = (local_mouse_pos - viewport.size / 2.0) / debug_camera.zoom + debug_camera.position
			_update_coords_display(debug_camera.position, world_mouse_pos)
			
			_queue_redraw_rulers()
			
			if is_dragging:
				var diff = event.position - last_mouse_pos
				target_camera_pos -= diff / debug_camera.zoom
				last_mouse_pos = event.position
				_update_coords_display(target_camera_pos, world_mouse_pos)
				viewport_container.accept_event()
				
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					is_dragging = true
					last_mouse_pos = event.position
				else:
					is_dragging = false
					
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_camera(1.1)
					viewport_container.accept_event()
					
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_camera(0.9)
					viewport_container.accept_event()

func _zoom_camera(factor: float) -> void:
	if _is_using_custom_camera():
		return
		
	if is_3d:
		if debug_camera3d and is_instance_valid(debug_camera3d):
			target_distance = clamp(target_distance * factor, 1.5, 90.0)
			_update_zoom_display()
	else:
		if debug_camera and is_instance_valid(debug_camera):
			var new_zoom = target_camera_zoom * factor
			new_zoom.x = clamp(new_zoom.x, 0.05, 20.0)
			new_zoom.y = clamp(new_zoom.y, 0.05, 20.0)
			target_camera_zoom = new_zoom
			_update_zoom_display()

func _update_zoom_display() -> void:
	if zoom_label:
		if is_3d:
			zoom_label.text = "Dist: %.1f" % target_distance
		else:
			var percentage = round(target_camera_zoom.x * 100)
			zoom_label.text = str(percentage) + "%"

func _update_coords_display(cam_pos: Vector2, mouse_pos: Vector2) -> void:
	if coords_label:
		if is_3d:
			if _is_using_custom_camera():
				var custom_cam = viewport.get_camera_3d()
				if custom_cam and is_instance_valid(custom_cam):
					coords_label.text = "Cámara Escena 3D: (X: %.1f, Y: %.1f, Z: %.1f)" % [
						custom_cam.global_position.x, custom_cam.global_position.y, custom_cam.global_position.z
					]
			else:
				if debug_camera3d and is_instance_valid(debug_camera3d):
					coords_label.text = "Cámara 3D: (X: %.1f, Y: %.1f, Z: %.1f) | Pivot: (X: %.1f, Y: %.1f, Z: %.1f)" % [
						debug_camera3d.position.x, debug_camera3d.position.y, debug_camera3d.position.z,
						target_pivot_pos.x, target_pivot_pos.y, target_pivot_pos.z
					]
		else:
			if _is_using_custom_camera():
				var custom_cam = viewport.get_camera_2d()
				if custom_cam and is_instance_valid(custom_cam):
					coords_label.text = "Cámara Escena: (%d, %d) | Cursor: (%d, %d)" % [round(custom_cam.position.x), round(custom_cam.position.y), round(mouse_pos.x), round(mouse_pos.y)]
			else:
				coords_label.text = "Cámara: (%d, %d) | Cursor: (%d, %d)" % [round(cam_pos.x), round(cam_pos.y), round(mouse_pos.x), round(mouse_pos.y)]

func _queue_redraw_rulers() -> void:
	if left_ruler: left_ruler.queue_redraw()
	if top_ruler: top_ruler.queue_redraw()

func _on_visibility_changed() -> void:
	_update_viewport_render_mode()

func _update_viewport_render_mode() -> void:
	if not viewport:
		return
		
	if is_visible_in_tree() and active_scene_instance != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		set_process(true)
	else:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(false)

# ----------------- CONFIGURACIÓN Y SELECCIÓN DE CÁMARA DE LA ESCENA -----------------

func _refresh_camera_selector() -> void:
	if not camera_selector:
		return
		
	camera_selector.clear()
	# Opción por defecto
	camera_selector.add_item("Cámara de Depuración (Interactiva)")
	camera_selector.set_item_metadata(0, "debug")
	
	if not active_scene_instance or not is_instance_valid(active_scene_instance):
		return
		
	var found_cams: Array[Node] = []
	_find_scene_cameras(active_scene_instance, found_cams)
	
	for i in range(found_cams.size()):
		var cam = found_cams[i]
		var rel_path = active_scene_instance.get_path_to(cam)
		camera_selector.add_item(cam.name + " (" + str(rel_path) + ")")
		camera_selector.set_item_metadata(i + 1, cam)

func _find_scene_cameras(node: Node, accum: Array[Node]) -> void:
	if not node or not is_instance_valid(node):
		return
		
	if is_3d:
		if node is Camera3D and not node.name.contains("DebugCamera"):
			accum.append(node)
	else:
		if node is Camera2D and not node.name.contains("DebugCamera"):
			accum.append(node)
			
	for child in node.get_children():
		_find_scene_cameras(child, accum)

func _is_using_custom_camera() -> bool:
	if not camera_selector:
		return false
	return camera_selector.selected > 0

func _get_active_camera_2d() -> Camera2D:
	if _is_using_custom_camera():
		var custom = viewport.get_camera_2d()
		if custom and is_instance_valid(custom):
			return custom
	return debug_camera

func _on_camera_selected(index: int) -> void:
	if not camera_selector:
		return
		
	var metadata = camera_selector.get_item_metadata(index)
	var is_custom = index > 0
	
	# Deshabilitar botones interactivos si usamos cámara propia del juego
	reset_button.disabled = is_custom
	fit_button.disabled = is_custom
	zoom_in_button.disabled = is_custom
	zoom_out_button.disabled = is_custom
	
	if metadata is String and metadata == "debug":
		# Activar la cámara interactiva de depuración
		if is_3d:
			if debug_camera3d and is_instance_valid(debug_camera3d):
				debug_camera3d.make_current()
		else:
			if debug_camera and is_instance_valid(debug_camera):
				debug_camera.make_current()
				
		if status_label: status_label.text = "Cámara de depuración interactiva activa"
		_update_zoom_display()
	elif metadata is Node and is_instance_valid(metadata):
		# Activar la cámara personalizada de la escena
		metadata.make_current()
		if status_label: status_label.text = "Cámara de Escena activa: " + metadata.name
		if not is_3d and metadata is Camera2D:
			var percentage = round(metadata.zoom.x * 100)
			if zoom_label: zoom_label.text = str(percentage) + "%"
		else:
			if zoom_label: zoom_label.text = "---"

# ----------------- DIBUJO DE REGLAS DE PÍXELES (2D ONLY) -----------------

func _on_top_ruler_draw() -> void:
	if not top_ruler or is_3d:
		return
		
	top_ruler.draw_rect(Rect2(Vector2.ZERO, top_ruler.size), Color(0.09, 0.11, 0.14, 0.96), true)
	top_ruler.draw_line(Vector2(0, top_ruler.size.y - 1), Vector2(top_ruler.size.x, top_ruler.size.y - 1), Color(0.25, 0.3, 0.38, 0.8), 1.0)
	
	var active_cam = _get_active_camera_2d()
	if not active_cam or not is_instance_valid(active_cam):
		return
		
	var cam_pos = active_cam.position
	var cam_zoom = active_cam.zoom
	var ruler_width = top_ruler.size.x
	var ruler_height = top_ruler.size.y
	var center_x = ruler_width / 2.0
	
	var step = 100.0
	if cam_zoom.x < 0.2:
		step = 1000.0
	elif cam_zoom.x < 0.5:
		step = 400.0
	elif cam_zoom.x > 3.0:
		step = 10.0
	elif cam_zoom.x > 1.5:
		step = 50.0
		
	var min_world_x = (0 - center_x) / cam_zoom.x + cam_pos.x
	var max_world_x = (ruler_width - center_x) / cam_zoom.x + cam_pos.x
	
	var ticks_count = (max_world_x - min_world_x) / step
	if ticks_count > 150:
		step *= ceil(ticks_count / 100.0)
		
	var start_world_x = floor(min_world_x / step) * step
	var end_world_x = ceil(max_world_x / step) * step
	
	var default_font = ThemeDB.fallback_font
	var font_color := Color(0.55, 0.68, 0.8, 0.8)
	
	for wx in range(int(start_world_x), int(end_world_x) + 1, int(step)):
		var lx = (wx - cam_pos.x) * cam_zoom.x + center_x
		top_ruler.draw_line(Vector2(lx, ruler_height - 10), Vector2(lx, ruler_height - 1), font_color, 1.0)
		
		if default_font:
			var text = str(wx)
			var text_size = default_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
			top_ruler.draw_string(default_font, Vector2(lx - text_size.x / 2.0, 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, font_color)
			
		var half_lx = lx + (step * cam_zoom.x) / 2.0
		if half_lx < ruler_width:
			top_ruler.draw_line(Vector2(half_lx, ruler_height - 5), Vector2(half_lx, ruler_height - 1), Color(font_color.r, font_color.g, font_color.b, 0.3), 1.0)

	var local_mouse = top_ruler.get_local_mouse_position()
	if local_mouse.x >= 0 and local_mouse.x <= ruler_width:
		top_ruler.draw_line(Vector2(local_mouse.x, 0), Vector2(local_mouse.x, ruler_height), Color(0.9, 0.35, 0.35, 0.7), 1.2)

func _on_left_ruler_draw() -> void:
	if not left_ruler or is_3d:
		return
		
	left_ruler.draw_rect(Rect2(Vector2.ZERO, left_ruler.size), Color(0.09, 0.11, 0.14, 0.96), true)
	left_ruler.draw_line(Vector2(left_ruler.size.x - 1, 0), Vector2(left_ruler.size.x - 1, left_ruler.size.y), Color(0.25, 0.3, 0.38, 0.8), 1.0)
	
	var active_cam = _get_active_camera_2d()
	if not active_cam or not is_instance_valid(active_cam):
		return
		
	var cam_pos = active_cam.position
	var cam_zoom = active_cam.zoom
	var ruler_width = left_ruler.size.x
	var ruler_height = left_ruler.size.y
	var center_y = ruler_height / 2.0
	
	var step = 100.0
	if cam_zoom.y < 0.2:
		step = 1000.0
	elif cam_zoom.y < 0.5:
		step = 400.0
	elif cam_zoom.y > 3.0:
		step = 10.0
	elif cam_zoom.y > 1.5:
		step = 50.0
		
	var min_world_y = (0 - center_y) / cam_zoom.y + cam_pos.y
	var max_world_y = (ruler_height - center_y) / cam_zoom.y + cam_pos.y
	
	var ticks_count = (max_world_y - min_world_y) / step
	if ticks_count > 150:
		step *= ceil(ticks_count / 100.0)
		
	var start_world_y = floor(min_world_y / step) * step
	var end_world_y = ceil(max_world_y / step) * step
	
	var default_font = ThemeDB.fallback_font
	var font_color := Color(0.55, 0.68, 0.8, 0.8)
	
	for wy in range(int(start_world_y), int(end_world_y) + 1, int(step)):
		var ly = (wy - cam_pos.y) * cam_zoom.y + center_y
		left_ruler.draw_line(Vector2(ruler_width - 10, ly), Vector2(ruler_width - 1, ly), font_color, 1.0)
		
		if default_font:
			var text = str(wy)
			left_ruler.draw_string(default_font, Vector2(2, ly + 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, font_color)
			
		var half_ly = ly + (step * cam_zoom.y) / 2.0
		if half_ly < ruler_height:
			left_ruler.draw_line(Vector2(ruler_width - 5, half_ly), Vector2(ruler_width - 1, half_ly), Color(font_color.r, font_color.g, font_color.b, 0.3), 1.0)

	var local_mouse = left_ruler.get_local_mouse_position()
	if local_mouse.y >= 0 and local_mouse.y <= ruler_height:
		left_ruler.draw_line(Vector2(0, local_mouse.y), Vector2(ruler_width, local_mouse.y), Color(0.9, 0.35, 0.35, 0.7), 1.2)

# ----------------- CONTROL DE RELACIÓN DE ASPECTO -----------------

func _on_aspect_toggled(_toggled_on: bool) -> void:
	_update_aspect_ratio_mode()

func _on_aspect_container_resized() -> void:
	if aspect_button and not aspect_button.button_pressed:
		_update_aspect_ratio_mode()

func _update_aspect_ratio_mode() -> void:
	if not aspect_ratio_container:
		return
		
	if aspect_button and aspect_button.button_pressed:
		# Modo Aspecto Nativo del Proyecto
		var width = ProjectSettings.get_setting("display/window/size/viewport_width")
		var height = ProjectSettings.get_setting("display/window/size/viewport_height")
		if width and height:
			aspect_ratio_container.ratio = float(width) / float(height)
		else:
			aspect_ratio_container.ratio = 1.0
	else:
		# Modo Ajustar/Expandir completamente al panel dock
		if aspect_ratio_container.size.y > 0:
			aspect_ratio_container.ratio = float(aspect_ratio_container.size.x) / float(aspect_ratio_container.size.y)

# ----------------- PARIDAD DE RENDERIZADO DEL PROYECTO -----------------

func _apply_project_rendering_settings() -> void:
	if not viewport:
		return
		
	# 1. Copiar configuración de MSAA 2D
	var msaa_2d_val = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d")
	if msaa_2d_val != null:
		viewport.msaa_2d = msaa_2d_val
		
	# 2. Copiar configuración de MSAA 3D
	var msaa_3d_val = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")
	if msaa_3d_val != null:
		viewport.msaa_3d = msaa_3d_val
		
	# 3. Copiar configuración de Screen Space AA (FXAA)
	var ss_aa_val = ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa")
	if ss_aa_val != null:
		viewport.screen_space_aa = ss_aa_val
		
	# 4. Copiar configuración de Debanding
	var debanding_val = ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_debanding")
	if debanding_val != null:
		viewport.use_debanding = debanding_val
		
	# 5. Copiar configuración de HDR 2D
	var hdr_2d_val = ProjectSettings.get_setting("rendering/viewport/hdr_2d")
	if hdr_2d_val != null:
		viewport.use_hdr_2d = hdr_2d_val
		
	# 6. Copiar filtro de textura por defecto para 2D
	var tex_filter_val = ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")
	if tex_filter_val != null:
		viewport.canvas_item_default_texture_filter = tex_filter_val
		
	# 7. Copiar ajuste de Pixel Snapping de 2D si está configurado en el proyecto
	var snap_transforms = ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel")
	if snap_transforms != null:
		viewport.snap_2d_transforms_to_pixel = snap_transforms
		
	var snap_vertices = ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel")
	if snap_vertices != null:
		viewport.snap_2d_vertices_to_pixel = snap_vertices

# ----------------- ACTUALIZACIÓN EN CALIENTE (REAL-TIME HOT RELOAD) -----------------

func _on_watched_scene_changed() -> void:
	if debounce_timer and active_scene_instance != null:
		debounce_timer.start()

func _on_debounce_timeout() -> void:
	if active_scene_instance == null:
		return
		
	# Guardar configuración de la cámara actual
	var saved_cam_index = 0
	if camera_selector:
		saved_cam_index = camera_selector.selected
		
	var saved_target_pos = target_camera_pos
	var saved_target_zoom = target_camera_zoom
	var saved_rot_x = target_rot_x
	var saved_rot_y = target_rot_y
	var saved_dist = target_distance
	var saved_pivot = target_pivot_pos
	
	# Recargar en caliente desde la memoria
	_reload_active_scene()
	
	# Restaurar configuración de cámara
	target_camera_pos = saved_target_pos
	target_camera_zoom = saved_target_zoom
	target_rot_x = saved_rot_x
	target_rot_y = saved_rot_y
	target_distance = saved_dist
	target_pivot_pos = saved_pivot
	
	if camera_selector and saved_cam_index < camera_selector.item_count:
		camera_selector.selected = saved_cam_index
		_on_camera_selected(saved_cam_index)

func _reload_active_scene() -> void:
	if active_scene_instance == null:
		return
		
	var was_scene_mode = scene_mode_button.button_pressed if scene_mode_button else false
	
	# Limpiar instancia anterior
	if active_scene_instance and is_instance_valid(active_scene_instance):
		active_scene_instance.queue_free()
	active_scene_instance = null
	
	# Limpiar hijos temporales excepto cámaras y luz de depuración
	for child in viewport.get_children():
		if child != debug_camera and child != debug_camera3d and child != debug_light and child != grid_overlay:
			child.queue_free()
			
	var loaded_scene: PackedScene = null
	var scene_path = "res://main.tscn"
	
	if was_scene_mode:
		if Engine.is_editor_hint():
			var root = EditorInterface.get_edited_scene_root()
			if root and is_instance_valid(root):
				scene_path = root.scene_file_path
				# Serializar en caliente directamente desde la memoria (incluye cambios no guardados)
				var packed = PackedScene.new()
				var err = packed.pack(root)
				if err == OK:
					loaded_scene = packed
					
	if not loaded_scene:
		loaded_scene = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		
	if loaded_scene:
		active_scene_instance = loaded_scene.instantiate()
		viewport.add_child(active_scene_instance)
		
		_refresh_camera_selector()
		_update_aspect_ratio_mode()
		_apply_project_rendering_settings()
		
		if status_label:
			status_label.text = "Actualizado en Vivo: " + scene_path.get_file()
		
	# 8. Sincronizar el escalado de resolución lógica 2D (size_2d_override) para que la UI se auto-ajuste y escale
	var width = ProjectSettings.get_setting("display/window/size/viewport_width")
	var height = ProjectSettings.get_setting("display/window/size/viewport_height")
	if width and height and not is_3d:
		viewport.size_2d_override = Vector2i(width, height)
		viewport.size_2d_override_stretch = true
