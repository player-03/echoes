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
	
	private override function __update__(dt:Float, priority:Int):Void {
		#if echoes_profiling
		var startTime:Float = haxe.Timer.stamp();
		#end
		
		__dt__ = dt;
		clock.addTime(dt);
		for(step in clock) {
			for(system in systems) {
				system.__update__(step, system.__priority__);
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
			existingSystem.__priority__ < system.__priority__);
		
		if(index >= 0) {
			systems.insert(index, system);
		} else {
			systems.push(system);
		}
		
		system.parent = this;
		
		if(active) {
			system.__activate__();
		}
		
		if(system.__children__ != null) {
			for(child in system.__children__) {
				add(child);
			}
		}
		
		return this;
	}
	
	public function exists(system:System):Bool {
		return systems.contains(system);
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
