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
 * Enables a way to treat entities more like class instances. Simply create an
 * `abstract` wrapping `Entity`, and define one or more properties:
 * 
 * ```haxe
 * typedef Color = Int;
 * @:build(echoes.macro.AbstractEntity.build())
 * abstract ColorfulEntity(Entity) {
 *     public var color:Color;
 * }
 * ```
 * 
 * Instead of acting like normal variables, these will get and set the entity's
 * components. They function the same as `add()`, `get()`, and `remove()` which
 * are also still available.
 * 
 * ```haxe
 * var redBall = new ColorfulEntity();
 * redBall.add((0x990000:Color));
 * trace(StringTools.hex(redBall.color)); //990000
 * redBall.color = 0xFF0000;
 * trace(StringTools.hex(redBall.get(Color))); //FF0000
 * redBall.color = null;
 * trace(redBall.exists(Color)); //false
 * ```
 * 
 * You can add functions to your `abstract` as normal:
 * 
 * ```haxe
 * typedef Color = Int;
 * @:build(echoes.macro.AbstractEntity.build())
 * abstract ColorfulEntity(Entity) {
 *     public var color:Color;
 *     
 *     public inline function getRed():Int {
 *         return color >> 16;
 *     }
 *     public inline function getGreen():Int {
 *         return (color >> 8) & 0xFF;
 *     }
 *     public inline function getBlue():Int {
 *         return color & 0xFF;
 *     }
 *     public function setRGB(r:Int, g:Int, b:Int):Void {
 *         color = (r << 16) | (g << 8) | b;
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
		
		//Get information about parent types, and allow converting to each.
		var parentType:Type = type.type;
		var parentMakeExpr:Null<Expr> = null;
		var isEntity:Bool = false;
		for(i in 0...100) {
			switch(parentType) {
				case TInst(_.get().kind => KAbstractImpl(_.get() => parentAbstract), _),
					TAbstract(_.get() => parentAbstract, _):
					var name:String = "to" + parentAbstract.name;
					var complexType:ComplexType = parentType.toComplexType();
					fields.pushFields(macro class ToParent {
						@:to private inline function $name():$complexType {
							return cast this;
						}
					});
					
					if(parentAbstract.name == "Entity" && parentAbstract.pack.length == 1 && parentAbstract.pack[0] == "echoes") {
						isEntity = true;
						break;
					} else {
						parentType = parentAbstract.type;
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
		
		//Process the variables.
		var initializeVariables:Array<{ name:String, expr:Expr }> = [];
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
				initializeVariables.push({
					name: switch(componentType) {
						case TPath({ name: name, sub: null }):
							name;
						case TPath({ sub: sub }):
							sub;
						default:
							new Printer().printComplexType(componentType);
					},
					expr: macro entity.addIfMissing(($expr:$componentType))
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
			field.kind = FProp("get", "set", componentType, null);
			
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
		
		//Add the `convert()` function.
		var complexType:ComplexType = TPath({ pack: [], name: type.name });
		fields.pushFields(macro class Convert {
			public static function convert(entity:echoes.Entity):$complexType $b{
				initializeVariables.map(v -> v.expr)
					.concat([macro return cast entity])
			}
		});
		if(initializeVariables.length > 0) {
			fields[fields.length - 1].doc = 'Converts an entity to `${ type.name }` by '
				+ "adding any of the following that don't already exist: `"
				+ initializeVariables.map(v -> v.name).join("`, `")
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
					//Assume the parent type takes no arguments. If it does, the
					//user will have to define their own constructor.
					this = new $parentTypePath();
				}
			}).fields[0];
			
			fields.push(constructor);
		}
		
		//Make sure the constructor calls `convert()`.
		switch(constructor.kind) {
			case FFun(func):
				var block:Array<Expr> = switch(func.expr.expr) {
					case EBlock(exprs):
						exprs;
					default:
						[func.expr];
				};
				
				for(i => expr in block) {
					if(expr.expr.match(EBinop(OpAssign, { expr: EConst(CIdent("this")) }, _))) {
						block.insert(i + 1, macro convert(this));
						break;
					}
				}
			default:
		}
		
		return fields;
	}
}
