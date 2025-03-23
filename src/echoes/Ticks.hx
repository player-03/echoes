package echoes;

abstract Ticks(haxe.Int32) {
    public static inline final MAX: Ticks = cast 1 << 30;
    public static inline final ONE: Ticks = cast 1;
    public static inline final ZERO: Ticks = cast 0;

    public var ms(get, never): haxe.Int32;

    public static function fromMilliseconds(ms: haxe.Int32): Ticks
        return cast ms;

	#if !echoes_no_timer
    public static function now(): Ticks
        return fromMilliseconds(cast haxe.Timer.stamp() * 1000);
    #end

    @:op(this + rhs)
    public function add(rhs: Ticks): Ticks
        return cast this + cast rhs;

    @:op(this - rhs)
    public function diff(rhs: Ticks): Ticks
        return cast this - cast rhs;

    @:op(this * rhs)
    public function mult(rhs: Float): Ticks
        return cast this * rhs;

    @:op(this > rhs)
    public function greater(rhs: Ticks): Bool
        return cast this > cast rhs;

    public function get_ms(): haxe.Int32
        return cast this;
}