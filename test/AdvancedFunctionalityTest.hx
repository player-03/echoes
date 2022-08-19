package;

import Components;
import echoes.Echoes;
import echoes.Entity;
import echoes.utils.Signal;
import echoes.View;
import Systems;
import utest.Assert;
import utest.Test;

@:depends(BasicFunctionalityTest)
class AdvancedFunctionalityTest extends Test {
	private function teardown():Void {
		Echoes.reset();
		MethodCounter.reset();
	}
	
	private function testSignals():Void {
		//Haxe creates a new closure each time you access an instance method,
		//meaning `function1 != function1`.
		Assert.notEquals(function1, function1, "Haxe changed how it handles closures.");
		Assert.isTrue(Reflect.compareMethods(function1, function1));
		
		//Make some listener functions.
		var count1:Int = 0;
		var count2:Int = 0;
		
		function function1():Void {
			count1++;
		}
		function function2():Void {
			count2++;
		}
		
		//Make a signal.
		var signal:Signal<()->Void> = new Signal();
		
		signal.push(function1);
		Assert.isTrue(signal.contains(function1));
		Assert.isTrue(signal.contains(function1));
		
		signal.push(function2);
		Assert.isTrue(signal.contains(function2));
		
		//Dispatch it.
		signal.dispatch();
		Assert.equals(1, count1);
		Assert.equals(1, count2);
		
		//Remove a function and dispatch again.
		signal.remove(function1);
		Assert.isFalse(signal.contains(function1));
		
		signal.dispatch();
		Assert.equals(1, count1);
		Assert.equals(2, count2);
	}
	
	private function testTypeParameters():Void {
		var entity:Entity = new Entity();
		
		entity.add([1, 2, 3]);
		Assert.isFalse(entity.exists(IntArray)); //Regular typedef
		Assert.isTrue(entity.exists(EagerIntArray)); //@:eager typedef
		Assert.isTrue(entity.exists((_:Array<Int>)));
	}
	
	private function testViews():Void {
		//Make several entities with varying components.
		var name:Entity = new Entity().add(("name1":Name));
		var shape:Entity = new Entity().add(CIRCLE);
		var colorName:Entity = new Entity().add((0x00FF00:Color), ("name2":Name));
		var colorShape:Entity = new Entity().add((0xFFFFFF:Color), STAR);
		
		//Make some views; each should see a different selection of entities.
		var viewOfName:View<Name> = Echoes.getView();
		Assert.equals(2, viewOfName.entities.length);
		Assert.isTrue(viewOfName.entities.has(name));
		Assert.isTrue(viewOfName.entities.has(colorName));
		
		var viewOfShape:View<Shape> = Echoes.getView();
		Assert.equals(2, viewOfShape.entities.length);
		Assert.isTrue(viewOfShape.entities.has(shape));
		Assert.isTrue(viewOfShape.entities.has(colorShape));
		
		//Test iter().
		var joinedNames:String = "";
		viewOfName.iter((e:Entity, n:Name) -> joinedNames += n);
		Assert.equals("name1name2", joinedNames);
		
		//Remove a component.
		colorName.remove(Name);
		Assert.equals(1, viewOfName.entities.length);
		Assert.isFalse(viewOfName.entities.has(colorName));
		
		//Make a view that's linked to a system.
		var nameSystem:NameSystem = new NameSystem();
		var viewOfColor:View<Color> = nameSystem.makeLinkedView();
		Assert.isFalse(viewOfColor.active);
		Assert.equals(0, viewOfColor.entities.length);
		
		//Adding/removing the system should activate/deactivate the linked view.
		Echoes.addSystem(nameSystem);
		Assert.isTrue(viewOfColor.active);
		Assert.equals(2, viewOfColor.entities.length);
		Assert.isTrue(viewOfColor.entities.has(colorName));
		Assert.isTrue(viewOfColor.entities.has(colorShape));
		
		Echoes.removeSystem(nameSystem);
		Assert.isFalse(viewOfColor.active);
		Assert.equals(0, viewOfColor.entities.length);
	}
	
	private function testViewSignals():Void {
		var entity:Entity = new Entity();
		
		var viewOfShape:View<Shape> = Echoes.getView();
		
		var signalDispatched:Bool = false;
		function listener(e:Entity, s:Shape):Void {
			Assert.equals(entity, e);
			Assert.equals(STAR, s);
			
			signalDispatched = true;
		}
		
		//Test onAdded.
		viewOfShape.onAdded.push(listener);
		
		entity.add(STAR);
		Assert.isTrue(signalDispatched);
		
		//Test onRemoved.
		viewOfShape.onRemoved.push(listener);
		signalDispatched = false;
		
		entity.removeAll();
		Assert.isTrue(signalDispatched);
	}
}

typedef IntArray = Array<Int>;
@:eager typedef EagerIntArray = Array<Int>;
