package;

import Components;
import Components.Color as ColorAlias;
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
	
	private function testAllArgumentsOptional():Void {
		new OptionalListenerSystem().activate();
		Echoes.update();
		assertTimesCalled(0, "OptionalListenerSystem.optionalNameUpdated");
		
		final entity:Entity = new Entity();
		entity.add(("name":Name));
		Echoes.update();
		assertTimesCalled(1, "OptionalListenerSystem.optionalNameUpdated");
		
		//When there are multiple entities, the function should be called for
		//each, whether or not they have `Name` components.
		new Entity();
		Echoes.update();
		assertTimesCalled(3, "OptionalListenerSystem.optionalNameUpdated");
	}
	
	private function testChildSystems():Void {
		new NameSubsystem().activate();
		
		final entity:Entity = new Entity();
		entity.add(("Name":Name));
		assertTimesCalled(0, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSubsystem.nameAdded");
		
		new NameSystem().activate();
		assertTimesCalled(1, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		assertTimesCalled(0, "NameSubsystem.nameRemoved");
		
		entity.add(("Other Name":Name));
		assertTimesCalled(2, "NameSystem.nameAdded");
		assertTimesCalled(2, "NameSubsystem.nameAdded");
		
		//`nameRemoved` isn't overridden.
		assertTimesCalled(2, "NameSystem.nameRemoved");
		assertTimesCalled(0, "NameSubsystem.nameRemoved");
	}
	
	private function testComponentsExist():Void {
		new ComponentsExistSystem().activate();
		
		final entity:Entity = new Entity();
		entity.add(("name":Name));
		entity.add((0xFFFFFF:Color));
		entity.remove(Color);
		entity.remove(Name);
		
		entity.add((0xFFFFFF:Color));
		entity.add(("name":Name));
		entity.destroy();
		
		//The system's functions contain the important tests; all we need to do
		//here is make sure they were called.
		assertTimesCalled(2, "ComponentsExistSystem.nameAdded");
		assertTimesCalled(2, "ComponentsExistSystem.nameAndColorAdded");
		assertTimesCalled(2, "ComponentsExistSystem.nameOrColorRemoved");
		assertTimesCalled(2, "ComponentsExistSystem.nameRemoved");
	}
	
	@:access(echoes.Entity)
	private function testEntityIDSerialization():Void {
		final entity0:Entity = new Entity();
		new Entity();
		Assert.equals(2, Entity.nextID);
		Assert.same([], Entity.idPool);
		
		final savedData = Echoes.serialize();
		entity0.destroy();
		Assert.same([0], Entity.idPool);
		Assert.same([1], Echoes.activeEntities);
		
		Echoes.unserialize(savedData);
		Assert.same([0], Entity.idPool);
		Assert.equals(2, Entity.nextID);
		Assert.same([1], Echoes.activeEntities);
	}
	
	private function testEntityIndices():Void {
		inline function assertOrder(order:Array<Entity>, ?posInfos:PosInfos):Void {
			if(Assert.equals(order.length, Echoes.activeEntities.length, posInfos)) {
				for(i in 0...order.length) {
					Assert.equals(order[i], Echoes.activeEntities[i],
						'expected ${ order[i] } at index $i, got ${ Echoes.activeEntities[i] }', posInfos);
				}
			}
		}
		
		final a:Entity = new Entity();
		final b:Entity = new Entity();
		final c:Entity = new Entity();
		final d:Entity = new Entity();
		
		#if echoes_stable_order
		
		assertOrder([a, b, c, d]);
		
		//Removing an entity should shift the rest, preserving order.
		a.deactivate();
		assertOrder([b, c, d]);
		
		a.activate();
		assertOrder([b, c, d, a]);
		
		d.deactivate();
		assertOrder([b, c, a]);
		
		b.deactivate();
		assertOrder([c, a]);
		
		a.deactivate();
		assertOrder([c]);
		
		#else
		
		assertOrder([a, b, c, d]);
		
		//Removing an entity should move the final entity, saving time.
		a.deactivate();
		assertOrder([d, b, c]);
		
		a.activate();
		assertOrder([d, b, c, a]);
		
		c.deactivate();
		assertOrder([d, b, a]);
		
		d.deactivate();
		assertOrder([a, b]);
		
		b.deactivate();
		assertOrder([a]);
		
		#end
	}
	
	private function testImportAs():Void {
		final entity:Entity = new Entity();
		
		Assert.notNull(Echoes.getComponentStorage(ColorAlias));
		
		entity.add((0x112233:ColorAlias));
		Assert.equals(0x112233, entity.get(Color));
		
		entity.remove(Color);
		Assert.isFalse(entity.exists(ColorAlias));
	}
	
	private function testNullComponents():Void {
		final entity:Entity = new Entity();
		
		entity.add("Hello world.");
		Assert.isTrue(entity.exists(String));
		Assert.notNull(entity.get(String));
		
		entity.add((null:String));
		Assert.isFalse(entity.exists(String));
		Assert.isNull(entity.get(String));
	}
	
	private function testRedundantOperations():Void {
		new AppearanceSystem().activate();
		
		final entity:Entity = new Entity(false);
		
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
		new NameSystem().activate();
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
		final entity:Entity = new Entity();
		
		//Activate the system first so that it can process events first.
		new RecursiveEventSystem().activate();
		
		//Certain events should stop propagating after `RecursiveEventSystem`
		//gets to them. On some targets, this can happen when the entity ID is 0
		//and reading past the end of an int array returns 0 instead of null.
		Echoes.getView(One, Two).onAdded.push((entity, one, two)
			-> Assert.fail('ComponentStorage.add() didn\'t stop iterating despite One component being removed from entity ${ entity.id }.'));
		Echoes.getView(Two, Three).onAdded.push((entity, two, three)
			-> Assert.fail('ComponentStorage.add() didn\'t stop iterating despite Two component being removed from entity ${ entity.id }.'));
		Echoes.getView(Brief, One).onAdded.push((entity, brief, one)
			-> Assert.fail('ComponentStorage.add() didn\'t stop iterating despite Brief component being removed from entity ${ entity.id }.'));
		Echoes.getView(Brief).onAdded.push((entity, brief)
			-> Assert.fail('ViewBuilder.dispatchAddedCallback() didn\'t stop iterating despite Brief component being removed from entity ${ entity.id }.'));
		
		//However, `RecursiveEventSystem` shouldn't be able to interrupt
		//`onRemoved` events.
		var permanentRemoveFlags:Int = 0;
		Echoes.getView(Permanent).onRemoved.push((entity, permanent)
			-> permanentRemoveFlags |= 1);
		Echoes.getView(Permanent, One).onRemoved.push((entity, permanent, one)
			-> permanentRemoveFlags |= 2);
		
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
		
		//`RecursiveEventSystem` will attempt to undo `remove(Permanent)`, which
		//should throw an error. Afterwards, `Permanent` should remain gone, and
		//all listeners should have been called.
		Assert.raises(() -> entity.remove(Permanent));
		Assert.isFalse(entity.exists(Permanent));
		Assert.equals(1 | 2, permanentRemoveFlags);
		
		//`remove()` should only prevent adding `Permanent` while it's ongoing.
		entity.add((80:Permanent));
		Assert.equals(80.0, entity.get(Permanent));
	}
	
	private function testRemoveDuringUpdate():Void {
		final system:RemoveStringSystem = new RemoveStringSystem();
		system.activate();
		
		final entity0:Entity = new Entity();
		final entity1:Entity = new Entity();
		final entity2:Entity = new Entity();
		
		entity0.add("remove");
		entity1.add("keep");
		Assert.equals(2, Echoes.getView(String).entities.length);
		
		Echoes.update();
		assertTimesCalled(2, "RemoveStringSystem.removeString");
		Assert.equals(1, Echoes.getView(String).entities.length);
		
		entity0.add("remove");
		entity1.add("keep");
		entity2.add("remove");
		MethodCounter.reset();
		Echoes.update();
		assertTimesCalled(3, "RemoveStringSystem.removeString");
		Assert.equals(1, Echoes.getView(String).entities.length);
		
		entity0.add("remove");
		entity1.add("keep");
		entity2.add("remove");
		MethodCounter.reset();
		Echoes.getView(String).iter(system.removeString);
		assertTimesCalled(3, "RemoveStringSystem.removeString");
		Assert.equals(1, Echoes.getView(String).entities.length);
		
		final view:DynamicView = new DynamicView(Echoes.getComponentStorage(Bool));
		view.activate();
		var count:Int = 0;
		entity0.add(false);
		entity1.add(true);
		entity2.add(true);
		view.iter((entity, components) -> {
			count++;
			if(components[0] == true) {
				entity.remove(Bool);
			}
		});
		Assert.equals(1, view.entities.length);
		Assert.equals(3, count);
	}
	
	private function testSystemLists():Void {
		final list0:SystemList = new SystemList();
		final list1:SystemList = new SystemList();
		final system:NameSystem = new NameSystem();
		
		list0.add(system);
		Assert.equals(list0, system.parent);
		
		list1.add(system);
		Assert.equals(list1, system.parent);
		Assert.equals(0, list0.length);
		Assert.equals(1, list1.length);
	}
	
	private function testTypeParsing():Void {
		final entity:Entity = new Entity();
		final infos:PosInfos = ((?infos:PosInfos) -> infos)();
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

class ComponentsExistSystem extends System implements IMethodCounter {
	@:add private function nameAdded(name:Name, entity:Entity):Void {
		Assert.notNull(entity.get(Name));
		Assert.equals(name, entity.get(Name));
	}
	
	@:add private function nameAndColorAdded(name:Name, color:Color, entity:Entity):Void {
		Assert.notNull(entity.get(Name));
		Assert.equals(name, entity.get(Name));
		Assert.notNull(entity.get(Color));
		Assert.equals(color, entity.get(Color));
	}
	
	@:remove private function nameRemoved(name:Name, entity:Entity):Void {
		Assert.isNull(entity.get(Name));
		Assert.notNull(name);
	}
	
	@:remove private function nameOrColorRemoved(name:Name, color:Color, entity:Entity):Void {
		Assert.isFalse(entity.exists(Name) && entity.exists(Color));
		Assert.isTrue(entity.exists(Name) || entity.exists(Color));
		Assert.notNull(name);
		Assert.notNull(color);
	}
}

class NameSubsystem extends NameSystem {
	private override function nameAdded(name:Name):Void {}
}

class OptionalListenerSystem extends System implements IMethodCounter {
	@:update private function optionalNameUpdated(?name:Name):Void {}
	
	//These aren't allowed, and would throw compile errors, preventing the tests
	//from running at all.
	//@:add private function optionalNameAdded(?name:Name):Void {}
	//@:remove private function optionalNameRemoved(?name:Name):Void {}
}

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
	
	@:remove private function permanentTriesToAddItself(permanent:Permanent, entity:Entity):Void {
		//This is not allowed, and should throw an error. If it was allowed, it
		//would keep the component around permanently, hence the name.
		entity.add(permanent);
	}
}

class RemoveStringSystem extends System implements IMethodCounter {
	@:update public function removeString(entity:Entity, string:String):Void {
		if(string == "remove") {
			entity.remove(String);
		}
	}
}
