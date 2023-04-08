package echoes.utils;

@:forward(first, iterator, isEmpty, last, length)
@:forward.new
abstract ReadOnlyList<T>(List<T>) from List<T> to Iterable<T> {
	public inline function has(item:T):Bool return Lambda.has(this, item);
}

typedef ReadOnlyArray<T> = haxe.ds.ReadOnlyArray<T>;
