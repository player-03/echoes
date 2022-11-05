package echoes.utils;

#if macro
import haxe.macro.Expr;
#end

@:forward @:forward.new
abstract Signal<T:haxe.Constraints.Function>(Array<T>) {
	public inline function add(listener:T):Void {
		this.push(listener);
	}
	
	public function contains(listener:T):Bool {
		for(l in this) {
			if(Reflect.compareMethods(l, listener)) {
				return true;
			}
		}
		
		return false;
	}
	
	public macro function dispatch(self:Expr, args:Array<Expr>):Expr {
		return macro for(listener in $self) {
			listener($a{ args });
		};
	}
	
	public function indexOf(listener:T):Int {
		for(i => l in this) {
			if(Reflect.compareMethods(l, listener)) {
				return i;
			}
		}
		
		return -1;
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
