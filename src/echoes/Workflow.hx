package echoes;

import echoes.core.ComponentStorage;
import echoes.core.ISystem;
import echoes.core.ReadOnlyData;
import echoes.Entity;
import echoes.View;

class Workflow {
	@:allow(echoes.Entity) @:allow(echoes.core.ComponentStorage)
	private static var componentStorage:Array<DynamicComponentStorage> = [];
	
	@:allow(echoes.Entity)
	private static var _activeEntities:List<Entity> = new List();
	public static var activeEntities(get, never):ReadOnlyList<Entity>;
	private static inline function get_activeEntities():ReadOnlyList<Entity> return _activeEntities;
	
	@:allow(echoes.ViewBase)
	private static var _activeViews:Array<ViewBase> = [];
	public static var activeViews(get, never):ReadOnlyArray<ViewBase>;
	private static inline function get_activeViews():ReadOnlyArray<ViewBase> return _activeViews;
	
	private static var _activeSystems:Array<ISystem> = [];
	public static var activeSystems(get, never):ReadOnlyArray<ISystem>;
	private static inline function get_activeSystems():ReadOnlyArray<ISystem> return _activeSystems;
	
	#if echoes_profiling
	private static var lastUpdateLength:Int = 0;
	#end
	
	private static var lastUpdate:Float = 0;
	
	/**
	 * Returns the workflow statistics:
	 * 
	 * ```text
	 * ( systems count ) { views count } [ entities count | entity cache size ]
	 * ```
	 * 
	 * If `echoes_profiling` is set, additionally returns:
	 * 
	 * ```text
	 *  : update time ms
	 * ( system name ) : update time ms
	 * { view name } [ entities in view ]
	 * ```
	 */
	public static function info():String {
		var ret = '# ( ${activeSystems.length} ) { ${activeViews.length} } [ ${activeEntities.length} | ${Entity.idPool.length} ]'; // TODO version or something
		
		#if echoes_profiling
		ret += ' : $lastUpdateLength ms'; // total
		for(system in activeSystems) {
			ret += '\n${ system.info('    ', 1) }';
		}
		for(view in activeViews) {
			ret += '\n    {$view} [${ view.entities.length }]';
		}
		#end
		
		return ret;
	}
	
	/**
	 * Updates all active systems.
	 */
	public static function update():Void {
		var startTime:Float = haxe.Timer.stamp();
		var dt:Float = startTime - lastUpdate;
		lastUpdate = startTime;
		
		for(system in activeSystems) {
			system.__update__(dt);
		}
		
		#if echoes_profiling
		lastUpdateLength = Std.int((haxe.Timer.stamp() - startTime) * 1000);
		#end
	}
	
	/**
	 * Removes all views, systems and entities from the workflow, and resets the
	 * id sequence.
	 */
	public static function reset():Void {
		for(entity in activeEntities) {
			entity.destroy();
		}
		
		//Iterate backwards when removing items from arrays.
		var i:Int = activeSystems.length;
		while(--i >= 0) {
			removeSystem(activeSystems[i]);
		}
		i = activeViews.length;
		while(--i >= 0) {
			activeViews[i].reset();
		}
		for(storage in componentStorage) {
			storage.clear();
		}
		
		Entity.idPool.resize(0);
		Entity.statuses.resize(0);
		
		Entity.nextId = 0;
	}
	
	//System management
	//=================
	
	public static function addSystem(system:ISystem):Void {
		if(!hasSystem(system)) {
			_activeSystems.push(system);
			system.__activate__();
		}
	}
	
	public static function removeSystem(system:ISystem):Void {
		if(_activeSystems.remove(system)) {
			system.__deactivate__();
		}
	}
	
	public static inline function hasSystem(system:ISystem):Bool {
		return activeSystems.contains(system);
	}
}
