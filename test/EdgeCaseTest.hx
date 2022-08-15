package;

import Components;
import echoes.Echoes;
import echoes.Entity;
import echoes.System;
import echoes.View;
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
		Assert.equals(Inactive, entity.status());
		
		entity.deactivate();
		Assert.equals(Inactive, entity.status());
		
		//Activate the entity twice.
		entity.activate();
		entity.activate();
		Assert.equals(Active, entity.status());
		Assert.equals(1, Echoes.activeEntities.length);
		
		//Add a `Color` twice in a row.
		entity.add((0x000000:Color));
		Assert.equals(0x000000, entity.get(Color));
		
		entity.add((0xFFFFFF:Color));
		Assert.equals(0xFFFFFF, entity.get(Color));
		assertTimesCalled(1, "AppearanceSystem.colorAdded");
		assertTimesCalled(0, "AppearanceSystem.colorRemoved");
		
		//Remove the `Color` twice in a row.
		entity.remove(Color);
		Assert.isNull(entity.get(Color));
		
		entity.remove(Color);
		Assert.isNull(entity.get(Color));
		assertTimesCalled(1, "AppearanceSystem.colorAdded");
		assertTimesCalled(1, "AppearanceSystem.colorRemoved");
	}
	
	private function testRecursiveEvents():Void {
		var entity:Entity = new Entity();
		
		//Activate the system first so that it can process events first.
		Echoes.addSystem(new RecursiveEventSystem());
		
		//Thanks to `ComponentStorage`'s optimizations, certain events should
		//stop propagating after the `RecursiveEventSystem` functions. (The
		//`View` finishes dispatching it to all listeners, but other views of
		//that component aren't notified.)
		(Echoes.getView():View<One, Two>).onAdded.push((entity, one, two) -> Assert.fail("Added event propagated to a second view despite being canceled."));
		(Echoes.getView():View<Two, Three>).onAdded.push((entity, two, three) -> Assert.fail("Added event propagated to a second view despite being canceled."));
		(Echoes.getView():View<Brief, One>).onAdded.push((entity, brief, one) -> Assert.fail("Added event propagated to a second view despite being canceled."));
		(Echoes.getView():View<Permanent, One>).onRemoved.push((entity, permanent, one) -> Assert.fail("Removed event propagated to a second view despite being canceled."));
		
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
		
		//Clear the permanent listener before cleaning up.
		(Echoes.getView():View<Permanent, One>).onRemoved.pop();
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
