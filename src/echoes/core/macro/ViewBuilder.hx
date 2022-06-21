package echoes.core.macro;

#if macro
import echoes.core.macro.MacroTools.*;
import echoes.core.macro.ComponentBuilder.*;
import echoes.core.macro.ViewsOfComponentBuilder.*;
import haxe.crypto.Md5;
import haxe.macro.Expr;
import haxe.macro.Type;

using echoes.core.macro.MacroTools;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using Lambda;

class ViewBuilder {
	private static var viewIndex = -1;
	private static var viewTypeCache:Map<String, Type> = new Map();
	
	public static var viewIds = new Map<String, Int>();
	public static var viewNames = new Array<String>();
	
	public static var viewCache = new Map<String, { cls:ComplexType, components:Array<ComplexType> }>();
	
	public static function getView(components:Array<ComplexType>):ComplexType {
		return createViewType(components).toComplexType();
	}
	
	public static function getViewName(components:Array<ComplexType>):String {
		var name:String = components.joinFullName("_");
		if(name.length > 80) {
			return "View_" + Md5.encode(name);
		} else {
			return "ViewOf_" + name;
		}
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
		
		// first time call in current build
		
		var index = ++viewIndex;
		
		try {
			viewType = Context.getType(viewClsName);
		} catch(err:String) {
			// type was not cached in previous build
			// TODO: How safe is it to cache this way?
			
			var viewTypePath:TypePath = { pack: [], name: viewClsName };
			
			/**
			 * For instance, in a `View<Hue, Saturation>`, this would be
			 * `macro:(Entity, Hue, Saturation) -> Void`.
			 */
			var callbackType:ComplexType = TFunction([macro:echoes.Entity].concat(components), macro:Void);
			
			/**
			 * For instance, in a `View<Hue, Saturation>`, this would be
			 * `[macro entity, macro HueContainer.inst().get(entity), macro SaturationContainer.inst().get(entity)]`.
			 */
			var callbackArgs:Array<Expr> = [macro entity].concat(components.map(c -> macro $i{ getComponentContainer(c).followName() }.inst().get(entity)));
			
			var def:TypeDefinition = macro class $viewClsName extends echoes.core.AbstractView {
				private static var instance = new $viewTypePath();
				
				@:keep public static inline function inst() {
					return instance;
				}
				
				public var onAdded(default, null) = new echoes.utils.Signal<$callbackType>();
				public var onRemoved(default, null) = new echoes.utils.Signal<$callbackType>();
				
				private function new() {
					@:privateAccess echoes.Workflow.definedViews.push(this);
					
					//Complicated syntax explanation: we're assembling an array
					//of expressions, then unrolling that array to produce a
					//variable number of lines of code.
					$b{
						[for(c in components) {
							var viewsOfComponentName:String = getViewsOfComponent(c).followName();
							
							//Only the line beginning `macro` is added to the
							//array, and thus to the runtime code.
							macro @:privateAccess $i{ viewsOfComponentName }.inst().addRelatedView(this);
						}]
					}
				}
				
				private override function dispatchAddedCallback(entity:echoes.Entity):Void {
					onAdded.dispatch($a{ callbackArgs });
				}
				
				private override function dispatchRemovedCallback(entity:echoes.Entity):Void {
					onRemoved.dispatch($a{ callbackArgs });
				}
				
				private override function reset():Void {
					super.reset();
					onAdded.clear();
					onRemoved.clear();
				}
				
				public inline function iter(callback:$callbackType):Void {
					for(entity in entities) {
						callback($a{ callbackArgs });
					}
				}
				
				private override function isMatched(id:Int):Bool {
					return ${{
						//Create an `exists()` call for each component type.
						var checks:Array<Expr> = components.map(c -> macro $i{ getComponentContainer(c).followName() }.inst().exists(id));
						
						//Combine them into a single variable-length expression.
						checks.fold((a, b) -> macro $a && $b, checks.shift());
					}};
				}
				
				public override function toString():String {
					return $v{
						//Construct a variable-length string.
						components.map(c -> c.typeValidShortName()).join(", ")
					};
				}
			}
			
			Context.defineType(def);
			
			viewType = TPath(viewTypePath).toType();
		}
		
		// caching current build
		viewTypeCache.set(viewClsName, viewType);
		viewCache.set(viewClsName, { cls: viewType.toComplexType(), components: components });
		
		viewIds[viewClsName] = index;
		viewNames.push(viewClsName);
		
		return viewType;
	}
}

#end
