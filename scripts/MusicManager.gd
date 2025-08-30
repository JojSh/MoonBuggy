extends Node3D

var music_is_playing: bool = false

func start_music (track_selection: int = 1):
	if music_is_playing:
		return
	else:
		var track_name = "MoonbuggyOST" + str(track_selection)
		get_node(track_name).play()
		music_is_playing = true
