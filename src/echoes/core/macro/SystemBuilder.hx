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
	
	private static var ADD_META = "added";
	private static var REMOVE_META = "removed";
	private static var UPDATE_META = "updated";
	
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
		
		var clsType:ClassType = Context.getLocalClass().get();
		if(clsType == null) {
			Context.warning("SystemBuilder only acts on classes.", Context.currentPos());
			return fields;
		}
		
		var definedViews:Map<String, Expr> = new Map();
		
		//Initialize variables of type `View`.
		for(field in fields) {
			if(skipped(field)) continue;
			
			switch(field.kind) {
				case FVar(null, _):
				case FVar(_.followComplexType() => complexType = TPath({ name: clsName }), null):
					//If the variable is a view, `followComplexType()` will
					//invoke `ViewBuilder`, placing the type in the cache.
					if(viewCache.exists(clsName)) {
						var view:Expr = macro $i{ clsName }.inst();
						definedViews[clsName] = view;
						
						field.kind = FVar(complexType, view);
					}
				default:
			}
		}
		
		//Locate marked functions.
		var updateListeners:Array<ListenerFunction> = fields.filter(notSkipped).filter(containsMeta.bind(_, UPDATE_META)).map(ListenerFunction.fromField).filter(notNull);
		var addListeners:Array<ListenerFunction> = fields.filter(notSkipped).filter(containsMeta.bind(_, ADD_META)).map(ListenerFunction.fromField).filter(notNull);
		var removeListeners:Array<ListenerFunction> = fields.filter(notSkipped).filter(containsMeta.bind(_, REMOVE_META)).map(ListenerFunction.fromField).filter(notNull);
		
		//Define wrapper functions for each listener.
		for(listener in updateListeners) {
			if(listener.wrapperFunction != null) {
				fields.push(listener.wrapperFunction);
				
				definedViews[listener.viewName] = listener.view;
			}
		}
		for(listener in addListeners.concat(removeListeners)) {
			if(listener.wrapperFunction == null) {
				Context.error("An @:add or @:remove listener must have at least one required component.", listener.pos);
			}
			fields.push(listener.wrapperFunction);
			
			definedViews[listener.viewName] = listener.view;
		}
		
		//Add useful functions if they aren't already there.
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
		
		//Add lifecycle functions no matter what.
		var requiredFields:TypeDefinition = macro class RequiredFields {
			@:noCompletion public override function __activate__():Void {
				if(!activated) {
					activated = true;
					
					__dt__ = 0;
					
					$b{ [for(view in definedViews) macro $view.activate()] }
					
					$b{ addListeners.map(listener -> macro ${ listener.view }.onAdded.add(${ listener.wrapper })) }
					$b{ removeListeners.map(listener -> macro ${ listener.view }.onRemoved.add(${ listener.wrapper })) }
					
					//If any entities already exist, call the `@:add` listeners.
					$b{ addListeners.map(listener -> macro ${ listener.view }.iter(${ listener.wrapper })) }
					
					super.__activate__();
				};
			}
			
			@:noCompletion public override function __deactivate__():Void {
				if(activated) {
					activated = false;
					super.__deactivate__();
					
					$b{ [for(view in definedViews) macro $view.deactivate()] }
					
					$b{ addListeners.map(listener -> macro ${ listener.view }.onAdded.remove(${ listener.wrapper })) }
					$b{ removeListeners.map(listener -> macro ${ listener.view }.onRemoved.remove(${ listener.wrapper })) }
				}
			}
			
			@:noCompletion public override function __update__(dt:Float):Void {
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
	?componentTypes:Array<ComplexType>,
	?optionalComponentTypes:Array<ComplexType>,
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
	
	public var componentTypes(get, never):Array<ComplexType>;
	private function get_componentTypes():Array<ComplexType> {
		if(this.componentTypes == null) {
			this.componentTypes = [];
			for(arg in this.args) {
				switch(arg.type.followComplexType()) {
					case macro:StdTypes.Float, macro:StdTypes.Int, macro:echoes.Entity:
					default:
						if(!arg.opt) {
							this.componentTypes.push(arg.type.followComplexType());
						}
				}
			}
		}
		
		return this.componentTypes;
	}
	
	public var optionalComponentTypes(get, never):Array<ComplexType>;
	private function get_optionalComponentTypes():Array<ComplexType> {
		if(this.optionalComponentTypes == null) {
			this.optionalComponentTypes = [];
			for(arg in this.args) {
				switch(arg.type.followComplexType()) {
					case macro:StdTypes.Float, macro:StdTypes.Int, macro:echoes.Entity:
					default:
						if(arg.opt) {
							this.optionalComponentTypes.push(arg.type.followComplexType());
						}
				}
			}
		}
		
		return this.optionalComponentTypes;
	}
	
	public var view(get, never):Expr;
	private inline function get_view():Expr {
		return macro $i{ viewName }.inst();
	}
	
	public var viewName(get, never):String;
	private inline function get_viewName():String {
		if(this.viewName == null) {
			this.viewName = getViewName(componentTypes);
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
			if(componentTypes.length == 0) {
				return null;
			}
			
			if(!viewCache.exists(viewName)) {
				getView(componentTypes);
			}
			
			//The arguments used in the wrapper function signature.
			var args:Array<FunctionArg> =
				//The view always passes an `Entity` as the first argument.
				[{ name: "entity", type: macro:echoes.Entity }]
				//The remaining arguments must also be in the view's order.
				.concat(viewCache.get(viewName).components
					//Make sure to use the same names as the listener function uses.
					.map(type -> {
						name: this.args.find(arg -> arg.type.followName() == type.followName()).name,
						type: type
					}));
			for(arg in args) {
				if(arg.name == null) {
					Context.error('Could not locate an argument of type ${arg.type.followName()}. Please report this error, and include information about the type.', this.pos);
				}
			}
			
			var expr:Expr = call();
			/* if(optionalComponents.length > 0) {
				expr = macro {
					//TODO
					
					$expr;
				};
			} */
			
			this.wrapperFunction = {
				name: wrapperName,
				kind: FFun({
					args: args,
					ret: macro:Void,
					expr: expr
				}),
				pos: Context.currentPos()
			};
		}
		
		return this.wrapperFunction;
	}
	
	/**
	 * Calls this listener.
	 */
	public function call():Expr {
		//The trick when calling this listener is to refer to variables that
		//exist in the current context. Mostly, we'll try to reuse the wrapper
		//function's arguments, though sometimes the listener needs to be called
		//from outside a wrapper function.
		var args:Array<Expr> = [for(arg in this.args) {
			switch(arg.type.followComplexType()) {
				case macro:StdTypes.Float:
					//Defined as a private variable of `System`.
					macro __dt__;
				case macro:StdTypes.Int, macro:echoes.Entity:
					//Defined in `updateCall()` and `makeWrapperFunction()`.
					macro entity;
				default:
					//Defined in `makeWrapperFunction()`; this sort of listener
					//should only be called by its wrapper.
					macro $i{ arg.name };
			}
		}];
		
		return macro $i{ this.name }($a{ args });
	}
	
	/**
	 * Calls this listener one or more times as part of an `@:update` step.
	 */
	public function callDuringUpdate():Expr {
		if(componentTypes.length > 0) {
			//Iterate over a `View`'s entities.
			return macro $i{ viewName }.inst().iter($wrapper);
		} else {
			for(arg in this.args) {
				switch(arg.type.followComplexType()) {
					case macro:StdTypes.Int, macro:echoes.Entity:
						//Iterate over all entities.
						return macro for(entity in echoes.Workflow.entities)
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
