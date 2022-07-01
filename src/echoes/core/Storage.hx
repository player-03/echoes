package echoes.core;

/**
 * `Storage<T>` stores all components of type `T`, indexed by entity id. That
 * means `storage[entityID]` will return that entity's component, if it has a
 * component of this type.
 * @see `echoes.core.macro.ComponentBuilder`
 */

#if echoes_custom_container

//If you define this, you also need to provide an `echoes.core.Storage<T>` class
//that matches the `IntMap` API.

#elseif echoes_array_container

@:forward.new
abstract Storage<T>(Array<T>) {
	@:arrayAccess public inline function set(id:Int, c:T):Void {
		this[id] = c;
	}
	
	@:arrayAccess public inline function get(id:Int):T {
		return this[id];
	}
	
	public inline function remove(id:Int):Bool {
		if(exists(id)) {
			this[id] = null;
			return true;
		} else {
			return false;
		}
	}
	
	public inline function exists(id:Int):Bool {
		return this[id] != null;
	}
	
	public inline function clear():Void {
		this.resize(0);
	}
}

#else

typedef Storage<T> = Map<Int, T>;

#end
