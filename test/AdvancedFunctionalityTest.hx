package;

import Components;
import echoes.ComponentStorage;
import echoes.Echoes;
import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.utils.ComponentTypes;
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
		//Echoes.reset() is called by echoes.test.UTest.
		MethodCounter.reset();
	}
	
	//Tests may be run in any order, but not in parallel.
	
	private function testComponentTypes():Void {
		final types:ComponentTypes = new ComponentTypes();
		types.add(Bool);
		types.add(Bool);
		Assert.equals(1, types.length);
		Assert.isTrue(types.containsComponentStorage(Echoes.getComponentStorage(Bool)));
		
		final stringStorage:DynamicComponentStorage = Echoes.getComponentStorage(String);
		types.addComponentStorage(stringStorage);
		Assert.equals(2, types.length);
		Assert.isTrue(types.contains(String));
		
		types.remove(Bool);
		Assert.isFalse(types.contains(Bool));
		Assert.isTrue(types.contains(String));
		
		types.removeComponentStorage(stringStorage);
		Assert.isFalse(types.contains(String));
	}
	
	private function testCustomStorage():Void {
		Assert.isTrue(Echoes.getComponentStorage(IntArray) is IntArrayStorage);
		Assert.isFalse(Echoes.getComponentStorage((_:Array<Int>)) is IntArrayStorage);
		Assert.isFalse(Echoes.getComponentStorage(EagerIntArray) is IntArrayStorage);
	}
	
	#if !echoes_no_addDynamic
	
	private function testDynamicComponents():Void {
		final entity:Entity = new Entity();
		
		final string:ComponentStorage<String> = Echoes.getComponentStorage(String);
		Assert.isFalse(string.addDynamic(entity, 5));
		Assert.isFalse(string.addDynamic(entity, ["string"]));
		Assert.isFalse(string.exists(entity));
		
		Assert.isTrue(string.addDynamic(entity, "string"));
		Assert.isTrue(string.exists(entity));
		
		final array:ComponentStorage<Array<String>> = Echoes.getComponentStorage((_:Array<String>));
		Assert.isFalse(array.addDynamic(entity, 5));
		Assert.isFalse(array.addDynamic(entity, "string"));
		Assert.isFalse(array.exists(entity));
		
		Assert.isTrue(array.addDynamic(entity, ["string"]));
		Assert.isTrue(array.exists(entity));
		
		Assert.isTrue(array.addDynamic(entity, [1, 2]),
			"Int array was (correctly but unexpectedly) rejected. If Haxe can now distinguish array types, please update the tests and documentation.");
		
		final func:ComponentStorage<() -> Void> = Echoes.getComponentStorage((_:() -> Void));
		Assert.isFalse(func.addDynamic(entity, (x:Int) -> x + 1),
			"Function was accepted despite having the wrong signature.");
		Assert.isFalse(func.addDynamic(entity, () -> trace("Hello, world")),
			"Function with the correct signature was unexpectedly accepted. If functions can now be verified, please update the tests and documentation.");
		
		final dyn:DynamicComponentStorage = new DynamicComponentStorage("component");
		Assert.isTrue(dyn.addDynamic(entity, 5));
		Assert.isTrue(dyn.addDynamic(entity, []));
		Assert.isTrue(dyn.addDynamic(entity, () -> ""));
		
		final bool:DynamicComponentStorage = new DynamicComponentStorage("bool", TBool);
		Assert.isFalse(bool.addDynamic(entity, 5));
		Assert.isFalse(bool.addDynamic(entity, []));
		Assert.isTrue(bool.addDynamic(entity, false));
	}
	
	private function testDynamicViews():Void {
		final component0:DynamicComponentStorage = new DynamicComponentStorage("component0");
		final component1:DynamicComponentStorage = new DynamicComponentStorage("component1");
		
		final view:DynamicView = new DynamicView(component0, component1);
		view.activate();
		var added:String = "";
		view.onAdded.add((entity, components) -> added += components.join(""));
		var removed:String = "";
		view.onRemoved.add((entity, components) -> removed += components.join(""));
		
		final entity0:Entity = new Entity();
		component0.addDynamic(entity0, "---");
		component0.remove(entity0);
		Assert.equals("", added);
		Assert.equals("", removed);
		
		component1.addDynamic(entity0, "b");
		component0.addDynamic(entity0, "a");
		Assert.equals("ab", added);
		Assert.equals("", removed);
		
		final entity1:Entity = new Entity();
		entity1.add("string");
		component0.addDynamic(entity1, 0);
		component1.addDynamic(entity1, 1);
		Assert.equals("ab01", added);
		Assert.equals("", removed);
		
		var updated:String = "";
		view.iter((entity, components) -> updated += components.join(""));
		Assert.equals("ab01", updated);
		
		component1.remove(entity1);
		component1.remove(entity0);
		Assert.equals("ab01", added);
		Assert.equals("01ab", removed);
	}
	
	#end
	
	private function testFindSystem():Void {
		final parent:SystemList = new SystemList();
		final child:SystemList = new SystemList();
		final name:NameSystem = new NameSystem();
		final appearance:AppearanceSystem = new AppearanceSystem();
		
		parent.add(child);
		parent.add(name);
		child.add(appearance);
		
		Assert.equals(name, parent.find(NameSystem));
		Assert.equals(appearance, parent.find(AppearanceSystem));
		
		Assert.equals(null, child.find(NameSystem));
		Assert.equals(appearance, child.find(AppearanceSystem));
	}
	
	private function testGenerics():Void {
		final system:GenericSystem<String, Int> = new GenericSystem<String, Int>();
		system.activate();
		
		final entity:Entity = new Entity();
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
		
		final system = new GenericSystem<Alias<Name>, String>();
		system.activate();
		
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
		Assert.equals("ComponentStorage<StdTypes.Bool>", Std.string(Echoes.getComponentStorage(Bool)));
		Assert.equals("ReadOnlyArray<Bool>", Echoes.getComponentStorage((_:haxe.ds.ReadOnlyArray<Bool>)).shortComponentType);
		
		final entity:Entity = new Entity();
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
		final list:SystemList = new SystemList();
		
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
		final high:HighPrioritySystem = new HighPrioritySystem();
		final middle:NameSystem = new NameSystem();
		final low:NameSystem = new NameSystem(-1);
		
		list.add(low);
		list.add(middle);
		list.add(high);
		assertListContents([high, middle, low]);
		
		//Next, add a system with children.
		final parent:UpdateOrderSystem = new UpdateOrderSystem();
		Assert.equals(0, parent.priority);
		final positiveChild:System = Lambda.find(parent.__children__, child -> child.priority == 1);
		Assert.notNull(positiveChild);
		final negativeChild:System = Lambda.find(parent.__children__, child -> child.priority == -1);
		Assert.notNull(negativeChild);
		
		list.add(parent);
		assertListContents([
			high, positiveChild, //1
			middle, parent, //0
			low, negativeChild //-1
		]);
		
		final updateOrder:Array<String> = [];
		new Entity(true).add(updateOrder);
		list.__activate__();
		list.update(1);
		Assert.equals("pre_update, update, update2, post_update", updateOrder.join(", "));
		
		//Update the priority of existing systems. Setting `low` to -1 should
		//move it to the end of that bracket even though it already was -1.
		parent.priority = 2;
		middle.priority = -1;
		low.priority = -1;
		assertListContents([
			parent, //2
			high, positiveChild, //1
			negativeChild, middle, low //-1
		]);
		
		updateOrder.resize(0);
		list.update(1);
		Assert.equals("update, update2, pre_update, post_update", updateOrder.join(", "));
	}
	
	@:access(echoes.Echoes)
	@:access(echoes.Entity)
	private function testSerialization():Void {
		var addNameCount:Int = 0;
		final named:View<Name> = Echoes.getView(Name);
		named.onAdded.add((entity, name) -> addNameCount++);
		
		final entity0:Entity = new Entity();
		final entity1:Entity = new Entity();
		final entity2:Entity = new Entity();
		
		entity0.add(("zero":Name));
		entity0.add((0xFFFFFF:Color));
		
		entity1.add(("one":Name));
		entity1.add((0.5:Alias<Float>));
		entity1.add(["red", "green", "blue"]);
		
		entity2.add(("two":Name));
		entity2.add((4:Alias<Float>));
		
		Assert.equals(3, addNameCount);
		Assert.equals(3, named.entities.length);
		Assert.same([entity0, entity1, entity2], Echoes.activeEntities);
		
		entity0.deactivate();
		#if echoes_stable_order
		entity1.deactivate();
		entity1.activate();
		#end
		Assert.same([entity2, entity1], Echoes.activeEntities);
		Assert.same([Entity.INACTIVE, 1, 0], Echoes.entityStates);
		
		//Bulk serialization
		
		final data:String = Echoes.serialize();
		Echoes.reset();
		
		addNameCount = 0;
		named.activate();
		named.onAdded.add((entity, name) -> addNameCount++);
		
		Echoes.unserialize(data);
		
		Assert.same([entity2, entity1], Echoes.activeEntities);
		Assert.same([Entity.INACTIVE, 1, 0], Echoes.entityStates);
		Assert.isFalse(entity0.active);
		Assert.isTrue(entity1.active && entity2.active);
		
		Assert.equals("zero", entity0.get(Name));
		Assert.equals(0xFFFFFF, entity0.get(Color));
		
		Assert.equals("one", entity1.get(Name));
		Assert.equals(0.5, entity1.get((_:Alias<Float>)));
		Assert.same(["red", "green", "blue"], entity1.get((_:Array<String>)));
		
		Assert.equals("two", entity2.get(Name));
		Assert.equals(4.0, entity2.get((_:Alias<Float>)));
		
		Assert.equals(2, addNameCount);
		Assert.equals(2, named.entities.length);
		entity0.activate();
		Assert.equals(3, addNameCount);
		Assert.equals(3, named.entities.length);
		
		//Single-component serialization
		
		entity2.remove(Name);
		final data:String = Echoes.getComponentStorage(Name).serialize();
		
		entity0.remove(Name);
		entity1.add(("entity1":Name));
		entity2.add(("":Name));
		
		addNameCount = 0;
		var removeNameCount:Int = 0;
		named.onRemoved.add((entity, name) -> removeNameCount++);
		Echoes.getComponentStorage(Name).unserialize(data);
		
		Assert.equals(2, addNameCount);
		Assert.equals(2, removeNameCount);
		Assert.equals(2, named.entities.length);
		
		Assert.equals("zero", entity0.get(Name));
		Assert.equals("one", entity1.get(Name));
		Assert.isNull(entity2.get(Name));
		
		Assert.isTrue(entity0.getComponents().contains(Name));
		Assert.isTrue(entity1.getComponents().contains(Name));
		Assert.isFalse(entity2.getComponents().contains(Name));
	}
	
	private function testSignals():Void {
		count1 = 0;
		var count2:Int = 0;
		
		#if (hl || cpp)
		Assert.equals(listener1, listener1);
		#else
		//Each time you access an instance method, Haxe will (or used to) create
		//a new closure, meaning `listener1 != listener1`. The only reliable way
		//to compare methods is (or was) via `Reflect`.
		Assert.notEquals(listener1, listener1, "Haxe changed how it handles instance methods.");
		#end
		Assert.isTrue(Reflect.compareMethods(listener1, listener1));
		
		//However, local functions have always worked fine.
		function listener2():Void {
			count2++;
		}
		Assert.equals(listener2, listener2);
		Assert.isTrue(Reflect.compareMethods(listener2, listener2));
		
		//Make a signal.
		final signal:Signal<()->Void> = new Signal();
		
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
		final entity:Entity = new Entity();
		
		entity.add([1, 2, 3]);
		Assert.isFalse(entity.exists(IntArray)); //Regular typedef
		Assert.isTrue(entity.exists(EagerIntArray)); //@:eager typedef
		Assert.isTrue(entity.exists((_:Array<Int>)), null);
	}
	
	private function testViews():Void {
		//Make several entities with varying components.
		final name:Entity = new Entity().add(("name1":Name));
		final shape:Entity = new Entity().add(CIRCLE);
		final colorName:Entity = new Entity().add((0x00FF00:Color), ("name2":Name));
		final colorShape:Entity = new Entity().add((0xFFFFFF:Color), STAR);
		
		//Make some views; each should see a different selection of entities.
		final viewOfName:View<Name> = Echoes.getView(Name);
		Assert.equals(2, viewOfName.entities.length);
		Assert.isTrue(viewOfName.entities.contains(name));
		Assert.isTrue(viewOfName.entities.contains(colorName));
		
		final viewOfShape:View<Shape> = Echoes.getView(Shape);
		Assert.equals(2, viewOfShape.entities.length);
		Assert.isTrue(viewOfShape.entities.contains(shape));
		Assert.isTrue(viewOfShape.entities.contains(colorShape));
		
		//Test `iter()`.
		var joinedNames:String = "";
		viewOfName.iter((e:Entity, n:Name) -> joinedNames += n);
		Assert.equals("name1name2", joinedNames);
		
		//Remove a component.
		colorName.remove(Name);
		Assert.equals(1, viewOfName.entities.length);
		Assert.isFalse(viewOfName.entities.contains(colorName));
		
		//Make a view that's linked to a system.
		final nameSystem:NameSystem = new NameSystem();
		final viewOfColor:View<Color> = nameSystem.getLinkedView(Color);
		Assert.isFalse(viewOfColor.active);
		Assert.equals(0, viewOfColor.entities.length);
		
		//Adding/removing the system should activate/deactivate the linked view.
		nameSystem.activate();
		Assert.isTrue(viewOfColor.active);
		Assert.equals(2, viewOfColor.entities.length);
		Assert.isTrue(viewOfColor.entities.contains(colorName));
		Assert.isTrue(viewOfColor.entities.contains(colorShape));
		
		nameSystem.deactivate();
		Assert.isFalse(viewOfColor.active);
		Assert.equals(0, viewOfColor.entities.length);
	}
	
	private function testViewSignals():Void {
		final entity:Entity = new Entity();
		
		final viewOfShape:View<Shape> = Echoes.getView(Shape);
		
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

@:echoes_storage(new AdvancedFunctionalityTest.IntArrayStorage())
typedef IntArray = Array<Int>;

@:echoes_storage(new AdvancedFunctionalityTest.IntArrayStorage()) //ignored
@:eager typedef EagerIntArray = Array<Int>;

class IntArrayStorage extends ComponentStorage<IntArray> {
	public function new() {
		super("IntArray");
	}
}
