package echoes.core;

import echoes.Entity;
import echoes.core.ReadOnlyData;

class AbstractView {
	private var _entities:List<Entity> = new List();
	/**
	 * List of entities in view.
	 */
	public var entities(get, never):ReadOnlyList<Entity>;
	private inline function get_entities():ReadOnlyList<Entity> return _entities;
	
	private var collected:Array<Bool> = [];
	
	private var activations:Int = 0;
	
	public function activate():Void {
		activations++;
		if(activations == 1) {
			Workflow._activeViews.push(this);
			for(e in Workflow.activeEntities) {
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
	
	public inline function isActive():Bool {
		return activations > 0;
	}
	
	public inline function size():Int {
		return entities.length;
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
	
	private function dispatchRemovedCallback(entity:Entity, ?removedComponentStorage:ICleanableComponentContainer, ?removedComponent:Any):Void {
		//Overridden by `ViewBuilder`.
	}
	
	@:allow(echoes.Workflow) function addIfMatched(entity:Entity):Void {
		if(collected[entity] != true) {
			if(isMatched(entity)) {
				collected[entity] = true;
				_entities.add(entity);
				dispatchAddedCallback(entity);
			}
		}
	}
	
	@:allow(echoes.Workflow) function removeIfExists(entity:Entity, ?removedComponentStorage:ICleanableComponentContainer, ?removedComponent:Any):Void {
		if(collected[entity] == true) {
			collected[entity] = false;
			_entities.remove(entity);
			dispatchRemovedCallback(entity, removedComponentStorage, removedComponent);
		}
	}
	
	@:allow(echoes.Workflow) function reset():Void {
		activations = 0;
		Workflow._activeViews.remove(this);
		while(entities.length > 0) {
			removeIfExists(_entities.pop());
		}
		collected.resize(0);
	}
	
	public function toString():String {
		return "AbstractView";
	}
}
