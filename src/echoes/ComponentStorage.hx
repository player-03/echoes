package echoes;

import echoes.Echoes;
import echoes.Entity;
import echoes.utils.ReadOnlyData;
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
	public var relatedViews(get, never):ReadOnlyArray<ViewBase>;
	private inline function get_relatedViews():ReadOnlyArray<ViewBase> {
		return _relatedViews;
	}
	
	@:allow(echoes.ViewBase)
	private final _relatedViews:Array<ViewBase> = [];
	
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
		
		var components:List<DynamicComponentStorage> = EntityComponents.components[entity.id];
		if(components == null) {
			EntityComponents.components[entity.id] = components = new List();
		}
		
		//Add to the beginning of the list, so that `remove()` will search
		//recently-added components first. This way, short-term components can
		//be added and removed quickly, and long-lasting components filter down
		//to the end of the list where they don't get in the way.
		components.push(this);
		
		if(entity.active) {
			for(view in relatedViews) {
				view.add(entity);
				
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
		
		if(removedComponent != null) {
			EntityComponents.components[entity.id].remove(this);
			
			if(entity.active) {
				for(view in relatedViews) {
					view.remove(entity, this, removedComponent);
					
					//Stop dispatching events if a listener added it back.
					if(exists(entity)) {
						return;
					}
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
@:forward(clear, componentType, exists, get, name, relatedViews, remove)
abstract DynamicComponentStorage(ComponentStorage<Dynamic>) {
	@:from private static inline function fromComponentStorage<T>(componentStorage:ComponentStorage<T>):DynamicComponentStorage {
		return cast componentStorage;
	}
}

/**
 * The components currently attached to an entity. This isn't a good way to look
 * up an individual component, but it helps with batch operations such as
 * `deactivate()` and `destroy()`.
 */
@:forward @:allow(echoes.ComponentStorage)
abstract EntityComponents(ReadOnlyList<DynamicComponentStorage>) from List<DynamicComponentStorage> to ReadOnlyList<DynamicComponentStorage> {
	/**
	 * The source data for all `EntityComponents` lists. This should only be
	 * updated by `ComponentStorage`, or by `Echoes.reset()`.
	 */
	@:allow(echoes.Echoes)
	private static final components:Array<List<DynamicComponentStorage>> = [];
	
	/**
	 * Gets the `EntityComponents` list for the given entity.
	 */
	@:allow(echoes.Entity)
	private static inline function forEntity(entity:Entity):EntityComponents {
		if(components[entity.id] == null) {
			return components[entity.id] = new List();
		} else {
			return components[entity.id];
		}
	}
	
	/**
	 * @see `Entity.removeAll()`
	 */
	@:allow(echoes.Entity)
	private static inline function removeAll(entity:Entity):Void {
		if(components[entity.id] != null) {
			//`List` is designed to allow iteration while removing items.
			for(componentStorage in components[entity.id]) {
				componentStorage.remove(entity);
			}
		}
	}
	
	@:to private inline function toIterable():Iterable<DynamicComponentStorage> {
		return this;
	}
	
	/**
	 * Creates a `Map` of the entity's components, mapping types onto values.
	 * For instance, if the entity has `Bool` and `String` components, the map
	 * might be `["StdTypes.Bool" => true, "String" => "Hello World"]`.
	 */
	@:to private inline function toMap():Map<String, Dynamic> {
		var entity:Entity = switch(components.indexOf(cast this)) {
			case -1:
				throw "This EntityComponents instance was disposed.";
			case x:
				cast x;
		};
		
		return [for(storage in this) storage.componentType => storage.get(entity)];
	}
}
