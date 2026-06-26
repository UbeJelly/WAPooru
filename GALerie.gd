@tool class_name GALerieClient extends HTTPRequest

#region Variables

enum Get { TREE, LANG, IMG }

var is_hovered_meta := false	## Toggles on hover [url]; for tooltips
var push_log_output := true		## Toggles log output setting
var allow_animation := true		## Toggles animations setting
var sync_no_motions := false	## Follows system's prefers-reduced-motion
var settings_values := {
	"push_log_output": push_log_output,
	"allow_animation": allow_animation,
	"sync_no_motions": sync_no_motions,
}

var query: int = 0				## Current query type (e.g. Get.TREE)
var trees: Array = []			## List of langs trees (i.e. main dir)
var i_url: Array = []			## List of langs' images (blob urls)
var blobs: Array = []			## List of img blobs to use as texture
var cache_blobs: Array = []		## List of cached texture resources

var files_path: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)+"/GALerie"
var anime_path: String = files_path+"/Anime_Girls"			## The download directory
var config_sav: String = files_path+"/settings.json"		## The settings save file
var cache_path: String = OS.get_user_data_dir()+"/cache"	## %AppData%/Roaming/GALerie/cache
var saves_path: String = cache_path+"/caches.json"			## Cache data save file

## Path of auth.json which contains data of repo owner and API token
var _AUTH_PATH: String = ProjectSettings.globalize_path("res://.env/%s")
var git_url := "https://api.github.com/repos/%s/Anime-Girls-Holding-Programming-Books/git"
var headers := [
	"Accept: image/avif,image/webp,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5",
	"Authorization: Bearer %s"
]

@export_category("Terminal")
@export var print_data := false		## Show or hide the requested data.

@onready var gui: Panel = $GUI
@onready var languages: VBoxContainer = $%Langs
@onready var catalog: ScrollContainer = $%Catalog
@onready var animes: HFlowContainer = $%Gals
@onready var logs_text: RichTextLabel = $%LogsText
@onready var tooltip: RichTextLabel = $%Tooltip

@onready var push_log_output_toggle: CheckButton = $%PushLogOutputToggle
@onready var allow_animation_toggle: CheckButton = $%EnableAnimationsButton
@onready var sync_no_motions_toggle: CheckButton = $%FollowReducedMotionsButton

@onready var tabs: Array = get_tree().get_nodes_in_group("Tabs")
@onready var bars: Array = get_tree().get_nodes_in_group("Scrollbars")

@onready var bounce_fx: RichTextEffect = Bounce.new()
@onready var roll_fx: RichTextEffect = Roll.new()

#endregion

#region Settings

## Saves a Dictionary of settings values into a file.
## [param save_data] are settings values to save.
func save_settings(save_data: Dictionary) -> void:
	var file := FileAccess.open(config_sav, FileAccess.WRITE)
	var json_text = JSON.stringify(save_data, "\t")
	if file:
		file.store_string(json_text)
		file.close()


