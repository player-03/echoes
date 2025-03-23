package echoes.macro;

#if macro

import haxe.crypto.Md5;
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using echoes.macro.ComponentStorageBuilder;
using echoes.macro.MacroTools;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using Lambda;

class ViewBuilder {
	private static final viewCache:Map<String, { cls:ComplexType, components:Array<ComplexType>, type:Type }> = new Map();
	
	public static inline function isView(name:String):Bool {
		return viewCache.exists(name);
	}
	
	/**
	 * Returns the canonical ordering of these components. (If such an ordering
	 * hasn't been defined, the given order will become canonical.)
	 */
	public static function getComponentOrder(components:Array<ComplexType>):Array<ComplexType> {
		final name:String = getViewName(components);
		if(!viewCache.exists(name)) {
			createViewType(components);
		}
		
		return viewCache[name].components;
	}
	
	/**
	 * Returns the name of the `View` class corresponding to the given
	 * components. Will return the same name regardless of component order.
	 * 
	 * Note: C++ compilation requires generating a .cpp file for each Haxe
	 * class, including views. To avoid Windows's file length limit, view names
	 * will be limited to 80 characters in C++. To adjust this limit, use
	 * `-Dechoes_max_name_length=[number]`.
	 */
	public static function getViewName(components:Array<ComplexType>):String {
		//Use the fully-qualified component names to generate a unique hash.
		final md5:String = "_" + Md5.encode(components.joinNames("_")).substr(0, 5);
		
		//Use the unqualified component names for the final result, as they're
		//easier to read. Include part of the hash to avoid collisions.
		final name:String = "ViewOf_" + components.joinNames("_", false) + md5;
		
		if(Context.defined("cpp")) {
			var maxLength:Null<Int> = null;
			if(Context.defined("echoes_max_name_length")) {
				maxLength = Std.parseInt(Context.definedValue("echoes_max_name_length"));
			}
			if(maxLength == null) maxLength = 80;
			
			if(name.length > maxLength) {
				return name.substr(0, maxLength - md5.length) + md5;
			}
		}
		
		return name;
	}
	
	public static function build():Type {
		switch(Context.getLocalType()) {
			case TInst(_, types) if(types != null && types.length > 0):
				return createViewType([for(type in types)
					type.followMono().toComplexType()]);
			default:
				Context.error("Expected one or more type parameters.", Context.currentPos());
				return null;
		}
	}
	
