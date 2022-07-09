package echoes.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;

using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;

@:dce
class MacroTools {
	/**
	 * Acts like `Context.follow()`, but doesn't follow abstracts and typedefs
	 * unless they're marked `@:eager`. Normally, it only follows monomorphs
	 * and `Null<T>` types.
	 */
	public static function followMono(type:Type):Type {
		return switch(type) {
			case TMono(_.get() => innerType):
				followMono(innerType);
			case TAbstract(_.get() => { name:"Null" }, [innerType]):
				followMono(innerType);
			case TAbstract(_.get() => { type: innerType, meta: meta }, _)
				| TType(_.get() => { type: innerType, meta: meta }, _)
				if(meta.has(":eager")):
				followMono(innerType);
			default:
				type;
		};
	}
	
	/**
	 * Adds package information and finds the type underlying an `Unknown<0>`
	 * and/or `Null<T>`, making it easier to examine the type.
	 */
	public static function followComplexType(type:ComplexType):ComplexType {
		return followMono(type.toType()).toComplexType();
	}
	
	public static function followName(type:ComplexType):String {
		return new Printer().printComplexType(followComplexType(type));
	}
	
	public static function parseClassExpr(e:Expr):ComplexType {
		switch(e.expr) {
			case EParenthesis({ expr:ECheckType(_, type) }):
				return followComplexType(type);
			case EConst(CIdent(typeString)):
				try {
					return followMono(typeString.getType()).toComplexType();
				} catch(err:String) {}
			default:
		}
		
		Context.error('Failed to parse `${ new Printer().printExpr(e) }`. Try making a typedef or using the special type check syntax: `entity.get((_:MyType))` instead of `entity.get(MyType)`.', Context.currentPos());
		return macro:Dynamic;
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
	
	public static function compareStrings(a:String, b:String):Int {
		a = a.toLowerCase();
		b = b.toLowerCase();
		return (a < b) ? -1 : (a > b) ? 1 : 0;
	}
	
	public static function joinNames(types:Array<ComplexType>, sep:String, ?qualify:Bool = true):String {
		var typeNames:Array<String> = [for(type in types) toIdentifier(type, qualify)];
		typeNames.sort(compareStrings);
		return typeNames.join(sep);
	}
}

#end
