package;

import haxe.extern.EitherType;
import Components;
import echoes.Entity;
import echoes.System;
import MethodCounter;

class AppearanceSystem extends System implements IMethodCounter {
	@:a private function colorAdded(color:Color):Void {}
	@:u private function colorUpdated(color:Color):Void {}
	@:r private function colorRemoved(color:Color):Void {}
	
	@:add private function shapeAdded(shape:Shape, entity:Entity):Void {}
	@:upd private function shapeUpdated(shape:Shape, entity:Entity):Void {}
	@:rem private function shapeRemoved(shape:Shape, entity:Entity):Void {}
	
	@:added private function colorAndShapeAdded(shape:Shape, color:Color):Void {}
	@:updated private function colorAndShapeUpdated(shape:Shape, color:Color):Void {}
	@:removed private function colorAndShapeRemoved(shape:Shape, color:Color):Void {}
}

@:genericBuild(echoes.macro.SystemBuilder.genericBuild())
class GenericSystem<S:String, I:EitherType<Int, String>> extends System {
	public var record:Array<S>;
	
	@:add private function onAdded(s:S, i:I, entity:Entity):Void {
		if(record == null) {
			record = new Array<S>();
		}
		
		record.push(s + i);
		
		if(!entity.exists((_:Array<S>))) {
			entity.add(record);
		}
	}
}

@:priority(1)
class HighPrioritySystem extends System {
	public function new();
	
	@:update private function update():Void {}
}

@:priority(-1)
class LowPrioritySystem extends System {
}

class NameSystem extends System implements IMethodCounter {
	@:add private function nameAdded(name:Name):Void {}
	@:update private function nameUpdated(name:Name):Void {}
	@:remove private function nameRemoved(name:Name):Void {}
}

class OptionalComponentSystem extends System implements IMethodCounter {
	@:add private function colorAndNameAdded(color:Color, ?shape:Shape, name:Name):Void {}
	@:update private function colorAndNameUpdated(color:Color, ?shape:Shape, name:Name):Void {}
	@:remove private function colorAndNameRemoved(color:Color, ?shape:Shape, name:Name):Void {}
}

class TimeCountSystem extends System implements IMethodCounter {
	public var colorTime:Float = 0;
	public var shapeTime:Float = 0;
	public var colorAndShapeTime:Float = 0;
	public var totalTime:Float = 0;
	
	@:update private function colorUpdated(color:Color, time:Float):Void {
		colorTime += time;
	}
	
	@:update private function shapeUpdated(shape:Shape, time:Float):Void {
		shapeTime += time;
	}
	
	@:update private function colorAndShapeUpdated(color:Color, shape:Shape, time:Float):Void {
		colorAndShapeTime += time;
	}
	
	@:update private function update(time:Float):Void {
		totalTime += time;
	}
}

class UpdateOrderSystem extends System {
	@:update @:priority(-1) private function post_update(order:Array<String>):Void {
		order.push("post_update");
	}
	
	@:update private function update(order:Array<String>):Void {
		order.push("update");
	}
	
	@:update @:priority(1) private function pre_update(order:Array<String>):Void {
		order.push("pre_update");
	}
	
	@:update private function update2(order:Array<String>):Void {
		order.push("update2");
	}
}
