package echoes;

import echoes.ComponentStorage;

#if macro
import echoes.macro.EntityTools;
import haxe.macro.Expr;

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
abstract Entity(Int) {
	/**
	 * Whether this entity is active. If it is, events will be dispatched
	 * whenever a component is added or removed. If not, those events will be
	 * postponed until it becomes active again.
	 */
	public var active(get, never):Bool;
	private inline function get_active():Bool {
		return Echoes.entityStates[this] >= BEING_DESTROYED;
	}
	
	/**
	 * Whether this entity is in the process of being destroyed.
	 */
	public var beingDestroyed(get, never):Bool;
	private inline function get_beingDestroyed():Bool {
		return Echoes.entityStates[this] == BEING_DESTROYED;
	}
	
	/**
	 * Whether this entity has been destroyed, and should no longer be used.
	 */
	public var destroyed(get, never):Bool;
	private inline function get_destroyed():Bool {
		return Echoes.entityStates[this] == DESTROYED;
	}
	
	/**
	 * This entity's unique integer ID. Used internally.
	 */
	public var id(get, never):Int;
	private inline function get_id():Int {
		return this;
	}
	
	/**
	 * @param active Whether to activate this entity immediately. Otherwise,
	 * you'll have to call `activate()`.
	 */
	public inline function new(?active:Bool = true) {
		final id:Null<Int> = idPool.pop();
		
		this = id != null ? id : Echoes.entityStates.length;
		
		if(active) {
			Echoes.entityStates[this] = Echoes._activeEntities.length;
			Echoes._activeEntities.push(cast this);
		} else {
			Echoes.entityStates[this] = INACTIVE;
		}
	}
	
	/**
	 * Registers this entity so it can be found in views and updated by systems.
	 */
	public function activate():Void {
		if(!active) {
			Echoes.entityStates[this] = Echoes._activeEntities.length;
			Echoes._activeEntities.push(cast this);
			
			for(storage in getComponents()) {
				for(view in storage.relatedViews) {
					view.add(cast this);
				}
			}
		}
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
	 * Removes this entity from all views and systems, but saves all associated
	 * components. Call `activate()` to restore it.
	 * 
	 * Note: this will trigger `@:remove` events for all of the entity's
	 * components, even though the components aren't removed.
	 */
	public function deactivate():Void {
		final index:Int = Echoes.entityStates[this];
		//Testing `>= 0` ensures the entity is active and not being destroyed.
		if(index >= 0) {
			Echoes.entityStates[this] = INACTIVE;
			Echoes.removeActiveEntityAt(index);
			
			for(storage in getComponents()) {
				final component:Dynamic = storage.get(cast this);
				for(view in storage.relatedViews) {
					view.remove(cast this, storage, component);
				}
			}
		}
	}
	
	/**
	 * Removes all of this entity's components, deactivates it, and frees its id
	 * for reuse. Don't save any references to this entity afterwards.
	 */
	public function destroy():Void {
		if(!destroyed && !beingDestroyed) {
			final index:Int = Echoes.entityStates[this];
			
			if(active) {
				Echoes.entityStates[this] = BEING_DESTROYED;
			}
			
			removeAll();
			
			if(index >= 0) {
				Echoes.removeActiveEntityAt(index);
			}
			
			Echoes.entityStates[this] = DESTROYED;
			idPool.push(this);
		}
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public macro function exists(self:Expr, type:ExprOf<Class<Any>>):ExprOf<Bool> {
		return EntityTools.exists(self, type.parseClassExpr(true));
	}
	
	/**
	 * Gets this entity's component of the given type, if this entity has a
	 * component of the given type.
	 * @param type The type of the component to get.
	 * @return The component, or `null` if the entity doesn't have it.
	 */
	public macro function get<T>(self:Expr, type:ExprOf<Class<T>>):ExprOf<T> {
		return EntityTools.get(self, type.parseClassExpr(true));
	}
	
	/**
	 * Finds all the `ComponentStorage` instances currently storing information
	 * about this entity. This is roughly equivalent to a list of components.
	 * @see `get()` for a faster way to look up individual components.
	 */
	public inline function getComponents():EntityComponents {
		return EntityComponents.forEntity(cast this);
	}
	
	/**
	 * Removes one or more components from the entity.
	 * @param types The type(s) of the components to remove. _Not_ the
	 * components themselves!
	 * @return This entity.
	 */
	public macro function remove(self:Expr, types:Array<ExprOf<Class<Any>>>):ExprOf<echoes.Entity> {
		return EntityTools.remove(self, [for(type in types) type.parseClassExpr(true)]);
	}
	
	/**
	 * Removes all of this entity's components, but does not deactivate or
	 * destroy it. Caution: if a `@:remove` listener adds a component to the
	 * entity, that component may remain afterwards.
	 */
	public inline function removeAll():Void {
		EntityComponents.removeAll(cast this);
	}
	
	//Internal
	//========
	
	/**
	 * Indicates an entity that is in the process of being destroyed. Any value
	 * greater than or equal to this indicates an active entity.
	 */
	private static var BEING_DESTROYED(get, never):Int;
	private static inline function get_BEING_DESTROYED():Int {
		return -1;
	}
	
	/**
	 * Indicates an entity that has been destroyed.
	 */
	private static var DESTROYED(get, never):Int;
	private static inline function get_DESTROYED():Int {
		return -3;
	}
	
	/**
	 * Indicates an entity that isn't active, but still exists.
	 */
	private static var INACTIVE(get, never):Int;
	private static inline function get_INACTIVE():Int {
		return -2;
	}
	
	/**
	 * IDs of destroyed entities, to be reused when new entities are created.
	 */
	private static final idPool:Array<Int> = [];
}

@:deprecated("Instead, install the echoes-templates Haxelib, and use echoes.Template.build().")
macro function build():Array<Field> {
	return echoes.macro.EntityTemplateBuilder.build();
}
