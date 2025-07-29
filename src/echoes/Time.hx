package echoes;

import haxe.Timer;

#if !echoes_millisecond_time

/**
 * An amount of time, in seconds.
 * 
 * In `@:update` functions, a `Time` or `Float` argument (the two are fully
 * interchangeable) has a special meaning: instead of getting the value of a
 * component, it gets the length of the update.
 * @see `echoes.utils.Clock`
 */
@:eager abstract Time(Float) from Float to Float {
	public static var MAX(get, never):Time;
	private static inline function get_MAX():Time {
		return Math.POSITIVE_INFINITY;
	}
	
	//Large enough to reliably avoid rounding. Not the true minimum.
	public static inline final MIN_POSITIVE:Time = 1e-16;
	
	public static inline function fromMilliseconds(milliseconds:Int):Time {
		return milliseconds / 1000;
	}
	
	public static inline function stamp():Time {
		return Timer.stamp();
	}
	
	public inline function toMilliseconds():Int {
		return Std.int(this * 1000);
	}
	
	@:op(A + B) private function sum(b:Time):Time;
	@:op(A += B) private inline function add(b:Time):Time {
		return this += (b:Float);
	}
	@:op(A - B) private function difference(b:Time):Time;
	@:op(A -= B) private inline function subtract(b:Time):Time {
		return this -= (b:Float);
	}
	@:op(A * B) private function product(b:Time):Time;
	@:op(A *= B) private inline function quotient(b:Time):Time {
		return this *= (b:Float);
	}
	
	@:op(A > B) private function greater(b:Time):Bool;
	@:op(A >= B) private function greaterEqual(b:Time):Bool;
	@:op(A < B) private function less(b:Time):Bool;
	@:op(A <= B) private function lessEqual(b:Time):Bool;
	@:op(A != B) private function notEqual(b:Time):Bool;
}

#else

/**
 * An amount of time, in milliseconds.
 * 
 * In `@:update` functions, a `Time` argument has a special meaning: instead of
 * getting the value of a component, it gets the length of the update.
 * 
 * To use this version of `Time`, set `-D echoes_millisecond_time`.
 * @see `echoes.utils.Clock`
 */
abstract Time(Int) from Int to Int {
	public static inline final MAX:Time = 0x7FFFFFFF;
	public static inline final MIN_POSITIVE:Time = 1;
	
	public static inline function fromMilliseconds(milliseconds:Int):Time {
		return milliseconds;
	}
	
	public static inline function stamp():Time {
		return Std.int(Timer.stamp() * 1000);
	}
	
	public inline function toMilliseconds():Int {
		return this;
	}
	
	@:op(A + B) private function sum(b:Time):Time;
	@:op(A += B) private inline function add(b:Time):Time {
		return this += (b:Int);
	}
	@:op(A - B) private function difference(b:Time):Time;
	@:op(A -= B) private inline function subtract(b:Time):Time {
		return this -= (b:Int);
	}
	@:op(A * B) private function product(b:Time):Time;
	@:op(A *= B) private inline function quotient(b:Time):Time {
		return this *= (b:Int);
	}
	
	@:op(A > B) private function greater(b:Time):Bool;
	@:op(A >= B) private function greaterEqual(b:Time):Bool;
	@:op(A < B) private function less(b:Time):Bool;
	@:op(A <= B) private function lessEqual(b:Time):Bool;
	@:op(A != B) private function notEqual(b:Time):Bool;
}

#end
