package echoes.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using echoes.macro.MacroTools;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;

class ComponentStorageBuilder {
	public static inline final PREFIX:String = "ComponentStorage_";

	private static var storageCache:Map<String, TypeDefinition> = new Map();
	
	private static var registered:Bool = false;
	
	public static inline function getComponentStorage(componentComplexType:ComplexType):Expr {
		return macro @:pos(Context.currentPos()) $i{ getComponentStorageName(componentComplexType) }.instance;
	}
	
	public static function getComponentStorageName(componentComplexType:ComplexType):String {
		componentComplexType = componentComplexType.followComplexType();
		
		var error:String = componentComplexType.getReservedComponentMessage();
		if(error != null) {
			Context.error(error, Context.currentPos());
		}
		
		var storageTypeName:String = PREFIX + componentComplexType.toIdentifier();
		if(storageCache.exists(storageTypeName)) {
			return storageTypeName;
		}
		
		var componentTypeName:String = new Printer().printComplexType(componentComplexType);
		var storageTypePath:TypePath = { pack: [], name: storageTypeName };
		var storageType:ComplexType = TPath(storageTypePath);
		var def:TypeDefinition = macro class $storageTypeName extends echoes.ComponentStorage<$componentComplexType> {
			public static final instance:$storageType = new $storageTypePath();
			
			//Known issue: after a failed build, this line may produce "Missing
			//function body" errors. Workaround: restart the language server.
			private function new() {
				super($v{ componentTypeName });
			}
		};
		
		storageCache.set(storageTypeName, def);
		if(!registered) {
			registered = true;
			Context.onTypeNotFound(storageCache.get);
		}
		
		Report.componentNames.push(componentTypeName);
		Report.gen();
		
		return storageTypeName;
	}
}

#end
