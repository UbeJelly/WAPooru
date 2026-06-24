@tool class_name GALerieClient extends HTTPRequest

#region Variables

enum Get { TREE, LANG, IMG }

var is_hovered_meta := false		## Toggles on hover [url]; for tooltips

var query: int = 0					## Current query type (e.g. Get.TREE)
var trees: Array = []				## List of langs trees (i.e. main dir)
var i_url: Array = []				## List of langs' images (blob urls)
var blobs: Array = []				## List of img blobs to use as texture

var files_path: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)+"/GALerie"
var anime_path: String = files_path+"/Anime_Girls"	## The download directory

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

@onready var tabs: Array = get_tree().get_nodes_in_group("Tabs")
@onready var bars: Array = get_tree().get_nodes_in_group("Scrollbars")

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


func _ready() -> void:
	_set_auth(_get_auth())
	_init_directory(files_path)
	_init_directory(anime_path)
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

## Pushes terminal outputs on Logs section.
func push_logs(text: String) -> void:
	logs_text.text += text+"\n"

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
			var newline := ""
			if not method == "get_repo_tree":
				newline = "\n"
			var endpoint_log := "%sRequest endpoint: %s" % [newline, url + endpoint]
			var success_run := "[color=%s][b]✓[/b] %s() run successfully.[/color]"
			print(endpoint_log)
			push_logs(endpoint_log)
			print_rich(success_run % ["green", method])
			push_logs(success_run % ["2aa300", method])
		else:
			var failed_run := "[color=%s][b]❌[/b] %s() failed.[/color]"
			print_rich(failed_run % ["red", method])
			push_logs(failed_run % ["cc0000", method])
	else:
		var missing_args := "[color=%s][b]❌[/b] GALerie() failed. The url or endpoint cannot be empty."
		print_rich(missing_args % "red")
		push_logs(missing_args % "cc0000")


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
	var download_notice := "%sDownloading %s blob%s...%s"
	print_rich(download_notice % ["", blob_name, "[wave]", "[/wave]"])
	push_logs(download_notice % [" [roll][b][i] )[/i][/b][/roll]  ", blob_name, " [bounce]", "[/bounce]"])

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
			var endpoint: String = item["url"].trim_prefix(git_url)
			get_anime_blob(endpoint, item["path"])
			await request_completed


## Creates a texture after each image blob request.
## [param index] is the current index in the array of blobs.
func set_thumbnail_texture(index: int) -> void:
	var blob: String = blobs[index]["content"]
	if not blob == null:
		var buffer: PackedByteArray = Marshalls.base64_to_raw(blob)
		if not buffer == null:
			var imagetexture = load_image_from_buffer(buffer)
			if not imagetexture == null:
				var texture = imagetexture
				var thumbnail := TextureButton.new()
				var thumbnail_texture := TextureRect.new()

				# Save images as resource to load by valid resource paths
				var image_name: String = i_url[index]["path"]
				var texture_res_path: String = "user://%s.res" % image_name
				ResourceSaver.save(texture, texture_res_path)

				var thumbnail_load_notice := "%sLoading %s thumbnail%s...%s"
				print_rich(thumbnail_load_notice % ["", image_name.get_file(), "[wave]", "[/wave]"])
				push_logs(thumbnail_load_notice % [" [roll][b][i] )[/i][/b][/roll]  ", image_name.get_file(), " [bounce]", "[/bounce]"])

				# Bind _on_thumbnail_pressed & its args to TextureButton.pressed signal
				thumbnail.pressed.connect(_on_thumbnail_pressed.bind(texture.get_image(), anime_path+"/"+image_name))
				thumbnail.mouse_entered.connect(_on_thumbnail_hovered.bind(thumbnail))
				thumbnail.mouse_exited.connect(_on_thumbnail_unhover.bind(thumbnail))

				thumbnail.clip_contents = true
				thumbnail.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
				thumbnail.custom_minimum_size = Vector2((catalog.size.x/3)-10, (catalog.size.y/3)-10)

				thumbnail_texture.texture = texture
				thumbnail.name = image_name.get_file()
				thumbnail_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				thumbnail_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				thumbnail_texture.custom_minimum_size = Vector2((catalog.size.x/3)-10, (catalog.size.y/3)-10)
				thumbnail_texture.pivot_offset = Vector2(thumbnail_texture.custom_minimum_size.x/2, thumbnail_texture.custom_minimum_size.y/2)
				thumbnail_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
				thumbnail.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

				thumbnail.add_child(thumbnail_texture, true)
				animes.add_child(thumbnail, true)

				var thumbnail_success := "[color=%s][b]✓[/b][/color] %s thumbnail loaded successfully."
				print_rich(thumbnail_success % ["green", image_name.get_file()])
				push_logs(thumbnail_success % ["2aa300", image_name.get_file()])
	else:
		print("Blob not found, nothing to make Image resource from.")
		return

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
	for item in data["tree"]:
		if item["type"] == "blob":
			var obj := { "path": item["path"], "url": item["url"] }
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
	var error_msg: String = "\n%s"+paths["name"]+"%s"+paths["dir"]+"%s"

	match format:
		"png": error = image.save_png(image_save_path)
		"jpg": error = image.save_jpg(image_save_path, 1.0)
		"webp": error = image.save_webp(image_save_path, false, 1.0)
		"bmp": error = image.save_jpg(image_save_path, 1.0)

	if error == OK:
		print_rich(error_msg % ["[color=%s][b]✓ Successfully saved[/b][/color] [url underline=always tooltip='View image' href={file}]".format(paths), "[/url] on [url underline=always tooltip='Open folder' href={dir}]".format(paths), "[/url]\n"] % "green")
		push_logs(error_msg % ["[color=%s][b]✓ Successfully saved[/b][/color] [url underline=always tooltip='View image' href={file}]".format(paths), "[/url] on [url underline=always tooltip='Open folder' href={dir}]".format(paths), "[/url]\n"] % "2aa300")
	else:
		print_rich(error_msg % ["[color=%s][b]❌ Failed to save[/b][/color] ", " on ", "\n"] % "red")
		push_logs(error_msg % ["[color=%s][b]❌ Failed to save[/b][/color] ", " on ", "\n"] % "cc0000")


