package echoes;

import echoes.core.ISystem;
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
@:allow(echoes)
class SystemList implements ISystem {
	#if echoes_profiling
	private var lastUpdateLength:Int = 0;
	#end
	
	private var name:String;
	
	private var systems:Array<ISystem> = [];
	
	private var activated:Bool = false;
	
	private var timestep:Timestep;
	
	public function new(?name = "SystemList", ?timestep:Timestep) {
		this.name = name;
		this.timestep = timestep != null ? timestep : new Timestep();
	}
	
	@:noCompletion public function __activate__():Void {
		if(!activated) {
			activated = true;
			for(system in systems) {
				system.__activate__();
			}
		}
	}
	
	@:noCompletion public function __deactivate__():Void {
		if(activated) {
			activated = false;
			for(system in systems) {
				system.__deactivate__();
			}
		}
	}
	
	@:noCompletion public function __update__(dt:Float):Void {
		#if echoes_profiling
		var startTime:Float = haxe.Timer.stamp();
		#end
		
		timestep.advance(dt);
		for(step in timestep) {
			for(system in systems) {
				system.__update__(step);
			}
		}
		
		#if echoes_profiling
		lastUpdateLength = Std.int((haxe.Timer.stamp() - startTime) * 1000);
		#end
	}
	
	public function isActive():Bool {
		return activated;
	}
	
	public function info(?indent:String = "    ", ?level:Int = 0):String {
		var result:StringBuf = new StringBuf();
		for(i in 0...level) {
			result.add(indent);
		}
		
		result.add(name);
		
		#if echoes_profiling
		result.add(' : $lastUpdateLength ms');
		#end
		
		for(system in systems) {
			result.add('\n${ system.info(indent, level + 1) }');
		}
		
		return result.toString();
	}
	
	public function add(system:ISystem):SystemList {
		if(!exists(system)) {
			systems.push(system);
			if(activated) {
				system.__activate__();
			}
		}
		
		return this;
	}
	
	public function remove(system:ISystem):SystemList {
		if(exists(system)) {
			systems.remove(system);
			if(activated) {
				system.__deactivate__();
			}
		}
		
		return this;
	}
	
	public function exists(system:ISystem):Bool {
		return systems.contains(system);
	}
	
	public function toString():String return name;
}
