package echoes.macro;

import haxe.macro.ComplexTypeTools;
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;
import haxe.macro.TypeTools;

using echoes.macro.ComponentStorageBuilder;
using echoes.macro.EntityTools;
using echoes.macro.MacroTools;
using haxe.EnumTools;
using haxe.macro.Context;
using haxe.macro.ExprTools;
using Lambda;

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
class AbstractEntity {
	public static function build():Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		
		//Information gathering
		//=====================
		
		//Get information about the `abstract` being built.
		var type:AbstractType = switch(Context.getLocalType()) {
			case TInst(_.get().kind => KAbstractImpl(_.get() => type), _):
				type;
			default:
				Context.fatalError("Entity.build() only works on abstract types.", Context.currentPos());
		};
		
		if(type.params != null && type.params.length > 0) {
			Context.fatalError('${ type.name } may not have any parameters.', Context.currentPos());
		}
		
		//Get information about parent types.
		var parents:Array<{ complexType:ComplexType, abstractType:AbstractType }> = [];
		var isEntity:Bool = false;
		var nextParent:Type = type.type;
		for(i in 0...100) {
			switch(nextParent) {
				case TInst(_.get().kind => KAbstractImpl(_.get() => parentAbstract), _),
					TAbstract(_.get() => parentAbstract, _):
					parents.push({
						complexType: nextParent.toComplexType(),
						abstractType: parentAbstract
					});
					
					if(parentAbstract.name == "Entity" && parentAbstract.pack.length == 1 && parentAbstract.pack[0] == "echoes") {
						isEntity = true;
						break;
					} else {
						nextParent = parentAbstract.type;
					}
				default:
					break;
			}
		}
		
		if(!isEntity) {
			Context.fatalError('${ type.name } must wrap echoes.Entity.', Context.currentPos());
		}
		
		//Modifications
		//=============
		
		//Forward all parent fields.
		if(!type.meta.has(":forward")) {
			type.meta.add(":forward", [], type.pos);
		}
		
		//Allow converting to all parent types.
		for(parent in parents) {
			var name:String = "to" + parent.abstractType.name;
			var complexType:ComplexType = parent.complexType;
			fields.pushFields(macro class ToParent {
				@:to private inline function $name():$complexType {
					return cast this;
				}
			});
		}
		
		//Process the variables.
		var requiredVariables:Array<{ name:String, expr:Expr }> = [];
		for(field in fields) {
			//Parse the field kind.
			var componentType:Null<ComplexType>;
			var expr:Null<Expr>;
			switch(field.kind) {
				//Skip static variables, but not static properties.
				case FVar(_, _) if(field.access != null && field.access.contains(AStatic)):
					continue;
				case FVar(t, e), FProp(_, _, t, e):
					componentType = t;
					expr = e;
				default:
					continue;
			}
			
			//Infer the component type, if not explicitly specified.
			if(componentType == null) {
				if(expr != null) {
					try {
						componentType = expr.parseComponentType().toComplexType();
					} catch(e:haxe.Exception) {
					}
				}
				
				if(componentType == null) {
					Context.fatalError('${ field.name } requires a type.', field.pos);
					continue;
				}
			}
			
			//Record the initial value.
			if(expr != null) {
				requiredVariables.push({
					name: switch(componentType) {
						case TPath({ name: name, sub: null }):
							name;
						case TPath({ sub: sub }):
							sub;
						default:
							new Printer().printComplexType(componentType);
					},
					expr: macro ($expr:$componentType)
				});
			}
			
			//Check for reserved types.
			switch(componentType) {
				case macro:Entity, macro:echoes.Entity:
					Context.fatalError("Entity is reserved. Consider using a typedef, abstract, or Int", field.pos);
				case macro:Float, macro:StdTypes.Float:
					Context.fatalError("Float is reserved for lengths of time. Consider using a typedef or abstract", field.pos);
				default:
			}
			
			//Convert the field to a property, and remove the expression.
			field.kind = FProp("get", "set", macro:Null<$componentType>, null);
			
			var getter:String = "get_" + field.name;
			var setter:String = "set_" + field.name;
			
			fields.pushFields(macro class Accessors {
				private inline function $getter():$componentType {
					return this.get((_:$componentType));
				}
				
				private inline function $setter(value:$componentType):$componentType {
					this.add(value);
					return value;
				}
			});
		}
		
		//Add the `applyTemplateTo()` function.
		var complexType:ComplexType = TPath({ pack: [], name: type.name });
		var applyParentTemplate:Expr = switch(type.type.toComplexType()) {
			case TPath({ pack: ["echoes"], name: "Entity" }):
				macro null;
			case TPath(p):
				var parts:Array<String> = p.pack.copy();
				parts.push(p.name);
				if(p.sub != null) {
					parts.push(p.sub);
				}
				macro $p{ parts }.applyTemplateTo(entity);
			default:
				macro null;
		};
		fields.pushFields(macro class Convert {
			public static function applyTemplateTo(entity:echoes.Entity):$complexType $b{
				requiredVariables.map(v -> macro entity.addIfMissing(${ v.expr }))
					.concat([applyParentTemplate, macro return cast entity])
			}
		});
		if(requiredVariables.length > 0) {
			var apply:Field = fields[fields.length - 1];
			apply.doc = 'Converts an entity to `${ type.name }` by '
				+ "adding any of the following that don't already exist: `"
				+ requiredVariables.map(v -> v.name).join("`, `")
				+ "`.";
		}
		
		//Add a default constructor, if needed.
		var constructor:Field = fields.find(field -> field.name == "new" || field.name == "_new");
		if(constructor == null) {
			var parentTypePath:TypePath = switch(type.type.toComplexType()) {
				case TPath(p):
					p;
				case x:
					//This shouldn't be possible after the `isEntity` test, but
					//it's easy enough 
					Context.error("Can't call new " + new Printer().printComplexType(x) + "().", Context.currentPos());
			};
			
			constructor = (macro class DefaultConstructor {
				public inline function new() {
					//Assume the parent type takes no arguments. If this fails,
					//you must write your own constructor.
					this = new $parentTypePath();
				}
			}).fields[0];
			
			fields.push(constructor);
		}
		
		//Make the constructor initialize all required variables.
		switch(constructor.kind) {
			case FFun(func):
				var block:Array<Expr>;
				switch(func.expr.expr) {
					case EBlock(exprs):
						block = exprs;
					default:
						block = [func.expr];
				};
				
				var index:Int = block.findIndex(expr -> expr.expr.match(EBinop(OpAssign, { expr: EConst(CIdent("this")) }, _)));
				if(index < 0) {
					//Assume the first expression contains `this = ...`.
					index = 0;
				}
				
				//Use `add()` rather than `addIfMissing()`. Any existing
				//components can only come from parents, and if there's a
				//conflict, the child's defaults should take precedence.
				block = block.slice(0, index + 1)
					.concat(requiredVariables.map(v -> macro this.add(${ v.expr })))
					.concat(block.slice(index + 1));
				
				func.expr.expr = EBlock(block);
			default:
		}
		
		return fields;
	}
}
