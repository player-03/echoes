package echoes.core.macro;

#if macro

import echoes.core.macro.MacroTools.*;
import haxe.macro.Expr;

using echoes.core.macro.MacroTools;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Type;
using Lambda;

class ComponentBuilder {
	private static var componentContainerTypeCache = new Map<String, Type>();
	
	public static function createComponentContainerType(componentComplexType:ComplexType) {
		var componentTypeName:String = componentComplexType.followName();
		var componentContainerTypeName:String = "ContainerOf" + componentComplexType.typeName();
		var componentContainerType:Type = componentContainerTypeCache.get(componentContainerTypeName);
		
		if(componentContainerType != null) {
			return componentContainerType;
		}
		
		var componentContainerTypePath:TypePath = {
			pack: [],
			name: componentContainerTypeName
		};
		var componentContainerComplexType:ComplexType = TPath(componentContainerTypePath);
		
		var def = macro class $componentContainerTypeName implements echoes.core.ICleanableComponentContainer {
			private static var instance = new $componentContainerTypePath();
			
			@:keep public static inline function inst():$componentContainerComplexType {
				return instance;
			}
			
			/**
			 * All components of this type.
			 */
			private var storage:echoes.core.Storage<$componentComplexType> = new echoes.core.Storage();
			
			/**
			 * All views that involve this type of component.
			 */
			private var relatedViews:Array<echoes.core.AbstractView> = [];
			
			/**
			 * IDs for entities with ongoing @:add or @:remove events.
			 */
			private var ongoingEvents:Array<echoes.Entity> = [];
			
			private function new() {
				@:privateAccess echoes.Workflow.definedContainers.push(this);
			}
			
			public inline function get(id:Int):$componentComplexType {
				return storage.get(id);
			}
			
			public inline function exists(entity:echoes.Entity):Bool {
				return storage.exists(entity);
			}
			
			public function add(entity:echoes.Entity, c:$componentComplexType):Void {
				storage.set(entity, c);
				
				if(entity.isActive()) {
					if(ongoingEvents.indexOf(entity) >= 0) {
						ongoingEvents.remove(entity);
						throw "Can't add a " + $v{componentTypeName} + " component in the middle of its own @:remove event.";
					}
					
					ongoingEvents.push(entity);
					
					for(view in relatedViews) {
						if(view.isActive()) {
							@:privateAccess view.addIfMatched(entity);
						}
					}
					
					ongoingEvents.remove(entity);
				}
			}
			
			public function remove(entity:echoes.Entity):Void {
				var removedComponent:$componentComplexType = storage.get(entity);
				storage.remove(entity);
				
				if(entity.isActive()) {
					if(ongoingEvents.indexOf(entity) >= 0) {
						ongoingEvents.remove(entity);
						throw "Can't remove a " + $v{componentTypeName} + " component in the middle of its own @:add event.";
					}
					
					ongoingEvents.push(entity);
					
					for(v in relatedViews) {
						if(v.isActive()) {
							@:privateAccess v.removeIfExists(entity, this, removedComponent);
						}
					}
					
					ongoingEvents.remove(entity);
				}
			}
			
			public inline function reset():Void {
				storage.clear();
			}
			
			public inline function addRelatedView(v:echoes.core.AbstractView):Void {
				relatedViews.push(v);
			}
			
			public inline function print(id:Int):String {
				return $v{componentTypeName} + "=" + Std.string(storage.get(id));
			}
		}
		
		Context.defineType(def);
		
		componentContainerType = componentContainerComplexType.toType();
		
		componentContainerTypeCache.set(componentContainerTypeName, componentContainerType);
		
		Report.componentNames.push(componentTypeName);
		Report.gen();
		
		return componentContainerType;
	}
	
	public static function getComponentContainer(componentComplexType:ComplexType):ComplexType {
		return createComponentContainerType(componentComplexType).toComplexType();
	}
}

#end
