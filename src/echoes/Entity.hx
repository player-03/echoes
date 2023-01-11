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
 * An entity is a collection of components. These components can be managed
 * using `entity.add()` and `entity.remove()`. Sample usage:
 * 
 * ```haxe
 * var entity:Entity = new Entity();
 * 
 * //Almost any Haxe type can be added as a component.
 * entity.add("string component");
 * entity.add(["array", "of", "strings", "component"]);
 * 
 * //Entities can only have one component of a given type. If you add a
 * //component that already exists, it will be replaced.
 * entity.add("a different string");
 * 
 * //Components can be retrieved using `get()`.
 * trace(entity.get(String)); //"a different string"
 * 
 * //Components can be removed using `remove()`.
 * entity.remove(String);
 * trace(entity.get(String)); //null
 * 
 * //`Float` and `Entity` are reserved, and can't be added as components.
 * //However, `typedef`s of `Float` and `Entity` work fine.
 * entity.add((1.1:FloatTypedef)); //Instead of `entity.add(1.1);`
 * entity.add((entity:EntityTypedef)); //Instead of `entity.add(entity);`
 * ```
 */
@:allow(echoes.Echoes)
abstract Entity(Int) from Int to Int {
	/**
	 * The next entity ID that will be allocated, if `idPool` is empty.
	 */
	private static var nextId:Int = 0;
	
	/**
	 * A destroyed entity's ID will go in this pool, and will then be reassigned
	 * to the next entity to be created.
	 */
	private static var idPool:Array<Int> = [];
	
	/**
	 * The status (`Active`, `Inactive`, or `Destroyed`) of every entity ID
	 * that has been allocated thus far.
	 */
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
	 * Returns the status of this entity: `Active`, `Inactive`, or `Destroyed`.
	 */
	public inline function status():Status {
		return statuses[this];
	}
	
	/**
	 * Removes all of this entity's components, but does not deactivate or
	 * destroy it. Caution: if a `@:remove` listener adds a component to the
	 * entity, that component may remain afterwards.
	 */
	public function removeAll():Void {
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
	 * 
	 * When a component is replaced this way, no events will be dispatched
	 * unless the component type is tagged `@:echoes_replace`, in which case
	 * both events (`@:remove` and `@:add`) will be dispatched.
	 * @param components Components of `Any` type.
	 * @return This entity.
	 */
	public macro function add(self:Expr, components:Array<Expr>):ExprOf<echoes.Entity> {
		return EntityTools.add(self, components);
	}
	
	/**
	 * Adds one or more components to the entity, but only if those components
	 * don't already exist. If the entity already has a component of the same
	 * type, the old component will remain.
	 * 
	 * Any side-effects of creating a component will only occur if that
	 * component is added. For instance, `entity.addIfMissing(array.pop())` will
	 * only pop an item from `array` if that component was missing.
	 * @param components Components of `Any` type.
	 * @return This entity.
	 */
	public macro function addIfMissing(self:Expr, components:Array<Expr>):ExprOf<echoes.Entity> {
		return EntityTools.addIfMissing(self, components);
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
