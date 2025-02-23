package echoes;

import echoes.ComponentStorage;
import echoes.Entity;
import echoes.utils.Clock;
import echoes.utils.ReadOnlyData;
import echoes.View;
import haxe.Serializer;
import haxe.Unserializer;

#if macro
import haxe.macro.Expr;

using echoes.macro.ComponentStorageBuilder;
using echoes.macro.MacroTools;
using echoes.macro.ViewBuilder;
using haxe.macro.Context;
#end

class Echoes {
	#if ((haxe_ver < 4.2) && macro)
	private static function __init__():Void {
		Context.error("Error: Echoes requires at least Haxe 4.2.", Context.currentPos());
	}
	#end
	
	@:allow(echoes.ComponentStorage)
	private static final _componentStorage:Array<DynamicComponentStorage> = [];
	public static var componentStorage(get, never):ReadOnlyArray<DynamicComponentStorage>;
	private static inline function get_componentStorage():ReadOnlyArray<DynamicComponentStorage> return _componentStorage;
	
	@:allow(echoes.Entity)
	private static final _activeEntities:Array<Entity> = [];
	/**
	 * All currently-active entities.
	 * 
	 * Note: to improve performance, this array is re-ordered whenever an entity
	 * is deactivated or destroyed. To suppress this behavior and keep the array
	 * in a consistent order, use `-D echoes_stable_order`.
	 */
	public static var activeEntities(get, never):ReadOnlyArray<Entity>;
	private static inline function get_activeEntities():ReadOnlyArray<Entity> return _activeEntities;
	
	/**
	 * The index of each entity in `activeEntities`. For any active entity,
	 * `entity == activeEntities[activeEntityIndices[entity.id]]`.
	 */
	@:allow(echoes.Entity)
	private static final activeEntityIndices:Array<Null<Int>> = [];
	
	@:allow(echoes.ViewBase)
	private static final _activeViews:Array<ViewBase> = [];
	/**
	 * All currently-active views.
	 */
	public static var activeViews(get, never):ReadOnlyArray<ViewBase>;
	private static inline function get_activeViews():ReadOnlyArray<ViewBase> return _activeViews;
	
	/**
	 * All currently-active systems. Unlike `activeEntities` and `activeViews`,
	 * this is not a flat array, but rather the root node of a tree: it may
	 * contain `SystemList`s containing `SystemList`s. All active systems will
	 * be somewhere in this tree.
	 * 
	 * Adding a system to this list (whether directly, via `addSystem()`, or by
	 * adding a list containing that system) activates that system.
	 * 
	 * Removing a system from this list (whether directly, via `removeSystem()`,
	 * or by removing a list containing that system) deactivates that system.
	 * 
	 * To search the full tree, use `activeSystems.find()`.
	 */
	public static final activeSystems:SystemList = {
		final activeSystems:SystemList = new SystemList();
		activeSystems.__activate__();
		activeSystems.clock.maxTime = 1;
		activeSystems;
	};
	
	/**
	 * The clock used to update `activeSystems`. This starts with all the usual
	 * defaults, except `maxTime` is set to 1 second. Any changes you make to
	 * this clock will be preserved, even after `Echoes.reset()`.
	 */
	public static var clock(get, never):Clock;
	private static inline function get_clock():Clock {
		return activeSystems.clock;
	}
	
	#if echoes_profiling
	private static var lastUpdateLength:Int = 0;
	#end
	
	private static var lastUpdate:Float = haxe.Timer.stamp();
	private static var updateTimer:haxe.Timer;
	
	/**
	 * @param fps The number of updates to perform each second. If this is zero,
	 * you will need to call `Echoes.update()` yourself.
	 */
	public static function init(?fps:Float = 60):Void {
		lastUpdate = haxe.Timer.stamp();
		
		if(updateTimer != null) {
			updateTimer.stop();
			updateTimer = null;
		}
		if(fps > 0) {
			updateTimer = new haxe.Timer(Std.int(1000 / fps));
			updateTimer.run = update;
		}
	}
	
	/**
	 * Returns statistics about the app in JSON-compatible form.
	 */
	public static function getStatistics():AppStatistics {
		return {
			cachedEntities: Entity.idPool.length,
			entities: activeEntities.length,
			systems: [for(system in activeSystems) system.getStatistics()],
			views: [for(view in activeViews)
				{
					name: Std.string(view),
					entities: view.entities.length
				}]
		};
	}
	
	/**
	 * Updates all active systems.
	 */
	public static function update():Void {
		final startTime:Float = haxe.Timer.stamp();
		final dt:Float = startTime - lastUpdate;
		lastUpdate = startTime;
		
		activeSystems.__update__(dt);
		
		#if echoes_profiling
		lastUpdateLength = Std.int((haxe.Timer.stamp() - startTime) * 1000);
		#end
	}
	
