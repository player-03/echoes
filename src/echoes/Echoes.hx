package echoes;

import echoes.ComponentStorage;
import echoes.Entity;
import echoes.utils.Clock;
import echoes.utils.ReadOnlyData;
import echoes.View;

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
	private static var componentStorage:Array<DynamicComponentStorage> = [];
	
	@:allow(echoes.Entity)
	private static var _activeEntities:List<Entity> = new List();
	public static var activeEntities(get, never):ReadOnlyList<Entity>;
	private static inline function get_activeEntities():ReadOnlyList<Entity> return _activeEntities;
	
	@:allow(echoes.ViewBase)
	private static var _activeViews:Array<ViewBase> = [];
	public static var activeViews(get, never):ReadOnlyArray<ViewBase>;
	private static inline function get_activeViews():ReadOnlyArray<ViewBase> return _activeViews;
	
	public static var activeSystems(default, null):SystemList = {
		var activeSystems:SystemList = new SystemList();
		activeSystems.__activate__();
		activeSystems.clock.maxTime = 1;
		activeSystems;
	};
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
		var startTime:Float = haxe.Timer.stamp();
		var dt:Float = startTime - lastUpdate;
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
		for(i in 0...Entity.statuses.length) {
			Entity.statuses[i] = false;
		}
		
		_activeEntities.clear();
		activeSystems.removeAll();
		
		//Iterate backwards when removing items from arrays.
		var i:Int = activeViews.length;
		while(--i >= 0) {
			activeViews[i].reset();
		}
		
		for(storage in componentStorage) {
			storage.clear();
		}
		EntityComponents.components.resize(0);
		
		Entity.idPool.resize(0);
		Entity.statuses.resize(0);
		
		Entity.nextId = 0;
		
		init(0);
	}
	
	//System management
	//=================
	
	public static inline function addSystem(system:System):Void {
		activeSystems.add(system);
	}
	
	public static inline function removeSystem(system:System):Void {
		activeSystems.remove(system);
	}
	
	public static inline function hasSystem(system:System):Bool {
		return activeSystems.exists(system);
	}
	
	//Singleton getters
	//=================
	
	/**
	 * Returns the `ComponentStorage` singleton for the given component.
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
		var componentComplexTypes:Array<ComplexType> = [for(type in componentTypes) type.parseClassExpr()];
		var viewName:String = componentComplexTypes.getViewName();
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
		var view:Expr = getInactiveView(componentTypes);
		
		return macro {
			$view.activate();
			$view;
		};
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