## Loads a save file of settings values.
## [param save_file] is the path of the file to load the settings values from.
func load_settings(save_file: String) -> Dictionary:
	var data := {}
	if FileAccess.file_exists(save_file):
		var file = FileAccess.open(save_file, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			if not JSON.parse_string(json_text) == settings_values:
				save_settings(settings_values)
			else:
				data = JSON.parse_string(json_text)
			file.close()
	return data


## Pushes terminal outputs on Logs section.
func push_logs(text: String) -> void:
	logs_text.text += text+"\n"


func _on_setting_toggled(toggled_on: bool, source: BaseButton) -> void:
	match source.name:
		"PushLogOutputToggle":
			push_log_output = toggled_on
			settings_values["push_log_output"] = push_log_output
			save_settings(settings_values)

		"EnableAnimationsButton":
			allow_animation = toggled_on
			settings_values["allow_animation"] = allow_animation
			bounce_fx._set("animated", allow_animation)
			roll_fx._set("animated", allow_animation)
			save_settings(settings_values)


func _init_settings() -> void:
	load_cached_files(cache_path)

	logs_text.custom_effects = []

	if not Engine.is_editor_hint():
		logs_text.install_effect(bounce_fx)
		logs_text.install_effect(roll_fx)

	if DisplayServer.accessibility_should_reduce_animation() == 1:
		sync_no_motions = true
		settings_values["sync_no_motions"] = sync_no_motions
	else:
		sync_no_motions = false
		settings_values["sync_no_motions"] = sync_no_motions
	sync_no_motions_toggle.button_pressed = sync_no_motions

	save_settings(settings_values)
	settings_values = load_settings(config_sav)

	if sync_no_motions == true:
		settings_values["allow_animation"] = false
	else:
		settings_values["allow_animation"] = allow_animation

	save_settings(settings_values)
	settings_values = load_settings(config_sav)

	push_log_output = settings_values["push_log_output"]
	push_log_output_toggle.button_pressed = push_log_output

	save_settings(settings_values)
	settings_values = load_settings(config_sav)

	if settings_values["allow_animation"] == true:
		allow_animation = settings_values["allow_animation"]
		allow_animation_toggle.button_mask = 1
		allow_animation_toggle.shortcut_feedback = true
		allow_animation_toggle.shortcut_in_tooltip = true
		allow_animation_toggle.focus_mode = Control.FOCUS_ALL
		allow_animation_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
		allow_animation_toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		allow_animation_toggle.button_pressed = true
		bounce_fx._set("animated", true)
		roll_fx._set("animated", true)
	else:
		allow_animation = false
		allow_animation_toggle.button_mask = 0
		allow_animation_toggle.shortcut_feedback = false
		allow_animation_toggle.shortcut_in_tooltip = false
		allow_animation_toggle.focus_mode = Control.FOCUS_NONE
		allow_animation_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		allow_animation_toggle.mouse_default_cursor_shape = Control.CURSOR_ARROW
		allow_animation_toggle.button_pressed = false
		bounce_fx._set("animated", false)
		roll_fx._set("animated", false)

#endregion

#region Initialize

func _set_auth(auth_file: String) -> void:
	var data: String = FileAccess.get_file_as_string(_AUTH_PATH % auth_file)
	var auth: Dictionary = JSON.parse_string(data)
	git_url = git_url % auth["owner"]
	headers[1] = headers[1] % auth["token"]


func _get_auth() -> String:
	var JSON_file_name := ""
	var dir = DirAccess.open(_AUTH_PATH % "")
	if dir:
		for file in dir.get_files():
			if file.get_extension().to_lower() == "json":
				JSON_file_name = file
	else:
		print("An error occurred when trying to access the path.")
	return JSON_file_name


## Initializes the directory for images.
## [param path] is the directory path to save and load images from.
func _init_directory(path: String = "") -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_absolute(path)


## Loads saved texture resources from cache_path.
## [param path] is the directory of the cached files.
func load_cached_files(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir:
		for file in dir.get_files():
			if file.get_extension().to_lower() == "res":
				cache_blobs.append(file.get_file().trim_suffix(".res"))


func _ready() -> void:
	_set_auth(_get_auth())
	_init_directory(files_path)
	_init_directory(anime_path)

	_init_settings()

	set_tabs()
	set_bars()

	if not Engine.is_editor_hint():
		get_repo_tree()
		await request_completed
		set_langs_buttons(trees)

		var endpoint: String = trees[randi_range(0, trees.size()-1)]["url"].trim_prefix(git_url)
		get_language(endpoint)
		await request_completed

		set_anime_thumbnails(i_url)

#endregion

#region API calls

## The main function that requests various endpoints.
## [param url] is the main url that hosts the API.
## [param endpoint] is the request endpoint, e.g. /trees/master.
## [param method] is the method which uses this function for specific requests.
func GALerieClient(url: String, endpoint: String, method: String) -> void:
	if not url == "" or not endpoint == "":
		var error: int = 0
		error = request(url + endpoint, headers, HTTPClient.METHOD_GET)
		if error == OK:
			if push_log_output == true:
				var newline := ""
				if not method == "get_repo_tree":
					newline = "\n"

				var endpoint_log := "%sRequest endpoint: %s" % [newline, url + endpoint]
				var success_run := "[color=%s][b]✓[/b] %s() run successfully.[/color]"

				format_output_prints(endpoint_log, [""], [""])
				format_output_prints(success_run, ["green", method], ["2aa300", method])
		else:
			if push_log_output == true:
				format_output_prints(
					"[color=%s][b]❌[/b] %s() failed.[/color]",
					["red", method], ["cc0000", method]
				)
	else:
		if push_log_output == true:
			format_output_prints(
				"[color=%s][b]❌[/b] GALerie() failed. The url or endpoint cannot be empty.",
				["red"], ["cc0000"]
			)


## Returns a Dictionary of trees, i.e. directories in a repo branch.
## [param endpoint] is the request endpoint.
func get_repo_tree(endpoint: String = "/trees/master") -> void:
	query = Get.TREE
	GALerieClient(git_url, endpoint, "get_repo_tree")


## Returns a Dictionary of animes w/ coding books.
## [param endpoint] is the request endpoint.
func get_language(endpoint: String) -> void:
	query = Get.LANG
	GALerieClient(git_url, endpoint, "get_language")


## Returns a blob content of animes w/ coding books.
## [param endpoint] is the request endpoint.
func get_anime_blob(endpoint: String, blob_name: String) -> void:
	query = Get.IMG
	GALerieClient(git_url, endpoint, "get_anime_blob")

	if push_log_output == true:
		format_output_prints(
			"%sDownloading %s blob%s",
			["", blob_name, "[wave]...[/wave]"],
			[" [roll][b][i] )[/i][/b][/roll]  ", blob_name, " [bounce]...[/bounce]"]
		)

#endregion

#region Load GUI

## Creates the languages buttons, then sets as children of Languages node.
## [param list] is an array of objects that contains the path and url of a language.
func set_langs_buttons(list: Array) -> void:
	if not list.is_empty():
		for item in list:
			var button := Button.new()
			button.name = item["path"]
			button.text = item["path"]
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.set_meta("url", item["url"])
			button.pressed.connect(_on_langs_btn_pressed.bind(button.get_meta("url")))
			languages.add_child(button, true)


## Loads image from buffer and sets a new ImageTexture based from its supported Image format.
## [param buffer] is the buffer to load image data from.
func load_image_from_buffer(buffer: PackedByteArray) -> ImageTexture:
	if buffer.is_empty():
		return null

	var image := Image.new()
	var error := ERR_INVALID_DATA

	var signatures: Dictionary[StringName, PackedByteArray] = {
		"png": [137, 80, 78, 71, 13, 10, 26, 10],
		"jpg": [255, 216, 255],
		"webp": [82, 73, 70, 70],
		"bmp": [66, 77],
		"gif": [71, 73, 70]
	}

	if buffer.size() >= 8 and buffer.slice(0, 8) == signatures["png"]:
		error = image.load_png_from_buffer(buffer)
	elif buffer.size() >= 3 and buffer.slice(0, 3) == signatures["jpg"]:
		error = image.load_jpg_from_buffer(buffer)
	elif buffer.size() >= 4 and buffer.slice(0, 4) == signatures["webp"]:
		error = image.load_webp_from_buffer(buffer)
	elif buffer.size() >= 2 and buffer.slice(0, 2) == signatures["bmp"]:
		error = image.load_bmp_from_buffer(buffer)
	elif buffer.size() >= 3 and buffer.slice(0, 3) == signatures["gif"]:
		print("GIF format detected, but unsupported by Image load buffers.")
		return null
	else:
		error = image.load_tga_from_buffer(buffer) # fallback

	if error == OK:
		return ImageTexture.create_from_image(image)
	else:
		print("Failed to parse image from buffer. Error code: ", error)

	return null


## Loop thru i_url[] and make request each url.
## [param list] is the array which contains the blobs to request from.'
## list = i_url[{ "path": item["path"], "url": item["url"] }]
func set_anime_thumbnails(list: Array) -> void:
	if not list.is_empty():
		for item in list:
			var endpoint: String = ""
			if item["url"].trim_prefix(git_url) == "cached":
				set_thumbnail_texture(list.find(item))
			else:
				endpoint = item["url"].trim_prefix(git_url)
				get_anime_blob(endpoint, item["path"])
				await request_completed


## Creates a texture after each image blob request.
## [param index] is the current index in the array of blobs.
func set_thumbnail_texture(index: int) -> void:
	if i_url.size() > 0:
		var image_name: String = ""
		var texture = null
		var thumbnail := TextureButton.new()
		var thumbnail_texture := TextureRect.new()
		var thumbnail_info = null
		var thumbnail_info_text = null

		if not i_url[index]["url"] == "cached":
			var blob: String = blobs[index]["content"]
			if not blob == null:
				var buffer: PackedByteArray = Marshalls.base64_to_raw(blob)
				if not buffer == null:
					var imagetexture = load_image_from_buffer(buffer)
					if not imagetexture == null:
						texture = imagetexture

						# Save images as resource to load by valid resource paths
						image_name = i_url[index]["path"]
						var texture_res_path: String = cache_path+"/%s.res" % image_name
						ResourceSaver.save(texture, texture_res_path)
						thumbnail_texture.texture = texture
			else:
				print("Blob not found, nothing to make Image resource from.")

		else:
			image_name = i_url[index]["path"]
			texture = load(cache_path+"/%s.res" % image_name)
			thumbnail_texture.texture = texture

		if push_log_output == true:
			format_output_prints(
				"%sLoading %s thumbnail%s...%s",
				["", image_name.get_file(), "[wave]", "[/wave]"],
				[" [roll][b][i] )[/i][/b][/roll]  ", image_name.get_file(), " [bounce]", "[/bounce]"]
			)

		# Bind _on_thumbnail_pressed & its args to TextureButton.pressed signal
		thumbnail.pressed.connect(_on_thumbnail_pressed.bind(texture.get_image(), anime_path+"/"+image_name))
		thumbnail.mouse_entered.connect(_on_thumbnail_hovered.bind(thumbnail))
		thumbnail.mouse_exited.connect(_on_thumbnail_unhover.bind(thumbnail))

		thumbnail.clip_contents = true
		thumbnail.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		thumbnail.custom_minimum_size = Vector2((catalog.size.x/3)-10, (catalog.size.y/3)-10)

		thumbnail.name = image_name.get_file()
		thumbnail.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		thumbnail_info = load("res://ThumbnailInfo.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		thumbnail_info.custom_minimum_size = Vector2((catalog.size.x/3)-10, 60)
		thumbnail_info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		thumbnail_info.position.y = thumbnail.custom_minimum_size.y

		thumbnail.add_child(thumbnail_info, true)

		if not thumbnail_info == null:
			thumbnail_info_text = thumbnail_info.get_child(0)

			if not thumbnail_info_text == null:
				thumbnail_info_text.text = image_name.get_file().trim_suffix("."+image_name.get_extension()).replace("_", " ").replace("Holding", "holding")

				if " In " in thumbnail_info_text.text:
					thumbnail_info_text.text = thumbnail_info_text.text.replace(" In ", " in ")

				if " At " in thumbnail_info_text.text:
					thumbnail_info_text.text = thumbnail_info_text.text.replace(" The ", " at ")

		thumbnail.add_child(thumbnail_texture, true)
		animes.add_child(thumbnail, true)

		if push_log_output == true:
			format_output_prints(
				"[color=%s][b]✓[/b][/color] %s thumbnail loaded successfully.",
				["green", image_name.get_file()],
				["2aa300", image_name.get_file()]
			)

		thumbnail_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumbnail_texture.custom_minimum_size = Vector2((catalog.size.x/3)-10, (catalog.size.y/3)-10)
		thumbnail_texture.pivot_offset = Vector2(thumbnail_texture.custom_minimum_size.x/2, thumbnail_texture.custom_minimum_size.y/2)

#endregion

#region Lists

## Gets a list of langs trees (i.e. main dir). Use to save to trees[].
## [param data] is the object to get and check items from.
func get_trees(data: Dictionary) -> Array:
	var list: Array = []
	for item in data["tree"]:
		if item["type"] == "tree":
			list.append(item)
	return list


## Gets a list of langs' images (blob urls). Use to save to i_url[].
## [param data] is the object to get and check items from.
func get_langs(data: Dictionary) -> Array:
	var list: Array = []
	var obj := {}
	for item in data["tree"]:
		if item["type"] == "blob":
			if not item["path"].trim_suffix(".res") in cache_blobs: # ignore already cached texture resources
				obj = { "path": item["path"], "url": item["url"] }
			else:
				obj = { "path": item["path"], "url": "cached" }
		list.append(obj)
	return list


## Gets a anime image blob content (base64 String).
## [param data] is the object to get and check items from.
func get_anime(data: Dictionary) -> Dictionary:
	return { "url": data.get("url"), "content": data.get("content") }

#endregion

func _on_request_completed(_result: int, _response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = parse_JSON(body)
	if not data == null:
		match query:
			Get.TREE:
				trees = get_trees(data)
			Get.LANG:
				i_url = get_langs(data)
			Get.IMG:
				blobs.append(get_anime(data))
				set_thumbnail_texture(blobs.size()-1)


## Signal when a language button is pressed. get_language() then sends a request to get available images from the language.
## [param url] is the url of the languages to get anime images from.
func _on_langs_btn_pressed(url: String) -> void:
	cancel_request()
	i_url = []
	blobs = []
	for thumbnail in animes.get_children():
		thumbnail.queue_free()
	var endpoint := url.trim_prefix(git_url)
	get_language(endpoint)
	await request_completed
	set_anime_thumbnails(i_url)


func _on_thumbnail_pressed(image: Image, image_save_path: String) -> void:
	var paths: Dictionary =	{
		"file": image_save_path,
		"name": image_save_path.get_file(),
		"dir": image_save_path.get_base_dir(),
		"format": image_save_path.get_extension()
	}
	var format: String = paths["format"]
	var error: int = ERR_INVALID_DATA
	var error_msg: String= "\n%s"+paths["name"]+"%s"+paths["dir"]+"%s"

	match format:
		"png": error = image.save_png(image_save_path)
		"jpg": error = image.save_jpg(image_save_path, 1.0)
		"webp": error = image.save_webp(image_save_path, false, 1.0)
		"bmp": error = image.save_jpg(image_save_path, 1.0)

	if error == OK:
		if push_log_output == true:
			format_output_prints(
				error_msg,
				["[color=green][b]✓ Successfully saved[/b][/color] [url underline=always tooltip='View image' href={file}]".format(paths), "[/url] on [url underline=always tooltip='Open folder' href={dir}]".format(paths), "[/url]\n"],
				["[color=2aa300][b]✓ Successfully saved[/b][/color] [url underline=always tooltip='View image' href={file}]".format(paths), "[/url] on [url underline=always tooltip='Open folder' href={dir}]".format(paths), "[/url]\n"]
			)

	else:
		if push_log_output == true:
			format_output_prints(
				error_msg,
				["[color=red][b]❌ Failed to save[/b][/color] ", " on ", "\n"],
				["[color=cc0000][b]❌ Failed to save[/b][/color] ", " on ", "\n"]
			)


func _on_thumbnail_hovered(button: TextureButton) -> void:
	var title: PanelContainer = button.get_child(0)
	var thumb: TextureRect = button.get_child(1)

	if allow_animation == true:
		var tween_image_modulate: Tween = create_tween()
		var tween_image_scale: Tween = create_tween()
		var tween_title_position: Tween = create_tween()
		tween_image_modulate.tween_property(thumb, "self_modulate", Color(1.125, 1.125, 1.125, 1.0), 0.15).set_ease(Tween.EASE_IN_OUT)
		tween_image_scale.tween_property(thumb, "scale", Vector2(1.125, 1.125), 0.25).set_ease(Tween.EASE_IN)
		tween_title_position.tween_property(title, "offset_bottom", 0, 0.15).set_ease(Tween.EASE_IN)
	else:
		thumb.self_modulate = Color(1.125, 1.125, 1.125, 1.0)
		thumb.scale = Vector2(1.125, 1.125)
		title.offset_bottom = 0


func _on_thumbnail_unhover(button: TextureButton) -> void:
	var title: PanelContainer = button.get_child(0)
	var thumb: TextureRect = button.get_child(1)

	if allow_animation == true:
		var tween_image_modulate: Tween = create_tween()
		var tween_image_scale: Tween = create_tween()
		var tween_title_position: Tween = create_tween()
		tween_image_modulate.tween_property(thumb, "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT_IN)
		tween_image_scale.tween_property(thumb, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT)
		tween_title_position.tween_property(title, "offset_bottom", 60, 0.15).set_ease(Tween.EASE_OUT)
	else:
		thumb.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
		thumb.scale = Vector2(1.0, 1.0)
		title.offset_bottom = 60


## Sets TabContainer's tab buttons' cursor
func set_tabs() -> void:
	for tab: TabContainer in tabs:
		var tabbar: TabBar = tab.get_tab_bar()
		tabbar.mouse_default_cursor_shape = Control.CursorShape.CURSOR_POINTING_HAND
		tabbar.mouse_exited.connect(_on_tab_unhovered)

		for i in tab.get_child_count():
			tab.set_tab_metadata(i, tab.get_child(i).get_meta("tooltip_text"))


func set_bars() -> void:
	for bar: ScrollContainer in bars:
		var h_scrollbar: HScrollBar = bar.get_h_scroll_bar()
		var v_scrollbar: VScrollBar = bar.get_v_scroll_bar()

		if not h_scrollbar == null:
			h_scrollbar.mouse_default_cursor_shape = Control.CursorShape.CURSOR_HSPLIT
		if not v_scrollbar == null:
			v_scrollbar.mouse_default_cursor_shape = Control.CursorShape.CURSOR_VSPLIT


## Parses JSON and returns as Array, Dictionary, or String.
## [param body] is the received object from a completed request.
func parse_JSON(body: PackedByteArray) -> Variant:
	var json := JSON.new()
	var string: String = body.get_string_from_utf8()
	var error: int = json.parse(string)

	if error == OK:
		var data_got: Variant = json.data
		if typeof(data_got) == TYPE_ARRAY or typeof(data_got) == TYPE_DICTIONARY:
			if print_data == true:
				if not query == Get.IMG:
					print(JSON.stringify(data_got, "\t")+"\n")
			return data_got
		elif typeof(data_got) == TYPE_STRING:
			if print_data == true:
				print("Received blob content.")
			return data_got
		else:
			if print_data == true:
				print("❌ parse_JSON() failed. Unexpected data.")
			return {}
	else:
		if print_data == true:
			print("❌ parse_JSON() error: ", json.get_error_message(), " in ", string, " at line ", json.get_error_line(), ".")
		return {}


#region Hover/click events

## Reusable signal callable for any hoverable nodes with metadata.
## [param meta] is any object which will be executed by OS.shell_open().
## [param source] is the node which has this meta.
func _on_meta_hover_entered(_meta: Variant, source: RichTextLabel) -> void:
	is_hovered_meta = true
	tooltip.size = Vector2.ZERO
	tooltip.show()

	if allow_animation == true:	
		tooltip.scale = Vector2.ZERO
		var tween: Tween = create_tween()
		tween.tween_property(tooltip, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BOUNCE)
	else:
		tooltip.scale = Vector2.ONE

	tooltip.text = source.get_tooltip(source.get_local_mouse_position())


## The reverse of _on_meta_hover_entered() where it detects mouse exit.
## [param meta] is any object which will be executed by OS.shell_open().
## [param source] is the node which has this meta.
func _on_meta_hover_exited(_meta: Variant) -> void:
	is_hovered_meta = false
	if allow_animation == true:
		var tween: Tween = create_tween()
		tween.tween_property(tooltip, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BOUNCE)
		await tween.loop_finished
	tooltip.hide()
	tooltip.text = ""
	tooltip.size = Vector2.ZERO
	tooltip.position = Vector2(0, -32)


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(meta)


func _on_tab_hovered(tab: int, source: TabContainer) -> void:
	if not Engine.is_editor_hint():
		is_hovered_meta = true
		tooltip.size = Vector2.ZERO
		tooltip.show()

		if allow_animation == true:	
			tooltip.scale = Vector2.ZERO
			var tween: Tween = create_tween()
			tween.tween_property(tooltip, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BOUNCE)
		else:
			tooltip.scale = Vector2.ONE

		tooltip.text = source.get_tab_metadata(tab)


func _on_tab_unhovered() -> void:
	if not Engine.is_editor_hint():
		is_hovered_meta = false
		if allow_animation == true:
			var tween: Tween = create_tween()
			tween.tween_property(tooltip, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BOUNCE)
			await tween.finished
		tooltip.hide()
		tooltip.text = ""
		tooltip.size = Vector2.ZERO
		tooltip.position = Vector2(0, -32)


func _process(_delta: float) -> void:
	if is_hovered_meta == true:
		var mouse_position = $GUI.get_global_mouse_position()
		var tooltip_offset := Vector2(16, 12)
		tooltip.position = mouse_position + tooltip_offset


func _on_child_entered_tree(node: Node, source: Node) -> void:
	# Remove default tooltip to display custom tooltip only
	if node is PopupPanel:
		if source.name == "LogsText" or "Info":
			node.queue_free()

#endregion


func _on_button_pressed(source: BaseButton) -> void:
	match source.name:
		"TrashImageCacheButton":
			move_to_trash_cached_files(cache_path)
		"DeleteImageCacheButton":
			delete_cached_files(cache_path)


## Moves to trash the saved texture resources from cache_path.
## [param path] is the directory of the cached files.
func move_to_trash_cached_files(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir:
		for file in dir.get_files():
			if file.get_extension().to_lower() == "res":
				OS.move_to_trash(ProjectSettings.globalize_path(file))


## Deletes permanently the saved texture resources from cache_path.
## [param path] is the directory of the cached files.
func delete_cached_files(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir:
		for file in dir.get_files():
			if file.get_extension().to_lower() == "res":
				dir.remove(file)


## Formats the string outputs for the Godot console and Logs' RichTextLabel.
## The 2 array of args are used for separate functions: print_rich() and push_logs().
## [param godot_console_args] is an array which string in the Godot console would format from i.e. %s will substituted with any values.
## [param logst_text_args] is an array which string in the Logs would format from i.e. %s will be substituted with any values.
func format_output_prints(string: String, godot_console_args: Array, logs_text_args: Array) -> void:
	if not "%s" in string:
		print_rich(string)
		push_logs(string)
	else:
		print_rich(string % godot_console_args)
		push_logs(string % logs_text_args)


func _on_Browse_Gals_resized(source: Control) -> void:
	if not source.get_children().is_empty():
		for thumbnail in source.get_children():
			# Main parent
			thumbnail.custom_minimum_size = Vector2(
			(catalog.size.x/3)-10, (catalog.size.y/3)-10)
			# Title
			thumbnail.get_child(1).custom_minimum_size = Vector2(
			(catalog.size.x/3)-10, (catalog.size.y/3)-10)
			# Image
			thumbnail.get_child(0).custom_minimum_size = Vector2(
			(catalog.size.x/3)-10, 60)
