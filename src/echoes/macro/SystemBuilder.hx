package echoes.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using echoes.macro.MacroTools;
using echoes.macro.ViewBuilder;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using Lambda;
using StringTools;

@:allow(echoes.macro.ListenerFunction)
class SystemBuilder {
	private static inline final ADD_META:String = "added";
	private static inline final REMOVE_META:String = "removed";
	private static inline final UPDATE_META:String = "updated";
	private static inline final PRIORITY_META:String = "priority";
	
	private static final genericSystemCache:Map<String, Type> = new Map();
	
	private static inline function notNull<T>(e:Null<T>):Bool {
		return e != null;
	}
	
	/**
	 * Finds the first metadata entry that matches a search term, or comes
	 * close. For the purpose of matching, leading colons are ignored, as is the
	 * prefix "echoes_" if the entry begins with that. Additionally, characters
	 * may be omitted from the end, as long as at least one character from the
	 * search term is found.
	 * 
	 * For example, the following entry names are considered eqivalent:
	 * 
	 * - "updated"
	 * - "upd"
	 * - ":update"
	 * - ":u"
	 * - "echoes_update"
	 * - "echoes_u"
	 * - ":echoes_updated"
	 * 
	 * @param searchTerms A metadata name consisting of lowercase letters (no
	 * colon, no "echoes_").
	 */
	private static function getMeta(meta:Metadata, searchTerm:String):Null<MetadataEntry> {
		for(entry in meta) {
			var name:String = entry.name;
			if(name.startsWith(":")) {
				name = name.substr(1);
			}
			if(name.startsWith("echoes_")) {
				name = name.substr("echoes_".length);
			}
			
			if(name.length > 0 && searchTerm.startsWith(name)) {
				if(!entry.name.startsWith(":")) {
					Context.warning('@${entry.name} is deprecated; use @:${entry.name} instead.'
						+ (entry.name == "remove" ? " (@:remove does have a reserved meaning when applied to interfaces, but not here.)" : ""),
						entry.pos);
				}
				
				return entry;
			}
		}
		
		return null;
	}
	
	private static function getPriority(meta:Metadata):Null<Int> {
		var entry:MetadataEntry = getMeta(meta, PRIORITY_META);
		switch(entry) {
			case null:
			case _.params => [_.expr => EConst(CInt(v))]:
				return Std.parseInt(v);
			default:
		}
		return null;
	}
	
	public static function build():Array<Field> {
		return buildInternal(false);
	}
	
	private static function buildInternal(isGenericBuild:Bool):Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		
		//Information gathering
		//=====================
		
		var substitutions:TypeSubstitutions = null;
		var nameWithParams:String;
		var classType:ClassType = switch(Context.getLocalType()) {
			case TInst(_.get() => inst, types):
				nameWithParams = inst.name;
				
				if(!isGenericBuild && inst.params.length > 0) {
					//Apply some default substitutions to improve completion.
					substitutions = new TypeSubstitutions(inst);
				} else if(types.length > 0) {
					substitutions = new TypeSubstitutions(inst, types);
					nameWithParams += "<" + [for(type in types) new Printer().printComplexType(type.toComplexType())].join(", ") + ">";
				}
				
				inst;
			default:
				Context.warning("SystemBuilder only acts on classes.", Context.currentPos());
				return fields;
		};
		
		/**
		 * `classType`, plus all superclasses in order, including `System`.
		 */
		var parentTypes:Array<ClassType> = [classType];
		{
			var parentType:ClassType = classType;
			while(parentType.superClass != null) {
				parentType = parentType.superClass.t.get();
				parentTypes.push(parentType);
			}
			if(parentTypes.length < 2 || parentType.name != "System"
				|| parentType.pack.length != 1 || parentType.pack[0] != "echoes") {
				Context.fatalError('${ classType.name } must extend echoes.System.', Context.currentPos());
			}
		}
		
		//Non-generic builds may be skipped.
		if(!isGenericBuild) {
			for(type in parentTypes) {
				if(type.meta.has(":skipBuildMacro")) {
					return fields;
				}
			}
		}
		
		//Type substitutions
		//==================
		
		if(substitutions != null) {
			if(!classType.meta.has(":genericBuild")) {
				Context.fatalError("Systems with type parameters must be tagged `@:genericBuild(echoes.macro.SystemBuilder.genericBuild())`.", Context.currentPos());
			}
			
			fields = fields.map(substitutions.substituteField);
		} else {
			if(classType.meta.has(":genericBuild")) {
				Context.fatalError("@:genericBuild requires type parameters.", Context.currentPos());
			}
		}
		
		//Linked views
		//============
		
