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

//Templates
//=========

@:build(echoes.Entity.build()) @:optionalArguments(Name)
abstract NamedEntity(Entity) {
	public static inline final DEFAULT_NAME:Name = "defaultName";
	
	public var name:Name = DEFAULT_NAME;
}

@:build(echoes.Entity.build())
abstract NameStringEntity(NamedEntity) {
	public static inline final DEFAULT_STRING:String = "defaultString";
	public static inline final DEFAULT_NAME:String = "name";
	
	public var name:Name = DEFAULT_NAME;
	public var string:String = DEFAULT_STRING;
}

@:build(echoes.Entity.build())
abstract VisualEntity(Entity) {
	public static inline final DEFAULT_COLOR:Color = 0x123456;
	public static inline final DEFAULT_SHAPE:Shape = SQUARE;
	
	public var color:Color = DEFAULT_COLOR;
	public var shape = Shape.CIRCLE;
	
	private inline function onTemplateApplied():Void {
		shape = DEFAULT_SHAPE;
	}
}
