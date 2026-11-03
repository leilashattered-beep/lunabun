extends Node
## Autoload: background music, one looping melody per place.
##
## The title screen and the forest share a melody; the burrow has its own. The
## track follows the current scene by itself, so no location has to call
## anything: menu, forest and burrow all get the right music automatically.
##
## Nothing is re-encoded - the supplied MP3 files are played as they are.

## Supplied tracks, played exactly as delivered.
const FOREST_TRACK := "res://audio/clavier-music-ambient-video-game-music-438767.mp3"
const BURROW_TRACK := "res://audio/musicword-forest-song-306506.mp3"

## Which scenes use the forest melody. The menu uses it too, as asked.
const FOREST_SCENES := ["main.tscn", "main_menu.tscn"]
const BURROW_SCENES := ["burrow_inside.tscn"]

var _player: AudioStreamPlayer
var _streams := {}
## "forest" or "burrow": the melody that is playing right now.
var current := ""


func _ready() -> void:
	# Always processing, so the music keeps playing while a menu pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.name = "MusicPlayer"
	add_child(_player)
	# If a stream ever ends without looping, start it again rather than fall
	# silent.
	_player.finished.connect(_replay)


func _process(_delta: float) -> void:
	var wanted := _track_for_current_scene()
	if wanted != "" and wanted != current:
		play(wanted)
	# The volume follows the НАСТРОЙКИ setting live.
	if _player.stream != null:
		_player.volume_db = linear_to_db(maxf(GameState.music_volume, 0.0001))


## Plays one of the two melodies, ignoring a request for what is already playing.
func play(which: String) -> void:
	var path := FOREST_TRACK if which == "forest" else BURROW_TRACK
	if not ResourceLoader.exists(path):
		push_warning("Music: missing track " + path)
		return
	if not _streams.has(path):
		var stream: AudioStream = load(path)
		# Loop forever: these are ambient tracks, not stingers.
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		_streams[path] = stream
	current = which
	_player.stream = _streams[path]
	_player.play()


func stop() -> void:
	_player.stop()
	current = ""


func _replay() -> void:
	if _player.stream != null:
		_player.play()


## Works out which melody belongs to the scene that is on screen.
func _track_for_current_scene() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	var path := scene.scene_file_path
	for name in FOREST_SCENES:
		if path.ends_with(name):
			return "forest"
	for name in BURROW_SCENES:
		if path.ends_with(name):
			return "burrow"
	# Any other scene keeps whatever is playing.
	return ""
