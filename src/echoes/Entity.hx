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
			for(view in Echoes.activeViews) view.addIfMatched(cast this);
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
	 */
	public function deactivate():Void {
		if(active) {
			Echoes._activeEntities.remove(cast this);
			statuses[this] = false;
			for(view in Echoes.activeViews) view.removeIfExists(cast this);
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
	
	public function getComponents():Map<String, Dynamic> {
		var components:Map<String, Dynamic> = new Map();
		for(storage in Echoes.componentStorage) {
			if(storage.exists(cast this)) {
				components[storage.name] = storage.get(cast this);
			}
		}
		return components;
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
	public function removeAll():Void {
		for(storage in Echoes.componentStorage) {
			storage.remove(cast this);
		}
	}
}

/**
 * A build macro for entity templates. An entity template fills a similar role
 * to a class, allowing a user to easily create entities with pre-defined sets
 * of components. But unlike classes, it's possible to apply multiple templates
 * to a single entity.
 * 
 * Templates also offer syntax sugar for accessing components. For example,
 * if the template declares `var component:Component`, the user can then type
 * `entity.component` instead of `entity.get(Component)`.
 * 
 * Sample usage:
 * 
 * ```haxe
 * //`Fighter` is a template for entities involved in combat. A `Fighter` entity
 * //will always have `Damage`, `Health`, and `Hitbox` components.
 * @:build(echoes.Entity.build())
 * abstract Fighter(Entity) {
 *     //Each variable represents the component of that type. For instance,
 *     //`fighter.damage` will get/set the entity's `Damage` component.
 *     public var damage:Damage = 1;
 *     public var health:Health = 10;
 *     public var hitbox:Hitbox = Hitbox.square(1);
 *     
 *     //Variables without initial values are considered optional.
 *     public var sprite:Sprite;
 *     
 *     //Variables may also be initialized in the constructor, as normal. A
 *     //default constructor will be created if you leave it out.
 *     public inline function new(?sprite:Sprite) {
 *         this = new Entity();
 *         
 *         //Due to how abstracts work, you can't set `this.sprite = sprite`.
 *         //Instead, either rename the parameter or use a workaround:
 *         this.add(sprite);
 *         set_sprite(sprite);
 *         var self:Fighter = cast this; self.sprite = sprite;
 *     }
 *     
 *     //Other functions work normally.
 *     public inline function getDamage(target:Hitbox):Damage {
 *         if(target.overlapping(hitbox)) {
 *             return damage;
 *         } else {
 *             return 0;
 *         }
 *     }
 * }
 * 
 * class Main {
 *     public static function main():Void {
 *         var knight:Fighter = new Fighter(SpriteCache.get("knight.png"));
 *         
 *         //The variables now act as shortcuts for `add()` and `get()`.
 *         trace(knight.health); //10
 *         trace(knight.get(Health)); //10
 *         
 *         //Because the variables all have type hints, you don't need to
 *         //specify which type you mean.
 *         knight.health = 9;
 *         knight.damage = 3;
 *         trace(knight.get(Health)); //9
 *         trace(knight.get(Damage)); //3
 *         
 *         //If using `add()`, the normal rules apply.
 *         knight.add((8:Health));
 *         trace(knight.health); //8
 *         
 *         //It's also possible to convert a pre-existing entity to `Fighter`.
 *         var greenEntity:Entity = new Entity();
 *         greenEntity.add(Color.GREEN);
 *         greenEntity.add((20:Health));
 *         
 *         //`Fighter.applyTemplateTo()` adds all required components that are
 *         //currently missing, and returns the same entity as a `Fighter`.
 *         var greenKnight:Fighter = Fighter.applyTemplateTo(greenEntity);
 *         
 *         //`Health` and `Color` remain the same as before.
 *         trace(greenKnight.health); //20
 *         trace("0x" + StringTools.hex(greenKnight.get(Color), 6)); //0x00FF00
 *         
 *         //`Damage` and `Hitbox` weren't already defined, and so will have
 *         //their default values.
 *         trace(greenKnight.damage); //1
 *         trace(greenKnight.hitbox); //"Square at (0, 0) with width 1"
 *         
 *         //Since `Fighter` doesn't define `sprite`'s default value,
 *         //`applyTemplateTo()` won't add a `Sprite` component.
 *         trace(greenKnight.sprite); //null
 *     }
 * }
 * ```
 */
macro function build():Array<Field> {
	return echoes.macro.EntityTemplateBuilder.build();
}
