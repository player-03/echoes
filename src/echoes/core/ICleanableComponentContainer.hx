package echoes.core;

interface ICleanableComponentContainer {
	var name(get, never):String;
	function exists(id:Int):Bool;
	function getDynamic(id:Int):Dynamic;
	function remove(id:Int):Void;
	function reset():Void;
}
