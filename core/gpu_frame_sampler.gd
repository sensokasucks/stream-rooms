class_name GpuFrameSampler
extends Node
## Room-lighting colours from a video texture without copying the whole frame back from the GPU.
## The GPU shrinks the picture into a tiny viewport (ColorSampler.SAMPLE_W x SAMPLE_H, each
## pixel the average of a TAPS x TAPS grid under it); only that tiny image is read back.
## sample() returns the colours from an earlier render (one or two samples behind, ~50-100 ms)
## and queues a render of the current frame.
## With the Forward+/Mobile renderers the tiny image is read back asynchronously
## (RenderingDevice.texture_get_data_async), so the game never stalls waiting for the GPU;
## a stall there makes the frame late, and the NDI plugin feeds its sound once per frame.
## The Compatibility renderer falls back to a (small) synchronous read.

const TAPS: int = 6
const SHADER_CODE: String = """
shader_type canvas_item;
uniform sampler2D src : filter_linear, repeat_disable;
uniform vec2 grid = vec2(36.0, 20.0);
uniform int taps = 6;
void fragment() {
	vec2 cell = floor(UV * grid) / grid;
	vec3 acc = vec3(0.0);
	for (int j = 0; j < taps; j++) {
		for (int i = 0; i < taps; i++) {
			acc += texture(src, cell + (vec2(float(i), float(j)) + 0.5) / (grid * float(taps))).rgb;
		}
	}
	COLOR = vec4(acc / float(taps * taps), 1.0);
}
"""

var _vp: SubViewport
var _mat: ShaderMaterial
var _pending: bool = false
var _rd: RenderingDevice
var _async: bool = false
var _in_flight: bool = false
var _in_flight_ms: int = 0
var _latest: Array[Color] = []


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(ColorSampler.SAMPLE_W, ColorSampler.SAMPLE_H)
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("grid", Vector2(ColorSampler.SAMPLE_W, ColorSampler.SAMPLE_H))
	_mat.set_shader_parameter("taps", TAPS)
	var rect := ColorRect.new()
	rect.material = _mat
	rect.size = Vector2(_vp.size)
	_vp.add_child(rect)
	_rd = RenderingServer.get_rendering_device()
	_async = _rd != null and _rd.has_method("texture_get_data_async")


## [left, centre, right] from the last render, or [] until the first one is ready.
func sample(tex: Texture2D) -> Array[Color]:
	var out: Array[Color] = []
	if _async and _in_flight and Time.get_ticks_msec() - _in_flight_ms > 2000:
		_async = false          # no answer from the GPU: use the plain read from now on
		push_warning("GpuFrameSampler: async read-back didn't answer, using the synchronous read.")
	if _async:
		if _pending and not _in_flight:
			var rd_tex := RenderingServer.texture_get_rd_texture(_vp.get_texture().get_rid())
			if rd_tex.is_valid():
				_in_flight = true
				_in_flight_ms = Time.get_ticks_msec()
				_rd.call("texture_get_data_async", rd_tex, 0, _on_data)
		out = _latest
		_latest = []
	elif _pending:
		var img := _vp.get_texture().get_image()
		if img and not img.is_empty():
			out = ColorSampler.sample_thirds(img)
	_mat.set_shader_parameter("src", tex)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_pending = tex != null
	return out


func reset() -> void:
	_pending = false


func _on_data(data: PackedByteArray) -> void:
	_in_flight = false
	var w := ColorSampler.SAMPLE_W
	var h := ColorSampler.SAMPLE_H
	var fmt := -1
	if data.size() == w * h * 4:
		fmt = Image.FORMAT_RGBA8
	elif data.size() == w * h * 8:
		fmt = Image.FORMAT_RGBAH
	if fmt < 0:
		_async = false          # unexpected format: use the plain read from now on
		push_warning("GpuFrameSampler: unexpected read-back size %d, using the synchronous read." % data.size())
		return
	_latest = ColorSampler.sample_thirds(Image.create_from_data(w, h, false, fmt, data))
