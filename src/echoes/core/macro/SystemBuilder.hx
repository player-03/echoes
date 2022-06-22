package echoes.core.macro;

#if macro

import echoes.core.macro.MacroTools.*;
import echoes.core.macro.ViewBuilder.*;
import echoes.core.macro.ComponentBuilder.*;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using haxe.macro.ComplexTypeTools;
using haxe.macro.TypeTools;
using haxe.macro.Context;
using echoes.core.macro.MacroTools;
using StringTools;
using Lambda;

class SystemBuilder {
	private static var SKIP_META = "skip";
	
	private static var PRINT_META = "print";
	
	private static var ADD_META = "added";
	private static var REMOVE_META = "removed";
	private static var UPDATE_META = "updated";
	
	@:deprecated public static var systemIndex = -1;
	@:deprecated public static var systemIds = new Map<String, Int>();
	
	private static inline function notNull<T>(e:Null<T>):Bool {
		return e != null;
	}
	private static inline function notSkipped(field:Field):Bool {
		return !skipped(field);
	}
	private static inline function skipped(field:Field):Bool {
		return containsMeta(field, SKIP_META);
	}
	private static inline function isEntity(a:FunctionArg):Bool {
		return switch(a.type.followComplexType()) {
			case macro:StdTypes.Int, macro:echoes.Entity : true;
			default: false;
		};
	}
	
	/**
	 * Similar to `getMeta()`, but returns a boolean value indicating presence
	 * or absence of metadata.
	 */
	private static inline function containsMeta(field:Field, searchTerm:String):Bool {
		return getMeta(field, searchTerm) != null;
	}
	
	/**
	 * Finds the first metadata matching the `searchTerm`. Also checks several
	 * similar search terms:
	 * 
	 * - `"echoes_" + searchTerm`
	 * - `":" + searchTerm`
	 * - `":echoes_" + searchTerm`
	 * - All strings that can be formed by removing characters from the end of
	 *   any of the above. (E.g., `":" + searchTerm.substr(0, 3)`.)
	 * 
	 * @param searchTerms One or more metadata names.
	 */
	private static function getMeta(field:Field, ...searchTerms:String):Null<MetadataEntry> {
		return field.meta.find(function(meta:MetadataEntry):Bool {
			var name:String = meta.name;
			if(name.startsWith(":")) {
				name = name.substr(1);
			}
			if(name.startsWith("echoes_")) {
				name = name.substr("echoes_".length);
			}
			
			return name.length > 0
				&& searchTerms.toArray().exists(searchTerm -> searchTerm.startsWith(name));
		});
	}
	
	public static function build():Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		
		var clsType:ClassType = Context.getLocalClass().get();
		if(clsType == null) {
			Context.warning("SystemBuilder only acts on classes.", Context.currentPos());
			return fields;
		}
		
		systemIds[Context.getLocalType().toComplexType().followName()] = ++systemIndex;
		
		var definedViews = new Array<DefinedView>();
		
		// find and init manually defined views
		for(field in fields) {
			if(skipped(field)) continue;
			
			switch(field.kind) {
				// defined var only
				case FVar(cls, _) if(cls != null):
					var complexType = cls.followComplexType();
					switch(complexType) {
						// tpath only
						case TPath(_):
							var clsName = complexType.followName();
							// if it is a view, it was built (and collected to cache) when followComplexType() was called
							if(viewCache.exists(clsName)) {
								// init
								field.kind = FVar(complexType, macro $i{clsName}.inst());
								
								definedViews.push({
									name: field.name,
									inst: macro $i{ field.name }.inst(),
									cls: complexType,
									components: viewCache.get(clsName).components
								});
							}
						default:
					}
				default:
			}
		}
		
