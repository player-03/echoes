package;

import Components;
import echoes.Echoes;
import echoes.Entity;
import echoes.SystemList;
import echoes.Time;
import echoes.utils.Clock;
import MethodCounter.assertTimesCalled;
import Systems;
import utest.Assert;
import utest.Test;

class BasicFunctionalityTest extends Test {
	private function teardown():Void {
		Echoes.reset();
		MethodCounter.reset();
	}
	
	//Tests may be run in any order, but not in parallel.
	
	#if (echoes_storage != "Map")
	#if !eval
	//Test an array-specific edge case that potentially breaks every other test.
	//If this fails on any target, update `ComponentStorage.clear()`, then skip
	//this test on that target.
	private function testArrayBehavior():Void {
		final array:Array<Null<Int>> = [for(i in 0...5) i];
		Assert.equals(2, array[2]);
		Assert.isNull(array[6]);
		
		array.resize(0);
		Assert.isNull(array[2]);
		
		array[3] = 30;
		Assert.isNull(array[2]); //<- The only test likely to fail.
		Assert.equals(30, array[3]);
		Assert.isNull(array[4]);
	}
	#end
	#end
	
	private function testEntities():Void {
		//Make an inactive entity.
		final entity:Entity = new Entity(false);
		Assert.isFalse(entity.active);
		Assert.equals(0, Echoes.activeEntities.length);
		Assert.equals(0, entity.id);
		
		//Activate it.
		entity.activate();
		Assert.isTrue(entity.active);
		Assert.isFalse(entity.destroyed);
		Assert.equals(1, Echoes.activeEntities.length);
		
		//Add a component.
		entity.add(STAR);
		Assert.isTrue(entity.exists(Shape));
		
		//Deactivate the entity.
		entity.deactivate();
		Assert.isTrue(entity.exists(Shape));
		
		//Add and remove a component while inactive.
		entity.add(("entity":Name));
		Assert.isTrue(entity.exists(Name));
		
		entity.remove(Name);
		Assert.isFalse(entity.exists(Name));
		
		//Destroy it.
		entity.destroy();
		Assert.isFalse(entity.exists(Shape));
		Assert.isTrue(entity.destroyed);
		Assert.equals(1, @:privateAccess Entity.idPool.length);
		
		//Make a new entity (should use the same ID as the old).
		final newEntity:Entity = new Entity();
		Assert.equals(entity, newEntity);
		Assert.equals(0, @:privateAccess Entity.idPool.length);
		Assert.equals(0, newEntity.id);
	}
	
	private function testComponents():Void {
		//Create the entity.
		final blackSquare:Entity = new Entity();
		Assert.isTrue(blackSquare.active);
		Assert.equals(0, Lambda.count(blackSquare.getComponents()));
		
		//Create some interchangeable components.
		final black:Color = 0x000000;
		final nearBlack:Color = 0x111111;
		final name:Name = "blackSquare";
		final shortName:Name = "blSq";
		
		//Add components.
		blackSquare.add(black);
		Assert.equals(black, blackSquare.get(Color));
		Assert.isFalse(blackSquare.exists(Int));
		
		blackSquare.add(0xFFFFFF);
		Assert.notEquals(blackSquare.get(Color), blackSquare.get(Int));
		
		blackSquare.add(SQUARE);
		Assert.equals(SQUARE, blackSquare.get(Shape));
		
		blackSquare.add(name);
		Assert.equals(name, blackSquare.get(Name));
		Assert.isFalse(blackSquare.exists(String));
		
		//Overwrite existing components.
		blackSquare.add(nearBlack, shortName);
		Assert.equals(nearBlack, blackSquare.get(Color));
		Assert.equals(shortName, blackSquare.get(Name));
		
		//Don't overwrite existing components.
		blackSquare.addIfMissing(name, CIRCLE, "string");
		Assert.equals(shortName, blackSquare.get(Name));
		Assert.equals(SQUARE, blackSquare.get(Shape));
		Assert.equals("string", blackSquare.get(String));
		
		//Remove components.
		blackSquare.remove(Shape, Name, String);
		Assert.isTrue(blackSquare.exists(Color));
		Assert.isFalse(blackSquare.exists(Shape));
		Assert.isFalse(blackSquare.exists(Name));
		
		blackSquare.remove(Shape);
		Assert.isTrue(blackSquare.exists(Color));
		Assert.isFalse(blackSquare.exists(Shape));
		
		blackSquare.removeAll();
		Assert.isFalse(blackSquare.exists(Color));
	}
	
	private function testInactiveEntities():Void {
		final inactive:Entity = new Entity(false);
		Assert.isFalse(inactive.active);
		Assert.equals(0, Echoes.activeEntities.length);
		
		new AppearanceSystem().activate();
		assertTimesCalled(0, "AppearanceSystem.colorAdded");
		
		//Add some components the system looks for.
		inactive.add((0x0000FF:Color));
		assertTimesCalled(0, "AppearanceSystem.colorAdded");
		
		//The system should notice when the entity's state changes.
		inactive.activate();
		assertTimesCalled(1, "AppearanceSystem.colorAdded");
		
		assertTimesCalled(0, "AppearanceSystem.colorRemoved");
		
		inactive.deactivate();
		assertTimesCalled(1, "AppearanceSystem.colorRemoved");
	}
	
