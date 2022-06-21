package echoes.utils;

#if macro
import haxe.macro.Expr;
#end

@:forward @:forward.new
abstract Signal<T>(List<T>) {
	public inline function has(listener:T):Bool {
		return Lambda.has(this, listener);
	}
	
	public macro function dispatch(self:Expr, args:Array<Expr>) {
		return macro {
			for(listener in $self) {
				listener($a{args});
			}
		}
	}
}