		// find and init meta defined views
		for(field in fields) {
			if(skipped(field)) {
				continue;
			}
			
			var meta:Null<MetadataEntry> = getMeta(field, ADD_META, UPDATE_META, REMOVE_META);
			if(meta == null) {
				continue;
			}
			
			//Encourage users to include a colon in their metadata, making an
			//exception for `@remove`, since `@:remove` has another meaning.
			//(It's still fine to use it, but some users might not want to.)
			if(!meta.name.startsWith(":") && meta.name != "remove") {
				Context.warning('@${meta.name} is deprecated; use @:${meta.name} instead.', meta.pos);
			}
			
			switch(field.kind) {
				case FFun(func):
					var components:Array<ComplexType> = (func.args:FunctionArgs).toComponentTypes();
					
					if(components.length > 0) {
						var viewClsName:String = getViewName(components);
						var view = definedViews.find(v -> v.cls.followName() == viewClsName);
						
						if(view == null) {
							definedViews.push({
								name: viewClsName,
								inst: macro $i{ viewClsName }.inst(),
								cls: getView(components),
								components: viewCache.get(viewClsName).components
							});
						}
					}
				default:
			}
		}
		
		/**
		 * Gets data about a listener function, such as the view it represents
		 * and the arguments it requires.
		 */
		function procMetaFunc(field:Field):MetaFunc {
			switch(field.kind) {
				case FFun(func):
					var funcName = field.name;
					var funcCallArgs = (func.args:FunctionArgs).toCallArgs();
					var components = (func.args:FunctionArgs).toComponentTypes();
					
					if(components.length > 0) {
						// view iterate
						
						var viewClsName = getViewName(components);
						var view = definedViews.find(v -> v.cls.followName() == viewClsName);
						var viewArgs = [ arg("entity", macro:echoes.Entity) ].concat(view.components.toFunctionArgs(func.args));
						
						return { name: funcName, args: funcCallArgs, view: view, viewargs: viewArgs, type: VIEW_ITER, field: field };
					} else {
						if(func.args.exists(isEntity)) {
							// every entity iterate
							Context.warning("Are you sure you want to iterate over all the entities? If not, you should add some components or remove the Entity / Int argument", field.pos);
							
							return { name: funcName, args: funcCallArgs, view: null, viewargs: null, type: ENTITY_ITER, field: field };
						} else {
							// single call
							return { name: funcName, args: funcCallArgs, view: null, viewargs: null, type: SINGLE_CALL, field: field };
						}
					}
				default:
					return null;
			}
		}
		
		var ufuncs:Array<MetaFunc> = fields.filter(notSkipped).filter(containsMeta.bind(_, UPDATE_META)).map(procMetaFunc).filter(notNull);
		var afuncs:Array<MetaFunc> = fields.filter(notSkipped).filter(containsMeta.bind(_, ADD_META)).map(procMetaFunc).filter(notNull);
		var rfuncs:Array<MetaFunc> = fields.filter(notSkipped).filter(containsMeta.bind(_, REMOVE_META)).map(procMetaFunc).filter(notNull);
		
		var listeners:Array<MetaFunc> = afuncs.concat(rfuncs);
		
		//Define functions to bridge the gap between the `View`'s events and the
		//listeners. (The difference being that arguments might not be in the
		//same order.)
		for(listener in listeners.concat(ufuncs)) {
			if(listener.viewargs == null) {
				Context.error("An @:add or @:remove listener must take at least one component argument.", listener.field.pos);
			}
			
			fields.push({
				name: '__${listener.name}_listener__',
				kind: FFun({
					args: listener.viewargs,
					ret: macro:Void,
					expr: macro $i{ listener.name }($a{ listener.args })
				}),
				pos: Context.currentPos()
			});
		};
		
		//Add a couple convenience fields if they aren't already there.
		var optionalFields:TypeDefinition = macro class OptionalFields {
			public inline function new() {}
			
			public override function toString():String {
				return $v{ clsType.name };
			}
		};
		for(optionalField in optionalFields.fields) {
			if(!fields.exists(field -> field.name == optionalField.name)) {
				fields.push(optionalField);
			}
		}
		
