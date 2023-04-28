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
 * @see `echoes.Entity.build()`
 */
class EntityTemplateBuilder {
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
		for(_ in 0...100) {
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
				private inline function $getter():Null<$componentType> {
					return this.get((_:$componentType));
				}
				
				private inline function $setter(value:Null<$componentType>):Null<$componentType> {
					this.add(value);
					return value;
				}
			});
		}
		
		//Add the `applyTemplateTo()` function. Note: this requires two
		//functions because the public API should be static but `v.expr` may
		//need access to `this`.
		var applyTemplateToSelf:Array<Expr> = requiredVariables.map(v -> macro this.addIfMissing(${ v.expr }));
		if(parents.length > 1) {
			applyTemplateToSelf.push(macro @:privateAccess this.applyTemplateToSelf());
		}
		var complexType:ComplexType = TPath({ pack: [], name: type.name });
		fields.pushFields(macro class Convert {
			@:noCompletion private function applyTemplateToSelf():Void $b{ applyTemplateToSelf }
			public static inline function applyTemplateTo(entity:echoes.Entity):$complexType {
				(cast entity:$complexType).applyTemplateToSelf();
				return cast entity;
			}
		});
		if(requiredVariables.length > 0 && fields[fields.length - 1].name == "applyTemplateTo") {
			var apply:Field = fields[fields.length - 1];
			apply.doc = 'Converts an entity to `${ type.name }` by '
				+ "adding any of the following that don't already exist: `"
				+ requiredVariables.map(v -> v.name).join("`, `")
				+ "`.";
			
			if(parents.length > 1) {
				apply.doc += "\n\nThe function also adds components specified by `";
				
				var parentNames:Array<String> = parents.map(parent -> parent.abstractType.name);
				//The final parent is always `Entity`, not a template.
				parentNames.pop();
				
				if(parentNames.length <= 2) {
					apply.doc += parentNames.join("` and `");
				} else {
					var finalName:String = parentNames.pop();
					apply.doc += parentNames.join("`, `");
					apply.doc += "`, and `" + finalName;
				}
				
				apply.doc += "`.";
			}
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
