package echoes.core.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Type;

using echoes.core.macro.ComponentBuilder;
using echoes.core.macro.MacroTools;
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
	 * @param components Components of `Any` type.
	 * @return The entity.
	 */
	public static function add(self:Expr, components:Array<ExprOf<Any>>):ExprOf<echoes.Entity> {
		return macro {
			var entity:echoes.Entity = $self;
			
			$b{ [for(component in components) {
				var type:Type = switch(component.expr) {
					//Haxe (at least, some versions of it) will interpret
					//`new TypedefType()` as being the underlying type, but
					//Echoes wants to respect typedefs.
					case ENew(tp, _):
						TPath(tp).toType();
					//Haxe can overcomplicate type check expressions. There's no
					//need to parse the inner expression when the user already
					//told us what type to use.
					case ECheckType(_, t) | EParenthesis({ expr: ECheckType(_, t) }):
						t.toType();
					default:
						component.typeof();
				};
				
				var containerName:String = type.followMono().toComplexType().getComponentContainer().followName();
				macro @:privateAccess $i{ containerName }.inst().add(entity, $component);
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
				var containerName:String = type.getComponentContainer().followName();
				macro @:privateAccess $i{ containerName }.inst().remove(entity);
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
		var containerName:String = complexType.getComponentContainer().followName();
		
		return macro $i{ containerName }.inst().get($self);
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public static function exists(self:Expr, complexType:ComplexType):ExprOf<Bool> {
		var containerName:String = complexType.getComponentContainer().followName();
		
		return macro $i{ containerName }.inst().exists($self);
	}
}

#end