	public static function createViewType(components:Array<ComplexType>):Type {
		final viewClassName:String = getViewName(components);
		
		if(viewCache.exists(viewClassName)) {
			return viewCache[viewClassName].type;
		}
		
		final viewTypePath:TypePath = { pack: [], name: viewClassName };
		final viewComplexType:ComplexType = TPath(viewTypePath);
		
		/**
		 * The function signature for any event listeners attached to this view.
		 * Includes `Entity` as the first argument, meaning that in a
		 * `View<Hue, Saturation>`, listeners would need to have the signature
		 * `(Entity, Hue, Saturation) -> Void`.
		 */
		final callbackType:ComplexType = TFunction([macro:echoes.Entity].concat(components), macro:Void);
		
		/**
		 * The arguments required to dispatch an add or update event. In a
		 * `View<Hue, Saturation>`, the callback should look like this:
		 * 
		 * ```haxe
		 * callback(entity, HueContainer.instance.get(entity),
		 *     SaturationContainer.instance.get(entity));
		 * ```
		 */
		final callbackArgs:Array<Expr> = [for(component in components)
			macro ${ component.getComponentStorage() }.get(entity)];
		
		/**
		 * The arguments required to dispatch a remove event. Unlike with
		 * `callbackArgs`, one of the components will already have been removed
		 * from storage. We have to check which one was removed and replace its
		 * value with `removedComponent`.
		 * 
		 * In a `View<Hue, Saturation>`, the callback should look like this:
		 * 
		 * ```haxe
		 * callback(entity,
		 *     HueContainer.instance == removedComponentStorage
		 *         ? removedComponent : HueContainer.instance.get(entity),
		 *     SaturationContainer.instance == removedComponentStorage
		 *         ? removedComponent : SaturationContainer.instance.get(entity));
		 * ```
		 * 
		 * Note: these tests will be performed inside a `for` loop. While this
		 * may sound inefficient, in practice many (if not most) views will only
		 * run the loop for 0-1 iterations.
		 */
		final removedCallbackArgs:Array<Expr> = [for(component in components) {
			final inst:Expr = macro ${ component.getComponentStorage() };
			macro $inst == removedComponentStorage ? removedComponent : $inst.get(entity);
		}];
		
		//Pass `entity` as the first argument to both.
		callbackArgs.unshift(macro entity);
		removedCallbackArgs.unshift(macro entity);
		
		final def:TypeDefinition = macro class $viewClassName extends echoes.View.ViewBase {
			public static final instance:$viewComplexType = new $viewTypePath();
			
			public final onAdded = new echoes.utils.Signal<$callbackType>();
			public final onRemoved = new echoes.utils.Signal<$callbackType>();
			
			private function new() {
				super([$a{ { [for(component in components) macro ${ component.getComponentStorage() }]; } }]);
			}
			
			private override function dispatchAddedCallback(entity:echoes.Entity):Void {
				var index:Int = entities.lastIndexOf(entity);
				for(callback in onAdded) {
					callback($a{ callbackArgs });
					
					//If the callback removed the entity, stop. Cache the index
					//to save time in most cases. HashLink is known to return 0
					//when reading out of bounds, so it has to check length too.
					if(${ Context.defined("hl") ? macro index >= entities.length : macro false }
						|| entities[index] != entity) {
						index = entities.lastIndexOf(entity);
						if(index < 0) {
							break;
						}
					}
				}
			}
			
			private override function dispatchRemovedCallback(entity:echoes.Entity, ?removedComponentStorage:echoes.ComponentStorage.DynamicComponentStorage, ?removedComponent:Any):Void {
				var exception:haxe.Exception = null;
				for(callback in onRemoved) {
					try {
						callback($a{ removedCallbackArgs });
					} catch(e:haxe.Exception) {
						exception = e;
					}
				}
				
				if(exception != null) {
					throw exception;
				}
			}
			
			private override function reset():Void {
				super.reset();
				onAdded.clear();
				onRemoved.clear();
			}
			
			public function iter(callback:$callbackType):Void {
				${ {
					final args = [for(i => component in components)
						{ name: "component" + i, type: component }];
					args.unshift({ name: "entity", type: macro:echoes.Entity });
					forEachEntityInView(macro callback, args, macro 0);
				} }
			}
		}
		
		Context.defineType(def);
		
		final viewType:Type = viewComplexType.toType();
		viewCache.set(viewClassName, { cls: viewComplexType, components: components, type: viewType });
		
		Report.viewNames.push(viewClassName);
		
		return viewType;
	}
	
	public static function forEachEntityInView(func:Expr, args:Array<FunctionArg>, getDeltaTime:Expr):Expr {
		final requiredComponents:Array<ComplexType> = [];
		final funcArgs:Array<Expr> = [for(arg in args) {
			switch(arg.type.followComplexType()) {
				case macro:echoes.Ticks:
					getDeltaTime;
				case macro:echoes.Entity:
					macro entity;
				case x:
					if(!arg.opt && arg.value == null) {
						requiredComponents.push(x);
					}
					macro ${ x.getComponentStorage() }.get(entity);
			}
		}];
		
		return macro {
			var i:Int = 0;
			final entities:haxe.ds.ReadOnlyArray<echoes.Entity> = $i{ getViewName(requiredComponents) }.instance.entities;
			while(i < entities.length) {
				final entity:echoes.Entity = entities[i];
				@:nullSafety(Off) $func($a{ funcArgs });
				
				if(entity != entities[i] && !entities.contains(entity)) {
					//Entity was removed; don't increment.
				} else {
					i++;
				}
			}
		};
	}
}

#end
