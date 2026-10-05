/*
https://github.com/unvermuthet/godot-ndi
		(C) 2025 Henry Muth - unvermuthet

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "video_stream_playback_ndi.hpp"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/rd_texture_format.hpp>
#include <godot_cpp/classes/rd_texture_view.hpp>
#include <godot_cpp/classes/rendering_server.hpp>

#include <cstdlib> // need this for std:free..

using namespace godot;

VideoStreamPlaybackNDI::VideoStreamPlaybackNDI() {
	rd = RenderingServer::get_singleton()->get_rendering_device();
	texture.instantiate();
}

VideoStreamPlaybackNDI::VideoStreamPlaybackNDI(NDIlib_recv_create_v3_t p_recv_desc) :
		VideoStreamPlaybackNDI::VideoStreamPlaybackNDI() {
	recv_desc = p_recv_desc;
}

VideoStreamPlaybackNDI::~VideoStreamPlaybackNDI() {
	_stop();

	RID texture_rd_rid = texture->get_texture_rd_rid();
	if (texture_rd_rid.is_valid()) {
		rd->free_rid(texture_rd_rid);
	}

	texture.unref();
}

void VideoStreamPlaybackNDI::_play() {
	if (recv == nullptr) {
		recv = ndi->recv_create_v3(&recv_desc);
		ERR_FAIL_NULL(recv);
	}

	if (sync == nullptr) {
		sync = ndi->framesync_create(recv);
		ERR_FAIL_NULL(sync);
	}

	playing = true;
	audio_owed = 0.0;
	audio_primed = false;
}

void VideoStreamPlaybackNDI::_stop() {
	playing = false;

	if (sync != nullptr) {
		ndi->framesync_destroy(sync);
		sync = nullptr;
	}

	if (recv != nullptr) {
		ndi->recv_destroy(recv);
		recv = nullptr;
	}
}

bool VideoStreamPlaybackNDI::_is_playing() const {
	return playing;
}

void VideoStreamPlaybackNDI::_set_paused(bool p_paused) {
	paused = p_paused;
}

bool VideoStreamPlaybackNDI::_is_paused() const {
	return paused;
}

double VideoStreamPlaybackNDI::_get_length() const {
	return 0.0;
}

double VideoStreamPlaybackNDI::_get_playback_position() const {
	return 0.0;
}

void VideoStreamPlaybackNDI::_seek(double p_time) {}

void VideoStreamPlaybackNDI::_set_audio_track(int32_t p_idx) {}

int32_t VideoStreamPlaybackNDI::_get_channels() const {
	return 2;
	// As far as i know this is only querried once by the video player.
	// Might get updated afer stop/play
	// Hardcoded for now :/ Godoot
}

int32_t VideoStreamPlaybackNDI::_get_mix_rate() const {
	return ProjectSettings::get_singleton()->get_setting("audio/driver/mix_rate", 44100);
}

Ref<Texture2D> VideoStreamPlaybackNDI::_get_texture() const {
	return texture;
}

void VideoStreamPlaybackNDI::_update(double p_delta) {
	ERR_FAIL_COND_MSG(recv == nullptr || sync == nullptr, "VideoStreamPlaybackNDI wasn't setup properly");

	// NDI framesync delivers frames instantly but first ones are 0x0
	// Since the VideoStreamPlayer used to only adjust its size for the first frame, this workaround was needed before 4.5
	// PR that fixed it: https://github.com/godotengine/godot/pull/103912

	if (p_delta == 0 && (int)Engine::get_singleton()->get_version_info().get("hex", 0) < 0x040402) {
		// First frame is ticked with delta of 0
		wait_for_non_empty_frame();
	} else {
		if (!external_audio) {
			render_audio(p_delta);
		}
		render_video();
	}
}

void VideoStreamPlaybackNDI::_bind_methods() {}

void VideoStreamPlaybackNDI::update_texture(NDIlib_video_frame_v2_t p_video_frame) {
	Vector2i new_texture_size = Vector2i(p_video_frame.xres, p_video_frame.yres);

	// Copy the data into a PackedByteArray.
	PackedByteArray data;
	data.resize(p_video_frame.line_stride_in_bytes * p_video_frame.yres);
	memcpy(data.ptrw(), p_video_frame.p_data, data.size());

	RID texture_rd_rid = texture->get_texture_rd_rid();

	// If texture of correct size already exists, try to update it.
	if (new_texture_size == texture_size && texture_rd_rid.is_valid()) {
		if (rd->texture_update(texture_rd_rid, 0, data) != OK) {
			ERR_PRINT_ONCE_ED("NDI: Failed to update the video texture (only printed once)");
		}
		return;
	}

	// No existing texture of correct size. Create it.

	if (texture_rd_rid.is_valid()) {
		// Free texture of old size
		rd->free_rid(texture_rd_rid);
	}

	Ref<RDTextureFormat> tf;
	tf.instantiate();
	tf->set_format(RenderingDevice::DATA_FORMAT_B8G8R8A8_UNORM);
	tf->set_width(new_texture_size.x);
	tf->set_height(new_texture_size.y);
	tf->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT);

	// // These don't seem needed, probably defaults.
	// tf->set_depth(1);
	// tf->set_array_layers(1);
	// tf->set_mipmaps(1);
	// tf->set_samples(RenderingDevice::TEXTURE_SAMPLES_1);
	// tf->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);

	Ref<RDTextureView> tv;
	tv.instantiate();

	// RD::texture_create expects the data in a 2D array of layers, even if there is just one.
	Array texture_layers = Array();
	texture_layers.append(data);

	texture_rd_rid = rd->texture_create(tf, tv, texture_layers);

	// Clean up
	texture_layers.clear();
	tv.unref();
	tf.unref();

	// Point Texture2DRD to the new texture.
	texture->set_texture_rd_rid(texture_rd_rid);
	texture_size = new_texture_size;
}

void VideoStreamPlaybackNDI::wait_for_non_empty_frame() {
	for (size_t i = 0; i < 1000; i++) {
		if (render_video()) {
			return;
		}
		OS::get_singleton()->delay_msec(10);
	}

	// Failed to find source after 10s, create placeholder at most common resolution.
	ERR_FAIL_MSG("NDI: Source not found at playback start. It will play at fallback resolution of 1920x1080 once discovered. See docs for NDIOutput.");

	// Hijack NDIlib_video_frame_v2_t struct to create placeholder frame so that update_texture can do the rest.
	// This struct is populated just enough to work for update_texture. Don't let any NDI functions see this.

	NDIlib_video_frame_v2_t placeholder_frame;
	placeholder_frame.xres = 1920;
	placeholder_frame.yres = 1080;
	placeholder_frame.line_stride_in_bytes = placeholder_frame.xres * 4;
	placeholder_frame.p_data = (uint8_t *)calloc(placeholder_frame.line_stride_in_bytes * placeholder_frame.yres, 1);

	update_texture(placeholder_frame); // We can reuse this. YIPPIE

	std::free(placeholder_frame.p_data); // The Godot namspace overrides free, so gotta be explicit here.
}

bool VideoStreamPlaybackNDI::render_video() {
	bool updated = false;

	NDIlib_video_frame_v2_t video_frame;
	ndi->framesync_capture_video(sync, &video_frame, NDIlib_frame_format_type_progressive);

	if (video_frame.p_data != nullptr && video_frame.xres != 0 && video_frame.yres != 0 && (video_frame.FourCC == NDIlib_FourCC_type_BGRA || video_frame.FourCC == NDIlib_FourCC_type_BGRX)) {
		update_texture(video_frame);
		updated = true;
	}

	ndi->framesync_free_video(sync, &video_frame);

	return updated;
}

// Stream Rooms patch (fallback path, used when the game doesn't pull the audio itself):
//  - fractional samples are carried over instead of truncated every frame (that drained the
//    player's buffer by up to one sample per frame);
//  - no cap at the frame-sync queue depth (the frame-sync is meant to be pulled at the rate you
//    want; capping lost audio whenever a packet was late);
//  - a short pre-roll gives the player's buffer some slack against frame-time jitter;
//  - large pulls are written in chunks instead of dropping everything past 4096 samples.
void VideoStreamPlaybackNDI::render_audio(double p_delta) {
	const int rate = _get_mix_rate();
	audio_owed += (double)rate * p_delta;
	if (!audio_primed) {
		audio_owed += rate * 0.06; // 60 ms of slack
		audio_primed = true;
	}
	int requested_samples = (int)audio_owed;
	if (requested_samples <= 0) {
		return;
	}
	audio_owed -= requested_samples;

	ndi->framesync_capture_audio_v2(sync, &audio_frame, rate, _get_channels(), requested_samples);

	if (audio_frame.p_data != nullptr && audio_frame.no_samples > 0) {
		const int channels = audio_frame.no_channels;
		const int samples = audio_frame.no_samples;
		const int stride = audio_frame.channel_stride_in_bytes > 0 ? audio_frame.channel_stride_in_bytes : samples * 4;
		audio_buffer_interleaved.resize((int64_t)samples * channels);
		float *out = audio_buffer_interleaved.ptrw();
		for (int c = 0; c < channels; c++) {
			const float *plane = (const float *)(audio_frame.p_data + (int64_t)c * stride);
			for (int s = 0; s < samples; s++) {
				out[(int64_t)s * channels + c] = plane[s];
			}
		}

		const int chunk = 4096;
		for (int done = 0; done < samples;) {
			int n = Math::min(chunk, samples - done);
			int written = mix_audio(n, audio_buffer_interleaved, done * channels);
			if (written < n) {
				print_verbose("NDI: player audio buffer full, dropped " + String::num_int64(samples - done - written) + " samples");
				break;
			}
			done += n;
		}
	}

	ndi->framesync_free_audio_v2(sync, &audio_frame);
}

void VideoStreamPlaybackNDI::set_external_audio(bool p_enabled) {
	external_audio = p_enabled;
}

// Pulls p_frames stereo frames at p_mix_rate from the frame-sync. The frame-sync resamples to match
// the rate this is called at, so pulling what the sound card has used keeps audio clock-locked.
// Silence is returned while no audio has arrived.
PackedVector2Array VideoStreamPlaybackNDI::pull_audio(int p_frames, int p_mix_rate) {
	PackedVector2Array out;
	if (sync == nullptr || p_frames <= 0 || p_mix_rate <= 0) {
		return out;
	}
	NDIlib_audio_frame_v3_t frame;
	ndi->framesync_capture_audio_v2(sync, &frame, p_mix_rate, 2, p_frames);
	if (frame.p_data != nullptr && frame.no_samples > 0) {
		const int samples = frame.no_samples;
		const int stride = frame.channel_stride_in_bytes > 0 ? frame.channel_stride_in_bytes : samples * 4;
		const float *left = (const float *)frame.p_data;
		const float *right = frame.no_channels > 1 ? (const float *)(frame.p_data + stride) : left;
		out.resize(samples);
		Vector2 *w = out.ptrw();
		for (int s = 0; s < samples; s++) {
			w[s] = Vector2(left[s], right[s]);
		}
	}
	ndi->framesync_free_audio_v2(sync, &frame);
	return out;
}

int VideoStreamPlaybackNDI::get_audio_queue_depth() const {
	return sync != nullptr ? ndi->framesync_audio_queue_depth(sync) : 0;
}
