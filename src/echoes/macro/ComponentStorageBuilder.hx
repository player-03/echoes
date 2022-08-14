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
		switch(componentTypeName) {
			case "echoes.Entity":
				Context.error('Entity is not an allowed component type. Try using a typedef, an abstract, or Int instead.', Context.currentPos());
			case "StdTypes.Float":
				Context.error('Float is not an allowed component type. Try using a typedef or an abstract instead.', Context.currentPos());
			default:
		}
		
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
