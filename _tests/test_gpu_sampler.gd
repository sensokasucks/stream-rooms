extends Node
## GpuFrameSampler matches the old full-frame CPU sampling, and is cheaper at 1080p.
func _ready():
	var img := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 640, 1080), Color(0.9, 0.2, 0.1))
	img.fill_rect(Rect2i(640, 0, 640, 1080), Color(0.1, 0.8, 0.3))
	img.fill_rect(Rect2i(1280, 0, 640, 1080), Color(0.2, 0.3, 0.9))
	for i in 200:   # some detail so averaging matters
		img.fill_rect(Rect2i((i * 97) % 1900, (i * 53) % 1060, 20, 20), Color(1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	var s := GpuFrameSampler.new()
	add_child(s)
	await get_tree().process_frame
	var first := s.sample(tex)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var gpu := s.sample(tex)
	var t_gpu := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var cpu := ColorSampler.sample_thirds(tex.get_image())
	var t_cpu := Time.get_ticks_usec() - t0
	print("first call=", first)
	for i in 3:
		print("third ", i, " gpu=", gpu[i], " cpu=", cpu[i])
	print("gpu path us=", t_gpu, "  cpu path us=", t_cpu)
	print("DONE")
	AppState.request_quit()
