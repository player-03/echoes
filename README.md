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

//Using typedefs allows you to assign meaning to common types. Echoes will now
//distinguish between `Name`s and other `String`s.
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
	 * `View` constructor is private, you must call `getView()` instead.
	 */
	private var velocityView:View<Velocity> = getView();
	
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

### Compiler flags
Echoes offers a few ways to customize compilation.

- `-Dechoes_profiling` turns on time tracking. With this flag enabled, `Echoes.info()` will return a printable list of how much time was spent on each system during the most recent update.
- `-Dechoes_report` prints a list of all compiled components and views.
- `-Dechoes_max_name_length=[number]` adjusts the length of generated class names, which can help if you exceed your operating system's filename length limit.

## Installation

```bash
haxelib git echoes https://github.com/player-03/echoes.git
```

## Breaking changes

### Since version 0.1.0

Entities:

- `Entity.print()` is now `Entity.getComponents()`. This returns a `Map`, allowing you to iterate over all of the components.

Components:

- Typedefs are treated as their own components, distinct from the underlying type. To disable this behavior, mark the typedef `@:eager`.
- `Storage` and `ICleanableComponentContainer` have been merged into `ComponentStorage`.

Systems:

- Systems no longer initialize `View` variables automatically. You must now call `Echoes.getView()`. For instance: `private var namedEntities:View<Name> = Echoes.getView();`
- `@rm` is no longer a valid way to shorten `@:remove`. You may now omit any number of letters from the end, but not from the middle. (Thus, `@:rem` is now valid.)

Miscellaneous:

- Haxe 3 is no longer supported.
- `Echoes.update()` will calculate the elapsed time on its own, and no longer takes an argument. If you need to adjust the rate at which time passes, use a `SystemList` with a `ScaledTimestep`.
- `-Dechoes_array_container` and `-Dechoes_vector_container` have been removed.

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
