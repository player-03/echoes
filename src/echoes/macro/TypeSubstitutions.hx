package echoes.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using echoes.Echoes;
using echoes.macro.MacroTools;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using haxe.macro.ExprTools;

/**
 * Helps replace references to type parameters during a generic build macro. For
 * instance, if a system is `GenericSystem<T>` and the user calls
 * `new GenericSystem<Int>()`, all references to `T` must be replaced.
 * 
 * ```diff
 * -@:add public function recordValue(value:T, ?array:Array<T>, entity:Entity):Void
 * +@:add public function recordValue(value:Int, ?array:Array<Int>, entity:Entity):Void
 * {
 *     if(array == null) {
 * -       array = new Array<T>();
 * +       array = new Array<Int>();
 *         entity.add(array);
 *     }
 *     
 *     array.push(value);
 * }
 * ```
 */
class TypeSubstitutions {
	private static final cache:Map<String, CachedImports> = new Map();
	
	/**
	 * Replaces any null entries in `args` with their defaults, modifying
	 * `args` in place. Throws an error if the default is missing too.
	 * @param args The type arguments specified by the user when creating an
	 * instance of `classType`.
	 */
	public static inline function applyDefaultTypeParams(classType:ClassType, args:Array<Type>):Void {
		final params:Array<TypeParameter> = classType.params;
		
		if(params.length != args.length) {
			Context.fatalError('${ classType.name } requires ${ params.length } '
				+ 'type parameters; got ${ args.length }', Context.currentPos());
		}
		
		for(i => arg in args) {
			if(arg.followMono() == null) {
				if(params[i] == null) {
					Context.fatalError('Parameter ${ params[i]?.name } '
						+ "has no default type; you must specify one here.", Context.currentPos());
				}
				
				args[i] = params[i].defaultType;
			}
		}
	}
	
	public static inline function getCachedImports(classType:ClassType):CachedImports {
		var qualifiedClassName:String = classType.pack.join(".") + "." + classType.name;
		return cache[qualifiedClassName];
	}
	
	/**
	 * The name of the class that defined the type parameters. Necessary in case
	 * the user types `ClassName.T` instead of just `T`.
	 */
	public final className:String;
	
	private final classType:ClassType;
	
	/**
	 * Maps type parameter names onto the user's specified types. For
	 * instance, if `T` is `Int` then this will be `["T" => macro:Int]`.
	 */
	private final substitutions:Map<String, ComplexType> = new Map();
	
	private final substitutionExprs:Map<String, ExprDef> = new Map();
	
	/**
	 * @param types Omit this to perform default substitutions instead, based on
	 * type constraints. Will be modified in place to apply default values.
	 */
	public inline function new(classType:ClassType, ?types:Array<Type>) {
		className = classType.name;
		this.classType = classType;
		
		final params:Array<TypeParameter> = classType.params;
		
		var codeCompletionMode:Bool = types == null;
		if(codeCompletionMode) {
			//Replace each param with its constraint type. If multiple
			//constraints are specified, pick one.
			types = [for(param in params)
				switch(param.t) {
					case TInst(_.get() => { kind: KTypeParameter(constraints) }, _) if(constraints.length > 0):
						pickEitherType(constraints[0]);
					default:
						Context.fatalError('Expected type constraint for $className.${ param.name }.', Context.currentPos());
				}
			];
		}
		
		applyDefaultTypeParams(classType, types);
		
		for(i => param in params) {
			var type:ComplexType = types[i].followMono().toComplexType();
			addSubstitution(param.name, type);
			
			//Check for `Entity` and `Float`.
			var error:String = type.getReservedComponentMessage();
			if(error != null && !codeCompletionMode) {
				Context.error('$className.${ param.name }: ' + error, Context.currentPos());
			}
		}
		
		//Local imports and usings become inaccessible during a generic build,
		//so save them for future reference.
		var qualifiedClassName:String = classType.pack.join(".") + "." + className;
		if(!cache.exists(qualifiedClassName) && Context.getLocalModule() == classType.module) {
			cache[qualifiedClassName] = {
				imports: Context.getLocalImports(),
				usings: [for(u in Context.getLocalUsing()) if(u != null) {
					var usingType:ClassType = u.get();
					var parts:Array<String> = usingType.module.split(".");
					if(parts[parts.length - 1] != usingType.name) {
						parts.push(usingType.name);
					}
					parts.makeTypePath();
				}]
			};
		}
		
		//Substitute imported types as well, or Haxe probably won't find them.
		if(cache.exists(qualifiedClassName)) {
			for(i in cache.get(qualifiedClassName).imports) {
				switch(i.mode) {
					case INormal:
						addSubstitution(i.path[i.path.length - 1].name,
							TPath([for(p in i.path) p.name].makeTypePath()));
					case IAsName(alias):
						addSubstitution(alias,
							TPath([for(p in i.path) p.name].makeTypePath()));
					case IAll:
				}
			}
			
			for(u in cache.get(qualifiedClassName).usings) {
				if(u.sub != null) {
					addSubstitution(u.sub, TPath(u));
				} else {
					addSubstitution(u.name, TPath(u));
				}
			}
		}
	}
	
	public inline function addSubstitution(identifier:String, type:ComplexType):Void {
		if(!substitutions.exists(identifier)) {
			substitutions[identifier] = type;
			
			var printedType:String = new Printer().printComplexType(type);
			if(printedType.indexOf("<") < 0) {
				substitutionExprs[identifier] = printedType.parse(Context.currentPos()).expr;
			}
		}
	}
	
