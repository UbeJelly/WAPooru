@tool class_name WAPooruClient extends HTTPRequest

#region Variables

enum Get {
	TREE,
	LANG,
	IMG
}

var query: int = 0
var trees: Array = []				# List of langs trees (i.e. main dir)
var i_url: Array = []				# List of langs' images (blob urls)
var blobs: Array = []				# List of img blobs to use as texture
var waifu: PackedStringArray = []	# List of waifu image cache paths

var files_path: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)+"/WAPooru"
var waifu_path: String = files_path+"/Waifus"								## The download directory
var cache_path: String = OS.get_user_data_dir()+"/cache"					## Caches to %AppData%/Roaming/WAPooru
var saves_path: String = cache_path+"/ImgList"								## Save file path

## Path of auth.json which contains data of repo owner and API token
var _AUTH_PATH: String = ProjectSettings.globalize_path("res://.env/%s")	

var git_url := "https://api.github.com/repos/%s/Anime-Girls-Holding-Programming-Books/git"
var headers := [
	"Accept: image/avif,image/webp,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5",
	"Authorization: Bearer %s"
]

@export_category("Terminal")
@export var print_data := false			## Show or hide the requested data.

@onready var languages: VBoxContainer = $%Languages
@onready var catalog: ScrollContainer = $%Catalog
@onready var waifus: HFlowContainer = $%Waifus

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
	_init_directory(waifu_path)
	#_init_directory(cache_path)

	if not Engine.is_editor_hint():
		get_repo_tree()
		await request_completed
		set_langs_buttons(trees)

		var endpoint: String = trees[randi_range(0, trees.size()-1)]["url"].trim_prefix(git_url)
		get_language(endpoint)
		await request_completed

		set_waifu_thumbnails(i_url)

#endregion

#region API calls

## The main function that requests various endpoints.
## [param url] is the main url that hosts the API.
## [param endpoint] is the request endpoint, e.g. /trees/master.
## [param method] is the method which uses this function for specific requests.
func WAPooruClient(url: String, endpoint: String, method: String) -> void:
	if not url == "" or not endpoint == "":
		var error: int = 0
		error = request(url + endpoint, headers, HTTPClient.METHOD_GET)
		if error == OK:
			print("\nRequest endpoint: %s" % url + endpoint)
			print_rich("[color=green][b]✓[/b] %s() run successfully.[/color]" % method)
		else:
			print("❌ %s() failed." % method)
	else:
		print("❌ WAPooru() failed. The url or endpoint cannot be empty.")


## Returns a Dictionary of trees, i.e. directories in a repo branch.
## [param endpoint] is the request endpoint.
func get_repo_tree(endpoint: String = "/trees/master") -> void:
	query = Get.TREE
	WAPooruClient(git_url, endpoint, "get_repo_tree")


## Returns a Dictionary of waifus w/ coding books.
## [param endpoint] is the request endpoint.
func get_language(endpoint: String) -> void:
	query = Get.LANG
	WAPooruClient(git_url, endpoint, "get_language")


## Returns a blob content of waifus w/ coding books.
## [param endpoint] is the request endpoint.
func get_waifu_blob(endpoint: String, blob_name: String) -> void:
	query = Get.IMG
	WAPooruClient(git_url, endpoint, "get_waifu_blob")
	print_rich("Downloading %s blob[wave]...[/wave]" % blob_name)

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
func set_waifu_thumbnails(list: Array) -> void:
	if not list.is_empty():
		for item in list:
			var endpoint: String = item["url"].trim_prefix(git_url)
			get_waifu_blob(endpoint, item["path"])
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

				print_rich("Loading %s thumbnail[wave]...[/wave]" % image_name.get_file())

				# Bind _on_thumbnail_pressed & its args to TextureButton.pressed signal
				thumbnail.pressed.connect(_on_thumbnail_pressed.bind(texture.get_image(), waifu_path+"/"+image_name))
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
				waifus.add_child(thumbnail, true)

				print_rich("[color=green][b]✓[/b][/color] %s thumbnail loaded successfully." % image_name.get_file())
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


## Gets a waifu image blob content (base64 String).
## [param data] is the object to get and check items from.
func get_waifu(data: Dictionary) -> Dictionary:
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
				blobs.append(get_waifu(data))
				set_thumbnail_texture(blobs.size()-1)


## Signal when a language button is pressed. get_language() then sends a request to get available images from the language.
## [param url] is the url of the languages to get waifu images from.
func _on_langs_btn_pressed(url: String) -> void:
	i_url = []
	blobs = []
	for thumbnail in waifus.get_children():
		thumbnail.queue_free()
	var endpoint := url.trim_prefix(git_url)
	get_language(endpoint)
	await request_completed
	set_waifu_thumbnails(i_url)


func _on_thumbnail_pressed(image: Image, image_save_path: String) -> void:
	var format: String = image_save_path.get_extension()
	match format:
		"png": image.save_png(image_save_path)
		"jpg": image.save_jpg(image_save_path, 1.0)
		"webp": image.save_webp(image_save_path, false, 1.0)
		"bmp": image.save_jpg(image_save_path, 1.0)
	print(image_save_path.get_file()+" was saved successfully on "+image_save_path.get_base_dir())


## TODO: Show a small popup that shows its waifu's name and programming language.
func _on_thumbnail_hovered(button: TextureButton) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(button.get_child(0), "self_modulate", Color(1.125, 1.125, 1.125, 1.0), 0.15).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button.get_child(0), "scale", Vector2(1.125, 1.125), 0.15).set_ease(Tween.EASE_IN_OUT)


## TODO: Hide the small popup.
func _on_thumbnail_unhover(button: TextureButton) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(button.get_child(0), "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(button.get_child(0), "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT_IN)


## Initializes the directory for images.
## [param path] is the directory path to save and load images from.
func _init_directory(path: String = "") -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_absolute(path)


## Saves an array of images into a file.
## [param image_array] is an array of image paths.
func save_images(image_array: PackedStringArray) -> void:
	var file := FileAccess.open(saves_path, FileAccess.WRITE)
	file.store_var(image_array, true)
	file.close()


## Loads a save file of images array.
## [param save_file] is the path of the file to load the image array from.
func load_images(save_file: String) -> PackedStringArray:
	var file := FileAccess.open(save_file, FileAccess.READ)
	var loaded_array = file.get_var(true)
	return loaded_array


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
