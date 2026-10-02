extends Node
# Entry point. Adds the Colony button to Brotato's main menu; the colony mode
# itself is a standalone scene (content/colony/colony.tscn).

const MOD_ID = "Judah-InfDNA"
const LOG = "Judah-InfDNA"

var mod_dir: String = ""


func _init() -> void:
	mod_dir = ModLoaderMod.get_unpacked_dir().plus_file(MOD_ID)
	ModLoaderMod.install_script_extension(mod_dir.plus_file("extensions/main_menu.gd"))
	ModLoaderLog.info("InfDNA loaded", LOG)
