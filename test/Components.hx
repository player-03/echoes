package;

abstract Color(Int) from Int to Int {
	public static inline function fromRGB(r:Int, g:Int, b:Int):Color {
		return r << 16 | g << 8 | b;
	}
}

enum abstract Shape(String) {
	var CIRCLE;
	var LINE;
	var SQUARE;
	var STAR;
}

@:echoes_replace
typedef Name = String;
