package echoes;

import echoes.Entity;
import echoes.Echoes;
import echoes.View;

/**
 * A central location to store all components of a given type. For example, the
 * `ComponentStorage<String>` singleton stores every `String` components,
 * indexed by entity ID. `entity.get(String)` is actually shorthand for
 * `Echoes.getComponentStorage(String).get(entity)`.
 */
class ComponentStorage<T> {
	/**
	 * The component's fully-qualified type, in string form. For instance,
	 * `Echoes.getComponentStorage(Bool).componentType` is `"StdTypes.Bool"`.
	 */
	public final componentType:String;
	
	public var name(get, never):String;
	private inline function get_name():String {
		return 'ComponentStorage<$componentType>';
	}
	
	/**
	 * All components of this type.
	 */
	private var storage:Map<Entity, T> = new Map();
	
	/**
	 * All views that include this type of component.
	 */
	@:allow(echoes.ViewBase)
	private var relatedViews:Array<ViewBase> = [];
	
	private inline function new(componentType:String) {
		this.componentType = componentType;
		Echoes.componentStorage.push(this);
	}
	
	public function add(entity:Entity, component:T):Void {
		if(component == null) {
			remove(entity);
			return;
		}
		
		if(storage[entity] == component) {
			return;
		}
		
		storage[entity] = component;
		
		if(entity.active) {
			for(view in relatedViews) {
				view.addIfMatched(entity);
				
				//Stop dispatching events if a listener removed it.
				if(!exists(entity)) {
					return;
				}
			}
		}
	}
	
	@:allow(echoes.Echoes)
	private inline function clear():Void {
		storage.clear();
	}
	
	public inline function exists(entity:Entity):Bool {
		return storage.exists(entity);
	}
	
	public inline function get(entity:Entity):Null<T> {
		return storage[entity];
	}
	
	public function remove(entity:Entity):Void {
		var removedComponent:T = get(entity);
		if(storage.remove(entity) && entity.active) {
			for(view in relatedViews) {
				view.removeIfExists(entity, this, removedComponent);
				
				//Stop dispatching events if a listener added it back.
				if(exists(entity)) {
					return;
				}
			}
		}
	}
	
	/**
	 * Dispatches a `@:remove` event (if applicable) before adding `component`.
	 * To make Echoes use this, tag the component type with `@:echoes_replace`.
	 */
	public inline function replace(entity:Entity, component:T):Void {
		if(get(entity) != component) {
			remove(entity);
			add(entity, component);
		}
	}
}

/**
 * A version of `ComponentStorage` that stores components of unknown type. As
 * this makes it unsafe to call `add()`, that function is disabled.
 */
@:forward(name, get, exists, remove, clear)
abstract DynamicComponentStorage(ComponentStorage<Dynamic>) {
	@:from private static inline function fromComponentStorage<T>(componentStorage:ComponentStorage<T>):DynamicComponentStorage {
		return cast componentStorage;
	}
}
