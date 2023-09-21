package;

import Components;
import echoes.Echoes;
import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.utils.Signal;
import echoes.View;
import haxe.PosInfos;
import MethodCounter.assertTimesCalled;
import Systems;
import utest.Assert;
import utest.Test;

@:depends(BasicFunctionalityTest)
class AdvancedFunctionalityTest extends Test {
	private var count1:Int = 0;
	
	private function listener1():Void {
		count1++;
	}
	
	private function teardown():Void {
		Echoes.reset();
		MethodCounter.reset();
	}
	
	//Tests may be run in any order, but not in parallel.
	
	private function testEntityTemplates():Void {
		Echoes.addSystem(new NameSystem());
		Echoes.addSystem(new AppearanceSystem());
		
		var entity:Entity = new Entity();
		entity.add(("John":Name));
		
		var namedEntity:NamedEntity = NamedEntity.applyTemplateTo(entity);
		Assert.equals(entity, namedEntity);
		Assert.equals("John", namedEntity.name);
		assertTimesCalled(1, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		
		namedEntity.name = null;
		Assert.equals(null, namedEntity.name);
		assertTimesCalled(1, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSystem.nameRemoved");
		
		var visualEntity:VisualEntity = VisualEntity.applyTemplateTo(namedEntity);
		Assert.equals(VisualEntity.DEFAULT_COLOR, visualEntity.color);
		assertTimesCalled(1, "AppearanceSystem.colorAdded");
		assertTimesCalled(0, "AppearanceSystem.colorRemoved");
		
		Assert.equals(VisualEntity.DEFAULT_SHAPE, (visualEntity:Entity).get(Shape));
		
		Assert.equals(NamedEntity.DEFAULT_NAME, new NamedEntity().name);
		Assert.notEquals(NamedEntity.DEFAULT_NAME, new NamedEntity("not default").name);
		assertTimesCalled(3, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSystem.nameRemoved");
		
		Assert.equals(NameStringEntity.DEFAULT_NAME, new NameStringEntity().name);
		assertTimesCalled(4, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSystem.nameRemoved");
	}
	
	private function testFindSystem():Void {
		var parent:SystemList = new SystemList();
		var child:SystemList = new SystemList();
		var name:NameSystem = new NameSystem();
		var appearance:AppearanceSystem = new AppearanceSystem();
		
		parent.add(child);
		parent.add(name);
		child.add(appearance);
		
		Assert.equals(name, parent.find(NameSystem));
		Assert.equals(appearance, parent.find(AppearanceSystem));
		
		Assert.equals(null, child.find(NameSystem));
		Assert.equals(appearance, child.find(AppearanceSystem));
	}
	
	private function testGenerics():Void {
		var system:GenericSystem<String, Int> = new GenericSystem<String, Int>();
		Echoes.addSystem(system);
		
		var entity:Entity = new Entity();
		entity.add("STRING");
		entity.add(0);
		switch(system.record) {
			case ["string0"]:
				Assert.pass();
			default:
				Assert.fail("Incorrect record: " + system.record);
		}
		
		entity.add(3);
		switch(system.record) {
			case ["string0", "string3"]:
				Assert.pass();
			default:
				Assert.fail("Incorrect record: " + system.record);
		}
		
		var system = new GenericSystem<Alias<Name>, String>();
		Echoes.addSystem(system);
		
		entity.add(("NAME":Alias<Name>));
		switch(system.record) {
			//Only the first component should be converted to lowercase.
			case ["nameSTRING"]:
				Assert.pass();
			default:
				Assert.fail("Incorrect record: " + system.record);
		}
	}
	
	private function testGetComponentStorage():Void {
		//`String` and `Array` are already fully-qualified, but `Bool` is short
		//for `StdTypes.Bool`.
		Assert.equals("String", Echoes.getComponentStorage(String).componentType);
		Assert.equals("Array<StdTypes.Bool>", Echoes.getComponentStorage((_:Array<Bool>)).componentType);
		
		var entity:Entity = new Entity();
		entity.add(["xyz"]);
		switch(Echoes.getComponentStorage((_:Array<String>)).get(entity)) {
			case ["xyz"]:
				Assert.pass();
			case x:
				Assert.fail('Expected ["xyz"], got $x');
		}
	}
	
	@:access(echoes.System)
	private function testPriority():Void {
		var list:SystemList = new SystemList();
		
		inline function assertListContents(contents:Array<System>, ?pos:PosInfos):Void {
			if(Assert.equals(contents.length, list.length,
				'Expected ${ contents.length } systems; got ${ list.length }.', pos)) {
				for(i in 0...contents.length) {
					if(contents[i] != list.systems[i]) {
						Assert.fail('Expected $contents, got ${ list.systems } (index $i differs).', pos);
						break;
					}
				}
			}
		}
		
		//Add systems from low to high priority.
		var high:HighPrioritySystem = new HighPrioritySystem();
		var middle:NameSystem = new NameSystem();
		var low:NameSystem = new NameSystem(-1);
		
		list.add(low);
		list.add(middle);
		list.add(high);
		assertListContents([high, middle, low]);
		
		//Next, add a system with children.
		var parent:UpdateOrderSystem = new UpdateOrderSystem();
		Assert.equals(0, parent.priority);
		Assert.equals(1, parent.__children__[0].priority);
		Assert.equals(-1, parent.__children__[1].priority);
		
		list.add(parent);
		assertListContents([
			high, parent.__children__[0], //1
			middle, parent, //0
			low, parent.__children__[1] //-1
		]);
		
		var updateOrder:Array<String> = [];
		new Entity(true).add(updateOrder);
		list.__activate__();
		list.__update__(1);
		Assert.equals("pre_update, update, update2, post_update", updateOrder.join(", "));
		
		//Update the priority of existing systems. Setting `low` to -1 should
		//move it to the end of that bracket even though it already was -1.
		parent.priority = 2;
		middle.priority = -1;
		low.priority = -1;
		assertListContents([
			parent, //2
			high, parent.__children__[0], //1
			parent.__children__[1], middle, low //-1
		]);
		
		updateOrder.resize(0);
		list.__update__(1);
		Assert.equals("update, update2, pre_update, post_update", updateOrder.join(", "));
	}
	
	private function testSignals():Void {
		count1 = 0;
		var count2:Int = 0;
		
		#if !hl
		//Each time you access an instance method, Haxe will create a new
		//closure, meaning `listener1 != listener1`. The only reliable way to
		//compare methods is via `Reflect`.
		Assert.notEquals(listener1, listener1, "Haxe changed how it handles instance methods.");
		#end
		Assert.isTrue(Reflect.compareMethods(listener1, listener1));
		
		//However, local functions work fine.
		function listener2():Void {
			count2++;
		}
		Assert.equals(listener2, listener2);
		Assert.isTrue(Reflect.compareMethods(listener2, listener2));
		
		//Make a signal.
		var signal:Signal<()->Void> = new Signal();
		
		signal.push(listener1);
		Assert.isTrue(signal.contains(listener1));
		
		signal.push(listener2);
		Assert.isTrue(signal.contains(listener2));
		
		//Dispatch it.
		signal.dispatch();
		Assert.equals(1, count1);
		Assert.equals(1, count2);
		
		//Remove a function and dispatch again.
		signal.remove(listener1);
		Assert.isFalse(signal.contains(listener1));
		
		signal.dispatch();
		Assert.equals(1, count1);
		Assert.equals(2, count2);
	}
	
	private function testTypeParameters():Void {
		var entity:Entity = new Entity();
		
		entity.add([1, 2, 3]);
		Assert.isFalse(entity.exists(IntArray)); //Regular typedef
		Assert.isTrue(entity.exists(EagerIntArray)); //@:eager typedef
		Assert.isTrue(entity.exists((_:Array<Int>)), null);
	}
	
	private function testViews():Void {
		//Make several entities with varying components.
		var name:Entity = new Entity().add(("name1":Name));
		var shape:Entity = new Entity().add(CIRCLE);
		var colorName:Entity = new Entity().add((0x00FF00:Color), ("name2":Name));
		var colorShape:Entity = new Entity().add((0xFFFFFF:Color), STAR);
		
		//Make some views; each should see a different selection of entities.
		var viewOfName:View<Name> = Echoes.getView(Name);
		Assert.equals(2, viewOfName.entities.length);
		Assert.isTrue(viewOfName.entities.has(name));
		Assert.isTrue(viewOfName.entities.has(colorName));
		
		var viewOfShape:View<Shape> = Echoes.getView(Shape);
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
		var viewOfColor:View<Color> = nameSystem.getLinkedView(Color);
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
		
		var viewOfShape:View<Shape> = Echoes.getView(Shape);
		
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

typedef Alias<T> = T;
typedef IntArray = Array<Int>;
@:eager typedef EagerIntArray = Array<Int>;
