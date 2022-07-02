package echoes.core.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Type;

using echoes.core.macro.MacroTools;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;

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
			private var relatedViews:Array<echoes.View.ViewBase> = [];
			
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
					for(view in relatedViews) {
						@:privateAccess view.addIfMatched(entity);
						
						if(!storage.exists(entity)) {
							return;
						}
					}
				}
			}
			
			public function remove(entity:echoes.Entity):Void {
				var removedComponent:$componentComplexType = storage.get(entity);
				storage.remove(entity);
				
				if(entity.isActive()) {
					for(view in relatedViews) {
						@:privateAccess view.removeIfExists(entity, this, removedComponent);
						
						if(storage.exists(entity)) {
							return;
						}
					}
				}
			}
			
			public inline function reset():Void {
				storage.clear();
			}
			
			public inline function addRelatedView(v:echoes.View.ViewBase):Void {
				relatedViews.push(v);
			}
			
			public inline function removeRelatedView(v:echoes.View.ViewBase):Void {
				relatedViews.remove(v);
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
