import echoes.*;

using buddy.Should;

class ComponentTypeTest extends buddy.BuddySuite {
	public function new() {
		describe("Test Components of Different Types", {
			var e:Entity;
			var s:ComponentTypeSystem;
			
			beforeEach({
				Echoes.reset();
			});
			
			describe("When create System with Views of Components of Different Types", {
				beforeEach({
					e = new Entity();
					s = new ComponentTypeSystem();
					Echoes.addSystem(s);
				});
				
				it("views should be empty", {
					s.objects.entities.length.should.be(0);
					s.abstractObjects.entities.length.should.be(0);
					s.abstractPrimitives.entities.length.should.be(0);
					s.enums.entities.length.should.be(0);
					s.enumAbstracts.entities.length.should.be(0);
					s.iobjects.entities.length.should.be(0);
					s.extendObjects.entities.length.should.be(0);
					s.typeParams.entities.length.should.be(0);
					s.nestedTypeParams.entities.length.should.be(0);
					s.funcs.entities.length.should.be(0);
				});
				
				describe("Then get Echoes info", {
					var str = "\\# \\( 1 \\) \\{ 12 \\} \\[ 1 \\| 0 \\]";
					#if echoes_profiling
					str += " : \\d ms";
					str += "\n    ComponentTypeSystem : \\d ms";
					str += "\n    \\{ComponentTypeTest\\.ObjectComponent\\} \\[0\\]";
					str += "\n    \\{ComponentTypeTest\\.AbstractObjectComponent\\} \\[0\\]";
					str += "\n    \\{ComponentTypeTest\\.AbstractPrimitive\\} \\[0\\]";
					str += "\n    \\{ComponentTypeTest\\.EnumComponent\\} \\[0\\]";
					str += "\n    \\{ComponentTypeTest\\.EnumAbstractComponent\\} \\[0\\]";
					str += "\n    \\{ComponentTypeTest\\.IObjectComponent\\} \\[0\\]";
					str += "\n    \\{ComponentTypeTest\\.ExtendObjectComponent\\} \\[0\\]";
					str += "\n    \\{ComponentTypeTest\\.TypeParamComponent<ComponentTypeTest\\.ObjectComponent>\\} \\[0\\]";
					str += "\n    \\{ComponentTypeTest\\.TypeParamComponent<Array<ComponentTypeTest\\.ObjectComponent>>\\} \\[0\\]";
					str += "\n    \\{\\(ComponentTypeTest\\.ObjectComponent, ComponentTypeTest\\.ObjectComponent\\) -> StdTypes\\.Void\\} \\[0\\]";
					str += "\n    \\{\\(ComponentTypeTest\\.ObjectComponent -> ComponentTypeTest\\.ObjectComponent\\) -> StdTypes\\.Void\\} \\[0\\]";
					str += "\n    \\{Array<ComponentTypeTest\\.ObjectComponent -> ComponentTypeTest\\.ObjectComponent> -> StdTypes\\.Void\\} \\[0\\]";
					#end
					beforeEach({
						Echoes.update();
					});
					it("should have correct result", Echoes.info().should.match(new EReg(str, "")));
				});
				
				describe("Then add an ObjectComponent", {
					var c1 = new ObjectComponent("A");
					beforeEach(e.add(c1));
					it("should be returned by ObjectComponent", e.get(ObjectComponent).should.be(c1));
					it("should be returned by TypedefObjectComponent", e.get(TypedefObjectComponent).should.be(c1));
					it("should not be returned by AbstractObjectComponent", e.get(AbstractObjectComponent).should.not.be(c1));
					it("should be collected by View<ObjectComponent>", s.objects.entities.length.should.be(1));
				});
				
				describe("Then add an AbstractObjectComponent", {
					var c2 = new AbstractObjectComponent("A");
					beforeEach(e.add(c2));
					it("should not be returned by ObjectComponent", e.get(ObjectComponent).should.not.be(c2));
					it("should not be returned by TypedefObjectComponent", e.get(TypedefObjectComponent).should.not.be(c2));
					it("should be returned by AbstractObjectComponent", e.get(AbstractObjectComponent).should.be(c2));
					it("should be collected by View<AbstractObjectComponent>", s.abstractObjects.entities.length.should.be(1));
				});
				
				describe("Then add an AbstractPrimitiveComponent", {
					var c3 = new AbstractPrimitive(1);
					beforeEach(e.add(c3));
					it("should be returned by AbstractPrimitive", e.get(AbstractPrimitive).should.be(c3));
					it("should be collected by View<AbstractPrimitive>", s.abstractPrimitives.entities.length.should.be(1));
				});
				
				describe("Then add an EnumComponent", {
					var c4 = EnumComponent.E1("A");
					beforeEach(e.add(c4));
					it("should be returned by EnumComponent", e.get(EnumComponent).should.equal(c4));
					it("should return correct value", e.get(EnumComponent).should.equal(EnumComponent.E1("A")));
					it("should be collected by View<EnumComponent>", s.enums.entities.length.should.be(1));
				});
				
				describe("Then add an EnumAbstractComponent", {
					var c5 = EnumAbstractComponent.EA1;
					beforeEach(e.add(c5));
					it("should be returned by EnumAbstractComponent", e.get(EnumAbstractComponent).should.be(c5));
					it("should return correct value", e.get(EnumAbstractComponent).should.be(EnumAbstractComponent.EA1));
					it("should be collected by View<EnumAbstractComponent>", s.enumAbstracts.entities.length.should.be(1));
				});
				
				describe("Then add an IObjectComponent", {
					var c6 = (new ObjectComponent("A"):IObjectComponent);
					beforeEach(e.add(c6));
					it("should be returned by IObjectComponent", e.get(IObjectComponent).should.be(c6));
					it("should not be returned by ObjectComponent", e.get(ObjectComponent).should.not.be(c6));
					it("should be collected by View<IObjectComponent>", s.iobjects.entities.length.should.be(1));
				});
				
				describe("Then add an ExtendObjectComponent", {
					var c7 = new ExtendObjectComponent("A");
					beforeEach(e.add(c7));
					it("should be returned by ExtendObjectComponent", e.get(ExtendObjectComponent).should.be(c7));
					it("should not be returned by ObjectComponent", e.get(ObjectComponent).should.not.be(c7));
					it("should be collected by View<ExtendObjectComponent>", s.extendObjects.entities.length.should.be(1));
				});
				
				describe("Then add a TypeParamComponent", {
					var c8 = new TypeParamComponent<ObjectComponent>(new ObjectComponent("A"));
					beforeEach(e.add(c8));
					it("should be returned by TypeParamComponent", e.get(TypedefTypeParamComponent).should.be(c8));
					it("should not be returned by another TypeParamComponent", e.get(TypedefAnotherTypeParamComponent).should.not.be(c8));
					it("should be collected by View<TypeParamComponent>", s.typeParams.entities.length.should.be(1));
				});
				
				describe("Then add a NestedTypeParamComponent", {
					var c9 = new TypeParamComponent<Array<ObjectComponent>>([ new ObjectComponent("A") ]);
					beforeEach(e.add(c9));
					it("should be returned by NestedTypeParamComponent", e.get(TypedefNestedTypeParamComponent).should.be(c9));
					it("should not be returned by TypeParamComponent", e.get(TypedefTypeParamComponent).should.not.be(c9));
					it("should not be returned by another TypeParamComponent", e.get(TypedefAnotherTypeParamComponent).should.not.be(c9));
					it("should be collected by View<NestedTypeParamComponent>", s.nestedTypeParams.entities.length.should.be(1));
				});
				
				describe("Then add a Function", {
					var f1 = function(o1:ObjectComponent, o2:ObjectComponent) { trace("!"); };
					beforeEach(e.add(f1));
					it("should be returned by typedef", e.get(TypedefFunc).should.be(f1));
					it("should be collected by correct view", s.funcs.entities.length.should.be(1));
					it("should not be returned by other typedefs", {
						e.get(TypedefNestedFunc).should.not.be(f1);
						e.get(TypedefTypeParamFunc).should.not.be(f1);
					});
					it("should not be collected by other views", {
						s.nestedFuncs.entities.length.should.be(0);
						s.typeParamFuncs.entities.length.should.be(0);
					});
				});
				
				describe("Then add a Nested Function", {
					var f2 = function(f:ObjectComponent->ObjectComponent) { trace("!"); };
					beforeEach(e.add(f2));
					it("should be returned by typedef", e.get(TypedefNestedFunc).should.be(f2));
					it("should be collected by correct view", s.nestedFuncs.entities.length.should.be(1));
					it("should not be returned by other typedefs", {
						e.get(TypedefFunc).should.not.be(f2);
						e.get(TypedefTypeParamFunc).should.not.be(f2);
					});
					it("should not be collected by other views", {
						s.funcs.entities.length.should.be(0);
						s.typeParamFuncs.entities.length.should.be(0);
					});
				});
				
				describe("Then add a Type Param Function", {
					var f3 = function(a:Array<ObjectComponent->ObjectComponent>) { trace("!"); };
					beforeEach(e.add(f3));
					it("should be returned by typedef", e.get(TypedefTypeParamFunc).should.be(f3));
					it("should be collected by correct view", s.typeParamFuncs.entities.length.should.be(1));
					it("should not be returned by other typedefs", {
						e.get(TypedefNestedFunc).should.not.be(f3);
						e.get(TypedefFunc).should.not.be(f3);
					});
					it("should not be collected by other views", {
						s.funcs.entities.length.should.be(0);
						s.nestedFuncs.entities.length.should.be(0);
					});
				});
			});
		});
	}
}

