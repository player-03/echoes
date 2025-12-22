package echoes;

import echoes.ComponentStorage;
import echoes.Entity;
import echoes.utils.ReadOnlyData;
import echoes.utils.Signal;
import haxe.Exception;

#if !macro
@:genericBuild(echoes.macro.ViewBuilder.build())
#end
class View<Rest> extends ViewBase { }

class ViewBase {
	private var activations:Int = 0;
	public var active(get, never):Bool;
	private inline function get_active():Bool return activations > 0;
	
	/**
	 * All `ComponentStorage` instances related to this view.
	 */
	public final componentStorage:ReadOnlyArray<DynamicComponentStorage>;
	
	@:allow(echoes.Echoes) @:allow(echoes.ComponentStorage)
	private final _entities:Array<Entity> = [];
	/**
	 * All entities in this view.
	 */
	public var entities(get, never):ReadOnlyArray<Entity>;
	private inline function get_entities():ReadOnlyArray<Entity> return _entities;
	
	public inline function new(componentStorage:Array<DynamicComponentStorage>) {
		this.componentStorage = componentStorage;
	}
	
	public function activate():Void {
		activations++;
		if(activations == 1) {
			Echoes._activeViews.push(this);
			for(e in Echoes.activeEntities) {
				add(e);
			}
			for(storage in componentStorage) {
				storage._relatedViews.push(this);
			}
		}
	}
	
	@:allow(echoes.Entity) @:allow(echoes.ComponentStorage)
	private inline function add(entity:Entity):Void {
		var hasAllComponents:Bool = true;
		for(storage in componentStorage) {
			if(!storage.exists(entity)) {
				hasAllComponents = false;
				break;
			}
		}
		
		if(hasAllComponents) {
			if(!entities.contains(entity)) {
				_entities.push(entity);
			}
			dispatchAddedCallback(entity);
		}
	}
	
	public inline function deactivate():Void {
		activations--;
		if(activations <= 0) {
			reset();
		}
	}
	
	private function dispatchAddedCallback(entity:Entity):Void {
		//Overridden by `ViewBuilder`.
	}
	
	private function dispatchRemovedCallback(entity:Entity, removedComponentStorage:DynamicComponentStorage, removedComponent:Any):Void {
		//Overridden by `ViewBuilder`.
	}
	
	@:allow(echoes.Entity) @:allow(echoes.ComponentStorage)
	private inline function remove(entity:Entity, removedComponentStorage:DynamicComponentStorage, removedComponent:Any):Void {
		//Many applications will have a mix of short-lived and long-lived
		//entities. An entity being removed is more likely to be short-lived,
		//meaning it's near the end of the array.
		final index:Int = entities.lastIndexOf(entity);
		if(index >= 0) {
			#if echoes_stable_order
			_entities.splice(index, 1);
			#else
			_entities[index] = entities[entities.length - 1];
			_entities.pop();
			#end
			dispatchRemovedCallback(entity, removedComponentStorage, removedComponent);
		}
	}
	
	@:allow(echoes.Echoes) private function reset():Void {
		activations = 0;
		Echoes._activeViews.remove(this);
		_entities.resize(0);
		
		for(storage in componentStorage) {
			storage._relatedViews.remove(this);
		}
	}
	
	public inline function toString():String {
		return "View<" + [for(storage in componentStorage) storage.componentType].join(", ") + ">";
	}
}

/**
 * A `View` that can be created at runtime.
 * 
 * Sample usage:
 * 
 * ```haxe
 * //Storage for a custom component type.
 * public final customComponent:DynamicComponentStorage;
 * 
 * //A view of `customComponent` and `String`; it'll dispatch events for any
 * //entity that has both components.
 * public final view:DynamicView;
 * 
 * public function new() {
 *     customComponent = new DynamicComponentStorage("CustomComponent");
 *     
 *     view = new DynamicView(customComponent, Echoes.getComponentStorage(String));
 *     
 *     //Important: `DynamicView` doesn't activate itself.
 *     view.activate();
 *     
 *     //Add/remove listeners work normally, except the components are untyped.
 *     view.onAdded.add((entity:Entity, components:Array<Any>) -> trace('Entity $entity now has $components'));
 *     view.onRemoved.add((entity:Entity, components:Array<Any>) -> trace('Entity $entity no longer has all of $components'));
 * }
 * 
 * public function update(time:Float):Void {
 *     //Like with any other view, `iter()` doesn't allow for a time argument.
 *     //Here's one way to pass it in, but you could also simply leave it out.
 *     view.iter(updateEntity.bind(time));
 * }
 * 
 * private function updateEntity(time:Float, entity:Entity, components:Array<Any>):Void {
 *     trace('Updating entity $entity that has $components ($time seconds elapsed)')
 * }
 * ```
 */
class DynamicView extends ViewBase {
	public final onAdded:Signal<(Entity, Array<Any>) -> Void> = new Signal<(Entity, Array<Any>) -> Void>();
	public final onRemoved:Signal<(Entity, Array<Any>) -> Void> = new Signal<(Entity, Array<Any>) -> Void>();
	
	public inline function new(...componentStorage:DynamicComponentStorage) {
		super(componentStorage);
	}
	
	private override function dispatchAddedCallback(entity:Entity):Void {
		var index:Int = entities.lastIndexOf(entity);
		for(callback in onAdded) {
			callback(entity, [for(storage in componentStorage) storage.get(entity)]);
			
			//If the callback removed the entity, stop. Cache the index to save
			//time in most cases. HashLink is known to return 0 when reading out
			//of bounds, so it has to check length too.
			if(#if (hl || cpp) index >= entities.length || #end entities[index] != entity) {
				index = entities.lastIndexOf(entity);
				if(index < 0) {
					break;
				}
			}
		}
	}
	
	private override function dispatchRemovedCallback(entity:Entity, removedComponentStorage:DynamicComponentStorage, removedComponent:Any):Void {
		var exception:Exception = null;
		for(callback in onRemoved) {
			try {
				callback(entity, [for(storage in componentStorage)
					storage == removedComponentStorage ? removedComponent : storage.get(entity)]);	
			} catch(e:Exception) {
				exception = e;
			}
		}
		
		if(exception != null) {
			throw exception;
		}
	}
	
	private override function reset():Void {
		super.reset();
		onAdded.clear();
		onRemoved.clear();
	}
	
	public function iter(callback:(Entity, Array<Any>) -> Void):Void {
		var i:Int = 0;
		while(i < entities.length) {
			final entity:Entity = entities[i];
			callback(entity, [for(storage in componentStorage) storage.get(entity)]);
			
			if(entity != entities[i] && !entities.contains(entity)) {
				//Entity was removed; don't increment.
			} else {
				i++;
			}
		}
	}
}
