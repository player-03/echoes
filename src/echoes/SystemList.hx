package echoes;

import echoes.Echoes.SystemDetails;
import echoes.utils.Clock;

/**
 * A group of systems, to help with organization.
 * 
 * ```haxe
 * var physics:SystemList = new SystemList("Physics");
 * physics.add(new MovementSystem());
 * physics.add(new CollisionSystem());
 * Echoes.add(physics);
 * ```
 * 
 * Because `SystemList` extends `System`, you can add one `SystemList` to
 * another. However, `@:add`, `@:update`, and `@:remove` events are disabled for
 * `SystemList` and its subclasses.
 */
@:allow(echoes) @:skipBuildMacro
class SystemList extends System {
	public final clock:Clock;
	
	public var length(get, never):Int;
	private inline function get_length():Int {
		return systems.length;
	}
	
	public var name:String;
	
	public var paused(get, set):Bool;
	private inline function get_paused():Bool {
		return clock.paused;
	}
	private inline function set_paused(value:Bool):Bool {
		return clock.paused = paused;
	}
	
	private var systems:Array<System> = [];
	
	public function new(?name:String = "SystemList", ?clock:Clock, ?priority:Int = 0) {
		super(priority);
		
		this.name = name;
		this.clock = clock != null ? clock : new Clock();
	}
	
	private override function __activate__():Void {
		if(!active) {
			for(system in systems) {
				system.__activate__();
			}
			
			super.__activate__();
		}
	}
	
	private override function __deactivate__():Void {
		if(active) {
			for(system in systems) {
				system.__deactivate__();
			}
			
			super.__deactivate__();
		}
	}
	
	private function __recalculateOrder__(system:System):Void {
		if(systems.remove(system)) {
			var index:Int = Lambda.findIndex(systems, existingSystem ->
				existingSystem.priority < system.priority);
			
			if(index >= 0) {
				systems.insert(index, system);
			} else {
				systems.push(system);
			}	
		}
	}
	
	private override function __update__(dt:Float):Void {
		#if echoes_profiling
		var startTime:Float = haxe.Timer.stamp();
		#end
		
		__dt__ = dt;
		clock.addTime(dt);
		for(step in clock) {
			for(system in systems) {
				system.__update__(step);
			}
		}
		
		#if echoes_profiling
		__updateTime__ = Std.int((haxe.Timer.stamp() - startTime) * 1000);
		#end
	}
	
	/**
	 * Adds the given system to this list.
	 */
	public function add(system:System):SystemList {
		if(system.parent != null) {
			if(system.parent == this) {
				return this;
			}
			
			system.parent.remove(system);
		}
		
		var index:Int = Lambda.findIndex(systems, existingSystem ->
			existingSystem.priority < system.priority);
		
		if(index >= 0) {
			systems.insert(index, system);
		} else {
			systems.push(system);
		}
		
		system.parent = this;
		
		if(active) {
			system.__activate__();
		}
		
		for(child in system.__children__) {
			add(child);
		}
		
		return this;
	}
	
	/**
	 * Returns whether this list directly contains the given system.
	 * @see `find()` if you need to recursively search child lists.
	 */
	public inline function exists(system:System):Bool {
		return system.parent == this;
	}
	
	/**
	 * Searches this list and all child lists for a system of the given type,
	 * returning it if found.
	 */
	public override function find<T:System>(systemType:Class<T>):Null<T> {
		for(child in systems) {
			var result:Null<T> = child.find(systemType);
			
			if(result != null) {
				return result;
			}
		}
		
		return null;
	}
	
	public override function getStatistics():SystemDetails {
		var result:SystemDetails = super.getStatistics();
		result.children = [for(system in systems) system.getStatistics()];
		return result;
	}
	
	public inline function iterator():Iterator<System> {
		return systems.iterator();
	}
	
	public inline function keyValueIterator():KeyValueIterator<Int, System> {
		return systems.keyValueIterator();
	}
	
	public function remove(system:System):SystemList {
		if(systems.remove(system)) {
			system.__deactivate__();
			
			system.parent = null;
			
			if(system.__children__ != null) {
				for(child in system.__children__) {
					remove(child);
				}
			}
		}
		
		return this;
	}
	
	public function removeAll():SystemList {
		for(system in systems) {
			system.__deactivate__();
		}
		systems.resize(0);
		
		return this;
	}
	
	public override function toString():String {
		return name;
	}
}
