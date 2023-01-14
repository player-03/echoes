# Echoes
A macro-based [Entity Component System](https://en.wikipedia.org/wiki/Entity_component_system) framework, focusing on ease of use.

This framework was [designed and implemented by deepcake](https://github.com/deepcake/echo), and is now maintained by player-03.

## Overview

- A component is an individual piece of data. It can be a string, a class, an abstract, or any other valid Haxe type.
  - Usage: Components can be any type, but you need to make sure they're distinct. For instance, instead of storing a name as a plain `String`, define `typedef CharacterName = String` or `abstract CharacterName(String) {}`. Later, you'll be able to assign a unique meaning to `CharacterName`, separate from other strings.
- An [entity](src/echoes/Entity.hx) is a collection of data. It fills a similar role to object instances in object-oriented programming, but functions differently. Its components aren't pre-defined the way an object's variables are; in fact, you can mix and match them at runtime.
  - Usage: Create an entity with `new echoes.Entity()`. From here you can call `entity.add(new Component())` for all the components it needs.
- A [system](src/echoes/System.hx) updates and modifies entities. Whereas in object-oriented programming, objects usually have instance methods to update themselves, here that job is reserved for systems.
  - Systems use [views](src/echoes/View.hx) to filter entities. `View<A, B>` lists all entities with both the `A` component and the `B` component, which is convenient when a system wants to modify that specific data.
  - For usage instructions, [see "usage example"](#usage-example).
- The [`Echoes` class](src/echoes/Echoes.hx) tracks all active entities and systems.
  - Usage: Call `Echoes.init()` to begin, then call `Echoes.addSystem()` to activate each of your systems.

### Usage example

A single system with a single entity:

```haxe
import echoes.Entity;
import echoes.System;
import echoes.Echoes;

class EchoesExample {
	public static function main():Void {
		Echoes.init();
		
		//To use a system, you need to register an instance.
		Echoes.addSystem(new RenderSystem());
		
		//To use an entity, create a new instance and add the components your
		//systems will use.
		var appleTree:Entity = new Entity();
		appleTree.add(loadImage("assets/AppleTree.png"));
		appleTree.add(new Position(100, 0));
		//...
	}
	
	private static function loadImage(path:String):DisplayObject {
		//...
	}
}

class RenderSystem extends System {
	/**
	 * This function is called whenever any entity gains a `DisplayObject`
	 * component, and it adds the `DisplayObject` to the scene.
	 */
	@:add private function onDisplayObjectAdded(displayObject:DisplayObject):Void {
		Lib.current.addChild(displayObject);
	}
	
	/**
	 * This function is called whenever any entity loses a `DisplayObject`
	 * component, and it removes the `DisplayObject` from the scene.
	 */
	@:remove private function onDisplayObjectRemoved(displayObject:DisplayObject):Void {
		Lib.current.removeChild(displayObject);
	}
	
	/**
	 * This function is called several times per frame, once for every entity with
	 * **both** a `DisplayObject` and a `Position`. It keeps the two components in
	 * sync, moving the former to match the latter.
	 */
	@:update private function updatePosition(displayObject:DisplayObject, position:Position):Void {
		displayObject.x = position.x;
		displayObject.y = position.y;
	}
	
	/**
	 * This function is called once per frame, after all calls to
	 * `updatePosition()` have returned. If you need to clean anything up at the
	 * end of a frame, this is a good place to do it.
	 */
	@:update private function finalize():Void {
		//...
	}
}
```

Multiple systems with multiple entites:

```haxe
import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.Echoes;

class EchoesExample {
	public static function main():Void {
		Echoes.init();
		
		//Using a `SystemList` helps keep related systems organized.
		var physicsSystems:SystemList = new SystemList("Physics");
		physicsSystems.add(new MovementSystem());
		physicsSystems.add(new CollisionSystem());
		
		//Adding `physicsSystems` first means that all physics systems will run
		//before `RenderSystem`. (Even if new physics systems are added later
		//on, they will still run first.)
		Echoes.addSystem(physicsSystems);
		Echoes.addSystem(new RenderSystem());
		
		//Create entities: one tree and two rabbits.
		var appleTree:Entity = new Entity();
		appleTree.add(loadImage("assets/AppleTree.png"));
		appleTree.add(new Position(100, 0));
		
		//`add()` returns the entity, allowing you to chain calls.
		var john:Entity = new Entity()
			.add(new Position(0, 0))
			.add(new Velocity(2.5, 0))
			.add(loadImage("assets/Rabbit.png"))
			.add(("John":Name));
		
		//`add()` can also take multiple components.
		var jack:Entity = new Entity();
		jack.add(new Position(150, 0), new Velocity(-2.5, 0));
		jack.add(loadImage("assets/Rabbit.png"), ("Jack":Name));
		
		//You can manually access and modify components.
		john.get(Velocity).x = 4.5;
		trace(john.get(Velocity)); //{ x: 4.5, y: 0 }
		
		trace(jack.get(Position).x); //150
		trace(jack.get(Name)); //"Jack"
	}
}

//Using typedefs allows you to assign meaning to common types. `Name` is now its
//own component type, distinct from `String`. An entity will be able to have
//both a `Name` and a `String` component, or one without the other.
typedef Name = String;

class MovementSystem extends System {
	private var timeElapsed:Float = 0;
	
	/**
	 * This function is called several times per frame, once for every entity
	 * with **both** a `Position` and a `Velocity`.
	 * 
	 * `Float` is a special case, and is never treated as a component.
	 */
	@:update private function updatePosition(position:Position, velocity:Velocity, time:Float):Void {
		//Changing the entity's position a small amount each frame produces the
		//appearance of smooth motion.
		position.x += velocity.x * time;
		position.y += velocity.y * time;
	}
	
	/**
	 * This `View` object lists every entity with a `Velocity`. Because the
	 * `View` constructor is private, you must call `makeLinkedView()` instead.
	 */
	private var velocityView:View<Velocity> = makeLinkedView();
	
	/**
	 * Because `Float` is a special case, this function behaves like
	 * `RenderSystem.finalize()`, being called only once per update.
	 */
	@:update private function countTime(time:Float):Void {
		if(timeElapsed < 0) {
			return;
		}
		
		timeElapsed += time;
		
		if(timeElapsed >= 20) {
			trace("Race over!");
			
			//Iterate through all entities with `Velocity` components.
			for(entity in velocityView.entities) {
				var velocity:Velocity = entity.get(Velocity);
				velocity.x = 0;
				velocity.y = 0;
			}
		}
	}
}
```

#### Special arguments
Certain argument types have special meanings, for easy access to information. `Float` refers to the duration of this update, in seconds, and `Entity` refers to the entity being processed.

When you take an argument of either type, instead of getting a component as normal, you get the special value. Plus, the function will be called even though the entity doesn't have corresponding components. (In fact, entities aren't allowed to have those components.)

```haxe
//The entity must have `Position` and `Velocity`, but `Float` will be provided.
@:update private function updatePosition(position:Position, velocity:Velocity, time:Float):Void {
	position.x += velocity.x * time;
	position.y += velocity.y * time;
}

//Taking an `Entity` argument allows you to view and modify components.
@:update private function stopIfOutOfBounds(position:Position, entity:Entity):Void {
	//entity.get() is just a little more verbose, but does the same thing.
	if(position != entity.get(Position)) {
		throw "Those should always be equal.";
	}
	
	//You can create code that only runs when an optional component exists.
	if(entity.exists(Velocity) && Math.abs(position.x) > 200) {
		entity.remove(Velocity);
	}
}
```

Echoes also supports the standard "optional argument" syntax.

```haxe
//Only `Position` is required, but `Velocity` will be provided if available.
@:update private function stopAtBounds(position:Position, ?velocity:Velocity):Void {
	if(position.x > 200) {
		position.x = 200;
		
		if(velocity != null) {
			velocity.x = 0;
		}
	} else if(position.x < -200) {
		position.x = -200;
		
		if(velocity != null) {
			velocity.x = 0;
		}
	}
}
```

## Installation

```bash
haxelib git echoes https://github.com/player-03/echoes.git
```

## Advanced

### Update order

To make an app run smoothly, you often need to run updates in a specific order. For simple apps, all you need to do is call `Echoes.addSystem()` in the correct order and pay attention to the order of each system's `@:update` functions. The systems will run in the order you added them, and within each system, the `@:update` functions will run from top to bottom.

```haxe
class Main {
	public static function main():Void {
		Echoes.init();
		
		Echoes.add(new FirstSystem());
		Echoes.add(new SecondSystem());
	}
}

class FirstSystem extends System {
	@:update private function first():Void {
		trace(1);
	}
	@:update private function second():Void {
		trace(2);
	}
}

class SecondSystem extends System {
	@:update private function first():Void {
		trace(3);
	}
	@:update private function second():Void {
		trace(4);
	}
}
```

#### SystemList

[`SystemList`](src/echoes/SystemList.hx) is a system that tracks a list of other systems. During an update, it runs all of its systems in a row before returning.

```haxe
class Main {
	public static function main():Void {
		Echoes.init();
		
		var enterFrame:SystemList = new SystemList();
		var midFrame:SystemList = new SystemList();
		var exitFrame:SystemList = new SystemList();
		
		//Run all `enterFrame` systems first, then all `midFrame` systems, then
		//all `exitFrame` systems.
		Echoes.addSystem(enterFrame);
		Echoes.addSystem(midFrame);
		Echoes.addSystem(exitFrame);
		
		//Even if `exitFrame` systems are defined first, they'll run last.
		exitFrame.add(new ExitFrameSystem());
		exitFrame.add(new ExitFrameSystem2());
		
		//Even if `enterFrame` systems are defined second, they'll run first.
		enterFrame.add(new EnterFrameSystem());
		enterFrame.add(new EnterFrameSystem2());
		
		//Even if `midFrame` systems are defined last, they'll run in between
		//`enterFrame` and `exitFrame`.
		midFrame.add(new MidFrameSystem());
		midFrame.add(new MidFrameSystem2());
	}
}
```

Because `SystemList` is itself a system, you can nest lists for finer control.

```haxe
class Main {
	public static function main():Void {
		Echoes.init();
		
		var enterFrame:SystemList = new SystemList();
		enterFrame.add(new EnterFrameSystem());
		enterFrame.add(new EnterFrameSystem2());
		Echoes.addSystem(enterFrame);
		
		var midFrame:SystemList = new SystemList();
		midFrame.add(new MidFrameSystem());
		Echoes.addSystem(midFrame);
		
		//Set up `physics` as part of `midFrame`.
		var physics:SystemList = new SystemList();
		physics.add(new GravitySystem());
		physics.add(new MomentumSystem());
		midFrame.add(physics);
		
		//Any later additions to `midFrame` will run after `physics`.
		midFrame.add(new MidFrameSystem2());
		
		//Any later additions to `physics` will still run during `physics`,
		//which means after `MidFrameSystem2`.
		physics.add(new CollisionSystem());
		
		var exitFrame:SystemList = new SystemList();
		exitFrame.add(new ExitFrameSystem());
		exitFrame.add(new ExitFrameSystem2());
		Echoes.addSystem(exitFrame);
	}
}
```

Also note that each `SystemList` has its own `paused` property, which prevents `@:update` events for any system in that list. So in the above example, you could pause `physics` without pausing anything else. Or you could pause `midFrame` (which implicitly pauses `physics`) while allowing `enterFrame` and `exitFrame` to keep going.

#### Priority

If system lists aren't enough, Echoes allows setting a system's priority using the `@:priority` metadata. Within a `SystemList`, systems with higher priority will run before those with lower priority, no matter what order they're added in. For instance:

```haxe
class Main {
	public static function main():Void {
		Echoes.init();
		
		Echoes.add(new DefaultPrioritySystem());
		Echoes.add(new HighPrioritySystem());
	}
}

//The default priority is 0.
class DefaultPrioritySystem extends System {
	@:update private function first():Void {
		trace(3);
	}
	@:update private function second():Void {
		trace(4);
	}
}

//Priority 1 means this system will run before all default-priority systems,
//even if it's added last.
@:priority(1)
class HighPrioritySystem extends System {
	@:update private function first():Void {
		trace(1);
	}
	@:update private function second():Void {
		trace(2);
	}
}
```

Sometimes a system needs to run in between two others, but also needs to clean up after the others are done. This can be accomplished by adding the systems in order, then giving the cleanup function a low priority:

```haxe
class Main {
	public static function main():Void {
		Echoes.init();
		
		//Add three systems with default priority (0).
		Echoes.add(new FirstSystem());
		Echoes.add(new MiddleSystem());
		Echoes.add(new LastSystem());
	}
}

//...

class MiddleSystem extends System {
	//Functions without a `@:priority` tag will run as part of `MiddleSystem`.
	//In this case, that's after `FirstSystem` but before `LastSystem`.
	@:update private function first():Void {
		//Do work here.
	}
	
	@:update private function second():Void {
		//Do other work here.
	}
	
	//Functions with a `@:priority` tag will run at that priority. In this case,
	//that's after `LastSystem`.
	@:update @:priority(-1) private function last():Void {
		//Clean up here.
	}
}
```

Note that `@:priority` is only used to sort the parent `SystemList`. If you have lists within lists, only the bottommost list will take priority into account.

```haxe
class Main {
	public static function main():Void {
		Echoes.init();
		
		var parentList:SystemList = new SystemList();
		parentList.add(new DefaultPrioritySystem());
		
		//Because `DefaultPriorityList` and `childList` have the same priority,
		//they remain in that order. Because `childList` comes second, any
		//systems in `childList` come after `DefaultPrioritySystem`.
		var childList:SystemList = new SystemList();
		parentList.add(childList);
		
		//Comes after `DefaultPrioritySystem`, naturally.
		childList.add(new LowPrioritySystem());
		
		//No matter how high a system's priority, it can't go any earlier than
		//the start of its enclosing list, which is exactly where this will go.
		childList.add(new HighPrioritySystem());
	}
}
```

### Compiler flags
Echoes offers a few ways to customize compilation.

- `-Dechoes_profiling` turns on time tracking. With this flag enabled, `Echoes.getStatistics()` will include the amount of time spent on each system during the most recent update.
- `-Dechoes_report` prints a list of all compiled components and views.
- `-Dechoes_max_name_length=[number]` adjusts the length of generated class names, which can help if you exceed your operating system's filename length limit.

## Breaking changes

### Since version 0.1.0

Entities:

- `Entity.print()` is now `Entity.getComponents()`. This returns a `Map`, allowing you to iterate over all of the components.
- The `isActive()`, `isDestroyed()` and `status()` functions have been condensed into the `active` and `destroyed` properties.
- When you call `entity.add()`, Echoes will dispatch an `@:add` event whether or not a component of that type already existed. (Previously, it would only do so if it hadn't exist.)

Components:

- Typedefs are treated as their own components, distinct from the underlying type. To disable this behavior, mark the typedef `@:eager`.
- `Storage` and `ICleanableComponentContainer` have been merged into `ComponentStorage`.
- Components may no longer be `null`. Trying to add a null component instead removes that component (if it exists).

Systems:

- Systems no longer initialize `View` variables automatically. You must now call `makeLinkedView()` for the same behavior.
- `@rm` is no longer a valid way to shorten `@:remove`. You may now omit any number of letters from the end, but not from the middle. (Thus, `@:rem` is now valid.)
- As far as listener functions are concerned, `Int` no longer means anything special. To get a reference to the entity, take an argument of type `Entity`.

Miscellaneous:

- Haxe 3 is no longer supported.
- `Echoes.update()` will calculate the elapsed time on its own, and no longer takes an argument. If you need to adjust the rate at which time passes, use a `SystemList` with a `ScaledTimestep`.
- `-Dechoes_array_container` and `-Dechoes_vector_container` have been removed.
- `Echoes.info()` is now `Echoes.getStatistics()`.

Finally, several classes and variables were renamed. Use these find-and-replace operations to update your code.

Find | Replace with | Notes
-----|--------------|------
`echoes.core` | `echoes`
`Workflow` | `Echoes`
`Echoes.entities` | `Echoes.activeEntities`
`Echoes.views` | `Echoes.activeViews`
`Echoes.systems` | `Echoes.activeSystems`
`AbstractView` | `ViewBase` | Import `echoes.View`.
`ISystem` | `System` | Change "`implements`" to "`extends`," if applicable.
`ICleanableComponentContainer` | `ComponentStorage`
`view.size()` | `view.entities.length` | You might have used a different variable name than `view`.
`view.isActive()` | `view.active` | Ditto.
`onAdded.add()` | `onAdded.push()`
`onAdded.size()` | `onAdded.length`
`onRemoved.add()` | `onRemoved.push()`
`onRemoved.size()` | `onRemoved.length`