	private function testAddAndRemoveEvents():Void {
		//Add a system.
		final appearanceSystem:AppearanceSystem = new AppearanceSystem();
		Assert.equals(0, Echoes.activeSystems.length);
		
		appearanceSystem.activate();
		Assert.equals(1, Echoes.activeSystems.length);
		assertTimesCalled(0, "AppearanceSystem.colorAdded");
		
		//Add a red line.
		Assert.equals(0, Echoes.activeEntities.length);
		
		final redLine:Entity = new Entity();
		Assert.equals(1, Echoes.activeEntities.length);
		
		redLine.add((0xFF0000:Color), Shape.LINE);
		assertTimesCalled(1, "AppearanceSystem.colorAdded");
		assertTimesCalled(1, "AppearanceSystem.colorAndShapeAdded");
		assertTimesCalled(0, "AppearanceSystem.colorAndShapeRemoved");
		
		//Add a circle.
		final circle:Entity = new Entity();
		Assert.equals(2, Echoes.activeEntities.length);
		
		circle.add(CIRCLE);
		assertTimesCalled(1, "AppearanceSystem.colorAdded");
		assertTimesCalled(2, "AppearanceSystem.shapeAdded");
		assertTimesCalled(1, "AppearanceSystem.colorAndShapeAdded");
		assertTimesCalled(0, "AppearanceSystem.colorAndShapeRemoved");
		
		//Create and activate a system AFTER adding the component.
		circle.add(("circle":Name));
		assertTimesCalled(0, "NameSystem.nameAdded", "NameSystem doesn't exist but its method was still called.");
		
		final nameSystem:NameSystem = new NameSystem();
		
		redLine.add(("redLine":Name));
		assertTimesCalled(0, "NameSystem.nameAdded", "NameSystem isn't active but its method was still called.");
		
		nameSystem.activate();
		assertTimesCalled(2, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		
		//Overwrite some components.
		redLine.add(("darkRedLine":Name));
		assertTimesCalled(3, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSystem.nameRemoved");
		
		assertTimesCalled(2, "AppearanceSystem.shapeAdded");
		assertTimesCalled(0, "AppearanceSystem.shapeRemoved");
		circle.add(SQUARE);
		circle.add(CIRCLE);
		assertTimesCalled(4, "AppearanceSystem.shapeAdded");
		assertTimesCalled(0, "AppearanceSystem.shapeRemoved");
		
		//Deconstruct an entity.
		redLine.remove(Shape);
		assertTimesCalled(0, "AppearanceSystem.colorRemoved");
		assertTimesCalled(1, "AppearanceSystem.shapeRemoved");
		assertTimesCalled(1, "AppearanceSystem.colorAndShapeRemoved");
		
		redLine.remove(Color);
		assertTimesCalled(1, "AppearanceSystem.colorRemoved");
		assertTimesCalled(1, "AppearanceSystem.colorAndShapeRemoved");
		
		redLine.removeAll();
		assertTimesCalled(2, "NameSystem.nameRemoved");
		
		//Deactivate a system.
		nameSystem.deactivate();
		assertTimesCalled(2, "NameSystem.nameRemoved");
		
		//Destroy the remaining entity.
		assertTimesCalled(1, "AppearanceSystem.shapeRemoved");
		
		circle.destroy();
		assertTimesCalled(2, "NameSystem.nameRemoved");
		assertTimesCalled(2, "AppearanceSystem.shapeRemoved");
	}
	
	@:access(echoes.SystemList.__update__)
	private function testUpdateEvents():Void {
		final timeCountSystem:TimeCountSystem = new TimeCountSystem();
		Assert.equals((0:Time), timeCountSystem.totalTime);
		
		timeCountSystem.activate();
		
		//Create some entities, but none with both color and shape.
		final green:Entity = new Entity().add((0x00FF00:Color));
		Assert.equals((0:Time), timeCountSystem.colorTime);
		
		final star:Entity = new Entity().add(STAR, ("Proxima Centauri":Name));
		Assert.equals((0:Time), timeCountSystem.shapeTime);
		
		Assert.isNull(star.get(Color), star.get(Color) + " should be null. See ComponentStorage constructor for details.");
		
		//Run an update.
		Echoes.activeSystems.__update__(1);
		Assert.equals((1:Time), timeCountSystem.totalTime);
		Assert.equals((1:Time), timeCountSystem.colorTime);
		Assert.equals((1:Time), timeCountSystem.shapeTime);
		Assert.equals((0:Time), timeCountSystem.colorAndShapeTime);
		
		//Give one entity both a color and shape.
		star.add((0xFFFFFF:Color));
		
		//Run another few updates. (`colorTime` should now increment twice per
		//update, since now two entities have color.)
		Echoes.activeSystems.__update__(1);
		Assert.equals((2:Time), timeCountSystem.totalTime);
		Assert.equals((3:Time), timeCountSystem.colorTime);
		Assert.equals((2:Time), timeCountSystem.shapeTime);
		Assert.equals((1:Time), timeCountSystem.colorAndShapeTime);
		
		Echoes.activeSystems.__update__(1);
		Assert.equals((3:Time), timeCountSystem.totalTime);
		Assert.equals((5:Time), timeCountSystem.colorTime);
		Assert.equals((3:Time), timeCountSystem.shapeTime);
		Assert.equals((2:Time), timeCountSystem.colorAndShapeTime);
	}
}
