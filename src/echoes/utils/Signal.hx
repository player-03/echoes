package echoes.utils;

#if macro
import haxe.macro.Expr;
#end

@:forward @:forward.new
abstract Signal<T:haxe.Constraints.Function>(Array<T>) {
	public macro function dispatch(self:Expr, args:Array<Expr>) {
		return macro for(listener in $self) {
			listener($a{args});
		};
	}
	
	public inline function clear():Void {
		this.resize(0);
	}
}
