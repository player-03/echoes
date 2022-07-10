package echoes;

import echoes.macro.ViewBuilder;
import echoes.utils.Signal;
import echoes.View;
import haxe.macro.Expr;

/**
 * The base class for all systems. Using them requires three steps:
 * 
 * 1. Extend `System`.
 * 2. Add instance functions with the appropriate metadata (see below).
 * 3. Create a new instance of your system, and add it to the `Echoes`.
 * 
 * Instance functions marked with `@:update`, `@:add`, or `@:remove` (or a
 * variant thereof) will automatically become listener functions, listening for
 * events related to matching entities. Matches are found by taking the
 * function's arguments and searching for entities with those components.
 * 
 * ```haxe
 * //Entities match if they have both `A` and `B` components.
 * @:add private function addAB(a:A, b:B):Void {}
 * 
 * //Entities match if they have both `B` and `C` components.
 * @:update private function updateBC(b:B, c:C):Void {}
 * 
 * //Entities match if they have all three component types.
 * @:remove private function removeAnyOfThree(a:A, b:B, c:C):Void {}
 * ```
 * 
 * `@:update` listeners are called once per update (see `Timestamp`), per
 * matching entity. `@:add` functions are called when an entity gains enough
 * components to match the function. `@:remove` functions are called when a
 * previously-matching entity loses a required component.
 * 
 * For instance, here's when each of the above functions would be called:
 * 
 * ```haxe
 * var entity:Entity = new Entity(); //No components, no matches.
 * 
 * entity.add(new A()); //No matches; A isn't enough.
 * 
 * entity.add(new C()); //Still no matches; A+C isn't enough.
 * 
 * entity.add(new B()); //addAB() is called because the entity now has A+B.
 * 
 * Echoes.update(1); //updateBC() is called because the entity has B+C.
 * 
 * entity.remove(A); //removeAnyOfThree() is called because the entity used to
 *                   //have A+B+C, but now doesn't.
 * 
 * //The entity still has B+C, so as more updates happen, updateBC() will
 * //continue to be called.
 * ```
 * 
 * ---
 * 
 * As mentioned above, Echoes recognizes variants of the metadata. The full
 * versions are `@:echoes_updated`, `@:echoes_added`, and `@:echoes_removed`,
 * but you can freely omit the "echoes_" and/or omit characters from the end as
 * long as you keep the `u`, `a`, and `r`, respectively. This means `@:upd`,
 * `@:a`, `@:echoes_rem`, `@:echoes_u`, and several others are all valid.
 */
#if !macro
@:autoBuild(echoes.macro.SystemBuilder.build())
#end
class System {
	#if echoes_profiling
	@:noCompletion private var __updateTime__:Float = 0;
	#end
	
	@:noCompletion private var __dt__:Float = 0;
	
	public var onActivate:Signal<() -> Void> = new Signal();
	public var onDeactivate:Signal<() -> Void> = new Signal();
	public var active(default, null):Bool = false;
	
	@:allow(echoes.Echoes)
	private function __activate__():Void {
		if(!active) {
			active = true;
			__dt__ = 0;
			
			onActivate.dispatch();
		}
	}
	
	@:allow(echoes.Echoes)
	private function __deactivate__():Void {
		if(active) {
			active = false;
			
			onDeactivate.dispatch();
		}
	}
	
	@:allow(echoes.Echoes)
	private function __update__(dt:Float):Void {
		__dt__ = dt;
		
		//Everything else is handled by macro.
	}
	
	/**
	 * Returns the expected view (functioning like `Echoes.getView()`), except
	 * the view will activate and deactivate whenever this system does.
	 */
	public macro function makeLinkedView(self:Expr):Expr {
		var view:Expr = Echoes.getView(false);
		return macro {
			$self.onActivated.push($view.activate);
			$self.onDeactivated.push($view.deactivate);
			$view;
		};
	}
	
	public function info(?indent = "    ", ?level = 0):String {
		indent = StringTools.rpad("", indent, indent.length * level);
		
		#if echoes_profiling
		return '$indent$this : $__updateTime__ ms';
		#else
		return '$indent$this';
		#end
	}
	
	public function toString():String {
		return Type.getClassName(Type.getClass(this));
	}
}
