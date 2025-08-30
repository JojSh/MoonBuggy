extends Node3D

var music_is_playing: bool = false

func start_music ():
	if music_is_playing:
		return
	else:
		$MoonbuggyOST1.play()
		music_is_playing = true
