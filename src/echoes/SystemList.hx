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
 */
@:allow(echoes) @:skipBuildMacro
class SystemList extends System {
	public var length(get, never):Int;
	private inline function get_length():Int {
		return systems.length;
	}
	
	private var name:String;
	
	private var systems:Array<System> = [];
	
	private var clock:Clock;
	
	public function new(?name:String = "SystemList", ?clock:Clock) {
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
	
	/**
	 * Adds the given system to this list.
	 * @param before If any of these `System` subclasses already exist in the
	 * list, the new system will be inserted before the first.
	 */
	public function add(system:System):SystemList {
		if(!exists(system)) {
			var index:Int = Lambda.findIndex(systems, existingSystem ->
				existingSystem.priority < system.priority);
			
			if(index >= 0) {
				systems.insert(index, system);
			} else {
				systems.push(system);
			}
			
			if(active) {
				system.__activate__();
			}
		}
		
		return this;
	}
	
	public function remove(system:System):SystemList {
		if(exists(system)) {
			systems.remove(system);
			system.__deactivate__();
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
	
	public function exists(system:System):Bool {
		return systems.contains(system);
	}
	
	public override function toString():String {
		return name;
	}
}
