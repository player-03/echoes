package echoes.core.macro;

#if macro

import echoes.core.macro.MacroTools.*;
import haxe.macro.Expr.ComplexType;
using echoes.core.macro.MacroTools;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Type;

class ViewsOfComponentBuilder {
	private static var viewsOfComponentTypeCache = new Map<String, Type>();
	
	public static function createViewsOfComponentType(componentComplexType:ComplexType):haxe.macro.Type {
		var componentTypeName = componentComplexType.followName();
		var viewsOfComponentTypeName = "ViewsOfComponent" + componentComplexType.typeName();
		var viewsOfComponentType = viewsOfComponentTypeCache.get(viewsOfComponentTypeName);
		
		if(viewsOfComponentType != null) {
			return viewsOfComponentType;
		}
		
		var viewsOfComponentTypePath = tpath([], viewsOfComponentTypeName, []);
		var viewsOfComponentComplexType = TPath(viewsOfComponentTypePath);
		
		var def = macro class $viewsOfComponentTypeName {
			private static var instance = new $viewsOfComponentTypePath();
			
			@:keep public static inline function inst():$viewsOfComponentComplexType {
				return instance;
			}
			
			private var views = new Array<echoes.core.AbstractView>();
			
			private function new() { }
			
			public inline function addRelatedView(v:echoes.core.AbstractView) {
				views.push(v);
			}
			
			public inline function addIfMatched(id:Int) {
				for(v in views) {
					if(v.isActive()) {
						@:privateAccess v.addIfMatched(id);
					}
				}
			}
			
			public inline function removeIfExists(id:Int) {
				for(v in views) {
					if(v.isActive()) {
						@:privateAccess v.removeIfExists(id);
					}
				}
			}
		}
		
		Context.defineType(def);
		
		viewsOfComponentType = viewsOfComponentComplexType.toType();
		
		viewsOfComponentTypeCache.set(viewsOfComponentTypeName, viewsOfComponentType);
		
		return viewsOfComponentType;
	}
	
	public static function getViewsOfComponent(componentComplexType:ComplexType):ComplexType {
		return createViewsOfComponentType(componentComplexType).toComplexType();
	}
}

#end
