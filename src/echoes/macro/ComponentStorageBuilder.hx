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
		
		if(componentComplexType.match(macro:Dynamic)) {
			Context.error("Can't use Dynamic as a component type.", Context.currentPos());
		}
		
		final storageTypeName:String = PREFIX + componentComplexType.toIdentifier();
		if(storageCache.exists(storageTypeName)) {
			return storageTypeName;
		}
		
		final valueType:Expr = switch(componentComplexType.toType().followWithAbstracts()) {
			case TInst(_.get() => classType, _) if(!classType.isPrivate):
				macro TClass(${ classType.toClassExpr() });
			case TEnum(_.get() => enumType, _) if(!enumType.isPrivate):
				macro TEnum(${ enumType.toClassExpr() });
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
		var instanceType:ComplexType = macro:echoes.ComponentStorage<$componentComplexType>;
		var getInstance:Expr = macro new echoes.ComponentStorage<$componentComplexType>($v{ componentTypeName }, $valueType);
		
		//If a custom singleton is defined, use that instead.
		final componentBaseType:BaseType = componentComplexType.toType().toBaseType();
		final meta:MetaAccess = componentBaseType != null ? componentBaseType.meta : null;
		if(meta != null) {
			switch(meta.extract(":echoes_storage")) {
				case null, []:
				case [_.params => [expr = _.expr => ENew(t, params)]]:
					if(t.params.length > 0) {
						switch(componentComplexType) {
							case TPath(_.params => args) if(args != null):
								final args:Array<ComplexType> = [for(arg in args) switch(arg) {
									case TPType(t):
										t;
									case TPExpr(_):
										break;
								}];
								if(args.length == t.params.length) {
									final substitutions = new TypeSubstitutions(componentBaseType, args);
									expr = substitutions.substituteExpr(expr);
									t = substitutions.substituteTypePath(t);
								} else {
									final printer:Printer = new Printer();
									Context.warning('Could not apply type parameters: expected ${ t.params.length }, got ${ args.map(printer.printComplexType) }', Context.currentPos());
								}
							default:
						}
					}
					
					getInstance = expr;
					instanceType = TPath(t);
				case [_.params => [expr]]:
					getInstance = expr;
				default:
			}
		}
		
		final def:TypeDefinition = macro class $storageTypeName {
			public static final instance:$instanceType = $getInstance;
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