		//Add some lifecycle functions no matter what.
		var requiredFields:TypeDefinition = macro class RequiredFields {
			@:noCompletion public override function __activate__():Void {
				if(!activated) {
					activated = true;
					
					__dt__ = 0;
					
					//Activate views.
					$b{ definedViews.map(v -> macro ${ v.inst }.activate()) }
					
					//Add `@:add` and `@:remove` listeners.
					$b{ afuncs.map(f -> macro ${ f.view.inst }.onAdded.add($i{ '__${f.name}_listener__' })) }
					$b{ rfuncs.map(f -> macro ${ f.view.inst }.onRemoved.add($i{ '__${f.name}_listener__' })) }
					
					//Call all `@:add` listeners, in case entities were created
					//while the system was inactive.
					$b{ afuncs.map(f -> macro ${ f.view.inst }.iter($i{ '__${f.name}_listener__' })) }
					
					super.__activate__();
				};
			}
			
			@:noCompletion public override function __deactivate__():Void {
				if(activated) {
					activated = false;
					super.__deactivate__();
					
					//Deactivate views.
					$b{ definedViews.map(v -> macro ${ v.inst }.deactivate()) }
					
					//Remove `@:add` and `@:remove` listeners.
					$b{ afuncs.map(f -> macro ${ f.view.inst }.onAdded.remove($i{ '__${f.name}_listener__' })) }
					$b{ rfuncs.map(f -> macro ${ f.view.inst }.onRemoved.remove($i{ '__${f.name}_listener__' })) }
				}
			}
			
			@:noCompletion public override function __update__(dt:Float):Void {
				#if echoes_profiling
				var __timestamp__ = Date.now().getTime();
				#end
				
				__dt__ = dt;
				
				$b{
					ufuncs.map(f ->
						switch(f.type) {
							case SINGLE_CALL:
								macro $i{ f.name }($a{ f.args });
							case VIEW_ITER:
								macro ${ f.view.inst }.iter($i{ '__${f.name}_listener__' });
							case ENTITY_ITER:
								macro for(entity in echoes.Workflow.entities)
									$i{ f.name }($a{ f.args });
						}
					)
				}
				
				#if echoes_profiling
				this.__updateTime__ = Std.int(Date.now().getTime() - __timestamp__);
				#end
			}
		};
		//Put the required fields first so that Haxe will highlight the user's
		//fields in case of a conflict.
		fields = requiredFields.fields.concat(fields);
		
		if(clsType.meta.has(PRINT_META)) {
			Sys.println(new Printer().printTypeDefinition({
				pack: clsType.pack,
				name: clsType.name,
				pos: clsType.pos,
				kind: TDClass({ pack: ["echoes"], name: "System" }),
				fields: fields,
				meta: clsType.meta.get()
			}));
		}
		
		return fields;
	}
}

typedef MetaFunc = {
	name:String,
	args:Array<Expr>,
	view:Null<DefinedView>,
	viewargs:Array<FunctionArg>,
	type:MetaFuncType,
	field:Field
};

@:enum abstract MetaFuncType(Int) {
	var SINGLE_CALL = 1;
	var VIEW_ITER = 2;
	var ENTITY_ITER = 3;
}

typedef DefinedView = {
	/**
	 * The view's class name. (Not lowercase anymore.)
	 */
	name:String,
	/**
	 * The view's singleton instance.
	 */
	inst:Expr,
	cls:ComplexType,
	components:ComponentTypes
};

@:forward
abstract FunctionArgs(Array<FunctionArg>) from Array<FunctionArg> to Array<FunctionArg> {
	@:to public function toComponentTypes():Array<ComplexType> {
		var types:Array<ComplexType> = [];
		for(arg in this) {
			switch(arg.type.followComplexType()) {
				case macro:StdTypes.Float, macro:StdTypes.Int, macro:echoes.Entity:
				default:
					types.push(arg.type.followComplexType());
			}
		}
		return types;
	}
	
	@:to public function toCallArgs():CallArgs {
		return [for(arg in this) {
			switch(arg.type.followComplexType()) {
				case macro:StdTypes.Float : macro __dt__;
				case macro:StdTypes.Int : macro entity;
				case macro:echoes.Entity : macro entity;
				default: macro $i{ arg.name };
			}
		}];
	}
}

@:forward
abstract ComponentTypes(Array<ComplexType>) from Array<ComplexType> to Array<ComplexType> {
	public function toFunctionArgs(args:Array<FunctionArg>):FunctionArgs {
		return [for(type in this) {
			var componentClsName = type.followName();
			var a = args.find(a -> a.type.followName() == componentClsName);
			if(a != null) {
				arg(a.name, a.type);
			} else {
				arg(type.typeName().toLowerCase(), type);
			}
		}];
	}
}

@:forward
abstract CallArgs(Array<Expr>) from Array<Expr> to Array<Expr> {
}

#end
