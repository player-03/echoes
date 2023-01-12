package echoes;

import echoes.ComponentStorage;
import echoes.Entity;
import echoes.utils.ReadOnlyData;

#if !macro
@:genericBuild(echoes.macro.ViewBuilder.build())
#end
class View<Rest> extends ViewBase { }

class ViewBase {
	private var _entities:List<Entity> = new List();
	/**
	 * All entities in this view.
	 */
	public var entities(get, never):ReadOnlyList<Entity>;
	private inline function get_entities():ReadOnlyList<Entity> return _entities;
	
	private var activations:Int = 0;
	public var active(get, never):Bool;
	private inline function get_active():Bool return activations > 0;
	
	public function activate():Void {
		activations++;
		if(activations == 1) {
			Echoes._activeViews.push(this);
			for(e in Echoes.activeEntities) {
				addIfMatched(e);
			}
		}
	}
	
	public function deactivate():Void {
		activations--;
		if(activations <= 0) {
			reset();
		}
	}
	
	/**
	 * Returns whether the entity has all of the view's required components.
	 */
	private function isMatched(entity:Entity):Bool {
		//Overridden by `ViewBuilder`.
		return false;
	}
	
	private function dispatchAddedCallback(entity:Entity):Void {
		//Overridden by `ViewBuilder`.
	}
	
	private function dispatchRemovedCallback(entity:Entity, ?removedComponentStorage:DynamicComponentStorage, ?removedComponent:Any):Void {
		//Overridden by `ViewBuilder`.
	}
	
	@:allow(echoes.Entity) @:allow(echoes.ComponentStorage)
	private function addIfMatched(entity:Entity):Void {
		if(!entities.has(entity)) {
			if(isMatched(entity)) {
				_entities.add(entity);
				dispatchAddedCallback(entity);
			}
		} else {
			dispatchAddedCallback(entity);
		}
	}
	
	@:allow(echoes.Entity) @:allow(echoes.ComponentStorage)
	private function removeIfExists(entity:Entity, ?removedComponentStorage:DynamicComponentStorage, ?removedComponent:Any):Void {
		if(_entities.remove(entity)) {
			dispatchRemovedCallback(entity, removedComponentStorage, removedComponent);
		}
	}
	
	@:allow(echoes.Echoes) private function reset():Void {
		activations = 0;
		Echoes._activeViews.remove(this);
		while(!entities.isEmpty()) {
			removeIfExists(entities.first());
		}
	}
	
	public function toString():String {
		return "ViewBase";
	}
}
