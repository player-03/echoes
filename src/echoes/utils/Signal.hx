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
	
	public function contains(listener:T):Bool {
		for(l in this) {
			if(Reflect.compareMethods(l, listener)) {
				return true;
			}
		}
		
		return false;
	}
	
	public function remove(listener:T):Bool {
		for(i => l in this) {
			if(Reflect.compareMethods(l, listener)) {
				this.splice(i, 1);
				return true;
			}
		}
		
		return false;
	}
}
