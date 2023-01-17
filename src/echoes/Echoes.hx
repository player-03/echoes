package echoes;

import echoes.ComponentStorage;
import echoes.Entity;
import echoes.utils.Clock;
import echoes.utils.ReadOnlyData;
import echoes.View;

#if macro
import haxe.macro.Expr;
import haxe.macro.Printer;

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
	
	@:allow(echoes.Entity) @:allow(echoes.ComponentStorage)
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
		
		activeSystems.__update__(dt, 0);
		
		#if echoes_profiling
		lastUpdateLength = Std.int((haxe.Timer.stamp() - startTime) * 1000);
		#end
	}
	
	/**
	 * Deactivates all views and systems, destroys all entities, and cancels the
	 * automatic updates started during `init()`.
	 */
	public static function reset():Void {
		//Deactivate all entities so that no events are dispatched.
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
	
	//Singleton management
	//====================
	
	/**
	 * Returns the expected `View` or `ComponentStorage` instance. May also work
	 * for other `@:genericBuild` types, but those aren't officially supported.
	 * 
	 * To use this function, you must explicitly specify the expected type:
	 * 
	 * ```haxe
	 * var stringView:View<String> = Echoes.getSingleton();
	 * var colorShapeView = (Echoes.getSingleton():View<Color, Shape>);
	 * 
	 * var stringStorage:ComponentStorage<String> = Echoes.getSingleton();
	 * var colorStorage:ComponentStorage<Color> = Echoes.getSingleton();
	 * var shapeStorage = (Echoes.getSingleton():ComponentStorage<Shape>);
	 * ```
	 * @param activateView Whether to activate the `View` before returning it.
	 * Has no effect on `ComponentStorage` or any other type.
	 * @see `System.makeLinkedView()`
	 */
	//Tip: macros can call this function too!
	public static #if !macro macro #end function getSingleton(?activateView:Bool = true):Expr {
		//There's no need to invoke the builder; Haxe will automatically do so
		//at least once.
		switch(Context.getExpectedType().followMono().toComplexType()) {
			case TPath({ pack: [], name: className, params: [] }):
				if(className.isView() && activateView) {
					return macro {
						$i{ className }.instance.activate();
						$i{ className }.instance;
					};
				} else {
					return macro $i{ className }.instance;
				}
			case TPath({ pack: ["echoes"], name: "ComponentStorage", params: [
				TPType(_.getComponentStorage() => TPath({ name: className }))] }):
				//Bug: VS Code syntax highlighting breaks without some extra
				//braces. Hopefully this will get fixed.
				{
					return macro $i{ className }.instance;
				}
			case TPath(p):
				Context.error(new Printer().printComplexType(TPath(p)) + " is not a supported type.", Context.currentPos());
			default:
				Context.error("getSingleton() called without an expected type", Context.currentPos());
		}
		
		return macro null;
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
