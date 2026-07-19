package;

import echoes.Entity;

abstract Color(Int) from Int to Int {
	public static inline function fromRGB(r:Int, g:Int, b:Int):Color {
		return r << 16 | g << 8 | b;
	}
}

@:echoes_replace
typedef Name = String;

enum abstract Shape(String) {
	final CIRCLE;
	final LINE;
	final SQUARE;
	final STAR;
}
