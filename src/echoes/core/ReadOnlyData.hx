package echoes.core;

@:forward(first, iterator, last, length)
@:forward.new
abstract ReadOnlyList<T>(List<T>) from List<T> {
	public inline function has(item:T):Bool return Lambda.has(this, item);
}

@:forward(contains, iterator, length)
@:forward.new
abstract ReadOnlyArray<T>(Array<T>) from Array<T> {}