	/**
	 * A drop-in replacement for `MacroTools.parseClassExpr()` that accounts for
	 * type substitutions.
	 */
	public inline function parseClassExpr(expr:Expr):ComplexType {
		return switch(expr.expr) {
			case EConst(CIdent(s)) if(substitutions.exists(s)):
				substitutions[s];
			case EField(_.expr => EConst(CIdent(s)), field)
				if(s == className && substitutions.exists(field)):
				substitutions[field];
			default:
				expr.parseClassExpr();
		};
	}
	
	/**
	 * If `type` is `haxe.ds.EitherType`, picks one of the choices. Otherwise
	 * returns `type`.
	 */
	private static function pickEitherType(type:Type):Type {
		return switch(type) {
			case TAbstract(_.get().name => "EitherType", [t1, _]):
				pickEitherType(t1);
			default:
				type;
		};
	}
	
	public function substituteExpr(expr:Null<Expr>):Null<Expr> {
		if(expr == null) {
			return null;
		}
		
		return {
			pos: expr.pos,
			expr: switch(expr.expr) {
				case EConst(CIdent(s)) if(substitutionExprs.exists(s)):
					substitutionExprs[s];
				case EField(_.expr => EConst(CIdent(s)), field)
					if(s == className && substitutionExprs.exists(field)):
					substitutionExprs[field];
				case ENew(t, params):
					ENew(substituteTypePath(t), params.map(substituteExpr));
				case EVars(vars):
					EVars([for(v in vars) {
						name: v.name,
						type: substituteType(v.type),
						expr: substituteExpr(v.expr),
						isFinal: v.isFinal,
						meta: v.meta
					}]);
				case EFunction(kind, f):
					EFunction(kind, substituteFunction(f));
				case ECast(e, t):
					ECast(substituteExpr(e), substituteType(t));
				case ECheckType(e, t):
					ECheckType(substituteExpr(e), substituteType(t));
				case EIs(e, t):
					EIs(substituteExpr(e), substituteType(t));
				default:
					expr.map(substituteExpr).expr;
			}
		};
	}
	
	public function substituteField(field:Field):Field {
		return {
			name: field.name,
			doc: field.doc,
			access: field.access,
			kind: switch(field.kind) {
				case FVar(t, e):
					FVar(substituteType(t), substituteExpr(e));
				case FFun(f):
					FFun(substituteFunction(f));
				case FProp(get, set, t, e):
					FProp(get, set, substituteType(t), substituteExpr(e));
			},
			pos: field.pos,
			meta: field.meta
		};
	}
	
	public inline function substituteFunction(f:Function):Function {
		return {
			args: [for(arg in f.args) {
				name: arg.name,
				opt: arg.opt,
				type: substituteType(arg.type),
				//It shouldn't be possible to use `T` here.
				value: arg.value,
				meta: arg.meta
			}],
			ret: substituteType(f.ret),
			expr: substituteExpr(f.expr),
			params: [for(param in f.params) {
				name: param.name,
				meta: param.meta,
				//Recursive params not supported for now.
				params: param.params,
				constraints: param.constraints.map(substituteType)
			}]
		};
	}
	
	public function substituteType(type:Null<ComplexType>):ComplexType {
		if(type == null) {
			return null;
		}
		
		return switch(type) {
			case TPath(p):
				var p:TypePath = substituteTypePath(p);
				if(p.isResolvable()) {
					TPath(p).toType().toComplexType();
				} else {
					TPath(p);
				}
			case TFunction(args, ret):
				TFunction(args.map(substituteType), substituteType(ret));
			case TAnonymous(fields):
				TAnonymous(fields.map(substituteField));
			case TParent(t):
				TParent(substituteType(t));
			case TExtend(p, fields):
				//No need to substitute `p`; Haxe doesn't allow extending
				//type parameters.
				TExtend(p, fields.map(substituteField));
			case TOptional(t):
				TOptional(substituteType(t));
			case TNamed(n, t):
				TNamed(n, substituteType(t));
			case TIntersection(tl):
				TIntersection(tl.map(substituteType));
		};
	}
	
	public inline function substituteTypeParams(params:Null<Array<TypeParam>>):Null<Array<TypeParam>> {
		if(params == null) {
			return null;
		} else {
			return [for(param in params) switch(param) {
				case TPType(t):
					TPType(substituteType(t));
				case TPExpr(e):
					TPExpr(substituteExpr(e));
			}];
		}
	}
	
	public function substituteTypePath(typePath:TypePath):TypePath {
		var substitute:Bool = switch(typePath) {
			case { pack: [], name: name, sub: null }:
				true;
			case { pack: [module], name: name, sub: null },
				{ pack: [], name: module, sub: name }
				if(module == className):
				true;
			default:
				false;
		};
		
		if(substitute) {
			switch(substitutions[typePath.name]) {
				case TPath(p):
					var params:Null<Array<TypeParam>> = p.params;
					if(typePath.params != null
						&& (params == null || typePath.params.length >= params.length)) {
						params = substituteTypeParams(typePath.params);
					}
					return {
						pack: p.pack,
						name: p.name,
						params: params,
						sub: p.sub
					};
				default:
			}
		}
		
		return {
			pack: typePath.pack,
			name: typePath.name,
			sub: typePath.sub,
			params: substituteTypeParams(typePath.params)
		};
	}
}

private typedef CachedImports = {
	imports: Array<ImportExpr>,
	usings: Array<TypePath>
};

#end
