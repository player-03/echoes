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
  - For usage instructions, [see below](#sample-usage).
- The [workflow](src/echoes/Workflow.hx) (singular) tracks all active entities and systems.
  - Usage: Call `Workflow.addSystem()` to activate each of your systems. Alternatively, you can add your systems to a [`SystemList`](src/echoes/SystemList.hx), and add that to the workflow instead.
  - At regular intervals (typically once per frame), call `Workflow.update()` to run the game.

### Sample usage

```haxe
import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.Workflow;

class EchoesExample {
  public static function main():Void {
    var physicsSystems:SystemList = new SystemList("Physics");
    physicsSystems.add(new MovementSystem());
    physicsSystems.add(new CollisionSystem());
    
    Workflow.addSystem(physicsSystems);
    Workflow.addSystem(new Render());
    
    //Create three entities: two rabbits and one tree.
    var john:Entity = createRabbit(0, 0, 2.5, 0, "John");
    var jack:Entity = createRabbit(100, 0, -2.5, 0, "Jack");
    createTree(60, 0);
    
    //You can manually access and modify components, if needed.
    trace(jack.get(Position).x); //100
    john.get(Velocity).x = 3.5;
    trace(john.get(Velocity)); //{ x: 3.5, y: 0 }
    
    //Each component has a specific type. Even though `Name` is a typedef of
    //`String`, Echoes considers them to be different.
    trace(jack.get(String)); //null
    trace(jack.get(Name)); //"Jack"
    
    //Update the workflow 60 times per second.
    new Timer(Std.int(1000 / 60)).run = Workflow.update;
  }
  
  private static function createTree(x:Float, y:Float):Entity {
    return new Entity()
      .add(new Position(x, y))
      .add(new Bitmap(Assets.getBitmapData("assets/tree.png")));
  }
  
  private static function createRabbit(x:Float, y:Float, vx:Float, vy:Float, name:Name):Entity {
    var pos:Position = new Position(x, y);
    var vel:Velocity = new Velocity(vx, vy);
    var bmp:Bitmap = new Bitmap(Assets.getBitmapData("assets/rabbit.png"));
    return new Entity().add(pos, vel, bmp, name);
  }
}

typedef Name = String;

class MovementSystem extends System {
  private var timeElapsed:Float = 0;
  
  //@:update functions will be called once per frame per matching entity. Here,
  //a "matching entity" is one with both a `Position` and a `Velocity`. (The
  //`Float` argument is a special case, and is not treated as a component.)
  @:update
  private function updatePosition(position:Position, velocity:Velocity, time:Float):Void {
      //Changing the entity's position a small amount each frame produces the
      //appearance of smooth motion.
      position.x += velocity.x * time;
      position.y += velocity.y * time;
  }
  
  /**
   * This `View` object lists every entity with a `Velocity`. Because the `View`
   * constructor is private, you must call `getView()` instead.
   */
  private var velocityView:View<Velocity> = getView();
  
  //Functions without arguments, or with only a `Float` argument, will be called
  //only once per update.
  @:update private function countTime(time:Float):Void {
    if(timeElapsed < 0) {
      return;
    }
    
    timeElapsed += time;
    
    if(timeElapsed >= 20) {
      trace("Race over!");
      
      for(entity in velocityView.entities) {
        //An entity in `velocityView` is guaranteed to have a `Velocity`.
        var velocity:Velocity = entity.get(Velocity);
        velocity.x = 0;
        velocity.y = 0;
      }
    }
  }
}

class Render extends System {
  private var scene:DisplayObjectContainer;
  
  //Constructors are allowed but not required.
  public function new() {
    scene = Lib.current;
  }
  
  //@:add functions are called when an entity gains _all_ of the required
  //components. In this case, there's just one.
  @:add private function onBitmapAdded(bmp:Bitmap):Void {
    scene.addChild(spr);
  }
  
  //@:remove functions are called when an entity that previously had every
  //required component loses _any_ of them. Note that `Entity` is a special
  //type (similar to `Float`), and never affects when a function will be called.
  @:remove private function onBitmapRemoved(bmp:Bitmap, entity:Entity):Void {
    //The listener can always access the removed value.
    scene.removeChild(bmp);
    
    //Listeners can access other components, assuming those components exist.
    if(entity.exists(Name)) {
      trace('Oh my god! They removed ${ e.get(Name) }!');
    }
  }
  
  //You can shorten the meta tags if you like. @:u is equivalent to @:update.
  @:u private function updateBitmapPosition(bmp:Bitmap, pos:Position):Void {
    bmp.x = pos.x;
    bmp.y = pos.y;
  }
  
  //A system's @:update functions will run in order. Since this one comes last,
  //it will only run after all bitmap positions have been updated.
  @:update private function finalize():Void {
    //Render the scene, or otherwise finish up.
  }
}
```

### Compiler flags
Echoes offers a few ways to customize compilation.

- `-Dechoes_profiling` turns on time tracking. With this flag enabled, `Workflow.info()` will return a list of how much time was spent on each system during the most recent update.
- `-Dechoes_report` lists all known components and views at the end of compilation.
- `-Dechoes_array_container` causes Echoes to store data in `Array` format, rather than `IntMap` format. This is less efficient in most cases, but may help if your entities all use the same set of components.
- `-Dechoes_max_name_length=[number]` adjusts the length of generated class names, which can help if you exceed your operating system's filename length limit.

## Installation

```bash
haxelib git echoes https://github.com/player-03/echoes.git
```
