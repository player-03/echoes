package echoes.macro;

#if macro

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using echoes.macro.MacroTools;
using echoes.macro.ViewBuilder;
using StringTools;
using Lambda;

class SystemBuilder {
	private static var ADD_META = "added";
	private static var REMOVE_META = "removed";
	private static var UPDATE_META = "updated";
	
	private static inline function notNull<T>(e:Null<T>):Bool {
		return e != null;
	}
	
	/**
	 * Similar to `getMeta()`, but returns a boolean value indicating presence
	 * or absence of metadata.
	 */
	private static inline function containsMeta(field:Field, searchTerm:String):Bool {
		return getMeta(field, searchTerm) != null;
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
	 * @param searchTerms One or more metadata names, consisting of lowercase
	 * letters (no colon, no "echoes_").
	 */
	private static function getMeta(field:Field, ...searchTerms:String):Null<MetadataEntry> {
		for(meta in field.meta) {
			var name:String = meta.name;
			if(name.startsWith(":")) {
				name = name.substr(1);
			}
			if(name.startsWith("echoes_")) {
				name = name.substr("echoes_".length);
			}
			
			if(name.length > 0 && searchTerms.toArray().exists(searchTerm -> searchTerm.startsWith(name))) {
				//Encourage users to include a colon in their metadata.
				if(!meta.name.startsWith(":")) {
					Context.warning('@${meta.name} is deprecated; use @:${meta.name} instead.'
						+ (meta.name == "remove" ? " (@:remove does have a reserved meaning when applied to interfaces, but not here.)" : ""),
						meta.pos);
				}
				
				return meta;
			}
		}
		
		return null;
	}
	
	public static function build():Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		
		var classType:ClassType = Context.getLocalClass().get();
		if(classType == null) {
			Context.warning("SystemBuilder only acts on classes.", Context.currentPos());
			return fields;
		} else if(classType.meta.has(":skipBuildMacro")) {
			return fields;
		}
		
		//Locate marked functions.
		var updateListeners:Array<ListenerFunction> = fields.filter(containsMeta.bind(_, UPDATE_META)).map(ListenerFunction.fromField).filter(notNull);
		var addListeners:Array<ListenerFunction> = fields.filter(containsMeta.bind(_, ADD_META)).map(ListenerFunction.fromField).filter(notNull);
		var removeListeners:Array<ListenerFunction> = fields.filter(containsMeta.bind(_, REMOVE_META)).map(ListenerFunction.fromField).filter(notNull);
		for(listener in addListeners.concat(removeListeners)) {
			if(listener.wrapperFunction == null) {
				Context.error("An @:add or @:remove listener must take at least one component. (Optional arguments don't count.)", listener.pos);
			}
		}
		
		//Define wrapper functions for each listener.
		var viewNames:Array<String> = [];
		for(listener in addListeners.concat(removeListeners).concat(updateListeners)) {
			if(listener.wrapperFunction != null) {
				fields.push(listener.wrapperFunction);
				
				if(!viewNames.contains(listener.viewName))
					viewNames.push(listener.viewName);
			}
		}
		
		//Add useful functions if they aren't already there.
		var optionalFields:TypeDefinition = macro class OptionalFields {
			public inline function new() {}
			
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
					$b{ [for(view in viewNames) macro $i{ view }.instance.activate()] }
					
					$b{ addListeners.map(listener -> macro ${ listener.view }.onAdded.push(${ listener.wrapper })) }
					$b{ removeListeners.map(listener -> macro ${ listener.view }.onRemoved.push(${ listener.wrapper })) }
					
					super.__activate__();
					
					//If any entities already exist, call the `@:add` listeners.
					$b{ addListeners.map(listener -> macro ${ listener.view }.iter(${ listener.wrapper })) }
				};
			}
			
			private override function __deactivate__():Void {
				if(active) {
					$b{ [for(view in viewNames) macro $i{ view }.instance.deactivate()] }
					
					$b{ addListeners.map(listener -> macro ${ listener.view }.onAdded.remove(${ listener.wrapper })) }
					$b{ removeListeners.map(listener -> macro ${ listener.view }.onRemoved.remove(${ listener.wrapper })) }
					
					super.__deactivate__();
				}
			}
			
			private override function __update__(dt:Float):Void {
				#if echoes_profiling
				var __timestamp__ = Date.now().getTime();
				#end
				
				__dt__ = dt;
				
				$b{ updateListeners.map(listener -> listener.callDuringUpdate()) }
				
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
	?components:Array<ComplexType>,
	?optionalComponents:Array<ComplexType>,
	?viewName:String,
	?wrapperFunction:Field
};

@:forward
abstract ListenerFunction(ListenerFunctionData) from ListenerFunctionData {
	@:from public static function fromField(field:Field):ListenerFunction {
		switch(field.kind) {
			case FFun(func):
				return { name: field.name, args: func.args, pos: field.pos };
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
					//Float is reserved for delta time; Int and Entity are both
					//reserved for the entity.
					case macro:StdTypes.Float, macro:StdTypes.Int, macro:echoes.Entity:
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
					//Float is reserved for delta time; Int and Entity are both
					//reserved for the entity.
					case macro:StdTypes.Float, macro:StdTypes.Int, macro:echoes.Entity:
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
				case macro:StdTypes.Int, macro:echoes.Entity:
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
			for(arg in this.args) {
				switch(arg.type.followComplexType()) {
					case macro:StdTypes.Int, macro:echoes.Entity:
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
