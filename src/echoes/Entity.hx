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
 * entity.add("String component");
 * entity.add(new MyComponent("foo"));
 * 
 * //Entities can only have one component of a given type. If you add a
 * //component that already exists, it will be replaced.
 * entity.add(new MyComponent("bar"));
 * 
 * //Components can be retrieved using `get()`.
 * trace(entity.get(String)); //"String component"
 * trace(entity.get(MyComponent).name); //"bar"
 * 
 * //Components can be removed using `remove()`.
 * entity.remove(MyComponent);
 * trace(entity.get(MyComponent)); //null
 * 
 * //Types with parameters require a special syntax. Otherwise, Haxe will
 * //assume the angle brackets mean "less than" and "greater than."
 * entity.add(["colorless", "green", "ideas"]);
 * //trace(entity.exists(Array<String>)); //syntax error
 * trace(entity.exists((_:Array<String>))); //true
 * 
 * //`Float` and `Entity` are reserved. To use them as components, you must
 * //first wrap them in a `typedef` or `abstract`.
 * typedef MyFloat = Float;
 * entity.add((1.1:MyFloat));
 * 
 * abstract MyEntity(Entity) from Entity to Entity { }
 * entity.add((entity:MyEntity));
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
	 * The status of every entity ID that has been allocated thus far. True
	 * means the entity is active, false means it's inactive or destroyed.
	 */
	private static var statuses:Array<Bool> = [];
	
	/**
	 * Whether this entity is active. If false, it may also be destroyed.
	 */
	public var active(get, never):Bool;
	private inline function get_active():Bool {
		return statuses[this];
	}
	
	/**
	 * Whether this entity has been destroyed.
	 */
	public var destroyed(get, never):Bool;
	private inline function get_destroyed():Bool {
		//In most cases it's faster to check `active` than `idPool`.
		return !active && idPool.contains(this);
	}
	
	/**
	 * @param active Whether to activate this entity immediately. Otherwise,
	 * you'll have to call `activate()`.
	 */
	public inline function new(?active:Bool = true) {
		var id:Null<Int> = idPool.pop();
		
		this = id != null ? id : nextId++;
		
		statuses[this] = active;
		if(active) {
			Echoes._activeEntities.add(this);
		}
	}
	
	/**
	 * Registers this entity so it can be found in views and updated by systems.
	 */
	public function activate():Void {
		if(!active) {
			statuses[this] = true;
			Echoes._activeEntities.add(this);
			for(view in Echoes.activeViews) view.addIfMatched(this);
		}
	}
	
	/**
	 * Removes this entity from all views and systems, but saves all associated
	 * components. Call `activate()` to restore it.
	 */
	public function deactivate():Void {
		if(active) {
			Echoes._activeEntities.remove(this);
			statuses[this] = false;
			for(view in Echoes.activeViews) view.removeIfExists(this);
		}
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
	 * for reuse. Don't save any references to this entity afterwards.
	 */
	public function destroy():Void {
		if(!destroyed) {
			deactivate();
			removeAll();
			idPool.push(this);
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
	 * Adds one or more components to the entity, dispatching an `@:add` event
	 * for each one. If the entity already has a component of the same type, the
	 * old component will be replaced.
	 * 
	 * If a component is replaced and its type is tagged `@:echoes_replace`,
	 * this will dispatch a `@:remove` event before dispatching `@:add`.
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

/**
 * Declares getters and setters for each of an abstract's variables.
 * @see `echoes.macro.AbstractEntity`
 */
macro function build():Array<Field> {
	return echoes.macro.AbstractEntity.build();
}
