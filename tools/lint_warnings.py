# A rough stand-in for the editor's script warnings, which only show when a script is opened in
# the editor. Looks through every .gd file for the kinds the owner keeps finding:
#   - a local, loop variable or parameter named like a member of the script's base class
#     (SHADOWED_VARIABLE_BASE_CLASS), a global function (SHADOWED_GLOBAL_IDENTIFIER) or a
#     script-level name (SHADOWED_VARIABLE)
#   - a division between two whole numbers (INTEGER_DIVISION), unless the line above says
#     @warning_ignore("integer_division")
# It guesses: read each line it prints before changing anything.
#   python tools\lint_warnings.py
# GitHub runs it on every pull request (.github/workflows/tests.yml); it fails when anything is listed.
import glob
import os
import re
import sys

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

MEMBERS = {
    "Object": {"free", "connect", "disconnect", "emit_signal", "notification", "to_string", "get_class", "set", "get",
               "call", "callv", "set_meta", "get_meta", "has_meta", "get_script", "set_script", "tr",
               "is_queued_for_deletion", "cancel_free", "get_instance_id", "is_class", "set_deferred", "call_deferred"},
    "Node": {"name", "owner", "process", "ready", "tree", "multiplayer", "duplicate", "filter", "print_tree",
             "rpc", "queue_free", "replace_by", "propagate_call", "request_ready", "set_process", "reparent",
             "add_child", "remove_child", "get_child", "get_parent", "is_inside_tree", "get_node", "find_child",
             "get_index", "move_child", "get_path", "add_sibling", "unique_name_in_owner", "process_mode"},
    "Node3D": {"position", "rotation", "scale", "transform", "basis", "visible", "quaternion", "global_position",
               "global_rotation", "global_transform", "show", "hide", "look_at", "translate", "rotate", "to_local",
               "to_global", "orthonormalize", "top_level", "visibility_parent", "global_basis"},
    "CanvasItem": {"visible", "modulate", "material", "light_mask", "z_index", "show", "hide", "draw_line", "draw_rect",
                   "draw_circle", "draw_string", "draw_texture", "get_canvas", "get_viewport", "queue_redraw",
                   "top_level", "clip_children", "texture_filter", "texture_repeat", "self_modulate"},
    "Control": {"size", "position", "scale", "rotation", "pivot_offset", "theme", "tooltip_text", "focus_mode",
                "mouse_filter", "layout_direction", "grab_focus", "release_focus", "has_focus", "get_rect",
                "get_global_rect", "set_anchors_preset", "custom_minimum_size", "size_flags_horizontal",
                "size_flags_vertical", "clip_contents", "global_position", "get_minimum_size", "update_minimum_size",
                "accept_event", "get_cursor_shape", "get_theme_font", "add_theme_font_override", "offset_left",
                "offset_top", "anchor_left", "anchor_top"},
    "Viewport": {"size", "world_2d", "world_3d", "msaa_2d", "msaa_3d", "transparent_bg", "get_camera_3d", "get_texture",
                 "gui_get_focus_owner", "get_mouse_position", "warp_mouse"},
    "Window": {"title", "mode", "transient", "exclusive", "borderless", "always_on_top", "transparent", "unresizable",
               "popup", "min_size", "max_size", "current_screen", "theme", "wrap_controls", "visible", "position", "size"},
    "Resource": {"resource_name", "resource_path", "duplicate", "emit_changed", "take_over_path",
                 "resource_local_to_scene", "get_rid"},
    "Label": {"text", "horizontal_alignment", "vertical_alignment", "autowrap_mode", "clip_text"},
    "RichTextLabel": {"text", "bbcode_enabled", "fit_content", "scroll_active", "autowrap_mode", "newline", "clear"},
    "BaseButton": {"pressed", "disabled", "toggle_mode", "button_pressed", "shortcut"},
    "Button": {"text", "icon", "flat", "alignment"},
    "Camera3D": {"fov", "near", "far", "current", "projection", "size", "environment", "attributes"},
    "Light3D": {"light_color", "light_energy", "shadow_enabled", "light_indirect_energy"},
    "Sprite3D": {"texture", "offset", "pixel_size", "billboard", "shaded", "no_depth_test", "render_priority"},
    "Label3D": {"text", "font", "font_size", "outline_modulate", "outline_size", "billboard"},
    "MeshInstance3D": {"mesh", "skin", "skeleton"},
    "ColorRect": {"color"},
    "TextureRect": {"texture", "stretch_mode", "expand_mode"},
    "Timer": {"wait_time", "one_shot", "autostart", "paused", "start", "stop"},
}
INHERIT = {"Node": ["Object"], "Node3D": ["Node"], "CanvasItem": ["Node"], "Control": ["CanvasItem"],
           "Viewport": ["Node"], "Window": ["Viewport"], "SubViewport": ["Viewport"], "Resource": ["RefCounted"],
           "RefCounted": ["Object"], "Label": ["Control"], "RichTextLabel": ["Control"], "BaseButton": ["Control"],
           "Button": ["BaseButton"], "CheckBox": ["Button"], "OptionButton": ["Button"], "PanelContainer": ["Control"],
           "ColorRect": ["Control"], "TextureRect": ["Control"], "Container": ["Control"], "HBoxContainer": ["Container"],
           "VBoxContainer": ["Container"], "ScrollContainer": ["Container"], "MeshInstance3D": ["Node3D"],
           "Sprite3D": ["Node3D"], "Label3D": ["Node3D"], "Camera3D": ["Node3D"], "Light3D": ["Node3D"],
           "OmniLight3D": ["Light3D"], "SpotLight3D": ["Light3D"], "Marker3D": ["Node3D"], "Timer": ["Node"],
           "SceneTree": ["Object"], "EditorScript": ["RefCounted"], "AudioStreamPlayer": ["Node"]}
