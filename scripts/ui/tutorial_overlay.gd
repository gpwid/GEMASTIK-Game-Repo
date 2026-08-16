class_name TutorialOverlay
extends Control

## Tutorial layar penuh dengan lubang sorotan tanpa shader.
## Empat ColorRect menggelapkan area di sekeliling target.

const MASK_OVERLAP: float = 0.0

signal tutorial_started
signal tutorial_finished(was_skipped: bool)

@export_category("Tutorial Content")
@export var steps: Array[TutorialStep] = []

@export_category("Behaviour")
@export var pause_game_while_open: bool = true
@export var highlight_padding: Vector2 = Vector2(20.0, 20.0)

var current_step_index: int = -1
var _tree_was_paused: bool = false
var _current_target: Node = null

@onready var dim_top: ColorRect = %DimTop
@onready var dim_bottom: ColorRect = %DimBottom
@onready var dim_left: ColorRect = %DimLeft
@onready var dim_right: ColorRect = %DimRight
@onready var highlight_frame: Panel = %HighlightFrame

@onready var step_counter: Label = %StepCounter
@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var next_button: Button = %NextButton


func _ready() -> void:
	## Always diperlukan agar tombol tutorial tetap bekerja ketika game dijeda.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)


func _process(_delta: float) -> void:
	if not visible:
		return

	_update_highlight()

	## Membuat garis sorotan berdenyut ringan agar mudah terlihat.
	var pulse := (sin(Time.get_ticks_msec() / 180.0) + 1.0) * 0.5
	highlight_frame.modulate.a = lerpf(0.72, 1.0, pulse)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_accept"):
		_show_next_step()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		finish_tutorial(true)
		get_viewport().set_input_as_handled()


## Dapat dipanggil BaseLevel ketika level dimulai atau tombol Help kapan saja.
func start_tutorial() -> void:
	if steps.is_empty():
		push_warning("TutorialOverlay: daftar Steps masih kosong")
		return

	_tree_was_paused = get_tree().paused
	if pause_game_while_open:
		get_tree().paused = true

	## Memastikan tutorial digambar di atas sibling UI lainnya.
	if get_parent() != null:
		get_parent().move_child(
			self,
			get_parent().get_child_count() - 1
		)

	visible = true
	set_process(true)
	current_step_index = 0
	_show_current_step()
	tutorial_started.emit()


## Menutup tutorial dan mengembalikan status pause sebelum tutorial dibuka.
func finish_tutorial(was_skipped: bool = false) -> void:
	if not visible:
		return

	visible = false
	set_process(false)
	current_step_index = -1
	_current_target = null

	if pause_game_while_open:
		get_tree().paused = _tree_was_paused

	tutorial_finished.emit(was_skipped)


func _show_next_step() -> void:
	if current_step_index >= steps.size() - 1:
		finish_tutorial(false)
		return

	current_step_index += 1
	_show_current_step()


func _show_current_step() -> void:
	if current_step_index < 0 or current_step_index >= steps.size():
		finish_tutorial(false)
		return

	var step: TutorialStep = steps[current_step_index]
	step_counter.text = "%d / %d" % [
		current_step_index + 1,
		steps.size()
	]
	title_label.text = step.title
	description_label.text = step.description

	if current_step_index == steps.size() - 1:
		next_button.text = "Mulai Bermain"
	else:
		next_button.text = "Lanjut"

	_current_target = _find_target_in_current_level(step.target_group)
	if _current_target == null and not step.target_group.is_empty():
		push_warning(
			"TutorialOverlay: target group tidak ditemukan: "
			+ String(step.target_group)
		)

	_update_highlight()


## Mencari target hanya di dalam current_scene, bukan node level lain.
func _find_target_in_current_level(group_name: StringName) -> Node:
	if group_name.is_empty():
		return null

	var current_scene: Node = get_tree().current_scene
	for candidate in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(candidate):
			continue
		if current_scene == null:
			return candidate
		if candidate == current_scene or current_scene.is_ancestor_of(candidate):
			return candidate

	return null


