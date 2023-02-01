package;

import Components;
import echoes.Echoes;
import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.View;
import haxe.PosInfos;
import MethodCounter.assertTimesCalled;
import MethodCounter.IMethodCounter;
import Systems;
import utest.Assert;
import utest.Test;

@:depends(BasicFunctionalityTest)
class EdgeCaseTest extends Test {
	private function teardown():Void {
		Echoes.reset();
		MethodCounter.reset();
	}
	
	//Tests may be run in any order, but not in parallel.
	
	private function testNullComponents():Void {
		var entity:Entity = new Entity();
		
		entity.add("Hello world.");
		Assert.isTrue(entity.exists(String));
		
		entity.add((null:String));
		Assert.isFalse(entity.exists(String));
	}
	
	private function testRedundantOperations():Void {
		Echoes.addSystem(new AppearanceSystem());
		
		var entity:Entity = new Entity(false);
		
		//Deactivate an inactive entity.
		Assert.isFalse(entity.active);
		
		entity.deactivate();
		Assert.isFalse(entity.active);
		
		//Activate the entity twice.
		entity.activate();
		entity.activate();
		Assert.isTrue(entity.active);
		Assert.equals(1, Echoes.activeEntities.length);
		
		//Add a `Color` twice in a row.
		entity.add((0x000000:Color));
		Assert.equals(0x000000, entity.get(Color));
		
		entity.add((0xFFFFFF:Color));
		Assert.equals(0xFFFFFF, entity.get(Color));
		assertTimesCalled(2, "AppearanceSystem.colorAdded");
		assertTimesCalled(0, "AppearanceSystem.colorRemoved");
		
		//Remove the `Color` twice in a row.
		entity.remove(Color);
		Assert.isNull(entity.get(Color));
		
		entity.remove(Color);
		Assert.isNull(entity.get(Color));
		assertTimesCalled(2, "AppearanceSystem.colorAdded");
		assertTimesCalled(1, "AppearanceSystem.colorRemoved");
		
		//Replace a `Name` with itself.
		Echoes.addSystem(new NameSystem());
		entity.add(("name":Name));
		assertTimesCalled(1, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		
		entity.add(("name":Name));
		assertTimesCalled(1, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		
		entity.add(("otherName":Name));
		assertTimesCalled(2, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSystem.nameRemoved");
	}
	
	private function testRecursiveEvents():Void {
		var entity:Entity = new Entity();
		
		//Activate the system first so that it can process events first.
		Echoes.addSystem(new RecursiveEventSystem());
		
		//Certain events should stop propagating after `RecursiveEventSystem`
		//gets to them.
		Echoes.getView(One, Two).onAdded.push((entity, one, two)
			-> Assert.fail("ComponentStorage.add() didn't stop iterating despite component being removed."));
		Echoes.getView(Two, Three).onAdded.push((entity, two, three)
			-> Assert.fail("ComponentStorage.add() didn't stop iterating despite component being removed."));
		Echoes.getView(Brief, One).onAdded.push((entity, brief, one)
			-> Assert.fail("ComponentStorage.add() didn't stop iterating despite component being removed."));
		Echoes.getView(Permanent, One).onRemoved.push((entity, permanent, one)
			-> Assert.fail("ComponentStorage.remove() didn't stop iterating despite component being re-added."));
		Echoes.getView(Brief).onAdded.push((entity, brief)
			-> Assert.fail("ViewBuilder.dispatchAddedCallback() didn't stop iterating despite entity being removed."));
		Echoes.getView(Permanent).onRemoved.push((entity, permanent)
			-> Assert.fail("ViewBuilder.dispatchRemovedCallback() didn't stop iterating despite entity being re-added."));
		
		//Test components that add/remove other components.
		entity.add((1:One));
		entity.add((2:Two));
		Assert.isFalse(entity.exists(One));
		Assert.isTrue(entity.exists(Two));
		
		entity.add((3:Three));
		Assert.isTrue(entity.exists(One));
		Assert.isFalse(entity.exists(Two));
		Assert.isTrue(entity.exists(Three));
		
		entity.remove(Three);
		Assert.isFalse(entity.exists(One));
		Assert.isTrue(entity.exists(Two));
		Assert.isFalse(entity.exists(Three));
		
		entity.remove(Two);
		Assert.isTrue(entity.exists(One));
		Assert.isFalse(entity.exists(Two));
		Assert.isFalse(entity.exists(Three));
		
		//Don't remove `One`.
		
		//Test components that prevent themselves from being added/removed.
		entity.add((0:Brief));
		Assert.isFalse(entity.exists(Brief));
		
		entity.add((Math.POSITIVE_INFINITY:Permanent));
		Assert.isTrue(entity.exists(Permanent));
		
		entity.remove(Permanent);
		Assert.isTrue(entity.exists(Permanent));
		
		//Clear the permanent listeners before cleaning up.
		Echoes.getView(Permanent).onRemoved.pop();
		Echoes.getView(Permanent, One).onRemoved.pop();
	}
	
	private function testSystemLists():Void {
		var list0:SystemList = new SystemList();
		var list1:SystemList = new SystemList();
		var system:NameSystem = new NameSystem();
		
		list0.add(system);
		Assert.equals(list0, system.parent);
		
		list1.add(system);
		Assert.equals(list1, system.parent);
		Assert.equals(0, list0.length);
		Assert.equals(1, list1.length);
	}
	
	private function testTypeParsing():Void {
		var entity:Entity = new Entity();
		var infos:PosInfos = ((?infos:PosInfos) -> infos)();
		entity.add(infos);
		
		Assert.equals(infos, entity.get(PosInfos));
		Assert.equals(infos, entity.get(haxe.PosInfos));
		Assert.equals(infos, entity.get(infos));
	}
}

typedef One = Int;
typedef Two = Int;
typedef Three = Int;

typedef Brief = Float;
typedef Permanent = Float;

class RecursiveEventSystem extends System implements IMethodCounter {
	@:add private function twoRemovesOne(two:Two, entity:Entity):Void {
		entity.remove(One);
	}
	
	@:add private function threeRemovesTwo(three:Three, entity:Entity):Void {
		entity.remove(Two);
	}
	
	@:remove private function removingThreeAddsTwo(three:Three, entity:Entity):Void {
		entity.add((2:Two));
	}
	
	@:remove private function removingTwoAddsOne(two:Two, entity:Entity):Void {
		entity.add((1:One));
	}
	
	@:add private function briefRemovesItself(brief:Brief, entity:Entity):Void {
		entity.remove(Brief);
	}
	
	@:remove private function permanentAddsItself(permanent:Permanent, entity:Entity):Void {
		entity.add(permanent);
	}
}
