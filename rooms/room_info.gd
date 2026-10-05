class_name RoomInfo
extends Resource
## Static description of a swappable room. One room_info.tres per folder in res://rooms/.

@export var id: String = ""
@export var display_name: String = ""
## Path to the room scene (root must use room.gd). Kept as a path so listing
## rooms doesn't load every model into memory.
@export_file("*.tscn") var scene_path: String = ""
@export var sort_order: int = 0
@export var thumbnail: Texture2D

@export_group("Lighting")
@export var environment: Environment
## Scales how strongly the screen lights this room.
@export_range(0.0, 4.0) var screen_light_multiplier: float = 1.0
## Range of the three screen spotlights, in metres.
@export var screen_light_range: float = 22.0
## 0 = plain screen, 1 = LED-dot billboard look (good for giant outdoor screens).
@export_range(0.0, 1.0) var screen_led_amount: float = 0.0
## LEDs across and down the screen when the LED look is on.
@export var screen_led_count: Vector2 = Vector2(320, 180)
## 0 = clean picture, 1 = old projected film (grain, dust, scratches, flicker, weave).
@export_range(0.0, 1.0) var screen_film_amount: float = 0.0
## Colour cast of the faded film stock.
@export var screen_film_tint: Color = Color(1.0, 0.92, 0.78)
## Screen surface: 0 = black glass (TVs, LED walls), ~0.7 = white projection fabric
## (room lights then wash out the picture, like a real projector screen).
@export_range(0.0, 1.0) var screen_matte: float = 0.0
## See-through hologram screen: adds Hologram, Transparency and Glitch controls to the Room tab.
@export var screen_hologram: bool = false

@export_group("Audio")
@export var ambience: AudioStream
@export_range(0.0, 1.0) var reverb_room_size: float = 0.35
@export_range(0.0, 1.0) var reverb_damping: float = 0.5
@export_range(0.0, 1.0) var reverb_wet: float = 0.12
## 0 = clean sound. 1 = a small, old speaker: narrow band, mono, a little distortion
## and film "flutter". Scaled by the Speaker FX setting.
@export_range(0.0, 1.0) var speaker_lofi: float = 0.0