class ObjectComponent implements IObjectComponent {
	private var value:String;
	public function new(v:String) this.value = v;
	public function getValue() return value;
}

@:eager typedef TypedefObjectComponent = ObjectComponent;

@:forward(getValue)
abstract AbstractObjectComponent(ObjectComponent) {
	public function new(v:String) this = new ObjectComponent(v);
}

abstract AbstractPrimitive(Null<Int>) from Null<Int> to Null<Int> {
	public function new(i:Int) this = i;
}

enum EnumComponent {
	E1(value:String);
	E2(value:Int);
}

@:enum
abstract EnumAbstractComponent(Null<Int>) from Null<Int> to Null<Int> {
	var EA1 = 1;
	var EA2 = 2;
}

interface IObjectComponent {
	function getValue():String;
}

class ExtendObjectComponent extends ObjectComponent {
	public function new(v:String) {
		super(v);
	}
}

class TypeParamComponent<T> {
	private var value:T;
	public function new(v:T) {
		this.value = v;
	}
}

@:eager typedef TypedefTypeParamComponent = TypeParamComponent<ObjectComponent>;
@:eager typedef TypedefAnotherTypeParamComponent = TypeParamComponent<ExtendObjectComponent>;

@:eager typedef TypedefNestedTypeParamComponent = TypeParamComponent<Array<ObjectComponent>>;

