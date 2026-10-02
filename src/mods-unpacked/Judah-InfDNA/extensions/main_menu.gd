extends "res://ui/menus/pages/main_menu.gd"
# Adds a "Colony" button under Start on Brotato's main menu.

const INFDNA_SCENE = "res://mods-unpacked/Judah-InfDNA/content/colony/queen_select.tscn"

var _infdna_button: Button = null


func _ready() -> void:
	call_deferred("_infdna_add_button")


func init() -> void:
	.init()
	_infdna_add_button()


func _infdna_add_button() -> void:
	if _infdna_button != null and is_instance_valid(_infdna_button):
		return
	if start_button == null or not is_instance_valid(start_button):
		return
	# duplicate without signals so pressing it never triggers Start
	_infdna_button = start_button.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANCING)
	_infdna_button.name = "InfDNAColonyButton"
	_infdna_button.set("unique_name_in_owner", false)
	_infdna_button.text = "Colony (InfDNA)"
	start_button.get_parent().add_child_below_node(start_button, _infdna_button)
	_infdna_button.connect("pressed", self, "_on_InfDNAColonyButton_pressed")


func _on_InfDNAColonyButton_pressed() -> void:
	var _e = get_tree().change_scene(INFDNA_SCENE)
