package echoes.macro;

#if macro

#if echoes_report
import haxe.macro.Context;
import haxe.macro.Type;
#end

/**
 * Use `-Dechoes_report` to print all generated components and views, in the
 * order they were processed. Use `-Dechoes_report=sorted` instead to view them
 * in alphabetical order.
 */
class Report {
	@:allow(echoes.macro.ComponentStorageBuilder)
	private static var componentNames:Array<String> = [];
	
	@:allow(echoes.macro.ViewBuilder)
	private static var viewNames:Array<String> = [];
	
	private static var registered = false;
	
	public static function registerCallback():Void {
		#if echoes_report
		
		if(!registered) {
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
			registered = true;
		}
		
		#end
	}
}

#end
