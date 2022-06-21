package echoes.core.macro;

#if macro
import haxe.macro.Expr;
using echoes.core.macro.ComponentBuilder;
using echoes.core.macro.ViewsOfComponentBuilder;
using echoes.core.macro.MacroTools;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using Lambda;

/**
 * Entity manipulation functions. Mostly equivalent to the macros found in
 * `Entity`, except these are designed to be called by macros. The biggest
 * difference is that these take `ComplexType` instead of `ExprOf<Class<Any>>`,
 * because this way is more convenient for macros.
 */
class EntityTools {
	/**
	 * Adds one or more components to the entity. If the entity already has a
	 * component of the same type, the old component will be replaced.
	 * @param components Components of `Any` type.
	 * @return The entity.
	 */
	public static function add(self:Expr, components:Array<ExprOf<Any>>):ExprOf<echoes.Entity> {
		if(components.length == 0) {
			Context.error("Nothing to add; required one or more components", Context.currentPos());
		}
		
		var types = components
			.map(function(c) {
				var t = switch(c.expr) {
					case ENew(tp, _):
						TPath(tp).toType();
					case EParenthesis({ expr: ECheckType(_, t) }):
						t.toType();
					default:
						c.typeof();
				}
				
				return t.followMono().toComplexType();
			});
			
		var addComponentsToContainersExprs = [for(i in 0...components.length) {
				var c = components[i];
				var containerName = types[i].getComponentContainer().followName();
				macro @:privateAccess $i{ containerName }.inst().add(__entity__, $c);
			}];
			
		var addEntityToRelatedViewsExprs = types
			.map(function(ct) {
				return ct.getViewsOfComponent().followName();
			})
			.map(function(viewsOfComponentClassName) {
				return macro @:privateAccess $i{ viewsOfComponentClassName }.inst().addIfMatched(__entity__);
			});
			
		return macro #if(haxe_ver >= 4) inline #end
			( function(__entity__:echoes.Entity) {
				$b{addComponentsToContainersExprs}
				
				if(__entity__.isActive()) $b{ addEntityToRelatedViewsExprs }
				
				return __entity__;
			} )($self);
	}
	
	/**
	 * Removes one or more components from the entity.
	 * @param types The type(s) of the components to remove. _Not_ the
	 * components themselves!
	 * @return The entity.
	 */
	public static function remove(self:Expr, types:Array<ComplexType>):ExprOf<echoes.Entity> {
		if(types.length == 0) {
			Context.error("Nothing to remove; required one or more component types", Context.currentPos());
		}
		
		var removeComponentsFromContainersExprs = types
			.map(function(ct) {
				return ct.getComponentContainer().followName();
			})
			.map(function(componentContainerClassName) {
				return macro @:privateAccess $i{ componentContainerClassName }.inst().remove(__entity__);
			});
			
		var removeEntityFromRelatedViewsExprs = types
			.map(function(ct) {
				return ct.getViewsOfComponent().followName();
			})
			.map(function(viewsOfComponentClassName) {
				return macro @:privateAccess $i{ viewsOfComponentClassName }.inst().removeIfExists(__entity__);
			});
			
		return macro #if(haxe_ver >= 4) inline #end 
			( function(__entity__:echoes.Entity) {
				if(__entity__.isActive()) $b{ removeEntityFromRelatedViewsExprs }
				
				$b{ removeComponentsFromContainersExprs }
				
				return __entity__;
			} )($self);
	}
	
	/**
	 * Gets this entity's component of the given type, if this entity has a
	 * component of the given type.
	 * @param type The type of the component to get.
	 * @return The component, or `null` if the entity doesn't have it.
	 */
	public static function get<T>(self:Expr, complexType:ComplexType):ExprOf<T> {
		var containerName = complexType.getComponentContainer().followName();
		
		var ret = macro $i{ containerName }.inst().get($self);
		
		return ret;
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public static function exists(self:Expr, complexType:ComplexType):ExprOf<Bool> {
		var containerName = complexType.getComponentContainer().followName();
		
		var ret = macro $i{ containerName }.inst().exists($self);
		
		return ret;
	}
}
#end
