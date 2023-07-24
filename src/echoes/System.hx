package echoes;

import echoes.Echoes;
import echoes.macro.ViewBuilder;
import echoes.utils.Signal;
import echoes.View;
import haxe.macro.Expr;
import haxe.rtti.Meta;

/**
 * The base class for all systems. Using them requires three steps:
 * 
 * 1. Extend `System`.
 * 2. Add instance functions with the appropriate metadata (see below).
 * 3. Create a new instance of your system, and add it to `Echoes`.
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
	
	@:noCompletion private final __children__:Array<ChildSystem> = [];
	
	@:noCompletion private var __dt__:Float = 0;
	
	public var active(default, null):Bool = false;
	
	public final onActivate:Signal<() -> Void> = new Signal();
	public final onDeactivate:Signal<() -> Void> = new Signal();
	
	/**
	 * The list directly containing this system, if any.
	 */
	public var parent(default, null):SystemList;
	
	/**
	 * This system's base priority, applying to any listener function that
	 * doesn't have its own `@:priority` tag. This can be set via the
	 * constructor, or by adding a `@:priority` tag to the system itself.
	 * 
	 * Each `SystemList` is sorted based on the priority of the systems within,
	 * meaning within `parent`, this system will run before any system of lower
	 * priority, and after any system with higher priority.
	 * 
	 * Systems with the same priority will run in the order they were added to
	 * the list, with one caveat: setting `priority` places the system after all
	 * other systems of that priority. Even `system.priority = system.priority`
	 * will affect the ordering.
	 */
	public var priority(default, set):Int;
	private inline function set_priority(value:Int):Int {
		priority = value;
		
		if(parent != null) {
			parent.__recalculateOrder__(this);
		}
		
		return priority;
	}
	
	/**
	 * @param priority This system's initial priority. If omitted, this will
	 * default to the value set by `@:priority`, or 0 if that's omitted too.
	 */
	private inline function new(?priority:Int) {
		this.priority = priority != null ? priority : __getDefaultPriority__();
	}
	
	@:allow(echoes.Echoes)
	private function __activate__():Void {
		if(!active) {
			active = true;
			__dt__ = 0;
			
			#if !macro
			onActivate.dispatch();
			#end
		}
	}
	
	@:noCompletion
	private inline function __addListenersWithPriority__(priority:Int, runUpdateListeners:(Float) -> Void):Void {
		__children__.push(new ChildSystem(this, priority, runUpdateListeners));
	}
	
	@:allow(echoes.Echoes)
	private function __deactivate__():Void {
		if(active) {
			active = false;
			
			#if !macro
			onDeactivate.dispatch();
			#end
		}
	}
	
	/**
	 * Returns the value from the system's `@:priority` tag, if any.
	 */
	private function __getDefaultPriority__():Int {
		return 0;
	}
	
	@:allow(echoes.Echoes)
	private function __update__(dt:Float):Void {
		__dt__ = dt;
		
		//Everything else is handled by macro.
	}
	
	/**
	 * @see `SystemList.find()`
	 */
	private function find<T:System>(systemType:Class<T>):Null<T> {
		if(Std.isOfType(this, systemType)) {
			return cast this;
		} else {
			return null;
		}
	}
	
	public function getStatistics():SystemDetails {
		return {
			name: Std.string(this)
			#if echoes_profiling , deltaTime: __updateTime__ #end
		};
	}
	
	/**
	 * Returns a view that will activate and deactivate when the system does.
	 */
	public macro function getLinkedView(self:Expr, componentTypes:Array<ExprOf<Class<Any>>>):Expr {
		var view:Expr = Echoes.getInactiveView(componentTypes);
		return macro {
			var self = $self;
			self.onActivate.push($view.activate);
			self.onDeactivate.push($view.deactivate);
			$view;
		};
	}
	
	public function toString():String {
		return Type.getClassName(Type.getClass(this));
	}
}

@:skipBuildMacro
private class ChildSystem extends System {
	private final parentSystem:System;
	
	private final runUpdateListeners:(Float) -> Void;
	
	public inline function new(parentSystem:System, priority:Int, runUpdateListeners:(Float) -> Void) {
		super(priority);
		
		this.parentSystem = parentSystem;
		this.runUpdateListeners = runUpdateListeners;
	}
	
	private override function __update__(dt:Float):Void {
		#if echoes_profiling
		var __timestamp__ = Date.now().getTime();
		#end
		
		runUpdateListeners(dt);
		
		#if echoes_profiling
		this.__updateTime__ = Std.int(Date.now().getTime() - __timestamp__);
		#end
	}
	
	public override function toString():String {
		return parentSystem.toString() + ':$priority';
	}
}
