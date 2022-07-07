package echoes;

import echoes.utils.Timestep;

/**
 * A group of systems, to help with organization.
 * 
 * ```haxe
 * var physics:SystemList = new SystemList("Physics");
 * physics.add(new MovementSystem());
 * physics.add(new CollisionSystem());
 * Workflow.add(physics);
 * ```
 */
@:allow(echoes) @:skipBuildMacro
class SystemList extends System {
	private var name:String;
	
	private var systems:Array<System> = [];
	
	private var timestep:Timestep;
	
	public function new(?name:String = "SystemList", ?timestep:Timestep) {
		this.name = name;
		this.timestep = timestep != null ? timestep : new Timestep();
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
		timestep.advance(dt);
		for(step in timestep) {
			for(system in systems) {
				system.__update__(step);
			}
		}
		
		#if echoes_profiling
		__updateTime__ = Std.int((haxe.Timer.stamp() - startTime) * 1000);
		#end
	}
	
	public override function info(?indent:String = "    ", ?level:Int = 0):String {
		var result:StringBuf = new StringBuf();
		result.add(super.info(indent, level));
		
		for(system in systems) {
			result.add('\n${ system.info(indent, level + 1) }');
		}
		
		return result.toString();
	}
	
	public function add(system:System):SystemList {
		if(!exists(system)) {
			systems.push(system);
			if(active) {
				system.__activate__();
			}
		}
		
		return this;
	}
	
	public function remove(system:System):SystemList {
		if(exists(system)) {
			systems.remove(system);
			if(active) {
				system.__deactivate__();
			}
		}
		
		return this;
	}
	
	public function exists(system:System):Bool {
		return systems.contains(system);
	}
	
	public override function toString():String {
		return name;
	}
}
