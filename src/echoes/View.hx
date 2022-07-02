package echoes;

import echoes.Entity;
import echoes.core.ICleanableComponentContainer;
import echoes.core.ReadOnlyData;

#if !macro
@:genericBuild(echoes.core.macro.ViewBuilder.build())
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
		if(!entities.has(entity) && isMatched(entity)) {
			_entities.add(entity);
			dispatchAddedCallback(entity);
		}
	}
	
	@:allow(echoes.Workflow) function removeIfExists(entity:Entity, ?removedComponentStorage:ICleanableComponentContainer, ?removedComponent:Any):Void {
		if(_entities.remove(entity)) {
			dispatchRemovedCallback(entity, removedComponentStorage, removedComponent);
		}
	}
	
	@:allow(echoes.Workflow) function reset():Void {
		activations = 0;
		Workflow._activeViews.remove(this);
		while(!entities.isEmpty()) {
			removeIfExists(entities.first());
		}
	}
	
	public function toString():String {
		return "ViewBase";
	}
}
