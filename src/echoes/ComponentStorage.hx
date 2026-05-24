package echoes;

import echoes.Echoes;
import echoes.Entity;
import echoes.utils.ComponentTypes;
import echoes.utils.ReadOnlyData;
import echoes.utils.Signal;
import echoes.View;
import haxe.Exception;
import haxe.Serializer;
import haxe.Unserializer;
import Type;

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
	 * Dispatched for each error encountered during `@:add` and `@:remove`
	 * events. If this has at least one listener, it will prevent the error from
	 * being rethrown. If this has no listeners, the error will be rethrown,
	 * crashing the app unless caught.
	 * 
	 * The `Exception` passed to the listener will contain the entire stack
	 * trace, split into two parts. `exception.previous.stack` is the inner
	 * portion (from `throw` to `ComponentStorage`). `exception.stack` is the
	 * outer portion (from `ComponentStorage` to the main function). Use
	 * `exception.details()` to print both parts in order.
	 * 
	 * Caution: if you neither use `onError` nor catch the rethrown error, the
	 * target determines how to print it. Some targets will only print the outer
	 * portion of the stack trace, omitting the most specific lines.
	 */
	public static final onError:Signal<(Exception) -> Void> = new Signal();
	
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
	@:allow(echoes.Echoes)
	#if (echoes_storage == "Map")
	private final storage:Map<Int, T> = new Map();
	#else
	private final storage:Array<Null<T>> = [];
	#end
	
	private final valueType:ValueType;
	
	public inline function new(componentType:String, ?valueType:ValueType) {
		this.componentType = componentType;
		this.valueType = valueType != null ? valueType : TUnknown;
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
	
	public function add(entity:Entity, component:Null<T>):Void {
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
		
		EntityComponents.forEntity(entity).addComponentStorage(this);
		
		final exception:Null<Exception> = dispatchAddEvent(entity);
			
		if(exception != null) {
			//If you get an error here, see `onError`.
			throw exception;
		}
	}
	
	#if !echoes_no_addDynamic
	
	/**
	 * Adds the given component if it's the correct type. Returns whether the
	 * component was successfully added.
	 * 
	 * Caution: this only checks type information that's available at runtime,
	 * which means it can't verify type parameters.
	 */
	public function addDynamic(entity:Entity, component:Dynamic):Bool {
		if(isCorrectType(component)) {
			add(entity, cast component);
			return true;
		} else {
			return false;
		}
	}
	
	#end
	
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
	
	private inline function dispatchAddEvent(entity:Entity):Null<Exception> {
		if(entity.active) {
			var exception:Exception = null;
			for(view in relatedViews) {
				try {
					view.add(entity);
				} catch(e:Exception) {
					if(onError.length > 0) {
						onError.dispatch(new Exception('Error while adding $componentType to entity ${ entity.id }.', e));
					} else if(exception == null) {
						exception = e;
					}
				}
				
				//Stop dispatching events if a listener removed it.
				if(!exists(entity)) {
					break;
				}
			}
			
			return exception;
		} else {
			return null;
		}
	}
	
	private inline function dispatchRemoveEvent(entity:Entity, removedComponent:T):Null<Exception> {
		if(entity.active) {
			ongoingRemovals.push(entity.id);
			
			var exception:Exception = null;
			for(view in relatedViews) {
				try {
					view.remove(entity, this, removedComponent);
				} catch(e:Exception) {
					if(onError.length > 0) {
						onError.dispatch(new Exception('Error while removing $componentType from entity ${ entity.id }.', e));
					} else if(exception == null) {
						exception = e;
					}
				}
			}
			
			ongoingRemovals.remove(entity.id);
			
			return exception;
		} else {
			return null;
		}
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
	
	/**
	 * Checks whether the given component can be added to this storage.
	 * 
	 * Due to limitations of Haxe's type system, this can only verify basic
	 * types, class instances, and enum values. It will always return false for
	 * functions, anonymous structures, and private types.
	 * 
	 * Also, type parameters cannot be checked at runtime, so (for instance)
	 * this will treat `Array<Int>` and `Array<String>` as the same.
	 */
	public function isCorrectType(component:Dynamic):Bool {
		switch(valueType) {
			case TNull:
				//Special case: `TNull` means this was created as a
				//`DynamicComponentStorage` and should accept all components.
				return true;
			case TBool:
				return Std.isOfType(component, Bool);
			case TInt:
				return Std.isOfType(component, Int);
			case TFloat:
				return Std.isOfType(component, Float);
			case TClass(c):
				return c == Type.getClass(component);
			case TEnum(e):
				switch(Type.typeof(component)) {
					case TEnum(e2):
						return e == e2;
					default:
						return false;
				}
			default:
				return false;
		}
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
			
			final exception:Null<Exception> = dispatchRemoveEvent(entity, removedComponent);
			
			if(exception != null) {
				//If you get an error here, see `onError`.
				throw exception;
			}
		}
	}
	
	/**
	 * Removes all components of this type from all entities.
	 */
	public inline function removeAll():Void {
		for(entity => component in storage) {
			if(component != null) {
				remove(cast entity);
			}
		}
	}
	
	/**
	 * As `add()`, but first dispatches a `@:remove` event if the entity already
	 * had a component of this type.
	 * 
	 * Tag a component with `@:echoes_replace` to enable this behavior for that
	 * component. Then, any time that component is added via `Entity.add()`, it
	 * will dispatch a `@:remove` event for the old value (if any). This also
	 * applies to entity templates, which call `Entity.add()` under the hood.
	 * 
	 * You can circumvent `@:echoes_replace` using `ComponentStorage.add()`. For
	 * instance, `Echoes.getComponentStorage(MyType).add(entity, new MyType())`
	 * will not dispatch a `@:remove` event.
	 * 
	 * The component will be updated before either event is dispatched, meaning
	 * you can check `entity.get(T)` during the `@:remove` listener to see what
	 * it's being replaced with.
	 */
	public function replace(entity:Entity, component:Null<T>):Void {
		if(get(entity) == component) {
			return;
		}
		
		if(ongoingRemovals.contains(entity.id)) {
			throw 'Attempted to replace $componentType on entity ${ entity.id } during a @:remove listener for that component.';
		}
		
		final replacedComponent:Null<T> = get(entity);
		
		#if (echoes_storage == "Map")
		if(component == null) {
			storage.remove(entity.id);
		} else {
			storage[entity.id] = component;
		}
		#else
		storage[entity.id] = component;
		#end
		
		EntityComponents.forEntity(entity).addOrRemoveComponentStorage(this, component != null);
		
		var exception:Null<Exception> = null;
		
		if(replacedComponent != null) {
			exception = dispatchRemoveEvent(entity, replacedComponent);
		}
		
		if(component != null) {
			final exception2:Null<Exception> = dispatchAddEvent(entity);
			if(exception == null) {
				exception = exception2;
			}
		}
			
		if(exception != null) {
			//If you get an error here, see `onError`.
			throw exception;
		}
	}
	
	/**
	 * Saves all components of this type to string.
	 * @see `Echoes.serialize()` to save all components at once.
	 */
	public function serialize():String {
		return Serializer.run(storage);
	}
	
	private inline function toString():String {
		return name;
	}
	
	/**
	 * Restores all components of this type from string, overwriting any
	 * existing components.
	 * 
	 * Caution: serializing and unserializing are not well-tested. Use this at
	 * your own risk, and especially avoid unserializing if the component type
	 * could have changed. Even a minor change, such as changing `Int` to
	 * `Float`, can cause errors on some targets.
	 * @see `Echoes.unserialize()` to restore all components at once.
	 */
	public function unserialize(data:String):Void {
		removeAll();
		
		unserializeFromData(Unserializer.run(data));
	}
	
	@:allow(echoes.Echoes)
	private function unserializeFromData(data:#if (echoes_storage == "Map") Map<Int, T> #else Array<Null<T>> #end) {
		clear();
		
		if(data != null) {
			for(entity => component in data) {
				add(cast entity, component);
			}
		}
	}
}

/**
 * A version of `ComponentStorage` that stores components of unknown type.
 * Since this strips the compile-time type checks, you must use `addDynamic()`
 * instead of `add()`.
 */
@:forward(clear, componentType, exists, get, isCorrectType, name, relatedViews, remove, removeAll, shortComponentType #if !echoes_no_addDynamic , addDynamic #end)
abstract DynamicComponentStorage(ComponentStorage<Dynamic>) {
	@:from private static inline function fromComponentStorage<T>(componentStorage:ComponentStorage<T>):DynamicComponentStorage {
		return cast componentStorage;
	}
	
	public inline function new(componentType:String, ?valueType:ValueType) {
		this = new ComponentStorage<Dynamic>(componentType,
			valueType != null ? valueType : TNull);
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
	
	private inline function addOrRemoveComponentStorage(storage:DynamicComponentStorage, add:Bool):Void {
		if(add) {
			this.addComponentStorage(storage);
		} else {
			this.removeComponentStorage(storage);
		}
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
