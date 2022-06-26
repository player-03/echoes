package echoes.core.macro;

#if macro

import echoes.core.macro.MacroTools.*;
import echoes.core.macro.ViewBuilder.*;
import echoes.core.macro.ComponentBuilder.*;
import haxe.macro.Context;

using Lambda;

@:final
@:dce
class Report {
	private static var reportRegistered = false;
	
	public static function gen():Void {
		#if echoes_report
		
		if(!reportRegistered) {
			Context.onGenerate(function(types) {
				function sortedlist(array:Array<String>) {
					array.sort(compareStrings);
					return array;
				}
				
				var ret:StringBuf = new StringBuf();
				ret.add("ECHOES BUILD REPORT:");
				
				ret.add('\n    COMPONENTS [${componentNames.length}]:');
				ret.add("\n        " + sortedlist(componentNames.mapi(function(i, k) return '$k #${ componentIds.get(k) }').array()).join("\n        "));
				ret.add('\n    VIEWS [${viewNames.length}]:');
				ret.add("\n        " + sortedlist(viewNames.mapi(function(i, k) return '$k #${ viewIds.get(k) }').array()).join("\n        "));
				Sys.println(ret.toString());
			});
			reportRegistered = true;
		}
		
		#end
	}
}

#end
