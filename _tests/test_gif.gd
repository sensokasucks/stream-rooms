extends Node
## GifDecoder against GIFs made by Pillow (devtools/emote_srv), frames saved for comparison.
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	for fname in ["anim.gif", "anim_opt.gif", "interlaced.gif"]:
		var bytes := FileAccess.get_file_as_bytes(out + "/src/" + fname)
		var t0 := Time.get_ticks_msec()
		var r := GifDecoder.decode(bytes)
		var frames: Array = r.get("frames", [])
		print(fname, " frames=", frames.size(), " delays=", r.get("delays"), " ms=", Time.get_ticks_msec() - t0)
		for i in frames.size():
			(frames[i] as Image).save_png(out + "/%s_%02d.png" % [fname.get_basename(), i])
	get_tree().quit()
