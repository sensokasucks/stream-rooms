class_name SafeText
extends RefCounted
## Cleans chat text before a RichTextLabel lays it out.
## Redot 26.2's line breaker trips over a space (or tab, or other blank) followed by combining
## marks: Zalgo text, a lone U+FE0F emoji variation selector or U+200D joiner after a space, and
## so on. Every layout of that message then logs "Parameter "sd" is null" and "p_start < 0 ||
## p_length < 0" errors and the broken line is dropped. Marks after a blank have nothing to sit
## on anyway, so they are removed; everything else is left alone.


## The text with combining marks that follow a blank removed. Marks at the very start go too,
## because the chat window and speech bubble put a space or an emote before each piece of text.
static func clean(s: String) -> String:
	if s.is_empty() or s.to_utf8_buffer().size() == s.length():     # plain ASCII: nothing to fix
		return s
	var ts := TextServerManager.get_primary_interface()
	var t := " " + s
	# grapheme ends: a space plus the marks stuck to it is one grapheme. After a tab or a line
	# break the marks are graphemes of their own; " " + them being one grapheme gives them away.
	var ends := ts.string_get_character_breaks(t)
	var out := ""
	var from := 0
	var changed := false
	for end in ends:
		var c := t.unicode_at(from)
		if end - from > 1 and _is_blank(c):
			out += t[from]
			changed = true
		elif from > 0 and _is_break(t.unicode_at(from - 1)) and ts.string_get_character_breaks(" " + t.substr(from, end - from)).size() == 1:
			changed = true
		else:
			out += t.substr(from, end - from)
		from = end
	return out.substr(1) if changed else s


## Tab, line breaks and other control blanks: the marks after them don't join them.
static func _is_break(c: int) -> bool:
	return (c >= 0x09 and c <= 0x0D) or c == 0x85 or c == 0x2028 or c == 0x2029


static func _is_blank(c: int) -> bool:
	return c == 0x20 or (c >= 0x09 and c <= 0x0D) or c == 0x85 or c == 0xA0 or c == 0x1680 \
		or (c >= 0x2000 and c <= 0x200A) or c == 0x2028 or c == 0x2029 or c == 0x202F or c == 0x205F or c == 0x3000
