package echoes;

import echoes.Entity;
import echoes.Echoes;
import echoes.View;

/**
 * A central location to store all components of a given type. For example, the
 * `ComponentStorage<String>` singleton stores every `String` components,
 * indexed by entity ID, and `entity.get(String)` is shorthand for
 * `Echoes.getComponentStorage(String).get(entity)`.
 * 
 * By default, `ComponentStorage` stores data in arrays. Compared to maps, this
 * produces faster lookup times, but may take more memory if you have a large
 * number of entities. In this case, you can try `-D echoes_storage=Map`, though
 * be sure to test the performance impact.
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
	 * All views that include this type of component.
	 */
	@:allow(echoes.ViewBase)
	private final relatedViews:Array<ViewBase> = [];
	
	/**
	 * All components of this type.
	 */
	#if (echoes_storage == "Map")
	private final storage:Map<Int, T> = new Map();
	#else
	private final storage:Array<Null<T>> = [];
	#end
	
	private inline function new(componentType:String) {
		this.componentType = componentType;
		Echoes.componentStorage.push(this);
	}
	
	public function add(entity:Entity, component:T):Void {
		if(component == null) {
			remove(entity);
			return;
		}
		
		if(get(entity) == component) {
			return;
		}
		
		storage[entity.id] = component;
		
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
		#if (echoes_storage == "Map")
		storage.clear();
		#else
		#if eval
		//Work around a bug in the eval target.
		for(i in 0...storage.length) {
			storage[i] = null;
		}
		#end
		storage.resize(0);
		#end
	}
	
	public inline function exists(entity:Entity):Bool {
		#if (echoes_storage == "Map")
		return storage.exists(entity.id);
		#else
		return storage[entity.id] != null;
		#end
	}
	
	public inline function get(entity:Entity):Null<T> {
		return storage[entity.id];
	}
	
	public function remove(entity:Entity):Void {
		var removedComponent:Null<T> = get(entity);
		
		#if (echoes_storage == "Map")
		storage.remove(entity.id);
		#else
		storage[entity.id] = null;
		#end
		
		if(removedComponent != null && entity.active) {
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
	 * To use this for a given component, tag the type with `@:echoes_replace`.
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
@:forward(componentType, get, exists, remove, clear)
abstract DynamicComponentStorage(ComponentStorage<Dynamic>) {
	@:from private static inline function fromComponentStorage<T>(componentStorage:ComponentStorage<T>):DynamicComponentStorage {
		return cast componentStorage;
	}
}
