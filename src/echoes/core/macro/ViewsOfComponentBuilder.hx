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
			
			private var views:Array<echoes.core.AbstractView> = [];
			
			/**
			 * IDs for entities with ongoing @:add or @:remove events.
			 */
			private var ongoingEvents:Array<echoes.Entity> = [];
			
			private function new() { }
			
			public inline function addRelatedView(v:echoes.core.AbstractView):Void {
				views.push(v);
			}
			
			public inline function addIfMatched(entity:echoes.Entity):Void {
				if(ongoingEvents.indexOf(entity) >= 0) {
					ongoingEvents.remove(entity);
					throw "Can't add a " + $v{componentTypeName} + " component in the middle of its own @:remove event.";
				}
				
				ongoingEvents.push(entity);
				
				for(v in views) {
					if(v.isActive()) {
						@:privateAccess v.addIfMatched(entity);
					}
				}
				
				ongoingEvents.remove(entity);
			}
			
			public inline function removeIfExists(entity:echoes.Entity, removedComponentStorage:echoes.core.ICleanableComponentContainer, removedComponent:Any):Void {
				if(ongoingEvents.indexOf(entity) >= 0) {
					ongoingEvents.remove(entity);
					throw "Can't remove a " + $v{componentTypeName} + " component in the middle of its own @:add event.";
				}
				
				ongoingEvents.push(entity);
				
				for(v in views) {
					if(v.isActive()) {
						@:privateAccess v.removeIfExists(entity, removedComponentStorage, removedComponent);
					}
				}
				
				ongoingEvents.remove(entity);
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
