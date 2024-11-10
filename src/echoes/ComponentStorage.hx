package echoes;

import echoes.Echoes;
import echoes.Entity;
import echoes.utils.ComponentTypes;
import echoes.utils.ReadOnlyData;
import echoes.View;
import haxe.Exception;

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
	private static final DOT_PATH:EReg = ~/(?:\w+\.)*(\w+)/g;
	
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
	 * Entity IDs for which this component is currently being removed. During
	 * this time, the component cannot be re-added.
	 */
	private final ongoingRemovals:Array<Int> = [];
	
	/**
	 * All views that include this type of component.
	 */
	public var relatedViews(get, never):ReadOnlyArray<ViewBase>;
	private inline function get_relatedViews():ReadOnlyArray<ViewBase> {
		return _relatedViews;
	}
	
	@:allow(echoes.DynamicComponentStorage)
	private final _relatedViews:Array<ViewBase> = [];
	
	/**
	 * As `componentType`, except without package information. This is easier to
	 * read but may not be unique.
	 */
	public var shortComponentType(get, never):String;
	private inline function get_shortComponentType():String {
		return DOT_PATH.replace(componentType, "$1");
	}
	
	/**
	 * All components of this type.
	 */
	#if (echoes_storage == "Map")
	private final storage:Map<Int, T> = new Map();
	#else
	private final storage:Array<Null<T>> = [];
	#end
	
	public inline function new(componentType:String) {
		this.componentType = componentType;
		Echoes._componentStorage.push(this);
		
		//Some platforms get confused by the declaration of `Array<Null<T>>`,
		//and treat that as something like `Array<Dynamic>`, and then cast to
		//int, converting null to 0.
		
		//So far, this has only been seen in C++, and can be fixed by inserting
		//a null value anywhere in the array.
		#if (cpp && (echoes_storage != "Map"))
		storage[0] = null;
		#end
	}
	
	public function add(entity:Entity, component:T):Void {
		if(component == null) {
			remove(entity);
			return;
		}
		
		if(get(entity) == component) {
			return;
		}
		
		if(ongoingRemovals.contains(entity.id)) {
			throw 'Attempted to add $componentType to entity ${ entity.id } during a @:remove listener for that component.';
		}
		
		storage[entity.id] = component;
		
		var components:EntityComponents = EntityComponents.components[entity.id];
		if(components == null) {
			EntityComponents.components[entity.id] = components = new EntityComponents();
		}
		components.addComponentStorage(this);
		
		if(entity.active) {
			var exception:Exception = null;
			for(view in relatedViews) {
				try {
					view.add(entity);
				} catch(e:Exception) {
					if(exception == null) {
						exception = e;
					}
				}
				
				//Stop dispatching events if a listener removed it.
				if(!exists(entity)) {
					break;
				}
			}
			
			if(exception != null) {
				throw exception;
			}
		}
	}
	
	@:allow(echoes.Echoes)
	private inline function clear():Void {
		#if (echoes_storage == "Map")
		storage.clear();
		#else
		#if (eval && !haxe5)
		//Work around a bug in the eval target.
		for(i in 0...storage.length) {
			storage[i] = null;
		}
		#end
		storage.resize(0);
		#end
		
		ongoingRemovals.resize(0);
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
		final removedComponent:Null<T> = get(entity);
		
		#if (echoes_storage == "Map")
		storage.remove(entity.id);
		#else
		storage[entity.id] = null;
		#end
		
		if(removedComponent != null) {
			EntityComponents.components[entity.id].removeComponentStorage(this);
			
			if(entity.active) {
				ongoingRemovals.push(entity.id);
				
				var exception:Exception = null;
				for(view in relatedViews) {
					try {
						view.remove(entity, this, removedComponent);
					} catch(e:Exception) {
						if(exception == null) {
							exception = e;
						}
					}
				}
				
				ongoingRemovals.remove(entity.id);
				
				if(exception != null) {
					throw exception;
				}
			}
		}
	}
	
	/**
	 * Dispatches a `@:remove` event (if applicable) before adding `component`.
	 * To use this for a given component, tag the type with `@:echoes_replace`.
	 */
	public function replace(entity:Entity, component:T):Void {
		if(get(entity) != component) {
			var exception:Exception = null;
			try {
				remove(entity);
			} catch(e:Exception) {
				if(exception == null) {
					exception = e;
				}
			}
			
			try {
				add(entity, component);
			} catch(e:Exception) {
				if(exception == null) {
					exception = e;
				}
			}
			
			if(exception != null) {
				throw exception;
			}
		}
	}
	
	private inline function toString():String {
		return name;
	}
}

/**
 * A version of `ComponentStorage` that stores components of unknown type.
 * `add()` is disabled because there's no way to make sure the added component
 * is the correct type. `remove()` is still available because it doesn't need to
 * check any types.
 * 
 * If you're creating the `ComponentStorage` at runtime and want to be able to
 * add components, use `new ComponentStorage<Dynamic>()` instead. Obviously, no
 * type checking will be performed.
 */
@:forward(clear, componentType, exists, get, name, relatedViews, remove, shortComponentType)
abstract DynamicComponentStorage(ComponentStorage<Dynamic>) {
	@:from private static inline function fromComponentStorage<T>(componentStorage:ComponentStorage<T>):DynamicComponentStorage {
		return cast componentStorage;
	}
	
	@:allow(echoes.ViewBase)
	private var _relatedViews(get, never):Array<ViewBase>;
	private inline function get__relatedViews():Array<ViewBase> {
		return this._relatedViews;
	}
}

/**
 * The components currently attached to an entity. This isn't a good way to look
 * up an individual component, but it helps with batch operations such as
 * `deactivate()` and `destroy()`.
 */
@:forward(contains, containsComponentStorage, iterator, length) @:forward.new
@:allow(echoes.ComponentStorage)
abstract EntityComponents(ComponentTypes) from ComponentTypes {
	/**
	 * The source data for all `EntityComponents` lists. This should only be
	 * updated by `ComponentStorage`, or by `Echoes.reset()`.
	 */
	@:allow(echoes.Echoes)
	private static final components:Array<EntityComponents> = [];
	
	private inline function addComponentStorage(storage:DynamicComponentStorage):Void {
		this.addComponentStorage(storage);
	}
	
	/**
	 * Gets the `EntityComponents` list for the given entity.
	 */
	@:allow(echoes.Entity)
	private static inline function forEntity(entity:Entity):EntityComponents {
		if(components[entity.id] == null) {
			return components[entity.id] = new EntityComponents();
		} else {
			return components[entity.id];
		}
	}
	
	/**
	 * @see `Entity.removeAll()`
	 */
	@:allow(echoes.Entity)
	private static inline function removeAll(entity:Entity):Void {
		final entityComponents:EntityComponents = components[entity.id];
		if(entityComponents != null) {
			components[entity.id] = new EntityComponents();
			for(componentStorage in entityComponents) {
				componentStorage.remove(entity);
			}
		}
	}
	
	private inline function removeComponentStorage(storage:DynamicComponentStorage):Bool {
		return this.removeComponentStorage(storage);
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
		final entity:Entity = switch(components.indexOf(cast this)) {
			case -1:
				throw "This EntityComponents instance was disposed.";
			case x:
				cast x;
		};
		
		return [for(storage in this) storage.componentType => storage.get(entity)];
	}
}
