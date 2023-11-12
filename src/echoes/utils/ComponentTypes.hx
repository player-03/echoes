package echoes.utils;

import haxe.iterators.ArrayIterator;
import echoes.ComponentStorage;
import echoes.Echoes;
import echoes.Entity;
import haxe.macro.Expr;

using echoes.macro.ComponentStorageBuilder;
using echoes.macro.MacroTools;

/**
 * A set of component types, or equivalently, a set of `ComponentStorage`
 * instances for those components. Sample usage:
 * 
 * ```haxe
 * var types:ComponentTypes = new ComponentTypes();
 * 
 * //The simplest approach is to pass the component type.
 * types.add(Bool);
 * trace(types.contains(Bool));
 * types.remove(Bool);
 * 
 * //As normal, you can use type check syntax to pass type parameters.
 * types.add((_:Array<Bool>));
 * trace(types.contains((_:Array<Bool>)));
 * types.remove((_:Array<Bool>));
 * 
 * //If you can't hard-code the component type, use the "ComponentStorage"
 * //functions instead.
 * function example(storage:DynamicComponentStorage):Void {
 *     types.addComponentStorage(storage);
 *     trace(types.containsComponentStorage(storage));
 *     types.removeComponentStorage(storage);
 * }
 * 
 * //You can iterate over the component types in the set. Note: these will be
 * //returned as `DynamicComponentStorage` instances, and their order may not be
 * //the same every time.
 * for(componentStorage in types) {
 *     //You can still get the component type as a string.
 *     trace(componentStorage.componentType); 
 * }
 * ```
 */
@:forward(length) @:forward.new
abstract ComponentTypes(Array<DynamicComponentStorage>) from Array<DynamicComponentStorage> {
	#if macro static #else macro #end
	public function add(self:Expr, type:ExprOf<Class<Any>>):Expr {
		//Don't accept instances, as those are likely to be
		return macro $self.addComponentStorage(${ Echoes.getComponentStorage(type) });
	}
	
	public inline function addComponentStorage(storage:DynamicComponentStorage):Void {
		if(!this.contains(storage)) {
			this.push(storage);
		}
	}
	
	#if macro static #else macro #end
	public function contains(self:Expr, type:ExprOf<Class<Any>>):ExprOf<Bool> {
		return macro $self.containsComponentStorage(${ Echoes.getComponentStorage(type) });
	}
	
	public inline function containsComponentStorage(storage:DynamicComponentStorage):Bool {
		return this.contains(storage);
	}
	
	@:noCompletion public inline function iterator():ArrayIterator<DynamicComponentStorage> {
		return this.iterator();
	}
	
	#if macro static #else macro #end
	public function remove(self:Expr, type:ExprOf<Class<Any>>):ExprOf<Bool> {
		return macro $self.removeComponentStorage(${ Echoes.getComponentStorage(type) });
	}
	
	public inline function removeComponentStorage(storage:DynamicComponentStorage):Bool {
		final index:Int = this.lastIndexOf(storage);
		if(index >= 0) {
			this[index] = this[this.length - 1];
			this.pop();
			return true;
		} else {
			return false;
		}
	}
	
	@:to private inline function toIterable():Iterable<DynamicComponentStorage> {
		return this;
	}
}
