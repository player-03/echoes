package echoes.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using echoes.macro.MacroTools;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;

class ComponentStorageBuilder {
	private static var storageCache:Map<String, ComplexType> = new Map();
	
	public static function getComponentContainer(componentComplexType:ComplexType):ComplexType {
		var componentTypeName:String = componentComplexType.followName();
		var storageTypeName:String = "ComponentStorage_" + componentComplexType.toIdentifier();
		var storageType:ComplexType = storageCache.get(storageTypeName);
		
		if(storageType != null) {
			return storageType;
		}
		
		var storageTypePath:TypePath = { pack: [], name: storageTypeName };
		storageType = TPath(storageTypePath);
		
		var def:TypeDefinition = macro class $storageTypeName extends echoes.ComponentStorage<$componentComplexType> {
			public static var instance(default, null):$storageType = new $storageTypePath();
			
			private function new() {
				super($v{componentTypeName});
			}
		}
		
		Context.defineType(def);
		
		storageCache.set(storageTypeName, storageType);
		
		Report.componentNames.push(componentTypeName);
		Report.gen();
		
		return storageType;
	}
}

#end
