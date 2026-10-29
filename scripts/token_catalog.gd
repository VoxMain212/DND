@tool
extends RefCounted
## Built-in and generated portraits. Only hashes, never file paths, cross the network.
const MAX_BYTES := 512 * 1024
const MAX_DIMENSION := 768
static var cache_dir := "user://portraits"
static var _generated: Dictionary = {}
const TEXTURES := {
	"warrior": preload("res://assets/tokens/warrior.png"),
	"mage": preload("res://assets/tokens/mage.png"),
	"rogue": preload("res://assets/tokens/rogue.png"),
	"cleric": preload("res://assets/tokens/cleric.png"),
	"skeleton": preload("res://assets/tokens/skeleton.png"),
}
static func texture(key: String) -> Texture2D:
	if key.begins_with("generated:"):
		var digest := key.trim_prefix("generated:")
		if not _generated.has(digest):
			var bytes := png(digest)
			if not bytes.is_empty():
				store(bytes, digest)
		return _generated.get(digest, TEXTURES.warrior)
	return TEXTURES.get(key, TEXTURES.warrior)

static func valid_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true

static func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func valid_png(bytes: PackedByteArray, limit := MAX_BYTES) -> bool:
	if bytes.size() < 33 or bytes.size() > limit or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return false
	if bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return false
	var width := _big_endian(bytes, 16)
	var height := _big_endian(bytes, 20)
	return width > 0 and height > 0 and width <= MAX_DIMENSION and height <= MAX_DIMENSION

static func _big_endian(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

static func store(bytes: PackedByteArray, expected := "") -> String:
	if not valid_png(bytes):
		return ""
	var key := digest(bytes)
	if not expected.is_empty() and key != expected:
		return ""
	if _generated.has(key) and not png(key).is_empty():
		return key
	if not _generated.has(key) and _generated.size() >= 64:
		return ""
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return ""
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var file := FileAccess.open(cache_dir.path_join(key + ".png"), FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.flush()
	if file.get_error() != OK:
		return ""
	_generated[key] = ImageTexture.create_from_image(image)
	return key

static func png(key: String) -> PackedByteArray:
	if not valid_hash(key):
		return PackedByteArray()
	var path := cache_dir.path_join(key + ".png")
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	return bytes if valid_png(bytes) and digest(bytes) == key else PackedByteArray()

static func has_portrait(key: String) -> bool:
	if _generated.has(key):
		return true
	var bytes := png(key)
	return not bytes.is_empty() and not store(bytes, key).is_empty()
