package;

import Components;
import echoes.Echoes;
import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.utils.Signal;
import echoes.View;
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
	
	private function testAbstractEntities():Void {
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
		assertTimesCalled(2, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSystem.nameRemoved");
	}
	
	@:access(echoes.System)
	private function testPriority():Void {
		var list:SystemList = new SystemList();
		
		var high:HighPrioritySystem = new HighPrioritySystem();
		var name:NameSystem = new NameSystem();
		var low:LowPrioritySystem = new LowPrioritySystem();
		
		Assert.equals(high.__priority__, 1);
		Assert.equals(name.__priority__, 0);
		Assert.equals(low.__priority__, -1);
		
		list.add(low);
		list.add(name);
		list.add(high);
		
		Assert.equals(3, list.length);
		Assert.equals(high, list.systems[0]);
		Assert.equals(name, list.systems[1]);
		Assert.equals(low, list.systems[2]);
		
		//Also test a system that comes with different-priority children.
		var parent:UpdateOrderSystem = new UpdateOrderSystem();
		Assert.equals(parent.__priority__, 0);
		
		list.add(parent);
		Assert.equals(6, list.length);
		Assert.equals(high, list.systems[0]);
		Assert.equals(parent.__children__[1], list.systems[1]);
		Assert.equals(name, list.systems[2]);
		Assert.equals(parent, list.systems[3]);
		Assert.equals(low, list.systems[4]);
		Assert.equals(parent.__children__[0], list.systems[5]);
		
		var updateOrder:Array<String> = [];
		new Entity(true).add(updateOrder);
		list.__activate__();
		list.__update__(1, 0);
		Assert.equals("pre_update, update, update2, post_update", updateOrder.join(", "));
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
		Assert.isTrue(entity.exists((_:Array<Int>)));
	}
	
	private function testViews():Void {
		//Make several entities with varying components.
		var name:Entity = new Entity().add(("name1":Name));
		var shape:Entity = new Entity().add(CIRCLE);
		var colorName:Entity = new Entity().add((0x00FF00:Color), ("name2":Name));
		var colorShape:Entity = new Entity().add((0xFFFFFF:Color), STAR);
		
		//Make some views; each should see a different selection of entities.
		var viewOfName:View<Name> = Echoes.getSingleton();
		Assert.equals(2, viewOfName.entities.length);
		Assert.isTrue(viewOfName.entities.has(name));
		Assert.isTrue(viewOfName.entities.has(colorName));
		
		var viewOfShape:View<Shape> = Echoes.getSingleton();
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
		
		var viewOfShape:View<Shape> = Echoes.getSingleton();
		
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

@:build(echoes.Entity.build())
abstract NamedEntity(Entity) {
	public static inline final DEFAULT_NAME:Name = "defaultName";
	
	public var name:Name = DEFAULT_NAME;
}

@:build(echoes.Entity.build())
abstract NameStringEntity(NamedEntity) {
	public static inline final DEFAULT_STRING:String = "defaultString";
	
	public var string:String = DEFAULT_STRING;
}

@:build(echoes.Entity.build())
abstract VisualEntity(Entity) {
	public static inline final DEFAULT_COLOR:Color = 0x123456;
	public static inline final DEFAULT_SHAPE:Shape = SQUARE;
	
	public var color(never, never):Color = DEFAULT_COLOR;
	public var shape = Shape.SQUARE;
}
