class_name UIKit
extends RefCounted
## Small factory helpers so every screen shares one pixel UI style.

const INK := Color("2e222f")
const WHITE := Color("ffffff")
const PALE := Color("c7dcd0")
const GOLD := Color("f9c22b")
const RED := Color("e83b3b")
const ECHO := Color("30e1b9")
const DIM := Color("7f708a")


static func label(text: String, font_key := "main", color := WHITE, outline := 0, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Game.font(font_key))
	l.add_theme_font_size_override("font_size", Game.font_size(font_key))
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", outline)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0.18, 0.13, 0.18, 0.9))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func big_label(text: String, px := 30, color := WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Game.font("big"))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel(kind := "panel", rect := Rect2(0, 0, 100, 40)) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = load("res://assets/ui/%s.png" % kind)
	p.patch_margin_left = 6
	p.patch_margin_right = 6
	p.patch_margin_top = 6
	p.patch_margin_bottom = 6
	p.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	p.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func icon(icon_name: String, pos := Vector2.ZERO, scale := 1.0) -> TextureRect:
	var t := TextureRect.new()
	var path := "res://assets/ui/icon_%s.png" % icon_name
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/items/%s.png" % icon_name
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.position = pos
	t.scale = Vector2(scale, scale)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


static func rect(color: Color, r: Rect2) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Korean particle picker: josa("불도롱뇽", "은", "는") -> "불도롱뇽은",
## josa("잿빛늑대", "은", "는") -> "잿빛늑대는" (checks the final consonant).
static func josa(word: String, with_final: String, without_final: String) -> String:
	if word.is_empty():
		return without_final
	var c := word.unicode_at(word.length() - 1)
	if c >= 0xAC00 and c <= 0xD7A3 and (c - 0xAC00) % 28 != 0:
		return word + with_final
	return word + without_final


static func full(ctrl: Control) -> void:
	ctrl.position = Vector2.ZERO
	ctrl.size = Game.VIEW
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
