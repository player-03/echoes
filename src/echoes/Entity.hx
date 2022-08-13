package echoes;

#if macro
import echoes.macro.EntityTools;
import haxe.macro.Expr;
import haxe.macro.Printer;

using echoes.macro.ComponentStorageBuilder;
using echoes.macro.MacroTools;
using haxe.macro.Context;
using Lambda;
#end

/**
 * The entity part of entity-component-system.
 * 
 * Under the hood, an `Entity` is an integer key, used to look up components in
 * `Storage`. (Caution: don't use this integer as a unique id, as destroyed
 * entities will be cached and reused!)
 */
@:allow(echoes.Echoes)
abstract Entity(Int) from Int to Int {
	public static inline var INVALID:Entity = -1;
	private static var nextId:Int = 0;
	private static var idPool:Array<Int> = [];
	private static var statuses:Array<Status> = [];
	
	/**
	 * @param activate Whether to activate this entity immediately. Otherwise,
	 * you'll have to call `activate()`.
	 */
	public inline function new(?activate:Bool = true) {
		var id:Null<Int> = idPool.pop();
		
		this = id != null ? id : nextId++;
		
		if(activate) {
			statuses[this] = Active;
			Echoes._activeEntities.add(this);
		} else {
			statuses[this] = Inactive;
		}
	}
	
	/**
	 * Registers this entity so it can be found in views and updated by systems.
	 */
	public function activate():Void {
		if(status() == Inactive) {
			statuses[this] = Active;
			Echoes._activeEntities.add(this);
			for(view in Echoes.activeViews) view.addIfMatched(this);
		}
	}
	
	/**
	 * Removes this entity from all views and systems, but saves all associated
	 * components. Call `activate()` to restore it.
	 */
	public function deactivate():Void {
		if(status() == Active) {
			Echoes._activeEntities.remove(this);
			statuses[this] = Inactive;
			for(view in Echoes.activeViews) view.removeIfExists(this);
		}
	}
	
	public inline function isActive():Bool {
		return status() == Active;
	}
	
	public inline function isDestroyed():Bool {
		return status() == Destroyed;
	}
	
	/**
	 * Returns the status of this entity: Active, Inactive, or Destroyed.
	 */
	public inline function status():Status {
		return statuses[this];
	}
	
	/**
	 * Removes all of this entity's components, but does not deactivate or
	 * destroy it.
	 */
	public function removeAll():Void {
		if(status() == Active) {
			for(view in Echoes.activeViews) {
				view.removeIfExists(this);
			}
		}
		
		for(storage in Echoes.componentStorage) {
			storage.remove(this);
		}
	}
	
	/**
	 * Removes all of this entity's components, deactivates it, and frees its id
	 * for reuse. Do not call any of the entity's functions after this; their
	 * behavior is unspecified.
	 */
	public function destroy():Void {
		if(!isDestroyed()) {
			removeAll();
			Echoes._activeEntities.remove(this);
			idPool.push(this);
			statuses[this] = Destroyed;
		}
	}
	
	public function getComponents():Map<String, Dynamic> {
		var components:Map<String, Dynamic> = new Map();
		for(storage in Echoes.componentStorage) {
			if(storage.exists(this)) {
				components[storage.name] = storage.get(this);
			}
		}
		return components;
	}
	
	/**
	 * Adds one or more components to the entity. If the entity already has a
	 * component of the same type, the old component will be replaced.
	 * @param components Components of `Any` type.
	 * @return This entity.
	 */
	public macro function add(self:Expr, components:Array<Expr>):ExprOf<echoes.Entity> {
		return EntityTools.add(self, components);
	}
	
	/**
	 * Removes one or more components from the entity.
	 * @param types The type(s) of the components to remove. _Not_ the
	 * components themselves!
	 * @return This entity.
	 */
	public macro function remove(self:Expr, types:Array<ExprOf<Class<Any>>>):ExprOf<echoes.Entity> {
		return EntityTools.remove(self, [for(type in types) type.parseClassExpr()]);
	}
	
	/**
	 * Gets this entity's component of the given type, if this entity has a
	 * component of the given type.
	 * @param type The type of the component to get.
	 * @return The component, or `null` if the entity doesn't have it.
	 */
	public macro function get<T>(self:Expr, type:ExprOf<Class<T>>):ExprOf<T> {
		return EntityTools.get(self, type.parseClassExpr());
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public macro function exists(self:Expr, type:ExprOf<Class<Any>>):ExprOf<Bool> {
		return EntityTools.exists(self, type.parseClassExpr());
	}
}

@:enum abstract Status(Int) {
	/**
	 * Entity exists and has components, but will not be added to views or
	 * updated by systems.
	 */
	var Inactive = 0;
	/**
	 * Entity will be added to views and updated by systems.
	 */
	var Active = 1;
	/**
	 * Entity has no components and has been removed from all views. Its ID may
	 * be reused later, but until then it is unsafe to call any functions beyond
	 * `status()` and `isDestroyed()`.
	 */
	var Destroyed = 2;
}
