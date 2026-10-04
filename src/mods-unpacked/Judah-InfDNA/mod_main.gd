extends Node
# Entry point. Adds the Colony button to Brotato's main menu; the colony mode
# itself is a standalone scene (content/colony/colony.tscn).

const MOD_ID = "Judah-InfDNA"
const LOG = "Judah-InfDNA"
const BugReport = preload("res://mods-unpacked/Judah-InfDNA/core/bug_report.gd")

var mod_dir: String = ""


func _init() -> void:
	mod_dir = ModLoaderMod.get_unpacked_dir().plus_file(MOD_ID)
	ModLoaderMod.install_script_extension(mod_dir.plus_file("extensions/main_menu.gd"))
	ModLoaderLog.info("InfDNA loaded", LOG)


# Closing the game writes the developer's report (InfDNA_report.txt on the Desktop): a window close sends the quit request, the game's
# own Quit button only takes the tree down, so both are caught.
func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		_closing()


func _exit_tree() -> void:
	_closing()


func _closing() -> void:
	if BugReport.closing():
		return
	BugReport.write("game closed", true)
	# the art library (the menus use its icons too) lives in Engine metadata, which outlives the scripts at exit and crashed the game:
	# drop it while the scripts still run
	for k in ["infdna_art", "infdna_ug"]:
		if Engine.has_meta(k):
			var lib = Engine.get_meta(k)
			if lib != null and lib.has_method("shutdown"):
				lib.shutdown()
			Engine.remove_meta(k)
