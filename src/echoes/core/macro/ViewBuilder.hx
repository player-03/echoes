package echoes.core.macro;

#if macro

import echoes.core.macro.MacroTools.*;
import echoes.core.macro.ComponentBuilder.*;
import haxe.crypto.Md5;
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using echoes.core.macro.MacroTools;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using Lambda;

class ViewBuilder {
	private static var viewTypeCache:Map<String, Type> = new Map();
	
	public static var viewCache = new Map<String, { cls:ComplexType, components:Array<ComplexType> }>();
	
	public static function getView(components:Array<ComplexType>):ComplexType {
		return createViewType(components).toComplexType();
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
		return createViewType(parseComponents(Context.getLocalType()));
	}
	
	private static function parseComponents(type:Type):Array<ComplexType> {
		return switch(type) {
			case TInst(_, params = [x = TType(_, _) | TAnonymous(_) | TFun(_, _)]) if(params.length == 1):
				parseComponents(x);
				
			case TType(_.get() => { type: x }, []):
				parseComponents(x);
				
			case TAnonymous(_.get() => p):
				p.fields
					.map(f -> return f.type.followMono().toComplexType());
				
			case TFun(args, ret):
				args
					.map(a -> return a.t.followMono().toComplexType())
					.concat([ ret.followMono().toComplexType() ])
					.filter(ct -> switch(ct) {
						case (macro:StdTypes.Void): false;
						default: true;
					});
				
			case TInst(_, types):
				types.map(t -> t.followMono().toComplexType());
				
			case x: 
				Context.error('Unexpected Type Param: $x', Context.currentPos());
		}
	}
	
	public static function createViewType(components:Array<ComplexType>):Type {
		var viewClsName:String = getViewName(components);
		var viewType:Type = viewTypeCache.get(viewClsName);
		
		if(viewType != null) {
			return viewType;
		}
		
		var viewTypePath:TypePath = { pack: [], name: viewClsName };
		
		/**
		 * The function signature of the view's event dispatchers and associated
		 * event listeners. For instance, in a `View<Hue, Saturation>`, this
		 * would be `macro:(Entity, Hue, Saturation) -> Void`.
		 */
		var callbackType:ComplexType = TFunction([macro:echoes.Entity].concat(components), macro:Void);
		
		/**
		 * The arguments required to dispatch an event. For instance, in a
		 * `View<Hue, Saturation>`, this would be
		 * `[macro entity, macro HueContainer.inst().get(entity), macro SaturationContainer.inst().get(entity)]`.
		 */
		var callbackArgs:Array<Expr> = [macro entity]
			.concat([for(component in components)
				macro $i{ getComponentContainer(component).followName() }.inst().get(entity)
			]);
		
		var def:TypeDefinition = macro class $viewClsName extends echoes.core.AbstractView {
			private static var instance = new $viewTypePath();
			
			@:keep public static inline function inst() {
				return instance;
			}
			
			public var onAdded(default, null) = new echoes.utils.Signal<$callbackType>();
			public var onRemoved(default, null) = new echoes.utils.Signal<$callbackType>();
			
			private function new() {
				@:privateAccess echoes.Workflow.definedViews.push(this);
				
				//$b{} - Insert expressions from an `Array<Expr>`, in order.
				$b{
					//Each expression adds this `View` to a related list.
					[for(c in components) {
						var componentContainer:String = getComponentContainer(c).followName();
						macro @:privateAccess $i{ componentContainer }.inst().addRelatedView(this);
					}]
				}
			}
			
			private override function dispatchAddedCallback(entity:echoes.Entity):Void {
				//$a{} - Insert function arguments from an `Array<Expr>`.
				onAdded.dispatch($a{ callbackArgs });
			}
			
			private override function dispatchRemovedCallback(entity:echoes.Entity, ?removedComponentStorage:echoes.core.ICleanableComponentContainer, ?removedComponent:Any):Void {
				onRemoved.dispatch(
					//$a{} - Insert function arguments from an `Array<Expr>`.
					//Start with `entity` because that's always required.
					$a{ [macro entity].concat(
						//Each subsequent expression should look up a component.
						//However, if `removedComponent` was specified, we want
						//to use that in place of one of the components.
						[for(component in components) macro {
							var inst = $i{ getComponentContainer(component).followName() }.inst();
							inst == removedComponentStorage ? removedComponent : inst.get(entity);
						}]
					) });
			}
			
			private override function reset():Void {
				super.reset();
				onAdded.clear();
				onRemoved.clear();
			}
			
			public inline function iter(callback:$callbackType):Void {
				for(entity in entities) {
					//$a{} - Insert function arguments from an `Array<Expr>`.
					callback($a{ callbackArgs });
				}
			}
			
			private override function isMatched(id:Int):Bool {
				//Insert a single long expression.
				return ${{
					//The expression consists of several `exists()` checks. For
					//instance, in a `View<Hue, Saturation>`, the two checks
					//would be `HueContainer.inst().exists(entity)` and
					//`SaturationContainer.inst().exists(entity)`.
					var checks:Array<Expr> = components.map(c -> macro $i{ getComponentContainer(c).followName() }.inst().exists(id));
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
		
		viewType = TPath(viewTypePath).toType();
		
		viewTypeCache.set(viewClsName, viewType);
		viewCache.set(viewClsName, { cls: TPath(viewTypePath), components: components });
		
		Report.viewNames.push(viewClsName);
		
		return viewType;
	}
}

#end
