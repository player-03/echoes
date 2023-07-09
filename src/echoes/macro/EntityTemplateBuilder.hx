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
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using haxe.macro.ExprTools;
using Lambda;

/**
 * @see `echoes.Entity.build()`
 */
class EntityTemplateBuilder {
	static inline final ARGUMENTS_TAG:String = ":arguments";
	static inline final OPTIONAL_ARGUMENTS_TAG:String = ":optionalArguments";

	@:allow(echoes)
	private static function build():Array<Field> {
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
						break;
					} else {
						nextParent = parentAbstract.type;
					}
				default:
					return Context.fatalError('${ type.name } must wrap echoes.Entity.', Context.currentPos());
			}
		}
		
		//Check for important fields.
		var onTemplateApplied:Null<Field> = null;
		for(field in fields) {
			switch(field.name) {
				case "new", "_new":
					return Context.fatalError("The constructor must be generated by macro. Instead, declare an onTemplateApplied() function.", field.pos);
				case "applyTemplateTo", "applyTemplateToSelf":
					return Context.fatalError('${ field.name } is reserved. Instead, declare an onTemplateApplied() function.', field.pos);
				case "onTemplateApplied" if(field.kind.match(FFun(_.args => []))):
					onTemplateApplied = field;
				default:
			}
		}
		
		//Constructor arguments
		//---------------------
		
		/**
		 * An ordered list of parameters taken by the constructor and the
		 * "apply" functions.
		 * 
		 * Contains a temporary `storage` value, which is the identifier for the
		 * `ComponentStorage` for this type.
		 */
		var parameters:Array<FunctionArg & { storage:String }> = [];
		
		/**
		 * Arguments to pass to `applyTemplateToSelf()`.
		 */
		var arguments:Array<Expr> = [];
		
		/**
		 * Arguments to pass to the super type's `applyTemplateToSelf()`.
		 */
		var superArguments:Array<Expr> = [];
		
		/**
		 * The types marked as optional that don't yet have a default value.
		 */
		var optionalValuesRemaining:Map<String, ComplexType> = [];
		
		/**
		 * Adds the given value to `parameters` and `arguments` unless it's
		 * redundant. Also adds it to `superArguments` if the flag is set.
		 */
		inline function addParams(params:Array<Expr>, inherited:Bool, optional:Bool):Void {
			for(param in params) {
				var name:String = null;
				var type:ComplexType = null;
				switch(param.expr) {
					case EParenthesis({ expr:ECheckType(_.expr => EConst(CIdent(n)), t) }):
						name = n;
						type = t.followComplexType();
					default:
						var fieldChain:Null<String> = param.printFieldChain();
						if(fieldChain != null) {
							try {
								type = fieldChain.getType().followMono().toComplexType();
								
								name = fieldChain.split(".").pop();
								name = name.charAt(0).toLowerCase() + name.substr(1);
							} catch(err:haxe.Exception) { }
						}
						
						if(name == null) {
							Context.fatalError("Expected component type or type check.", param.pos);
						}
				}
				
				var storage:String = type.getComponentStorageName();
				var existingName:String = null;
				for(existing in parameters) {
					if(existing.storage == storage) {
						existingName = existing.name;
						break;
					}
				}
				
				if(existingName == null) {
					existingName = name;
					parameters.push({ name: name, type: type, storage: storage, opt: optional });
					
					arguments.push(macro $i{ existingName });
					
					if(optional) {
						optionalValuesRemaining[storage] = type;
					}
				}
				
				if(inherited) {
					superArguments.push(macro $i{ existingName });
				}
			}
		}
		
		//Add parameters from this type.
		for(entry in type.meta.extract(ARGUMENTS_TAG)) {
			addParams(entry.params, false, false);
		}
		for(entry in type.meta.extract(OPTIONAL_ARGUMENTS_TAG)) {
			addParams(entry.params, false, true);
		}
		
		//Add inherited parameters.
		for(parent in parents) {
			for(entry in parent.abstractType.meta.extract(ARGUMENTS_TAG)) {
				addParams(entry.params, true, false);
			}
			
			//Currently, don't inherit optional parameters.
			/* for(entry in parent.abstractType.meta.extract(ARGUMENTS_TAG)) {
				addParams(entry.params, true, false);
			} */
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
		
		//Process the component variables.
		var knownComponents:Array<FunctionArg> = [];
		for(field in fields) {
			if(field.access != null && field.access.contains(AStatic)) {
				continue;
			}
			
			//Parse the field.
			var componentType:Null<ComplexType>;
			var expr:Null<Expr>;
			switch(field.kind) {
				case FVar(t, e):
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
			} else {
				//Fully qualify the type to avoid "not found" errors.
				componentType = componentType.toType().toComplexType();
			}
			
			//Record the initial/default value.
			if(expr != null) {
				knownComponents.push({
					name: switch(componentType) {
						case TPath({ name: name, sub: null }):
							name;
						case TPath({ sub: sub }):
							sub;
						default:
							new Printer().printComplexType(componentType);
					},
					type: componentType,
					value: macro @:pos(expr.pos) ($expr:$componentType)
				});
				
				//Check for incompatabilities with the metadata. (We could also
				//update the metadata to make it match, but since macro order is
				//unspecified, a child type may have already been built using
				//the wrong metadata.)
				var storage:String = componentType.getComponentStorageName();
				var parameter:FunctionArg = parameters.find(p -> p.storage == storage);
				if(parameter != null) {
					if(parameter.opt) {
						optionalValuesRemaining.remove(storage);
					} else {
						Context.fatalError('Components listed in `$ARGUMENTS_TAG` can\'t have default values. '
							+ 'Consider adding this to `$OPTIONAL_ARGUMENTS_TAG` instead.', field.pos);
					}
				}
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
		
		if(!optionalValuesRemaining.empty()) {
			var missing:Array<String> = [for(type in optionalValuesRemaining)
				new Printer().printComplexType(type)];
			var s:String = missing.length == 1 ? "" : "s";
			
			Context.fatalError('Missing default value$s for the following component type$s: '
				+ missing.join(", "), Context.currentPos());
		}
		
		//"Apply" functions
		//-----------------
		
		/**
		 * An ordered list of parameters taken by the constructor and the
		 * "apply" functions. This version no longer exposes `storage`.
		 */
		var parameters:Array<FunctionArg> = [for(p in parameters) p];
		
		/**
		 * Adds `parameters` to each function in the given type definition, then
		 * inserts those functions at the beginning of `fields`, in order.
		 */
		inline function addFunctions(definition:TypeDefinition):Void {
			for(field in definition.fields) {
				switch(field.kind) {
					case FFun(f):
						f.args = f.args.concat(parameters);
					default:
						Context.fatalError("Not a function.", field.pos);
				}
			}
			
			//Insert the new fields first, so that if there's a name conflict,
			//Haxe will flag the user's version.
			fields = definition.fields.concat(fields);
		}
		
		//Add the constructor and `applyTemplateTo()`.
		var templateType:ComplexType = TPath({ pack: [], name: type.name });
		addFunctions(macro class Constructor {
			public static inline function applyTemplateTo(entity:echoes.Entity):$templateType {
				(cast entity:$templateType).applyTemplateToSelf($a{ arguments });
				return cast entity;
			}
			
			public inline function new() {
				this = cast new echoes.Entity();
				applyTemplateToSelf($a{ arguments });
			}
		});
		fields[0].doc = 'Converts the given entity to `${ type.name }` by '
			+ "adding any missing components.";
		
		//Prepare the `applyTemplateToSelf()` function. Set the components in
		//order of priority: values passed by the user, then known values, then
		//inherited values.
		var applyToSelfExprs:Array<Expr> = [];
		for(parameter in parameters) {
			applyToSelfExprs.push(macro this.addIfMissing($i{ parameter.name }));
		}
		for(component in knownComponents) {
			applyToSelfExprs.push(macro this.addIfMissing(${ component.value }));
		}
		if(parents.length > 1) {
			applyToSelfExprs.push(macro @:privateAccess this.applyTemplateToSelf($a{ superArguments }));
		}
		if(onTemplateApplied != null) {
			applyToSelfExprs.push(macro $i{ onTemplateApplied.name }());
		}
		
		//Add `applyTemplateToSelf()`; it must not be static because
		//`knownComponents` may refer to instance properties or functions.
		addFunctions((macro class ApplyToSelf {
			@:noCompletion private function applyTemplateToSelf():Void $b{ applyToSelfExprs }
		}));
		
		return fields;
	}
}
