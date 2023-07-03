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
	/**
	 * The name of the class that defined the type parameters. Necessary in case
	 * the user types `ClassName.T` instead of just `T`.
	 */
	public final className:String;
	
	/**
	 * Maps type parameter names onto the user's specified types. For
	 * instance, if `T` is `Int` then this will be `["T" => macro:Int]`.
	 */
	private final substitutions:Map<String, ComplexType> = new Map();
	
	private final substitutionExprs:Map<String, Expr> = new Map();
	
	public inline function new(className:String, params:Array<TypeParameter>, ?types:Array<Type>) {
		this.className = className;
		
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
		
		if(params.length != types.length) {
			Context.fatalError('$className requires ${ params.length } '
				+ 'type parameters; got ${ types.length }', Context.currentPos());
		}
		
		for(i => param in params) {
			var type:ComplexType = types[i].followMono().toComplexType();
			substitutions[param.name] = type;
			substitutionExprs[param.name] = new Printer().printComplexType(type).parse(Context.currentPos());
			
			//Check for `Entity` and `Float`.
			var error:String = type.getReservedComponentMessage();
			if(error != null && !codeCompletionMode) {
				Context.error('$className.${ param.name }: ' + error, Context.currentPos());
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
					substitutionExprs[s].expr;
				case EField(_.expr => EConst(CIdent(s)), field)
					if(s == className && substitutionExprs.exists(field)):
					substitutionExprs[field].expr;
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
				case EDisplayNew(t):
					EDisplayNew(substituteTypePath(t));
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
				TPath(substituteTypePath(p)).toType().toComplexType();
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
	
	public function substituteTypePath(typePath:TypePath):TypePath {
		if(substitutions.exists(typePath.name)) {
			switch(typePath) {
				case { pack: null | [], name: name, sub: null }:
					switch(substitutions[typePath.name]) {
						case TPath(p):
							return p;
						default:
					}
				case { pack: [packEntry], name: name, sub: null }
					if(packEntry == className):
					switch(substitutions[typePath.name]) {
						case TPath(p):
							return p;
						default:
					}
				default:
			}
		}
		
		return {
			pack: typePath.pack,
			name: typePath.name,
			sub: typePath.sub,
			params: [for(param in typePath.params) switch(param) {
				case TPType(t):
					TPType(substituteType(t));
				case TPExpr(e):
					TPExpr(substituteExpr(e));
			}]
		};
	}
}

#end
