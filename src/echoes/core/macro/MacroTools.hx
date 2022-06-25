package echoes.core.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Expr.Access;
import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr.Field;
import haxe.macro.Expr.FunctionArg;
import haxe.macro.Expr.TypePath;
import haxe.macro.Expr.Position;
import haxe.macro.Printer;
import haxe.macro.Type;

using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using Lambda;

@:dce
class MacroTools {
	public static function ffun(?meta:Metadata, ?access:Array<Access>, name:String, ?args:Array<FunctionArg>, ?ret:ComplexType, ?body:Expr, pos:Position):Field {
		return {
			meta: meta != null ? meta : [],
			name: name,
			access: access != null ? access : [],
			kind: FFun({
				args: args != null ? args : [],
				expr: body != null ? body : macro { },
				ret: ret
			}),
			pos: pos
		};
	}
	
	public static function fvar(?meta:Metadata, ?access:Array<Access>, name:String, ?type:ComplexType, ?expr:Expr, pos:Position):Field {
		return {
			meta: meta != null ? meta : [],
			name: name,
			access: access != null ? access : [],
			kind: FVar(type, expr),
			pos: pos
		};
	}
	
	public static function arg(name:String, type:ComplexType):FunctionArg {
		return {
			name: name,
			type: type
		};
	}
	
	public static function meta(name:String, ?params:Array<Expr>, pos:Position):MetadataEntry {
		return {
			name: name,
			params: params != null ? params : [],
			pos: pos
		}
	}
	
	public static function tpath(?pack:Array<String>, name:String, ?params:Array<TypeParam>, ?sub:String):TypePath {
		return {
			pack: pack != null ? pack : [],
			name: name,
			params: params != null ? params : [],
			sub: sub
		}
	}
	
	public static function followMono(t:Type) {
		return switch(t) {
			case TMono(_.get() => tt):
				followMono(tt);
			case TAbstract(_.get() => {name:"Null"}, [tt]):
				followMono(tt);
			default:
				t;
		}
	}
	
	public static function followComplexType(ct:ComplexType) {
		return followMono(ct.toType()).toComplexType();
	}
	
	public static function followName(ct:ComplexType):String {
		return new Printer().printComplexType(followComplexType(ct));
	}
	
	public static function parseComplexType(e:Expr):ComplexType {
		switch(e.expr) {
			case EParenthesis({expr:ECheckType(_, ct)}):
				return followComplexType(ct);
			default:
		}
		
		var type = new Printer().printExpr(e);
		
		try {
			return followMono(type.getType()).toComplexType();
		} catch(err:String) {
			throw 'Failed to parse `$type`. Try making a typedef, or use the special type check syntax: `entity.get((_:MyType))` instead of `entity.get(MyType)`.';
		}
	}
	
	private static function error(msg:String, pos:Position) {
		Context.error(msg, pos);
	}
	
	private static function capitalize(s:String) {
		return s.substr(0, 1).toUpperCase() + (s.length > 1 ? s.substr(1).toLowerCase() : "");
	}
	
	private static function typeParamName(p:TypeParam, f:ComplexType->String):String {
		switch(p) {
			case TPType(ct):
				return f(ct);
			case x:
				error('Unexpected $x!', Context.currentPos());
				return null;
		}
	}
	
	public static function typeValidShortName(ct:ComplexType):String {
		return typeName(ct, true, false);
	}
	
	public static function typeName(ct:ComplexType, shortify = false, escape = true):String {
		switch(followComplexType(ct)) {
			case TFunction(args, ret):
				return (escape ? "F" : "(")
					+ args.map(typeName.bind(_, shortify, escape)).join(escape ? "_" : "->") + (escape ? "_R" : "->") + typeName(ret, shortify, escape)
					+ (escape ? "" : ")");
			case TParent(t):
				return (escape ? "P" : "(") + typeName(t, shortify, escape) + (escape ? "" : ")");
			case TPath(t):
				var ret = "";
				
				// package
				ret += shortify ? "" : (t.pack.length > 0 ? t.pack.map(capitalize).join("") : "");
				// class name
				ret += shortify ? (t.sub != null ? t.sub : t.name) : (t.name + (t.sub != null ? t.sub : ""));
				
				// type params
				if(t.params != null && t.params.length > 0) {
					var tpName = typeParamName.bind(_, typeName.bind(_, shortify, escape));
					ret += (escape ? "Of" : "<") + t.params.map(tpName).join(escape ? "_" : ",") + (escape ? "" : ">");
				}
				
				return ret;
			case x:
				error('Unexpected $x!', Context.currentPos());
				return null;
		}
	}
	
	public static function compareStrings(a:String, b:String):Int {
		a = a.toLowerCase();
		b = b.toLowerCase();
		return (a < b) ? -1 : (a > b) ? 1 : 0;
	}
	
	public static function joinFullName(types:Array<ComplexType>, sep:String) {
		var typeNames = types.map(typeName.bind(_, false, true));
		typeNames.sort(compareStrings);
		return typeNames.join(sep);
	}
}

#end