## TODO: Show a small popup that shows its anime's name and programming language.
func _on_thumbnail_hovered(button: TextureButton) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(button.get_child(0), "self_modulate", Color(1.125, 1.125, 1.125, 1.0), 0.15).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button.get_child(0), "scale", Vector2(1.125, 1.125), 0.25).set_ease(Tween.EASE_IN)


## TODO: Hide the small popup.
func _on_thumbnail_unhover(button: TextureButton) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(button.get_child(0), "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(button.get_child(0), "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT)


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


## Initializes the directory for images.
## [param path] is the directory path to save and load images from.
func _init_directory(path: String = "") -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_absolute(path)


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


## Reusable signal callable for any hoverable nodes with metadata.
## [param meta] is any object which will be executed by OS.shell_open().
## [param source] is the node which has this meta.
func _on_meta_hover_entered(_meta: Variant, source: RichTextLabel) -> void:
	is_hovered_meta = true
	tooltip.size = Vector2.ZERO
	tooltip.scale = Vector2.ZERO
	tooltip.text = source.get_tooltip(source.get_local_mouse_position())
	tooltip.show()
	var tween: Tween = create_tween()
	tween.tween_property(tooltip, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BOUNCE)


## The reverse of _on_meta_hover_entered() where it detects mouse exit.
## [param meta] is any object which will be executed by OS.shell_open().
## [param source] is the node which has this meta.
func _on_meta_hover_exited(_meta: Variant, _source: RichTextLabel) -> void:
	is_hovered_meta = false
	var tween: Tween = create_tween()
	tween.tween_property(tooltip, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BOUNCE)
	await tween.loop_finished
	tooltip.hide()
	tooltip.text = ""
	tooltip.size = Vector2.ZERO
	tooltip.position = Vector2(0, -32)


func _on_tab_hovered(tab: int, source: TabContainer) -> void:
	is_hovered_meta = true
	tooltip.size = Vector2.ZERO
	tooltip.scale = Vector2.ZERO
	tooltip.text = source.get_tab_metadata(tab)
	tooltip.show()
	var tween: Tween = create_tween()
	tween.tween_property(tooltip, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BOUNCE)


func _on_tab_unhovered() -> void:
	is_hovered_meta = false
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
	if node is PopupPanel:
		if source.name == "LogsText":
			node.queue_free()
