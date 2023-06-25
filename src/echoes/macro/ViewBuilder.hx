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
	private static var viewCache:Map<String, { cls:ComplexType, components:Array<ComplexType>, type:Type }> = new Map();
	
	public static inline function isView(name:String):Bool {
		return viewCache.exists(name);
	}
	
	/**
	 * Returns the canonical ordering of these components. (If such an ordering
	 * hasn't been defined, the given order will become canonical.)
	 */
	public static function getComponentOrder(components:Array<ComplexType>):Array<ComplexType> {
		var name:String = getViewName(components);
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
		var md5:String = "_" + Md5.encode(components.joinNames("_")).substr(0, 5);
		
		//Use the unqualified component names for the final result, as they're
		//easier to read. Include part of the hash to avoid collisions.
		var name:String = "ViewOf_" + components.joinNames("_", false) + md5;
		
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
		var viewClassName:String = getViewName(components);
		
		if(viewCache.exists(viewClassName)) {
			return viewCache[viewClassName].type;
		}
		
		var viewTypePath:TypePath = { pack: [], name: viewClassName };
		var viewComplexType:ComplexType = TPath(viewTypePath);
		
		/**
		 * The function signature for any event listeners attached to this view.
		 * Includes `Entity` as the first argument, meaning that in a
		 * `View<Hue, Saturation>`, listeners would need to have the signature
		 * `(Entity, Hue, Saturation) -> Void`.
		 */
		var callbackType:ComplexType = TFunction([macro:echoes.Entity].concat(components), macro:Void);
		
		/**
		 * The arguments required to dispatch an add or update event. In a
		 * `View<Hue, Saturation>`, the callback should look like this:
		 * 
		 * ```haxe
		 * callback(entity, HueContainer.instance.get(entity),
		 *     SaturationContainer.instance.get(entity));
		 * ```
		 */
		var callbackArgs:Array<Expr> = [for(component in components)
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
		var removedCallbackArgs:Array<Expr> = [for(component in components) {
			var inst:Expr = macro ${ component.getComponentStorage() };
			macro $inst == removedComponentStorage ? removedComponent : $inst.get(entity);
		}];
		
		//Pass `entity` as the first argument to both.
		callbackArgs.unshift(macro entity);
		removedCallbackArgs.unshift(macro entity);
		
		var def:TypeDefinition = macro class $viewClassName extends echoes.View.ViewBase {
			public static final instance:$viewComplexType = new $viewTypePath();
			
			public var onAdded(default, null) = new echoes.utils.Signal<$callbackType>();
			public var onRemoved(default, null) = new echoes.utils.Signal<$callbackType>();
			
			private function new() { }
			
			public override function activate():Void {
				super.activate();
				
				//$b{} - Insert expressions from an `Array<Expr>`, in order.
				if(activations == 1) $b{
					//Each expression adds this `View` to a related list.
					[for(component in components) {
						var storage:Expr = component.getComponentStorage();
						macro $storage.relatedViews.push(this);
					}]
				}
			}
			
			private override function dispatchAddedCallback(entity:echoes.Entity):Void {
				//$a{} - Insert function arguments from an `Array<Expr>`.
				for(callback in onAdded) {
					callback($a{ callbackArgs });
					if(!entities.has(entity)) {
						break;
					}
				}
			}
			
			private override function dispatchRemovedCallback(entity:echoes.Entity, ?removedComponentStorage:echoes.ComponentStorage.DynamicComponentStorage, ?removedComponent:Any):Void {
				for(callback in onRemoved) {
					//$a{} - Insert function arguments from an `Array<Expr>`.
					callback($a{ removedCallbackArgs });
					if(entities.has(entity)) {
						break;
					}
				}
			}
			
			private override function reset():Void {
				super.reset();
				onAdded.resize(0);
				onRemoved.resize(0);
				
				//$b{} - Insert expressions from an `Array<Expr>`, in order.
				$b{
					//Each expression removes this `View` from a related list.
					[for(component in components) {
						var storage:Expr = component.getComponentStorage();
						macro ${ storage }.relatedViews.remove(this);
					}]
				}
			}
			
			public inline function iter(callback:$callbackType):Void {
				for(entity in entities) {
					//$a{} - Insert function arguments from an `Array<Expr>`.
					callback($a{ callbackArgs });
				}
			}
			
			private override function isMatched(entity:echoes.Entity):Bool {
				//Insert a single long expression.
				return ${{
					//The expression consists of several `exists()` checks. For
					//instance, in a `View<Hue, Saturation>`, the two checks
					//would be `HueContainer.instance.exists(entity)` and
					//`SaturationContainer.instance.exists(entity)`.
					var checks:Array<Expr> = [for(component in components)
						macro ${ component.getComponentStorage() }.exists(entity)];
					//The checks are joined by `&&` operators.
					checks.fold((a, b) -> macro $a && $b, checks.shift());
				}};
			}
			
			public override function toString():String {
				//Insert the value of a string formed by joining the component
				//names. For instance, in a `View<Hue, Saturation>`, the string
				//would be `"Hue, Saturation"`.
				return $v{
					components.map(new Printer().printComplexType).join(", ")
				};
			}
		}
		
		Context.defineType(def);
		
		var viewType:Type = viewComplexType.toType();
		viewCache.set(viewClassName, { cls: viewComplexType, components: components, type: viewType });
		
		Report.viewNames.push(viewClassName);
		
		return viewType;
	}
}

#end
