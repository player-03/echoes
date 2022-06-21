package echoes.core;

import echoes.Entity;

class AbstractView {
	/**
	 * List of entities in view.
	 */
	public var entities(default, null):RestrictedLinkedList<Entity> = new RestrictedLinkedList();
	
	private var collected:Array<Bool> = [];
	
	private var activations:Int = 0;
	
	public function activate():Void {
		activations++;
		if(activations == 1) {
			Workflow.views.add(this);
			for(e in Workflow.entities) {
				addIfMatched(e);
			}
		}
	}
	
	public function deactivate():Void {
		activations--;
		if(activations == 0) {
			Workflow.views.remove(this);
			while(entities.length > 0) {
				removeIfExists(entities.pop());
			}
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
		// macro generated
		return false;
	}
	
	private function dispatchAddedCallback(entity:Entity):Void {
		// macro generated
	}
	
	private function dispatchRemovedCallback(entity:Entity):Void {
		// macro generated
	}
	
	@:allow(echoes.Workflow) function addIfMatched(entity:Entity):Void {
		if(isMatched(entity)) {
			if(collected[entity] != true) {
				collected[entity] = true;
				entities.add(entity);
				dispatchAddedCallback(entity);
			}
		}
	}
	
	@:allow(echoes.Workflow) function removeIfExists(entity:Entity):Void {
		if(collected[entity] == true) {
			collected[entity] = false;
			entities.remove(entity);
			dispatchRemovedCallback(entity);
		}
	}
	
	@:allow(echoes.Workflow) function reset() {
		activations = 0;
		Workflow.views.remove(this);
		while(entities.length > 0) {
			removeIfExists(entities.pop());
		}
		collected.splice(0, collected.length);
	}
	
	public function toString():String {
		return "AbstractView";
	}
}
