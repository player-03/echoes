package echoes.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Type;

using echoes.macro.ComponentStorageBuilder;
using echoes.macro.MacroTools;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;

/**
 * Entity manipulation functions. Mostly equivalent to the macros found in
 * `Entity`, except these are designed to be called by macros. The biggest
 * difference is that these take `ComplexType` instead of `ExprOf<Class<Any>>`,
 * because that's more convenient for macros.
 */
class EntityTools {
	/**
	 * Adds one or more components to the entity, dispatching an `@:add` event
	 * for each one. If the entity already has a component of the same type, the
	 * old component will be replaced.
	 * 
	 * If a component is replaced and its type is tagged `@:echoes_replace`,
	 * this will dispatch a `@:remove` event before dispatching `@:add`.
	 */
	public static function add(self:Expr, components:Array<Expr>):ExprOf<echoes.Entity> {
		return macro {
			var entity:echoes.Entity = $self;
			
			$b{ [for(component in components) {
				var type:Type = component.parseComponentType();
				
				var operation:String = switch(type) {
					case TEnum(_.get().meta => m, _),
						TInst(_.get().meta => m, _),
						TType(_.get().meta => m, _),
						TAbstract(_.get().meta => m, _)
						if(m.has(":echoes_replace")):
						"replace";
					default:
						"add";
				};
				
				var storage:Expr = type.toComplexType().getComponentStorage();
				macro $storage.$operation(entity, $component);
			}] }
			
			entity;
		};
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
	 * @return The entity.
	 */
	public static function addIfMissing(self:Expr, components:Array<Expr>):ExprOf<echoes.Entity> {
		return macro {
			var entity:echoes.Entity = $self;
			
			$b{ [for(component in components) {
				var type:Type = component.parseComponentType();
				
				var storage:Expr = type.toComplexType().getComponentStorage();
				macro if(!$storage.exists(entity)) $storage.add(entity, $component);
			}] }
			
			entity;
		};
	}
	
	/**
	 * Removes one or more components from the entity.
	 * @param types The type(s) of the components to remove. _Not_ the
	 * components themselves!
	 * @return The entity.
	 */
	public static function remove(self:Expr, types:Array<ComplexType>):ExprOf<echoes.Entity> {
		return macro {
			var entity:echoes.Entity = $self;
			
			$b{ [for(type in types) {
				var storage:Expr = type.getComponentStorage();
				macro $storage.remove(entity);
			}] }
			
			entity;
		};
	}
	
	/**
	 * Gets this entity's component of the given type, if this entity has a
	 * component of the given type.
	 * @param type The type of the component to get.
	 * @return The component, or `null` if the entity doesn't have it.
	 */
	public static function get<T>(self:Expr, complexType:ComplexType):ExprOf<T> {
		var storage:Expr = complexType.getComponentStorage();
		return macro $storage.get($self);
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public static function exists(self:Expr, complexType:ComplexType):ExprOf<Bool> {
		var storage:Expr = complexType.getComponentStorage();
		return macro $storage.exists($self);
	}
}

#end