		/**
		 * Names of views that should activate and deactivate with the system.
		 */
		var linkedViews:Array<String> = [];
		
		//Variable initializers can't actually call `getLinkedView()`, so locate
		//and replace such calls.
		for(field in fields) {
			var expr:Expr = switch(field.kind) {
				case FVar(_, expr), FProp(_, _, _, expr) if(expr != null):
					expr;
				default:
					continue;
			};
			
			var params:Array<Expr> = switch(expr.expr) {
				case ECall(_.expr => EConst(CIdent("getLinkedView")) | EField(_, "getLinkedView"), params):
					params;
				default:
					continue;
			};
			
			//Get the inactive view for now.
			expr.expr = Echoes.getInactiveView(params).expr;
			
			var viewName:String = switch(expr.expr) {
				case EField(_.expr => EConst(CIdent(name)), "instance"):
					name;
				default:
					throw "Echoes.getInactiveView() returned an unexpected format. Please report this change.";
			};
			
			//Save the view to link later.
			if(!linkedViews.contains(viewName)) {
				linkedViews.push(viewName);
			}
		}
		
		//Listener function priorities
		//============================
		
		var updateListeners:Array<ListenerFunction> = fields.map(ListenerFunction.fromField.bind(_, UPDATE_META)).filter(notNull);
		var addListeners:Array<ListenerFunction> = fields.map(ListenerFunction.fromField.bind(_, ADD_META)).filter(notNull);
		var removeListeners:Array<ListenerFunction> = fields.map(ListenerFunction.fromField.bind(_, REMOVE_META)).filter(notNull);
		for(listener in addListeners.concat(removeListeners)) {
			if(listener.wrapperFunction == null) {
				Context.error("An @:add or @:remove listener must take at least one component. (Optional arguments don't count.)", listener.pos);
			}
		}
		
		/**
		 * Update listeners that have `@:priority` tags. Each group of these
		 * will be used to create a `ChildSystem`.
		 */
		var fixedPriorityUpdateListeners:Map<Int, Array<ListenerFunction>> = new Map();
		for(listener in updateListeners) {
			if(listener.priority != null) {
				if(!fixedPriorityUpdateListeners.exists(listener.priority)) {
					fixedPriorityUpdateListeners[listener.priority] = [];
				}
				
				fixedPriorityUpdateListeners[listener.priority].push(listener);
			}
		}
		
		var defaultPriority:Null<Int> = getPriority(classType.meta.get());
		if(defaultPriority != null) {
			fields.pushFields(macro class DefaultPriority {
				private override function __getDefaultPriority__():Int {
					return $v{ defaultPriority };
				}
			});
		}
		
		//Constructor
		//===========
		
		var initializeChildren:Array<Expr> = [for(priority => listeners in fixedPriorityUpdateListeners) {
			var body:Array<Expr> = [for(listener in listeners) listener.callDuringUpdate()];
			body.unshift(macro __dt__ = dt);
			
			macro __addListenersWithPriority__($v{ priority }, function(dt:Float) $b{ body });
		}];
		initializeChildren.push(macro if(parent != null) {
			for(child in __children__) {
				parent.add(child);
			}
		});
		
		switch(fields.find(field -> field.name == "new" || field.name == "_new")) {
			case null:
				//No constructor found; declare a new one.
				fields.push((macro class Constructor {
					public inline function new(?priority:Int) {
						super(priority);
						
						$b{ initializeChildren }
					}
				}).fields[0]);
			case _.getFunctionBody() => body if(body != null):
				if(!body.exists(e -> e.expr.match(
					ECall(_.expr => EConst(CIdent("super")), _)))) {
						body.unshift(macro super());
				}
				
				for(expr in initializeChildren) {
					body.push(expr);
				}
			default:
				//Allow Haxe to throw an error.
		}
		
		//Listener wrappers
		//=================
		
		//Define wrapper functions for each listener.
		for(listener in addListeners.concat(removeListeners).concat(updateListeners)) {
			if(listener.wrapperFunction != null) {
				if(!fields.exists(field -> field.name == listener.wrapperName))
					fields.push(listener.wrapperFunction);
				
				if(!linkedViews.contains(listener.viewName))
					linkedViews.push(listener.viewName);
			}
		}
		
		//New functions
		//=============
		
		//Add useful functions if they aren't already there.
		fields.pushFields(macro class OptionalFields {
			public override function toString():String {
				return $v{ nameWithParams };
			}
		});
		