func _update_highlight() -> void:
	if not is_instance_valid(_current_target):
		_show_full_dim()
		return

	var target_rect := _get_target_screen_rect(_current_target)
	if target_rect.size.x <= 0.0 or target_rect.size.y <= 0.0:
		_show_full_dim()
		return

	target_rect.position -= highlight_padding
	target_rect.size += highlight_padding * 2.0
	target_rect = _clamp_rect_to_screen(target_rect)

	if target_rect.size.x <= 0.0 or target_rect.size.y <= 0.0:
		_show_full_dim()
		return

	_apply_highlight_rect(target_rect)


func _get_target_screen_rect(target: Node) -> Rect2:
	## UI sudah mempunyai ukuran akurat, jadi tidak memerlukan ukuran manual.
	if target is Control:
		var target_control := target as Control
		var control_rect := target_control.get_global_rect()
		control_rect.position -= global_position
		return control_rect

	## Node dunia menggunakan transform canvas agar mengikuti kamera dan zoom.
	if target is Node2D:
		var target_node := target as Node2D
		var canvas_transform := target_node.get_global_transform_with_canvas()
		var target_size := Vector2(160.0, 160.0)

		if current_step_index >= 0 and current_step_index < steps.size():
			target_size = steps[current_step_index].world_highlight_size

		var canvas_scale := canvas_transform.get_scale().abs()
		target_size *= canvas_scale

		var center := canvas_transform.origin - global_position
		return Rect2(center - target_size * 0.5, target_size)

	return Rect2()


func _clamp_rect_to_screen(target_rect: Rect2) -> Rect2:
	var screen_rect := Rect2(Vector2.ZERO, size)
	var clipped_rect := target_rect.intersection(screen_rect)

	## Snap ke piksel penuh agar tidak muncul garis akibat koordinat pecahan.
	var snapped_position := clipped_rect.position.floor()
	var snapped_end := clipped_rect.end.ceil()
	return Rect2(
		snapped_position,
		snapped_end - snapped_position
	)


## Empat bidang gelap menyisakan lubang tepat pada target.
func _apply_highlight_rect(target_rect: Rect2) -> void:
	var screen_size := size
	var target_end := target_rect.end
	var bottom_start := maxf(target_end.y - MASK_OVERLAP, 0.0)
	var right_start := maxf(target_end.x - MASK_OVERLAP, 0.0)

	_set_control_rect(
		dim_top,
		Rect2(
			Vector2.ZERO,
			Vector2(
				screen_size.x,
				target_rect.position.y + MASK_OVERLAP
			)
		)
	)
	_set_control_rect(
		dim_bottom,
		Rect2(
			Vector2(0.0, bottom_start),
			Vector2(screen_size.x, screen_size.y - bottom_start)
		)
	)
	_set_control_rect(
		dim_left,
		Rect2(
			Vector2(0.0, target_rect.position.y),
			Vector2(
				target_rect.position.x + MASK_OVERLAP,
				target_rect.size.y
			)
		)
	)
	_set_control_rect(
		dim_right,
		Rect2(
			Vector2(right_start, target_rect.position.y),
			Vector2(screen_size.x - right_start, target_rect.size.y)
		)
	)

	highlight_frame.visible = true
	_set_control_rect(highlight_frame, target_rect)


func _show_full_dim() -> void:
	_set_control_rect(dim_top, Rect2(Vector2.ZERO, size))
	_set_control_rect(dim_bottom, Rect2())
	_set_control_rect(dim_left, Rect2())
	_set_control_rect(dim_right, Rect2())
	highlight_frame.visible = false


func _set_control_rect(control: Control, target_rect: Rect2) -> void:
	control.position = target_rect.position
	control.size = Vector2(
		maxf(target_rect.size.x, 0.0),
		maxf(target_rect.size.y, 0.0)
	)


func _on_next_button_pressed() -> void:
	_show_next_step()


func _on_skip_button_pressed() -> void:
	finish_tutorial(true)
