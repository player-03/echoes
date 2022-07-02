package echoes.core.macro;

#if macro

import haxe.macro.Context;
import haxe.macro.Type;

/**
 * Use `-Dechoes_report` to print all generated components and views, in the
 * order they were processed. Use `-Dechoes_report=sorted` instead to view them
 * in alphabetical order.
 */
class Report {
	@:allow(echoes.core.macro.ComponentStorageBuilder)
	private static var componentNames:Array<String> = [];
	
	@:allow(echoes.core.macro.ViewBuilder)
	private static var viewNames:Array<String> = [];
	
	private static var reportRegistered = false;
	
	public static function gen():Void {
		#if echoes_report
		
		if(!reportRegistered) {
			Context.onGenerate(function(types:Array<Type>):Void {
				if(Context.definedValue("echoes_report") == "sorted") {
					componentNames.sort(MacroTools.compareStrings);
					viewNames.sort(MacroTools.compareStrings);
				}
				
				Sys.println("ECHOES BUILD REPORT:\n"
					+ '    COMPONENTS [${componentNames.length}]:\n'
					+ "        " + componentNames.join("\n        ") + "\n"
					+ '    VIEWS [${viewNames.length}]:\n'
					+ "        " + viewNames.join("\n        "));
			});
			reportRegistered = true;
		}
		
		#end
	}
}

#end