		//Add lifecycle functions no matter what.
		var requiredFields:TypeDefinition = macro class RequiredFields {
			private override function __activate__():Void {
				if(!active) {
					$b{ [for(view in linkedViews) macro $i{ view }.instance.activate()] }
					
					$b{ addListeners.map(listener -> macro ${ listener.view }.onAdded.push(${ listener.wrapper })) }
					$b{ removeListeners.map(listener -> macro ${ listener.view }.onRemoved.push(${ listener.wrapper })) }
					
					super.__activate__();
					
					//If any entities already exist, call the `@:add` listeners.
					$b{ addListeners.map(listener -> macro ${ listener.view }.iter(${ listener.wrapper })) }
				};
			}
			
			private override function __deactivate__():Void {
				if(active) {
					$b{ [for(view in linkedViews) macro $i{ view }.instance.deactivate()] }
					
					$b{ addListeners.map(listener -> macro ${ listener.view }.onAdded.remove(${ listener.wrapper })) }
					$b{ removeListeners.map(listener -> macro ${ listener.view }.onRemoved.remove(${ listener.wrapper })) }
					
					super.__deactivate__();
				}
			}
			
			private override function __update__(dt:Float):Void {
				#if echoes_profiling
				var __timestamp__ = Date.now().getTime();
				#end
				
				${ if(parentTypes.length <= 2) {
					macro __dt__ = dt;
				} else {
					macro super.__update__(dt);
				} }
				
				$b{ {
					[for(listener in updateListeners) if(listener.priority == null)
						listener.callDuringUpdate()];
				} }
				
				/* ${ {
					expr: ESwitch(macro priority, [for(priority in childPriorities)
						{
							values: [macro $v{ priority }],
							expr: macro $b{
								[for(listener in updateListeners) if(listener.priority == priority)
									listener.callDuringUpdate()]
							}
						}
					], null),
					pos: (macro null).pos
				} } */
				
				#if echoes_profiling
				this.__updateTime__ = Std.int(Date.now().getTime() - __timestamp__);
				#end
			}
		};
		//Put the required fields first so that Haxe will highlight the user's
		//fields in case of a conflict.
		fields = requiredFields.fields.concat(fields);
		
		return fields;
	}
	
	public static function genericBuild():Type {
		var classType:ClassType;
		var name:String;
		switch(Context.getLocalType()) {
			case TInst(_.get() => inst, params):
				classType = inst;
				
				name = inst.name;
				for(param in params) {
					name += "_" + param.toComplexType().toIdentifier(false);
				}
			default:
				return Context.fatalError("SystemBuilder only acts on classes.", Context.currentPos());
		}
		
		var qualifiedName:String = classType.pack.concat([name]).join(".");
		if(genericSystemCache.exists(qualifiedName)) {
			return genericSystemCache[qualifiedName];
		}
		
		if(classType.superClass == null) {
			return Context.fatalError(classType.name + " must extend System.", Context.currentPos());
		}
		
		var superClass:ClassType = classType.superClass.t.get();
		var superClassModule:String = superClass.module.split(".").pop();
		var importsAndUsings:{ imports: Array<ImportExpr>, usings: Array<TypePath> }
			= TypeSubstitutions.getCachedImports(classType);
		
		Context.defineModule(qualifiedName, [{
			pack: classType.pack,
			fields: buildInternal(true),
			kind: TDClass({
				pack: superClass.pack,
				name: superClassModule,
				sub: superClassModule != superClass.name ? superClass.name : null
			}, null, null, null, null),
			pos: Context.currentPos(),
			name: name,
			meta: [{
				//In case the `@:autoBuild` macro runs on the output.
				name: ":skipBuildMacro",
				pos: Context.currentPos()
			}]
		}], importsAndUsings.imports, importsAndUsings.usings);
		
		var type:Type = TPath({
			pack: classType.pack,
			name: name
		}).toType();
		genericSystemCache[qualifiedName] = type;
		return type;
	}
}

@:noCompletion typedef ListenerFunctionData = {
	name:String,
	args:Array<FunctionArg>,
	pos:Position,
	priority:Null<Int>,
	?components:Array<ComplexType>,
	?optionalComponents:Array<ComplexType>,
	?viewName:String,
	?wrapperFunction:Field
};

