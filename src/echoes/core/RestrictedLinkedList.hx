package echoes.core;

@:allow(echoes)
@:forward(first, last, length, iterator, sort)
@:forward.new
abstract RestrictedLinkedList<T>(List<T>) {
	private inline function add(item:T) this.add(item);
	private inline function pop() return this.pop();
	private inline function remove(item:T) return this.remove(item);
	public inline function has(item:T) return Lambda.has(this, item);
}
