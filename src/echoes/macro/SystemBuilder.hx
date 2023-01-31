package echoes.macro;

#if macro

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using echoes.macro.MacroTools;
using echoes.macro.ViewBuilder;
using StringTools;
using Lambda;

@:allow(echoes.macro.ListenerFunction)
class SystemBuilder {
	private static inline final ADD_META:String = "added";
	private static inline final REMOVE_META:String = "removed";
	private static inline final UPDATE_META:String = "updated";
	private static inline final PRIORITY_META:String = "priority";
	
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
				//Encourage users to include a colon in their metadata.
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
	
	private static function getPriority(meta:Metadata, defaultPriority:Int):Int {
		var entry:MetadataEntry = getMeta(meta, PRIORITY_META);
		switch(entry) {
			case null:
			case { params: [{ expr: EConst(CInt(v))}] }:
				return Std.parseInt(v);
			default:
		}
		return defaultPriority;
	}
	
	public static function build():Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		
		var classType:ClassType = Context.getLocalClass().get();
		if(classType == null) {
			Context.warning("SystemBuilder only acts on classes.", Context.currentPos());
			return fields;
		} else {
			var parentType:ClassType = classType;
			while(true) {
				if(parentType.meta.has(":skipBuildMacro")) {
					return fields;
				}
				
				if(parentType.superClass != null) {
					parentType = parentType.superClass.t.get();
				} else {
					break;
				}
			}
		}
		
		var priority:Int = getPriority(classType.meta.get(), 0);
		
		/**
		 * Names of views that should activate and deactivate with the system.
		 */
		var linkedViews:Array<String> = [];
		
		//Locate `makeLinkedView()` calls in variable initializers. These will
		//cause compile errors when they access `this`, so we have to link the
		//view a different way.
		for(field in fields) {
			switch(field.kind) {
				case FVar(_.followComplexType() => TPath({ name: viewName }), expr),
						FProp(_, _, _.followComplexType() => TPath({ name: viewName }), expr)
						if(viewName.isView()):
					switch(expr) {
						case macro makeLinkedView(), macro this.makeLinkedView():
							//Save the view to link later.
							if(!linkedViews.contains(viewName)) linkedViews.push(viewName);
							
							//Get the view normally, without activating.
							expr.expr = (macro echoes.Echoes.getSingleton(false)).expr;
						default:
					}
				default:
			}
		}
		
		//Locate marked functions.
		var updateListeners:Array<ListenerFunction> = fields.map(ListenerFunction.fromField.bind(_, UPDATE_META, priority)).filter(notNull);
		var addListeners:Array<ListenerFunction> = fields.map(ListenerFunction.fromField.bind(_, ADD_META, priority)).filter(notNull);
		var removeListeners:Array<ListenerFunction> = fields.map(ListenerFunction.fromField.bind(_, REMOVE_META, priority)).filter(notNull);
		for(listener in addListeners.concat(removeListeners)) {
			if(listener.wrapperFunction == null) {
				Context.error("An @:add or @:remove listener must take at least one component. (Optional arguments don't count.)", listener.pos);
			}
		}
		
		//Figure out whether there are any extra priorities.
		var updatePriorities:Array<Int> = [];
		for(listener in updateListeners) {
			if(listener.priority == null) {
				listener.priority = priority;
			}
			if(!updatePriorities.contains(listener.priority)) {
				updatePriorities.push(listener.priority);
			}
		}
		var childPriorities:Array<Int> = updatePriorities.copy();
		childPriorities.remove(priority);
		
		//Define or update the constructor.
		var constructor:Field = null;
		var directSubclass:Bool = classType.superClass.t.get().name == "System";
		var superCall:Expr = macro super($v{ priority }, $a{
			childPriorities.map(childPriority -> macro $v{ childPriority }) });
		for(field in fields) {
			if(field.name != "new") {
				continue;
			}
			
			constructor = field;
			var constructorFunc:Function = switch(constructor.kind) {
				case FFun(f):
					f;
				default:
					Context.fatalError("Constructor must be a function.", constructor.pos);
			};
			if(constructorFunc.expr == null) {
				constructorFunc.expr = macro {};
			} else if(!constructorFunc.expr.expr.match(EBlock(_))) {
				constructorFunc.expr = macro {
					${ constructorFunc.expr }
				};
			}
			
			//Insert a `super()` call if needed.
			if(directSubclass) {
				switch(constructorFunc.expr.expr) {
					case EBlock(block):
						var replaced:Bool = false;
						for(i => expr in block) {
							if(expr.expr.match(ECall({ expr: EConst(CIdent("super")) }, _))) {
								replaced = true;
								block[i] = superCall;
								Context.warning("super() call will be replaced. Remove this call to suppress this warning.", expr.pos);
								break;
							}
						}
						
						if(!replaced) {
							block.unshift(superCall);
						}
					default:
						Context.fatalError("Expected block expr", constructorFunc.expr.pos);
				}
			}
			
			break;
		}
		if(constructor == null) {
			constructor = (macro class Constructor {
				public function new() {
					$superCall;
				}
			}).fields[0];
			fields.push(constructor);
		}
		
		//Define wrapper functions for each listener.
		for(listener in addListeners.concat(removeListeners).concat(updateListeners)) {
			if(listener.wrapperFunction != null) {
				if(!fields.exists(field -> field.name == listener.wrapperName))
					fields.push(listener.wrapperFunction);
				
				if(!linkedViews.contains(listener.viewName))
					linkedViews.push(listener.viewName);
			}
		}
		
		//Add useful functions if they aren't already there.
		var optionalFields:TypeDefinition = macro class OptionalFields {
			public override function toString():String {
				return $v{ classType.name };
			}
		};
		for(optionalField in optionalFields.fields) {
			if(!fields.exists(field -> field.name == optionalField.name)) {
				fields.push(optionalField);
			}
		}
		
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
			
			private override function __update__(dt:Float, priority:Int):Void {
				#if echoes_profiling
				var __timestamp__ = Date.now().getTime();
				#end
				
				__dt__ = dt;
				
				${ {
					expr: ESwitch(macro priority, [for(priority in updatePriorities)
						{
							values: [macro $v{ priority }],
							expr: macro $b{
								[for(listener in updateListeners) if(listener.priority == priority)
									listener.callDuringUpdate()]
							}
						}
					], null),
					pos: (macro null).pos
				} }
				
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
}

@:noCompletion typedef ListenerFunctionData = {
	name:String,
	args:Array<FunctionArg>,
	pos:Position,
	priority:Int,
	?components:Array<ComplexType>,
	?optionalComponents:Array<ComplexType>,
	?viewName:String,
	?wrapperFunction:Field
};

@:forward
abstract ListenerFunction(ListenerFunctionData) from ListenerFunctionData {
	public static function fromField(field:Field, listenerType:String, defaultPriority:Int):ListenerFunction {
		switch(field.kind) {
			case FFun(func):
				if(SystemBuilder.getMeta(field.meta, listenerType) == null) {
					return null;
				}
				
				return {
					name: field.name,
					args: func.args,
					pos: field.pos,
					priority: SystemBuilder.getPriority(field.meta, defaultPriority)
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
