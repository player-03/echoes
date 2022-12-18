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
	 * Adds one or more components to the entity. If the entity already has a
	 * component of the same type, the old component will be replaced.
	 * 
	 * When a component is replaced this way, no events will be dispatched
	 * unless the component type is tagged `@:echoes_replace`, in which case
	 * both events (`@:remove` and `@:add`) will be dispatched.
	 * @param components Components of `Any` type.
	 * @return The entity.
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
				
				var containerName:String = type.toComplexType().getComponentStorage().followName();
				macro @:privateAccess $i{ containerName }.instance.$operation(entity, $component);
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
				
				var containerName:String = type.toComplexType().getComponentStorage().followName();
				macro if(!$i{ containerName }.instance.exists(entity)) @:privateAccess $i{ containerName }.instance.add(entity, $component);
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
				var containerName:String = type.getComponentStorage().followName();
				macro @:privateAccess $i{ containerName }.instance.remove(entity);
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
		var containerName:String = complexType.getComponentStorage().followName();
		
		return macro $i{ containerName }.instance.get($self);
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public static function exists(self:Expr, complexType:ComplexType):ExprOf<Bool> {
		var containerName:String = complexType.getComponentStorage().followName();
		
		return macro $i{ containerName }.instance.exists($self);
	}
}

#end