@:eager typedef TypedefFunc = ObjectComponent->ObjectComponent->Void;
@:eager typedef TypedefNestedFunc = (ObjectComponent->ObjectComponent)->Void;
@:eager typedef TypedefTypeParamFunc = Array<ObjectComponent->ObjectComponent>->Void;

class ComponentTypeSystem extends System {
	public var objects:View<ObjectComponent> = makeLinkedView();
	public var abstractObjects:View<AbstractObjectComponent> = makeLinkedView();
	public var abstractPrimitives:View<AbstractPrimitive> = makeLinkedView();
	public var enums:View<EnumComponent> = makeLinkedView();
	public var enumAbstracts:View<EnumAbstractComponent> = makeLinkedView();
	public var iobjects:View<IObjectComponent> = makeLinkedView();
	public var extendObjects:View<ExtendObjectComponent> = makeLinkedView();
	public var typeParams:View<TypeParamComponent<ObjectComponent>> = makeLinkedView();
	public var nestedTypeParams:View<TypeParamComponent<Array<ObjectComponent>>> = makeLinkedView();
	public var funcs:View<ObjectComponent->ObjectComponent->Void> = makeLinkedView();
	public var nestedFuncs:View<(ObjectComponent->ObjectComponent)->Void> = makeLinkedView();
	public var typeParamFuncs:View<Array<ObjectComponent->ObjectComponent>->Void> = makeLinkedView();
}
