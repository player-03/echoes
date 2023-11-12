package echoes.macro;

#if macro

import haxe.Exception;
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using Lambda;

@:dce
class MacroTools {
	public static function compareStrings(a:String, b:String):Int {
		a = a.toLowerCase();
		b = b.toLowerCase();
		return (a < b) ? -1 : (a > b) ? 1 : 0;
	}
	
	/**
	 * Adds package information and finds the type underlying an `Unknown<0>`
	 * and/or `Null<T>`, making it easier to examine the type.
	 */
	public static function followComplexType(type:ComplexType):ComplexType {
		return followMono(type.toType()).toComplexType();
	}
	
	/**
	 * Acts like `Context.follow()`, but doesn't follow abstracts and typedefs
	 * unless they're marked `@:eager`. Normally, it only follows monomorphs
	 * and `Null<T>` types.
	 */
	public static function followMono(type:Type):Type {
		return switch(type) {
			case null:
				null;
			case TMono(_.get() => innerType):
				followMono(innerType);
			case TAbstract(_.get() => { name: "Null" }, [innerType]):
				followMono(innerType);
			case TAbstract(_.get() => { type: innerType, meta: meta }, _)
				| TType(_.get() => { type: innerType, meta: meta }, _)
				if(meta.has(":eager")):
				followMono(innerType);
			default:
				type;
		};
	}
	
	public static function followName(type:ComplexType):String {
		return new Printer().printComplexType(followComplexType(type));
	}
	
	/**
	 * If `field` is a function, returns its body as an array, making it easy to
	 * add new expressions. Otherwise, returns null.
	 */
	public static inline function getFunctionBody(field:Field):Null<Array<Expr>> {
		switch(field.kind) {
			case FFun(func):
				switch(func.expr) {
					case null:
						var block:Array<Expr> = [];
						func.expr = macro @:pos(field.pos) $b{ block };
						return block;
					case _.expr => EBlock(exprs):
						return exprs;
					case expr:
						var block:Array<Expr> = [expr];
						func.expr.expr = EBlock(block);
						return block;
				}
			default:
				return null;
		}
	}
	
	/**
	 * @param type A type for which you've already called `followMono()`.
	 * @return An error message if `type` is reserved, or null otherwise.
	 */
	public static function getReservedComponentMessage(type:ComplexType):Null<String> {
		return switch(type) {
			case TPath({ pack: [] | ["echoes"], name: "Entity"}):
				"Entity is not an allowed component type. Try using a typedef, an abstract, or Int instead.";
			case TPath({ pack: [], name: "Float" } | { name: "StdTypes", sub: "Float" }):
				"Float is not an allowed component type. Try using a typedef or an abstract instead.";
			default:
				null;
		};
	}
	
	public static inline function isResolvable(p:TypePath):Bool {
		return try {
			TPath(p).toType();
			true;
		} catch(e:Exception) {
			false;
		};
	}
	
	public static function joinNames(types:Array<ComplexType>, sep:String, ?qualify:Bool = true):String {
		var typeNames:Array<String> = [for(type in types) toIdentifier(type, qualify)];
		typeNames.sort(compareStrings);
		return typeNames.join(sep);
	}
	
	public static function makeTypePath(parts:Array<String>):TypePath {
		var typePath:TypePath = {
			pack: parts,
			name: parts.pop()
		};
		if(parts.length > 0 && ~/^[A-Z]/.match(parts[parts.length - 1])) {
			typePath.sub = typePath.name;
			typePath.name = parts.pop();
		}
		return typePath;
	}
	
	/**
	 * Given an expression representing a class (the sort of expression passed
	 * to `entity.get()`), determines the component type.
	 * @param acceptInstance Whether to accept an instance of the type instead
	 * of the identifier. For instance, with this enabled, the user could pass
	 * `true` or `false` instead of `Bool`.
	 */
	public static function parseClassExpr(e:Expr, ?acceptInstance:Bool = false):ComplexType {
		switch(e.expr) {
			case EParenthesis({ expr:ECheckType(_, type) }):
				return followComplexType(type);
			default:
		}
		
		var fieldChain:Null<String> = printFieldChain(e);
		if(fieldChain != null) {
			try {
				return followMono(fieldChain.getType()).toComplexType();
			} catch(err:Exception) { }
		}
		
		if(acceptInstance) {
			try {
				return followMono(e.typeof()).toComplexType();
			} catch(err:Exception) { }
		}
		
		var expr:String = new Printer().printExpr(e);
		if(~/^[\w\d\.]+$/.match(expr)) {
			Context.error('Type not found: `$expr`.', e.pos);
		} else {
			Context.error('Failed to parse type `$expr`. Try using the special type check syntax, e.g. `entity.get((_:$expr))` instead of `entity.get($expr)`.', e.pos);
		}
		
		return macro:Dynamic;
	}
	
	/**
	 * Given an expression representing a component instance (the sort of
	 * expression passed to `entity.add()`), determines the component type.
	 */
	public static function parseComponentType(e:Expr):Type {
		return followMono(switch(e.expr) {
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
				e.typeof();
		});
	}
	
	/**
	 * Converts a nested `EField` expression to string. If the given expression
	 * is anything other than a chain of identifiers, returns null.
	 * 
	 * ```haxe
	 * printFieldChain(macro foo); //"foo"
	 * printFieldChain(macro foo.bar); //"foo.bar"
	 * printFieldChain(macro foo().bar); //null
	 * printFieldChain(macro foo.bar[1]); //null
	 * ```
	 */
	public static function printFieldChain(fieldExpr:Expr):Null<String> {
		switch(fieldExpr.expr) {
			case EField(e, field):
				var sub:Null<String> = printFieldChain(e);
				return sub != null ? '$sub.$field' : null;
			case EConst(CIdent(s)):
				return s;
			default:
				return null;
		}
	}
	
	/**
	 * Copies fields from `source` to `destination`, skipping any that are
	 * already present.
	 */
	public static function pushFields(destination:Array<Field>, source:TypeDefinition):Void {
		for(field in source.fields) {
			if(!destination.exists(f -> f.name == field.name)
				//Special case: `new` is sometimes renamed `_new`; check both.
				&& (field.name != "new" || !destination.exists(f -> f.name == "_new"))) {
				destination.push(field);
			}
		}
	}
	
	/**
	 * Converts `type` to a valid Haxe identifier.
	 * @param qualify Whether to include package and module information. Setting
	 * this to false makes the output more readable but less unique.
	 */
	public static function toIdentifier(type:ComplexType, ?qualify = true):String {
		switch(followComplexType(type)) {
			case TFunction(args, ret):
				return "F"
					+ [for(arg in args) toIdentifier(arg, qualify)].join("_")
					+ "_R"
					+ toIdentifier(ret, qualify);
			case TParent(t):
				return "P" + toIdentifier(t, qualify);
			case TPath(t):
				var name:String;
				if(qualify) {
					name = t.pack.join("") + (t.name + (t.sub != null ? t.sub : ""));
				} else {
					name = t.sub != null ? t.sub : t.name;
				}
				
				if(t.params != null && t.params.length > 0) {
					name += "Of"
						+ [for(param in t.params)
							switch(param) {
								case TPType(type):
									toIdentifier(type, qualify);
								case x:
									Context.error('Unexpected $x!', Context.currentPos());
									null;
							}
						].join("_");
				}
				
				return name;
			case x:
				Context.error('Unexpected $x!', Context.currentPos());
				return null;
		}
	}
}

#end
