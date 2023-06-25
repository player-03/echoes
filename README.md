# Echoes
A macro-based [Entity Component System](https://en.wikipedia.org/wiki/Entity_component_system) framework, focusing on ease of use.

This framework was [designed and implemented by deepcake](https://github.com/deepcake/echo), and is now maintained by player-03.

## Overview

- A component is an individual piece of data. It can be a string, a class, an abstract, or any other type.
- An [entity](src/echoes/Entity.hx) is a collection of components. It fills a similar role to object instances in object-oriented programming, but functions differently. Its components aren't pre-defined the way an object's variables are; in fact, you can mix and match them at runtime.
  - Usage: Create an entity with `entity = new echoes.Entity()`. Next, call `entity.add(new Component())` for each component you want to add.
- A [system](src/echoes/System.hx) updates and modifies entities. Whereas in object-oriented programming, objects usually have instance methods to update themselves, here that job is reserved for systems.
  - Systems use [views](src/echoes/View.hx) to filter entities. `View<A, B>` lists all entities with both the `A` component and the `B` component, which is convenient when a system wants to modify that specific data.
  - Usage: Create a class that extends `echoes.System`, and write functions that take components as arguments. Echoes will automatically find entities with those components, allowing you to modify the data. See [usage](#usage) for details.
- The [`Echoes` class](src/echoes/Echoes.hx) tracks all active entities and systems.
  - Usage: Call `Echoes.init()` when the app loads, then call `Echoes.addSystem()` to activate each of your systems.

## Usage

To install Echoes, run `haxelib install echoes` or `haxelib git https://github.com/player-03/echoes.git`.

### One system

In this example, we create a single system and use it to manage a single entity. This system's only job is to render an entity's `DisplayObject` at that entity's `Position`. For now, we'll hard-code those two components.

```haxe
import echoes.Entity;
import echoes.System;
import echoes.Echoes;

class EchoesExample {
	public static function main():Void {
		Echoes.init();
		
		//Create and activate an instance of our system.
		Echoes.addSystem(new RenderSystem()); //Details below.
		
		//Create an entity with the components our system will use. Entities are
		//activated automatically unless `false` is passed.
		var appleTree:Entity = new Entity();
		appleTree.add(loadImage("assets/AppleTree.png"));
		appleTree.add(new Position(100, 0));
		//...
	}
	
	private static function loadImage(path:String):DisplayObject {
		//[Details omitted for brevity.]
	}
}

class RenderSystem extends System {
	public final scene:Scene;
	
	public function new(scene:Scene) {
		super();
		
		this.scene = scene;
	}
	
	/**
	 * This function is called whenever any entity gains a `DisplayObject`
	 * component, and it adds the `DisplayObject` to the scene.
	 */
	@:add private function onDisplayObjectAdded(displayObject:DisplayObject):Void {
		scene.addChild(displayObject);
	}
	
	/**
	 * This function is called whenever any entity loses a `DisplayObject`
	 * component, and it removes the `DisplayObject` from the scene.
	 */
	@:remove private function onDisplayObjectRemoved(displayObject:DisplayObject):Void {
		scene.removeChild(displayObject);
	}
	
	/**
	 * This function is called several times per frame, once for every entity
	 * with **both** a `DisplayObject` and a `Position`. It keeps the two
	 * components in sync, moving the former to match the latter.
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

### Two systems

This example adds a second system that move entities around.

```haxe
import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.Echoes;

class EchoesExample {
	public static function main():Void {
		Echoes.init();
		
		//Use a `SystemList` to group related systems.
		var physicsSystems:SystemList = new SystemList("Physics");
		physicsSystems.add(new MovementSystem()); //Details below.
		physicsSystems.add(new CollisionSystem()); //Not shown.
		
		//Adding `physicsSystems` first means that entire group will run before
		//`RenderSystem`, even if more systems are added later.
		Echoes.addSystem(physicsSystems);
		Echoes.addSystem(new RenderSystem()); //Details in previous example.
		
		//Create entities: one tree and two rabbits. The rabbits will race
		//towards the tree.
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
	
	private static function loadImage(path:String):DisplayObject {
		//[Details omitted for brevity.]
	}
}

//[RenderSystem omitted for brevity.]

//[Position and Velocity omitted for brevity.]

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
		//appearance of smooth motion. Later on, `RenderSystem` will update each
		//entity's `DisplayObject` to match this position.
		position.x += velocity.x * time;
		position.y += velocity.y * time;
	}
	
	/**
	 * This `View` object lists every entity with a `Velocity`. Because the
	 * `View` constructor is private, you must call `getLinkedView()` instead.
	 */
	private var velocityView:View<Velocity> = getLinkedView(Velocity);
	
	/**
	 * Because `Float` is a special case, this function behaves like
	 * `RenderSystem.finalize()`, being called only once per update.
	 */
	@:update private function countTime(time:Float):Void {
		if(timeElapsed >= 20) {
			return;
		}
		
		timeElapsed += time;
		
		if(timeElapsed >= 20) {
			trace("Race over!");
			
			//Iterate through all entities with `Velocity` components, and make
			//them all stop moving.
			for(entity in velocityView.entities) {
				var velocity:Velocity = entity.get(Velocity);
				velocity.x = 0;
				velocity.y = 0;
			}
		}
	}
}
```

### Special arguments
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

The `@:priority` metadata is another way to control update order. Raising a system's priority makes it run before lower-priority systems, and lowering its priority makes it run after. Within a priority bracket, systems run in the order they were added, as usual.

```haxe
//The default priority is 0.
class AverageSystem extends System {
	//...
}

//The `@:priority` metadata sets a system's priority.
@:priority(1)
class HighPrioritySystem extends System {
	//...
}

class Main {
	public static function main():Void {
		Echoes.init();
		
		//Priority 1 > priority 0, so `HighPrioritySystem` will run first
		//despite being added second.
		Echoes.add(new AverageSystem());
		Echoes.add(new HighPrioritySystem());
	}
}
```

Individual `@:update` listeners can have their own priorities. These listeners will run at a different time than the rest of the system.

```haxe
@:priority(1)
class MultiPrioritySystem extends System {
	//Any listener without a `@:priority` tag will run at the system's priority.
	//Like the system itself, `first()` will run near the start of an update.
	@:update private function first(data:Data):Void {
		//Begin collecting data.
		data.collectData = true;
	}
	
	//A listener with negative priority will run near the end of the update.
	@:update @:priority(-1) private function last(data:Data):Void {
		//Now that the default priority systems are done, analyze their data.
		data.analyze();
		
		//Don't collect data between updates.
		data.collectData = false;
	}
}
```

If using multiple `SystemList`s, be aware that priority only affects a system's position within its `parent` list. No matter how high or low the priority, the system can't run any earlier than the start of its `parent`, or any later than the end.

```haxe
class Main {
	public static function main():Void {
		Echoes.init();
		
		var list:SystemList = new SystemList();
		
		//Because `AverageSystem` and `list` both have priority 0, they run in
		//the order they're added.
		Echoes.addSystem(new AverageSystem());
		Echoes.addSystem(childList);
		
		//No matter how high a system's priority, if it's added to `list` it
		//will run during `list`, and will come after `AverageSystem`.
		list.add(new HighPrioritySystem());
	}
}
```

### Update length

As Glenn Fielder explains in his article ["Fix Your Timestep!"](https://www.gafferongames.com/post/fix_your_timestep/), games and physics simulations can be very sensitive to the length of each update. `@:update` listeners in Echoes are no exception.

Fix Your Timestep! lists a number of situations you may want to account for, and a couple different approaches. Fortunately, Echoes natively supports all of these solutions.

By default, `Echoes.update()` uses the "semi-fixed timestep" approach. It calculates how much time has passed since the last update, applies a maximum length of one second, and calls each `@:update` listener with that timestep.

If one second is too long, or if you want a fixed timestep, all you need to do is customize `Echoes.clock`. `Echoes.clock.maxTime` controls the maximum length of an update, and `Echoes.clock.setFixedTimestep()` divides each update into a number of fixed timesteps. (Any remaining time after an update will be carried over to the next update.)

In order to ["free the physics,"](https://www.gafferongames.com/post/fix_your_timestep/#free-the-physics) you may want to run physics-related systems at a different rate than everything else. Fortunately, each [`SystemList`](src/echoes/SystemList.hx) ([described above](#systemlist)) has its own [`Clock`](src/echoes/utils/Clock.hx). If you have a `SystemList` for physics systems, you can call `physicsSystemList.clock.setFixedTimestep()` without affecting any of the other systems.

### Entity templates

Sometimes, a combination of components comes up frequently enough that you want to be able to add them as a batch. For this, you can define an entity template, which is an abstract wrapping `Entity`.

```haxe
@:build(echoes.Entity.build())
abstract Fighter(Entity) {
	public var attack:Attack = 1;
	public var health:Health = 10;
}
```

In this example, the `Fighter` template represents an entity with `Attack` and `Health` components. In other words, it's an entity that can both deal and receive damage.

The build macro (`echoes.Entity.build()`) generates a constructor, as well as getters and setters for each component. This gives you a couple ways to interact with the fighter.

```haxe
var fighter:Fighter = new Fighter();

//You can treat components like variables.
trace(fighter.attack); //1
trace(fighter.health); //10
trace(fighter.hitbox); //"Square with width 1"

fighter.attack = 2;
trace(fighter.attack); //2

//Or you can treat `fighter` like a normal entity.
fighter.add((8:Health));
trace(fighter.get(Health)); //8

fighter.add(new TemporaryPowerup(7.5));
trace(fighter.get(TemporaryPowerup).timeLeft); //7.5
```

It's possible to apply multiple templates to a single entity.

```haxe
@:build(echoes.Entity.build())
abstract Fighter(Entity) {
	public var attack:Attack = 1;
	public var health:Health = 10;
}

@:build(echoes.Entity.build())
abstract Scout(Entity) {
	public var health:Health = 5;
	public var stealth:Stealth = 12;
}

class Main {
	public static function main():Void {
		var scout:Scout = new Scout();
		
		trace(scout.get(Attack)); //null
		
		//Each template provides an `applyTemplateTo()` function, which adds the
		//template's components to an entity.
		var scoutFighter:Fighter = Fighter.applyTemplateTo(scout);
		
		//It's still the same entity afterwards, just with more components.
		trace(scout == scoutFighter); //true
		
		trace(scout.get(Attack)); //1
		trace(scoutFighter.attack); //1
		
		trace(scout.stealth); //12
		trace(scoutFighter.get(Stealth)); //12
		
		//If a component already exists, `applyTemplateTo()` won't overwrite it.
		//In this case, `Scout` had already set `Health`.
		trace(scoutFighter.health); //5
	}
}
```

You can also take components as arguments using the `@:arguments` tag, or `@:optionalArguments` for components with values.

```haxe
@:build(echoes.Entity.build()) @:arguments(Sprite)
abstract Fighter(Entity) {
	public var attack:Attack = 1;
	public var health:Health = 10;
	public var sprite:Sprite;
}

class Main {
	public static function main():Void {
		//To construct a `Fighter`, you must pass a `Sprite`.
		var fighter:Fighter = new Fighter(new Sprite("meleeFighter.png"));
		
		//This also applies when calling `applyTemplateTo()`.
		var entity:Entity = new Entity();
		Fighter.applyTemplateTo(entity, new Sprite("rangedFighter.png"));
		
		//Note: if the entity already has a `Sprite`, the old one will be kept.
		Fighter.applyTemplateTo(entity, new Sprite("meleeFighter.png"));
		trace(entity.get(Sprite).path); //"rangedFighter.png"
	}
}
```

Additional notes:

- Like any other abstract, you can write instance functions. However, keep in mind that templates are meant to be optional, so these functions should be for convenience only. Important logic belongs in a system instead.
- A template can wrap another template, which behaves just like a subclass. All components and functions are inherited, unless re-declared.
- If a component lacks an initial value and isn't listed in `@:arguments`, it will default to null.
- You may not declare a constructor, but if you declare an `onApplyTemplate()` function, it will run when the template is constructed or applied.

### Compiler flags
Echoes offers a few ways to customize compilation.

- `-Dechoes_profiling` turns on time tracking. With this flag enabled, `Echoes.getStatistics()` will include the amount of time spent on each system during the most recent update.
- `-Dechoes_report` prints a list of all compiled components and views.
- `-Dechoes_max_name_length=[number]` adjusts the length of generated class names, which can help if you exceed your operating system's filename length limit.

## Breaking changes

### Since v1.0.0-rc.3

- Macro users only: `ComponentStorageBuilder.getComponentStorage()` now returns the full `StorageType.instance` expression, not just a value that can be parsed to find `StorageType`. If you need this value, use `getComponentStorageName()`. None of this affects `Echoes.getComponentStorage()`, which continues to work as before.
- Entity templates may no longer define their own constructor, and should instead declare an `onApplyTemplate()` function that takes no arguments.
- In an entity template, you must now use variables (not properties) to declare components. Properties now have their default Haxe behavior.
- In an entity template, only variables marked `@:optional` or `Null<>` are considered optional. If a non-optional variable lacks a value, it must now be set via constructor argument.

### Since v1.0.0-rc.2

- `Echoes.getSingleton()` is now `Echoes.getView()`, `Echoes.getInactiveView()`, and `Echoes.getComponentStorage()`, all of which take arguments instead of using `getExpectedType()`.
- `System.makeLinkedView()` is now `System.getLinkedView()`, which takes arguments instead of using `getExpectedType()`.

### Since deepcake/echo

Entities:

- `Entity.print()` is now `Entity.getComponents()`. This returns a `Map`, allowing you to iterate over all of the components.
- The `isActive()`, `isDestroyed()` and `status()` functions have been condensed into the `active` and `destroyed` properties.
- When you call `entity.add()`, Echoes will dispatch an `@:add` event whether or not a component of that type already existed. (Previously, it would only do so if it didn't exist.)
- You can no longer automatically convert `Entity` to or from `Int`.

Components:

- Typedefs are treated as their own components, distinct from the underlying type. To disable this behavior, mark the typedef `@:eager`.
- `Storage` and `ICleanableComponentContainer` have been merged into `ComponentStorage`.
- Components may no longer be `null`. Trying to add a null component instead removes that component (if it exists).

Systems:

- Systems no longer initialize `View` variables automatically. You must now call `getLinkedView()` for the same behavior.
- `@rm` is no longer a valid way to shorten `@:remove`. You may now omit any number of letters from the end, but not from the middle. (Thus, `@:rem` is now valid.)
- As far as listener functions are concerned, `Int` no longer means anything special. To get a reference to the entity, take an argument of type `Entity`.

Miscellaneous:

- Haxe 3 is no longer supported.
- `Echoes.update()` will calculate the elapsed time on its own, and no longer takes an argument. If you need to adjust the rate at which time passes, adjust `Echoes.activeSystems.clock`.
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
