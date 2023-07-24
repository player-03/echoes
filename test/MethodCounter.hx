package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.PosInfos;
import utest.Assert;

using echoes.macro.MacroTools;

/**
 * For any class that implements `IMethodCounter`, counts the number of times
 * that class's methods are called. This count can later be checked using
 * `assertTimesCalled()`.
 */
class MethodCounter {
	private static var counts:Map<String, Int> = new Map();
	
	/**
	 * Resets all counters.
	 */
	public static inline function reset():Void {
		counts.clear();
	}
	
	/**
	 * Asserts that the specified method was called `count` times since the
	 * latest reset.
	 * @param method A string in the form `"ClassName.methodName"`.
	 * @param debugErrors Whether to list debug information on a failure, to
	 * help locate typos and other mistakes. This information will be thrown as
	 * a `String` error.
	 */
	public static function assertTimesCalled(count:Int, method:String, ?message:String, ?debugErrors:Bool = false, ?pos:PosInfos):Void {
		var actualCount:Int = counts.exists(method) ? counts[method] : 0;
		if(message == null) {
			message = '$method expected $count ' + (count == 1 ? "time" : "times")
				+ ', but was called $actualCount ' + (actualCount == 1 ? "time." : "times.");
		}
		var result:Bool = Assert.equals(count, actualCount, message, pos);
		
		if(!result && debugErrors) {
			var methodClass:String = method.substr(0, method.indexOf(".") + 1);
			if(methodClass.length == 0) {
				throw 'The given method string ($method) has the wrong format.';
			}
			
			var knownMethods:Array<String> = [];
			for(key in counts.keys()) {
				if(StringTools.startsWith(key, methodClass)) {
					knownMethods.push(key.substr(methodClass.length));
				}
			}
			
			if(knownMethods.length == 0) {
				throw 'None of ${methodClass.substr(0, methodClass.length - 1)}\'s methods have been called since the last reset.';
			} else {
				throw "Did you mean one of the following?\n - " + knownMethods.join("\n - ");
			}
		}
	}
	
	@:noCompletion public static function count(key:String):Void {
		if(!counts.exists(key)) {
			counts[key] = 1;
		} else {
			counts[key]++;
		}
	}
	
	@:noCompletion public static macro function build():Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		
		var className:String = Context.getLocalClass().get().name;
		
		for(field in fields) {
			var body:Null<Array<Expr>> = field.getFunctionBody();
			if(body != null) {
				var key:String = '$className.${ field.name }';
				body.unshift(macro MethodCounter.count($v{ key }));
			}
		}
		
		return fields;
	}
}

@:autoBuild(MethodCounter.build())
interface IMethodCounter {}
