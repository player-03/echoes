package echoes.core.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Type;

using echoes.core.macro.MacroTools;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;

class ComponentStorageBuilder {
	private static var storageCache:Map<String, Type> = new Map();
	
	public static function createComponentStorageType(componentComplexType:ComplexType):Type {
		var componentTypeName:String = componentComplexType.followName();
		var storageTypeName:String = "ComponentStorage_" + componentComplexType.toIdentifier();
		var storageType:Type = storageCache.get(storageTypeName);
		
		if(storageType != null) {
			return storageType;
		}
		
		var storageTypePath:TypePath = {
			pack: [],
			name: storageTypeName
		};
		var storageComplexType:ComplexType = TPath(storageTypePath);
		
		var def:TypeDefinition = macro class $storageTypeName implements echoes.core.ICleanableComponentContainer {
			public static var instance(default, null):$storageComplexType = new $storageTypePath();
			
			public var name(get, never):String;
			private inline function get_name():String return $v{componentTypeName};
			
			/**
			 * All components of this type.
			 */
			private var storage:echoes.core.Storage<$componentComplexType> = new echoes.core.Storage();
			
			/**
			 * All views that involve this type of component.
			 */
			private var relatedViews:Array<echoes.View.ViewBase> = [];
			
			private function new() {
				@:privateAccess echoes.Workflow.componentStorage.push(this);
			}
			
			public inline function get(id:Int):$componentComplexType {
				return storage.get(id);
			}
			
			public inline function getDynamic(id:Int):Dynamic {
				return get(id);
			}
			
			public inline function exists(entity:echoes.Entity):Bool {
				return storage.exists(entity);
			}
			
			public function add(entity:echoes.Entity, component:$componentComplexType):Void {
				storage.set(entity, component);
				
				if(entity.isActive()) {
					for(view in relatedViews) {
						@:privateAccess view.addIfMatched(entity);
						
						//Stop dispatching events if a listener removed it.
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
						
						//Stop dispatching events if a listener added it back.
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
		}
		
		Context.defineType(def);
		
		storageType = storageComplexType.toType();
		
		storageCache.set(storageTypeName, storageType);
		
		Report.componentNames.push(componentTypeName);
		Report.gen();
		
		return storageType;
	}
	
	public static function getComponentContainer(componentComplexType:ComplexType):ComplexType {
		return createComponentStorageType(componentComplexType).toComplexType();
	}
}

#end
