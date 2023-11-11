package echoes;

import echoes.ComponentStorage;
import echoes.Entity;
import echoes.utils.ReadOnlyData;

#if !macro
@:genericBuild(echoes.macro.ViewBuilder.build())
#end
class View<Rest> extends ViewBase { }

class ViewBase {
	@:allow(echoes.Echoes) private final _entities:Array<Entity> = [];
	/**
	 * All entities in this view.
	 */
	public var entities(get, never):ReadOnlyArray<Entity>;
	private inline function get_entities():ReadOnlyArray<Entity> return _entities;
	
	private var activations:Int = 0;
	public var active(get, never):Bool;
	private inline function get_active():Bool return activations > 0;
	
	public function activate():Void {
		activations++;
		if(activations == 1) {
			Echoes._activeViews.push(this);
			for(e in Echoes.activeEntities) {
				add(e);
			}
		}
	}
	
	@:allow(echoes.Entity) @:allow(echoes.ComponentStorage)
	private inline function add(entity:Entity):Void {
		if(isMatched(entity)) {
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
	
	private function dispatchRemovedCallback(entity:Entity, ?removedComponentStorage:DynamicComponentStorage, ?removedComponent:Any):Void {
		//Overridden by `ViewBuilder`.
	}
	
	/**
	 * Returns whether the entity has all of the view's required components.
	 */
	private function isMatched(entity:Entity):Bool {
		//Overridden by `ViewBuilder`.
		return false;
	}
	
	@:allow(echoes.Entity) @:allow(echoes.ComponentStorage)
	private inline function remove(entity:Entity, ?removedComponentStorage:DynamicComponentStorage, ?removedComponent:Any):Void {
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
	}
	
	public function toString():String {
		return "ViewBase";
	}
}
