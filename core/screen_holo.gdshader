shader_type spatial;
// See-through screen (hologram rooms). Same as screen.gdshader, plus holo_alpha opacity.
render_mode blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
#define SCREEN_TRANSPARENT
#include "res://core/screen_inc.gdshaderinc"
