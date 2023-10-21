package echoes;

import echoes.ComponentStorage;
import echoes.utils.ReadOnlyData;

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
abstract Entity(Int) {
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
		var id:Null<Int> = idPool.pop();
		
		this = id != null ? id : nextId++;
		
		statuses[this] = active;
		if(active) {
			Echoes._activeEntities.add(cast this);
		}
	}
	
	/**
	 * Registers this entity so it can be found in views and updated by systems.
	 */
	public function activate():Void {
		if(!active) {
			statuses[this] = true;
			Echoes._activeEntities.add(cast this);
			
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
		if(active) {
			Echoes._activeEntities.remove(cast this);
			statuses[this] = false;
			
			for(storage in getComponents()) {
				for(view in storage.relatedViews) {
					view.remove(cast this);
				}
			}
		}
	}
	
	/**
	 * Removes all of this entity's components, deactivates it, and frees its id
	 * for reuse. Don't save any references to this entity afterwards.
	 */
	public function destroy():Void {
		if(!destroyed) {
			removeAll();
			deactivate();
			idPool.push(this);
		}
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public macro function exists(self:Expr, type:ExprOf<Class<Any>>):ExprOf<Bool> {
		return EntityTools.exists(self, type.parseClassExpr());
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
		return EntityTools.remove(self, [for(type in types) type.parseClassExpr()]);
	}
	
	/**
	 * Removes all of this entity's components, but does not deactivate or
	 * destroy it. Caution: if a `@:remove` listener adds a component to the
	 * entity, that component may remain afterwards.
	 */
	public inline function removeAll():Void {
		EntityComponents.removeAll(cast this);
	}
}

/**
 * A build macro for entity templates. An entity template fills a similar role
 * to a class, allowing a user to easily create entities with pre-defined sets
 * of components. But unlike classes, it's possible to apply multiple templates
 * to a single entity.
 * 
 * Templates also offer syntax sugar for accessing components. For example,
 * if the template declares `var component:Component`, the user can then refer
 * to `entity.component` instead of `entity.get(Component)`.
 * 
 * Sample usage:
 * 
 * ```haxe
 * //`Fighter` is a template for entities involved in combat. A `Fighter` entity
 * //will always have `Damage`, `Health`, and `Hitbox` components.
 * @:build(echoes.Entity.build()) @:arguments(Hitbox)
 * abstract Fighter(Entity) {
 *     //Each variable represents the component of that type. For instance,
 *     //`fighter.damage` will get/set the entity's `Damage` component.
 *     public var damage:Damage = 1;
 *     public var health:Health = 10;
 *     
 *     //Components listed in `@:arguments` (see above) don't need a value.
 *     //Instead, their value is passed to the constructor.
 *     public var hitbox:Hitbox;
 *     
 *     //Components without a value that aren't listed in `@:arguments` are
 *     //considered optional, and default to null.
 *     public var sprite:Sprite;
 *     
 *     //The constructor is generated automatically, but you can declare
 *     //`onApplyTemplate()` to run code afterwards. As the name indicates, this
 *     //also runs after `applyTemplateTo()`.
 *     private inline function onApplyTemplate():Void {
 *         if(health <= 0) {
 *             health = 1;
 *         }
 *     }
 *     
 *     //You may add any other function as normal.
 *     public inline function getDamageDealt(target:Hitbox):Damage {
 *         if(target.overlapping(hitbox)) {
 *             return damage;
 *         } else {
 *             return 0;
 *         }
 *     }
 * }
 * 
 * //Templates may inherit from one another. The `@:forward` metadata will be
 * //automatically added if not present.
 * @:build(echoes.Entity.build())
 * abstract RangedFighter(Fighter) {
 *     public var fireRate:FireRate = 1;
 *     public var range:Range = 2;
 *     
 *     //Components set in the child template override those from the parent.
 *     public var health:Health = 5;
 * }
 * 
 * class Main {
 *     public static function main():Void {
 *         var knight:Fighter = new Fighter(new SquareHitbox(1), new Sprite("fighter.png"));
 *         
 *         //The variables now act as shortcuts for `add()` and `get()`.
 *         trace(knight.health); //10
 *         trace(knight.get(Health)); //10
 *         
 *         //Because each variable has a different type, you don't need to
 *         //specify which type you mean.
 *         knight.health = 9;
 *         knight.damage = 3;
 *         trace(knight.get(Health)); //9
 *         trace(knight.get(Damage)); //3
 *         
 *         //If using `add()`, you still have to specify types.
 *         knight.add((8:Health));
 *         trace(knight.health); //8
 *         
 *         //It's also possible to convert a pre-existing entity to `Fighter`.
 *         var greenEntity:Entity = new Entity();
 *         greenEntity.add(Color.GREEN);
 *         greenEntity.add((20:Health));
 *         
 *         //`Fighter.applyTemplateTo()` adds all required components that are
 *         //currently missing, and casts the entity to `Fighter`.
 *         var greenKnight:Fighter = Fighter.applyTemplateTo(greenEntity, new RectHitbox(1, 2));
 *         
 *         //`Health` and `Color` remain the same as before.
 *         trace(greenKnight.health); //20
 *         trace("0x" + StringTools.hex(greenKnight.get(Color), 6)); //0x00FF00
 *         
 *         //`Damage` wasn't already defined, so it has its default value.
 *         trace(greenKnight.damage); //1
 *         
 *         //Since `sprite` is optional, `applyTemplateTo()` won't add one.
 *         trace(greenKnight.sprite); //null
 *     }
 * }
 * ```
 */
macro function build():Array<Field> {
	return echoes.macro.EntityTemplateBuilder.build();
}
