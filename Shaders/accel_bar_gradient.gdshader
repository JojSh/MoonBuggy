shader_type canvas_item;

uniform bool is_reverse = false;

void fragment() {
	// UV.y is 0 at top, 1 at bottom - we want gradient from bottom (yellow) to top (red)
	float t = 1.0 - UV.y;

	vec4 color;
	if (is_reverse) {
		// Blue gradient for reverse: dark blue at bottom to light blue at top
		color = vec4(0.2 + 0.3 * t, 0.4 + 0.4 * t, 1.0, 0.8);
	} else {
		// Forward: yellow (bottom) -> orange (middle) -> red (top)
		// Yellow = (1, 1, 0), Orange = (1, 0.5, 0), Red = (1, 0, 0)
		float green = 1.0 - t;  // 1 at bottom, 0 at top
		color = vec4(1.0, green, 0.0, 0.8);
	}

	COLOR = color;
}