	/**
	 * Deactivates all views and systems, destroys all entities, and cancels the
	 * automatic updates started during `init()`.
	 */
	public static function reset():Void {
		activeEntityIndices.resize(0);
		_activeEntities.resize(0);
		activeSystems.removeAll();
		
		//Iterate backwards when removing items from arrays.
		var i:Int = activeViews.length;
		while(--i >= 0) {
			activeViews[i].reset();
		}
		
		for(storage in _componentStorage) {
			storage.clear();
		}
		EntityComponents.components.resize(0);
		
		Entity.idPool.resize(0);
		Entity.nextId = 0;
		
		init(0);
	}
	
	//Singleton getters
	//=================
	
	/**
	 * Returns the `ComponentStorage` singleton for the given component type.
	 * 
	 * Sample usage:
	 * 
	 * ```haxe
	 * var stringStorage:ComponentStorage<String> = Echoes.getComponentStorage(String);
	 * 
	 * if(stringStorage.exists(entity)) {
	 *     trace(stringStorage.get(entity));
	 * } else {
	 *     stringStorage.add(entity, "string");
	 * }
	 * ```
	 */
	public static #if !macro macro #end function getComponentStorage(componentType:ExprOf<Class<Any>>):Expr {
		return componentType.parseClassExpr().getComponentStorage();
	}
	
	/**
	 * Gets an inactive `View` of the given components. The calling class should
	 * call `activate()` before attempting to use it.
	 * @see `getView()` to automatically activate the view.
	 */
	public static #if !macro macro #end function getInactiveView(componentTypes:Array<ExprOf<Class<Any>>>):Expr {
		final componentComplexTypes:Array<ComplexType> = [for(type in componentTypes) type.parseClassExpr()];
		final viewName:String = componentComplexTypes.getViewName();
		componentComplexTypes.createViewType();
		
		return macro $i{ viewName }.instance;
	}
	
	/**
	 * Gets an active `View` of the given components. The calling class should
	 * call `deactivate()` once done using it.
	 * 
	 * Sample usage:
	 * 
	 * ```haxe
	 * var view:View<A, B, C> = Echoes.getView(A, B, C);
	 * trace(view.entities.length);
	 * view.onAdded.push((entity:Entity, a:A, b:B, c:C) -> trace(a + b * c));
	 * ```
	 */
	public static #if !macro macro #end function getView(componentTypes:Array<ExprOf<Class<Any>>>):Expr {
		final view:Expr = getInactiveView(componentTypes);
		
		return macro {
			$view.activate();
			$view;
		};
	}
	
	//Serialization
	//=============
	
	public static function serialize():String {
		final data:Dynamic = {
			"echoes.Echoes.activeEntities": activeEntities,
			"echoes.Entity.idPool": Entity.idPool,
			"echoes.Entity.nextID": Entity.nextID
		};
		
		for(storage in componentStorage) {
			final components = (cast storage:ComponentStorage<Dynamic>).storage;
			
			//Omit empty arrays. It isn't as easy to check if a map is empty, so
			//just include all of them.
			if(#if (echoes_storage == "Map") true #else components.length > 0 #end) {
				Reflect.setField(data, storage.componentType, components);
			}
		}
		
		return Serializer.run(data);
	}
	
	/**
	 * Restores all entities and components recorded by `serialize()`,
	 * overwriting any existing entities or components.
	 * 
	 * Caution: serializing and unserializing are not well-tested. Use this at
	 * your own risk, and especially avoid unserializing if the component types
	 * could have changed. Even a minor change, such as changing `Int` to
	 * `Float`, can cause errors on some targets.
	 */
	public static function unserialize(data:String):Void {
		for(storage in _componentStorage) {
			storage.removeAll();
		}
		
		activeEntityIndices.resize(0);
		_activeEntities.resize(0);
		
		final data:Dynamic = Unserializer.run(data);
		for(entity in (Reflect.field(data, "echoes.Echoes.activeEntities"):Array<Entity>)) {
			activeEntityIndices[entity.id] = _activeEntities.length;
			_activeEntities.push(entity);
		}
		
		Entity.nextID = Reflect.field(data, "echoes.Entity.nextID");
		Entity.idPool.resize(0);
		for(id in (Reflect.field(data, "echoes.Entity.idPool"):Array<Int>)) {
			Entity.idPool.push(id);
		}
		
		for(storage in componentStorage) {
			(cast storage:ComponentStorage<Dynamic>).unserializeFromData(Reflect.field(data, storage.componentType));
		}
	}
}

typedef AppStatistics = {
	var cachedEntities:Int;
	var entities:Int;
	var systems:Array<SystemDetails>;
	var views:Array<{
		var name:String;
		var entities:Int;
	}>;
};

typedef SystemDetails = {
	var name:String;
	@:optional var children:Array<SystemDetails>;
	#if echoes_profiling
	var deltaTime:Int;
	#end
};
