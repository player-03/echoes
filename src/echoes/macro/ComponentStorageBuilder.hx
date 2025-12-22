package echoes.macro;

#if macro

import haxe.macro.CompilationServer;
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;
import haxe.PosInfos;

using echoes.macro.MacroTools;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;

class ComponentStorageBuilder {
	public static inline final PREFIX:String = "ComponentStorage_";

	private static final storageCache:Map<String, TypeDefinition> = new Map();
	
	private static var registered:Bool = false;
	
	public static inline function getComponentStorage(componentComplexType:ComplexType):Expr {
		if(Context.defined("display") || Sys.args().indexOf("--no-output") >= 0) {
			return macro new echoes.ComponentStorage<$componentComplexType>("For code completion only. If you see this at runtime, it's an error.");
		}
		
		return macro @:pos(Context.currentPos()) $i{ getComponentStorageName(componentComplexType) }.instance;
	}
	
	public static function getComponentStorageName(componentComplexType:ComplexType):String {
		componentComplexType = componentComplexType.followComplexType();
		
		final error:String = componentComplexType.getReservedComponentMessage();
		if(error != null) {
			Context.error(error, Context.currentPos());
		}
		
		final storageTypeName:String = PREFIX + componentComplexType.toIdentifier();
		if(storageCache.exists(storageTypeName)) {
			return storageTypeName;
		}
		
		final valueType:Expr = switch(componentComplexType.toType().followWithAbstracts()) {
			case TInst(_.get() => classType, _):
				final parts:Array<String> = classType.pack.copy();
				parts.push(classType.module);
				if(classType.name != classType.module) {
					parts.push(classType.name);
				}
				macro TClass($p{ parts });
			case TEnum(_.get() => enumType, _):
				final parts:Array<String> = enumType.pack.copy();
				parts.push(enumType.module);
				if(enumType.name != enumType.module) {
					parts.push(enumType.name);
				}
				macro TEnum($p{ parts });
			case TFun(_, _):
				macro TFunction;
			case TAnonymous(_):
				macro TObject;
			case TAbstract(_.get() => { pack: [], module: "StdTypes", name: name }, _)
				if(name == "Float" || name == "Int" || name == "Bool"):
				final name:String = "T" + name;
				macro $i{ name };
			default:
				macro TUnknown;
		};
		
		final componentTypeName:String = new Printer().printComplexType(componentComplexType);
		final storageTypePath:TypePath = { pack: [], name: storageTypeName };
		var getInstance:Expr = macro new echoes.ComponentStorage<$componentComplexType>($v{ componentTypeName }, $valueType);
		
		//If a custom singleton is defined, use that instead.
		final componentBaseType:BaseType = componentComplexType.toType().toBaseType();
		final meta:MetaAccess = componentBaseType != null ? componentBaseType.meta : null;
		if(meta != null) {
			switch(meta.extract(":echoes_storage")) {
				case null, []:
				case x if(componentBaseType.params.length > 0):
					Context.error("@:echoes_storage doesn't work with type params, for type " + new Printer().printComplexType(componentComplexType), Context.currentPos());
				case [_.params => [customSingleton]]:
					getInstance = customSingleton;
				default:
			}
		}
		
		final def:TypeDefinition = macro class $storageTypeName {
			public static final instance:echoes.ComponentStorage<$componentComplexType>
				= $getInstance;
		};
		
		storageCache.set(storageTypeName, def);
		if(!registered) {
			registered = true;
			Context.onTypeNotFound(storageCache.get);
		}
		
		Report.componentNames.push(componentTypeName);
		Report.registerCallback();
		
		return storageTypeName;
	}
	
	public static function invalidate():Void {
		if(!Context.defined("display") && Sys.args().indexOf("--no-output") < 0) {
			final filePath:String = ((?infos:PosInfos) -> infos.fileName)();
			CompilationServer.invalidateFiles([filePath]);
		}
	}
}

#end