GLOBALS = {"abs", "absf", "absi", "acos", "asin", "atan", "atan2", "ceil", "ceilf", "ceili", "clamp", "clampf", "clampi",
           "cos", "deg_to_rad", "ease", "exp", "floor", "floorf", "floori", "fmod", "fposmod", "hash", "inst_to_dict",
           "is_equal_approx", "is_zero_approx", "lerp", "lerpf", "log", "max", "maxf", "maxi", "min", "minf", "mini",
           "move_toward", "nearest_po2", "pingpong", "posmod", "pow", "print", "push_error", "push_warning",
           "rad_to_deg", "randf", "randi", "randomize", "range", "remap", "round", "roundf", "roundi", "seed", "sign",
           "signf", "signi", "sin", "smoothstep", "snapped", "sqrt", "str", "tan", "typeof", "type_convert",
           "var_to_str", "str_to_var", "weakref", "wrap", "wrapf", "wrapi", "len", "load", "preload", "assert",
           "is_instance_valid", "is_instance_of", "instance_from_id", "char", "ord", "bytes_to_var", "var_to_bytes",
           "error_string", "is_same", "randfn", "cubic_interpolate", "db_to_linear", "linear_to_db", "is_finite",
           "is_inf", "is_nan", "sinh", "cosh", "tanh"}


def members(cls, seen=None):
    seen = seen or set()
    if cls in seen:
        return set()
    seen.add(cls)
    out = set(MEMBERS.get(cls, set()))
    for b in INHERIT.get(cls, []):
        out |= members(b, seen)
    return out


files = [f for f in glob.glob("**/*.gd", recursive=True)
         if not f.replace("\\", "/").startswith(("addons/", "_backup/", "exported/")) and "_tmp_" not in f]
classes = {}
for f in files:
    s = open(f, encoding="utf-8", errors="replace").read()
    m = re.search(r"^class_name\s+(\w+)", s, re.M)
    e = re.search(r"^extends\s+([\w.]+)", s, re.M)
    if m:
        classes[m.group(1)] = e.group(1) if e else "RefCounted"


def base_of(cls):
    for _ in range(10):
        if cls not in classes:
            break
        cls = classes[cls]
    return cls


INT_ISH = re.compile(r"(\.size\(\)|\.length\(\)|\bint\([^()]*\)|\blen\([^()]*\)|\b\d+)\s*/\s*(\(|\bint\(|\d+\b|\w+\.size\(\)|[A-Z_]{3,}\b|\w+)")
found = 0
for f in files:
    s = open(f, encoding="utf-8", errors="replace").read()
    e = re.search(r"^extends\s+([\w.]+)", s, re.M)
    base = base_of(e.group(1)) if e else "RefCounted"
    mem = members(base)
    toplevel = set(re.findall(r"^(?:static\s+)?(?:var|func|signal|const)\s+(\w+)", s, re.M))
    lines = s.split("\n")
    for i, line in enumerate(lines, 1):
        code = line.split("#")[0]
        if not code.strip():
            continue
        names = re.findall(r"\bvar\s+(\w+)", code) + re.findall(r"\bfor\s+(\w+)\s*(?::|in\b)", code)
        fm = re.match(r"^\s*(?:static\s+)?func\s+\w+\(([^)]*)\)", code)
        if fm:
            names += [p.strip().split(":")[0].split("=")[0].strip() for p in fm.group(1).split(",") if p.strip()]
        is_top = not code.startswith(("\t", " "))
        for name in names:
            if not name or name.startswith("_"):
                continue
            if not is_top and name in mem:
                print(f"{f}:{i}: '{name}' shadows a {base} member"); found += 1
            elif name in GLOBALS:
                print(f"{f}:{i}: '{name}' shadows the global {name}()"); found += 1
            elif not is_top and name in toplevel:
                print(f"{f}:{i}: '{name}' shadows a script-level name"); found += 1
        if i >= 2 and 'warning_ignore("integer_division")' in lines[i - 2]:
            continue
        if "/" in code and not re.search(r"\d\.\d|float\(|\.[xyz]\b|randf|delta|lerp|\bfloat\b|\"|'", code):
            m = INT_ISH.search(code)
            if m and not re.search(r"^\d+\.\d", m.group(2)):
                print(f"{f}:{i}: whole-number division? {code.strip()[:100]}"); found += 1
print("candidates:", found)
# Exit code 1 when something was found, so the GitHub check can fail on it.
sys.exit(1 if found else 0)