@:forward
abstract ListenerFunction(ListenerFunctionData) from ListenerFunctionData {
	public static function fromField(field:Field, listenerType:String):ListenerFunction {
		switch(field.kind) {
			case FFun(func):
				if(SystemBuilder.getMeta(field.meta, listenerType) == null) {
					return null;
				}
				
				return {
					name: field.name,
					args: func.args,
					pos: field.pos,
					priority: SystemBuilder.getPriority(field.meta)
				};
			default:
				return null;
		}
	}
	
	public var components(get, never):Array<ComplexType>;
	private function get_components():Array<ComplexType> {
		if(this.components == null) {
			this.components = [];
			
			for(arg in this.args) {
				switch(arg.type.followComplexType()) {
					//Float is reserved for delta time; Entity is reserved for
					//the entity.
					case macro:StdTypes.Float, macro:echoes.Entity:
					default:
						//There are two ways to mark an argument as optional.
						if(!arg.opt && arg.value == null) {
							this.components.push(arg.type.followComplexType());
						}
				}
			}
		}
		
		return this.components;
	}
	
	public var optionalComponents(get, never):Array<ComplexType>;
	private function get_optionalComponents():Array<ComplexType> {
		if(this.optionalComponents == null) {
			this.optionalComponents = [];
			
			for(arg in this.args) {
				switch(arg.type.followComplexType()) {
					//Float is reserved for delta time; Entity is reserved for
					//the entity.
					case macro:StdTypes.Float, macro:echoes.Entity:
					default:
						//There are two ways to mark an argument as optional.
						if(arg.opt || arg.value != null) {
							this.optionalComponents.push(arg.type.followComplexType());
						}
				}
			}
		}
		
		return this.optionalComponents;
	}
	
	public var view(get, never):Expr;
	private inline function get_view():Expr {
		return macro $i{ viewName }.instance;
	}
	
	public var viewName(get, never):String;
	private function get_viewName():String {
		if(this.viewName == null) {
			this.viewName = components.getViewName();
		}
		return this.viewName;
	}
	
	public var wrapper(get, never):Expr;
	private inline function get_wrapper():Expr {
		return macro $i{ wrapperName };
	}
	
	public var wrapperName(get, never):String;
	private inline function get_wrapperName():String {
		return '__${ this.name }_bridge__';
	}
	
	/**
	 * A wrapper function for this. This wrapper can safely be passed to
	 * `view.iter()`, `view.onAdded`, and/or `view.onRemoved`.
	 */
	public var wrapperFunction(get, never):Field;
	private function get_wrapperFunction():Field {
		if(this.wrapperFunction == null) {
			if(components.length == 0) {
				return null;
			}
			
			//The arguments used in the wrapper function signature.
			var args:Array<FunctionArg> =
				//The view always passes an `Entity` as the first argument.
				[{ name: "entity", type: macro:echoes.Entity }]
				//The remaining arguments must also be in the view's order.
				.concat(ViewBuilder.getComponentOrder(components)
					//Make sure to use the same names as the listener function.
					.map(type -> {
						name: this.args.find(arg -> arg.type.followName() == type.followName()).name,
						type: type
					}));
			for(arg in args) {
				if(arg.name == null) {
					Context.error('Could not locate an argument of type ${arg.type.followName()}. Please report this error, and include information about the type.', this.pos);
				}
			}
			
			this.wrapperFunction = {
				name: wrapperName,
				kind: FFun({
					args: args,
					ret: macro:Void,
					expr: call()
				}),
				pos: Context.currentPos()
			};
		}
		
		return this.wrapperFunction;
	}
	
	/**
	 * Calls this listener. The returned expression will refer to `__dt__`,
	 * `entity`, and any required components, so it's important to ensure all of
	 * these values are available in the current context.
	 */
	private function call():Expr {
		var args:Array<Expr> = [for(arg in this.args) {
			switch(arg.type.followComplexType()) {
				case macro:StdTypes.Float:
					//Defined as a private variable of `System`.
					macro __dt__;
				case macro:echoes.Entity:
					//Defined as a wrapper function's first argument, and also
					//defined in `callDuringUpdate()`.
					macro entity;
				default:
					if(arg.opt || arg.value != null) {
						//Look up the optional component's value. (May be null
						//and that's fine.)
						EntityTools.get(macro entity, arg.type.followComplexType());
					} else {
						//Defined as one of the wrapper function's arguments.
						macro $i{ arg.name };
					}
			}
		}];
		
		return macro $i{ this.name }($a{ args });
	}
	
	/**
	 * Calls this listener one or more times as part of an `@:update` step.
	 */
	public function callDuringUpdate():Expr {
		if(components.length > 0) {
			//Iterate over a `View`'s entities.
			return macro $view.iter($wrapper);
		} else {
			//No components to filter by, but there may still be an `Entity`
			//argument. (And/or a `Float` argument, which isn't relevant.)
			for(arg in this.args) {
				switch(arg.type.followComplexType()) {
					case macro:echoes.Entity:
						//Iterate over all entities.
						return macro for(entity in echoes.Echoes.activeEntities)
							${ call() };
					default:
				}
			}
			
			//Don't iterate over anything.
			return call();
		}
	}
}

#end
