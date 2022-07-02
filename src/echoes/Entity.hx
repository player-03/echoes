package echoes;

#if macro
import echoes.core.macro.EntityTools;
import haxe.macro.Expr;
import haxe.macro.Printer;

using echoes.core.macro.ComponentStorageBuilder;
using echoes.core.macro.MacroTools;
using haxe.macro.Context;
using Lambda;
#end

/**
 * The entity part of entity-component-system.
 * 
 * Under the hood, an `Entity` is an integer key, used to look up components in
 * `Storage`. (Caution: don't use this integer as a unique id, as destroyed
 * entities will be cached and reused!)
 */
abstract Entity(Int) from Int to Int {
	public static inline var INVALID:Entity = Workflow.INVALID_ID;
	
	/**
	 * @param immediate Immediately adds this entity to the workflow if `true`,
	 * otherwise `activate()` call is required.
	 */
	public inline function new(immediate = true) {
		this = Workflow.id(immediate);
	}
	
	/**
	 * Adds this entity to the workflow, so it can be collected by views.
	 */
	public inline function activate() {
		Workflow.add(this);
	}
	
	/**
	 * Removes this entity from the workflow (and also from all views), but
	 * saves all associated components. Call `activate()` to add it again.
	 */
	public inline function deactivate() {
		Workflow.remove(this);
	}
	
	/**
	 * Returns `true` if this entity is added to the workflow, otherwise returns
	 * `false`.
	 */
	public inline function isActive():Bool {
		return Workflow.status(this) == Active;
	}
	
	/**
	 * Returns `true` if this entity has not been destroyed and therefore can be
	 * used safely.
	 */
	public inline function isValid():Bool {
		return Workflow.status(this) < Cached;
	}
	
	/**
	 * Returns the status of this entity: Active, Inactive, Cached or Invalid.
	 * Method is used mostly for debug purposes.
	 */
	public inline function status():Status {
		return Workflow.status(this);
	}
	
	/**
	 * Removes all of this entity's components, but does not deactivate or
	 * destroy it.
	 */
	public inline function removeAll() {
		Workflow.removeAllComponentsOf(this);
	}
	
	/**
	 * Removes all of this entity's components, deactivates it, and frees its id
	 * for reuse. Do not call any of the entity's functions after this; their
	 * behavior is unspecified.
	 */
	public inline function destroy() {
		Workflow.cache(this);
	}
	
	/**
	 * Returns the entity's id and components in string form.
	 */
	public inline function print():String {
		return Workflow.printAllComponentsOf(this);
	}
	
	/**
	 * Adds one or more components to the entity. If the entity already has a
	 * component of the same type, the old component will be replaced.
	 * @param components Components of `Any` type.
	 * @return This entity.
	 */
	public macro function add(self:Expr, components:Array<ExprOf<Any>>):ExprOf<echoes.Entity> {
		return EntityTools.add(self, components);
	}
	
	/**
	 * Removes one or more components from the entity.
	 * @param types The type(s) of the components to remove. _Not_ the
	 * components themselves!
	 * @return This entity.
	 */
	public macro function remove(self:Expr, types:Array<ExprOf<Class<Any>>>):ExprOf<echoes.Entity> {
		return EntityTools.remove(self, [for(type in types) type.parseClassExpr()]);
	}
	
	/**
	 * Gets this entity's component of the given type, if this entity has a
	 * component of the given type.
	 * @param type The type of the component to get.
	 * @return The component, or `null` if the entity doesn't have it.
	 */
	public macro function get<T>(self:Expr, type:ExprOf<Class<T>>):ExprOf<T> {
		return EntityTools.get(self, type.parseClassExpr());
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public macro function exists(self:Expr, type:ExprOf<Class<Any>>):ExprOf<Bool> {
		return EntityTools.exists(self, type.parseClassExpr());
	}
}

@:enum abstract Status(Int) {
	var Inactive = 0;
	var Active = 1;
	var Cached = 2;
	var Invalid = 3;
	@:op(A > B) static function gt(a:Status, b:Status):Bool;
	@:op(A < B) static function lt(a:Status, b:Status):Bool;
}
