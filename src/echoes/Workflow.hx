package echoes;

import echoes.Entity.Status;
import echoes.core.AbstractView;
import echoes.core.ICleanableComponentContainer;
import echoes.core.ISystem;
import echoes.core.ReadOnlyData;

class Workflow {
	@:allow(echoes.Entity) static inline var INVALID_ID = -1;
	
	private static var nextId = INVALID_ID + 1;
	
	private static var idPool = new Array<Int>();
	
	private static var statuses = new Array<Status>();
	
	// all of every defined component container
	private static var definedContainers = new Array<ICleanableComponentContainer>();
	// all of every defined view
	private static var definedViews = new Array<AbstractView>();
	
	private static var _activeEntities:List<Entity> = new List();
	public static var activeEntities(get, never):ReadOnlyList<Entity>;
	private static inline function get_activeEntities():ReadOnlyList<Entity> return _activeEntities;
	
	@:allow(echoes.core.AbstractView)
	private static var _activeViews:Array<AbstractView> = [];
	public static var activeViews(get, never):ReadOnlyArray<AbstractView>;
	private static inline function get_activeViews():ReadOnlyArray<AbstractView> return _activeViews;
	
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
		var ret = '# ( ${activeSystems.length} ) { ${activeViews.length} } [ ${activeEntities.length} | ${idPool.length} ]'; // TODO version or something
		
		#if echoes_profiling
		ret += ' : $lastUpdateLength ms'; // total
		for(s in activeSystems) {
			ret += '\n${ s.info('    ', 1) }';
		}
		for(v in activeViews) {
			ret += '\n    {$v} [${ v.entities.length }]';
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
		
		for(s in activeSystems) {
			s.__update__(dt);
		}
		
		#if echoes_profiling
		lastUpdateLength = Std.int((haxe.Timer.stamp() - startTime) * 1000);
		#end
	}
	
	/**
	 * Removes all views, systems and entities from the workflow, and resets the
	 * id sequence.
	 */
	public static function reset() {
		for(e in activeEntities) {
			e.destroy();
		}
		for(s in activeSystems) {
			removeSystem(s);
		}
		for(v in definedViews) {
			v.reset();
		}
		for(c in definedContainers) {
			c.reset();
		}
		
		idPool.splice(0, idPool.length);
		statuses.splice(0, statuses.length);
		
		nextId = INVALID_ID + 1;
	}
	
	// System
	
	public static function addSystem(s:ISystem) {
		if(!hasSystem(s)) {
			_activeSystems.push(s);
			s.__activate__();
		}
	}
	
	public static function removeSystem(s:ISystem) {
		if(hasSystem(s)) {
			s.__deactivate__();
			_activeSystems.remove(s);
		}
	}
	
	public static inline function hasSystem(s:ISystem):Bool {
		return activeSystems.contains(s);
	}
	
	// Entity
	
	@:allow(echoes.Entity) static function id(immediate:Bool):Int {
		var id = idPool.pop();
		
		if(id == null) {
			id = nextId++;
		}
		
		if(immediate) {
			statuses[id] = Active;
			_activeEntities.add(id);
		} else {
			statuses[id] = Inactive;
		}
		return id;
	}
	
	@:allow(echoes.Entity) static function cache(id:Int) {
		// Active or Inactive
		if(status(id) < Cached) {
			removeAllComponentsOf(id);
			_activeEntities.remove(id);
			idPool.push(id);
			statuses[id] = Cached;
		}
	}
	
	@:allow(echoes.Entity) static function add(id:Int) {
		if(status(id) == Inactive) {
			statuses[id] = Active;
			_activeEntities.add(id);
			for(v in activeViews) v.addIfMatched(id);
		}
	}
	
	@:allow(echoes.Entity) static function remove(id:Int) {
		if(status(id) == Active) {
			for(v in activeViews) v.removeIfExists(id);
			_activeEntities.remove(id);
			statuses[id] = Inactive;
		}
	}
	
	@:allow(echoes.Entity) static inline function status(id:Int):Status {
		return statuses[id];
	}
	
	@:allow(echoes.Entity) static inline function removeAllComponentsOf(id:Int) {
		if(status(id) == Active) {
			for(v in activeViews) {
				v.removeIfExists(id);
			}
		}
		for(c in definedContainers) {
			c.remove(id);
		}
	}
	
	@:allow(echoes.Entity) static inline function printAllComponentsOf(id:Int):String {
		var ret = '#$id:';
		for(c in definedContainers) {
			if(c.exists(id)) {
				ret += '${ c.print(id) },';
			}
		}
		return ret.substr(0, ret.length - 1);
	}
}
