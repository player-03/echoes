import echoes.*;

using buddy.Should;
using Lambda;

class ViewTest extends buddy.BuddySuite {
	public function new() {
		describe("Test View", {
			var log = '';
			
			var mvs:MatchingViewSystem;
			var ivs:IteratingViewSystem;
			
			beforeEach(Echoes.reset());
			beforeEach({
				log = '';
				mvs = new MatchingViewSystem();
				ivs = new IteratingViewSystem();
			});
			
			describe("Test Matching", {
				var entities:Array<Entity>;
				
				beforeEach({
					Echoes.addSystem(mvs);
					entities = new Array<Entity>();
				});
				
				describe("When add Entities with different Components", {
					beforeEach({
						for(i in 0...300) {
							var e = new Entity();
							e.add(new A());
							if(i % 2 == 0) e.add(new B());
							if(i % 3 == 0) e.add(new C());
							if(i % 4 == 0) e.add(new D());
							if(i % 5 == 0) e.add(new E());
							entities.push(e);
						}
					});
					it("should matching correctly", {
						mvs.a.entities.length.should.be(300);
						mvs.b.entities.length.should.be(150);
						mvs.ab.entities.length.should.be(150);
						mvs.bc.entities.length.should.be(50);
						mvs.abcd.entities.length.should.be(25);
					});
					
					describe("Then add a Component to all Entities", {
						beforeEach({
							for(e in entities) {
								e.add(new C());
							}
							Echoes.update();
						});
						it("should matching correctly", {
							mvs.a.entities.length.should.be(300);
							mvs.b.entities.length.should.be(150);
							mvs.ab.entities.length.should.be(150);
							mvs.bc.entities.length.should.be(150);
							mvs.abcd.entities.length.should.be(75);
						});
					});
					
					describe("Then remove a Component from all Entities", {
						beforeEach({
							for(e in entities) {
								e.remove(C);
							}
							Echoes.update();
						});
						it("should matching correctly", {
							mvs.a.entities.length.should.be(300);
							mvs.b.entities.length.should.be(150);
							mvs.ab.entities.length.should.be(150);
							mvs.bc.entities.length.should.be(0);
							mvs.abcd.entities.length.should.be(0);
						});
						
						describe("Then add a Component to all Entities back", {
							beforeEach({
								for(e in entities) {
									e.add(new C());
								}
								Echoes.update();
							});
							it("should matching correctly", {
								mvs.a.entities.length.should.be(300);
								mvs.b.entities.length.should.be(150);
								mvs.ab.entities.length.should.be(150);
								mvs.bc.entities.length.should.be(150);
								mvs.abcd.entities.length.should.be(75);
							});
						});
					});
					
					describe("Then remove all of Components", {
						beforeEach({
							for(e in entities) {
								e.removeAll();
							}
							Echoes.update();
						});
						it("should matching correctly", {
							mvs.a.entities.length.should.be(0);
							mvs.b.entities.length.should.be(0);
							mvs.ab.entities.length.should.be(0);
							mvs.bc.entities.length.should.be(0);
							mvs.abcd.entities.length.should.be(0);
						});
					});
					
					describe("Then deactivate Entities", {
						beforeEach({
							for(e in entities) {
								e.deactivate();
							}
							Echoes.update();
						});
						it("should matching correctly", {
							mvs.a.entities.length.should.be(0);
							mvs.b.entities.length.should.be(0);
							mvs.ab.entities.length.should.be(0);
							mvs.bc.entities.length.should.be(0);
							mvs.abcd.entities.length.should.be(0);
						});
						
						describe("Then activate Entities", {
							beforeEach({
								for(e in entities) {
									e.activate();
								}
								Echoes.update();
							});
							it("should matching correctly", {
								mvs.a.entities.length.should.be(300);
								mvs.b.entities.length.should.be(150);
								mvs.ab.entities.length.should.be(150);
								mvs.bc.entities.length.should.be(50);
								mvs.abcd.entities.length.should.be(25);
							});
						});
					});
					
					describe("Then destroy Entities", {
						beforeEach({
							for(e in entities) {
								e.destroy();
							}
							Echoes.update();
						});
						it("should matching correctly", {
							mvs.a.entities.length.should.be(0);
							mvs.b.entities.length.should.be(0);
							mvs.ab.entities.length.should.be(0);
							mvs.bc.entities.length.should.be(0);
							mvs.abcd.entities.length.should.be(0);
						});
					});
				});
			});
			
			describe("Test Signals", {
				var e:Entity;
				var onad = function(id:Entity, a:A, v:V) log += '+$v';
				var onrm = function(id:Entity, a:A, v:V) log += '-$v';
				
				beforeEach({
					Echoes.addSystem(mvs);
					mvs.av.onAdded.push(onad);
					mvs.av.onRemoved.push(onrm);
					e = new Entity();
				});
				
				describe("When add matched Components", {
					beforeEach(e.add(new A(), new V(1)));
					it("should be dispatched", log.should.be("+1"));
					
					describe("Then add matched Components again", {
						beforeEach(e.add(new V(2)));
						it("should not be dispatched", log.should.be("+1"));
					});
					
					describe("Then remove matched Components", {
						beforeEach(e.remove(V));
						it("should be dispatched", log.should.be("+1-1"));
						
						describe("Then remove matched Components again", {
							beforeEach(e.remove(V));
							it("should not be dispatched", log.should.be("+1-1"));
						});
						
						describe("Then add matched Components back", {
							beforeEach(e.add(new V(2)));
							it("should be dispatched", log.should.be("+1-1+2"));
						});
					});
					
					describe("Then remove all of Components", {
						beforeEach(e.removeAll());
						it("should be dispatched", log.should.be("+1-1"));
						
						describe("Then remove all of Components again", {
							beforeEach(e.removeAll());
							it("should not be dispatched", log.should.be("+1-1"));
						});
					});
					
					describe("Then deactivate Entity", {
						beforeEach(e.deactivate());
						it("should be dispatched", log.should.be("+1-1"));
						
						describe("Then deactivate Entity again", {
							beforeEach(e.deactivate());
							it("should not be dispatched", log.should.be("+1-1"));
						});
						
						describe("Then activate Entity", {
							beforeEach(e.activate());
							it("should be dispatched", log.should.be("+1-1+1"));
							
							describe("Then activate Entity again", {
								beforeEach(e.activate());
								it("should not be dispatched", log.should.be("+1-1+1"));
							});
						});
					});
					
					describe("Then destroy Entity", {
						beforeEach(e.destroy());
						it("should be dispatched", log.should.be("+1-1"));
						
						describe("Then create new Entity (reuse)", {
							beforeEach(new Entity().add(new A(), new V(2)));
							it("should be dispatched", log.should.be("+1-1+2"));
						});
					});
				});
			});
			
			describe("Test Iterating", {
				var onad = function(id:Entity, a:A, v:V) log += '+$v';
				var onrm = function(id:Entity, a:A, v:V) log += '-$v';
				
				beforeEach({
					Echoes.addSystem(ivs);
					ivs.av.onAdded.push(onad);
					ivs.av.onRemoved.push(onrm);
					for(i in 0...5) new Entity().add(new A(), new V(i));
				});
				
				describe("When iterating", {
					beforeEach({
						ivs.f = function(id, a, v) log += '$v';
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(5));
					it("should have correct log", log.should.be("+0+1+2+3+401234"));
					
					describe("Then add an Entity and iterating", {
						beforeEach({
							new Entity().add(new A(), new V(5));
							Echoes.update();
						});
						it("should have correct length", ivs.av.entities.length.should.be(6));
						it("should have correct log", log.should.be("+0+1+2+3+401234+5012345"));
					});
				});
				
				describe("Then remove Component while iterating", {
					beforeEach({
						ivs.f = function(id, a, v) id.remove(V);
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(0));
					it("should have correct log", log.should.be("+0+1+2+3+4-0-1-2-3-4"));
				});
				
				describe("Then remove all of Components while iterating", {
					beforeEach({
						ivs.f = function(id, a, v) id.removeAll();
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(0));
					it("should have correct log", log.should.be("+0+1+2+3+4-0-1-2-3-4"));
				});
				
				describe("Then destroy Entity while iterating", {
					beforeEach({
						ivs.f = function(id, a, v) id.destroy();
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(0));
					it("should have correct log", log.should.be("+0+1+2+3+4-0-1-2-3-4"));
				});
				
				describe("Then deactivate Entity while iterating", {
					beforeEach({
						ivs.f = function(id, a, v) id.deactivate();
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(0));
					it("should have correct log", log.should.be("+0+1+2+3+4-0-1-2-3-4"));
				});
				
				describe("Then create Entity while iterating", {
					beforeEach({
						ivs.f = function(id, a, v) {
							if('$v' != '9') {
								new Entity().add(new A(), new V(9));
							}
						}
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(10));
					it("should have correct log", log.should.be("+0+1+2+3+4+9+9+9+9+9"));
				});
				
				describe("Then destroy and create Entity while iterating", {
					beforeEach({
						ivs.f = function(id, a, v) {
							if('$v' != '9') {
								id.destroy();
								new Entity().add(new A(), new V(9));
							}
						}
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(5));
					it("should have correct log", log.should.be("+0+1+2+3+4-0+9-1+9-2+9-3+9-4+9"));
				});
				
				describe("Then remove Component while inner iterating", {
					beforeEach({
						ivs.f = function(id, a, v) {
							ivs.av.iter(function(e, a, v) e.remove(V));
						}
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(0));
					it("should have correct log", log.should.be("+0+1+2+3+4-0-1-2-3-4"));
				});
				
				describe("Then remove all of Components while inner iterating", {
					beforeEach({
						ivs.f = function(id, a, v) {
							ivs.av.iter(function(e, a, v) e.removeAll());
						}
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(0));
					it("should have correct log", log.should.be("+0+1+2+3+4-0-1-2-3-4"));
				});
				
				describe("Then destroy Entity while inner iterating", {
					beforeEach({
						ivs.f = function(id, a, v) {
							ivs.av.iter(function(e, a, v) e.destroy());
						}
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(0));
					it("should have correct log", log.should.be("+0+1+2+3+4-0-1-2-3-4"));
				});
				
				describe("Then deactivate Entity while inner iterating", {
					beforeEach({
						ivs.f = function(id, a, v) {
							ivs.av.iter(function(e, a, v) e.deactivate());
						}
						Echoes.update();
					});
					it("should have correct length", ivs.av.entities.length.should.be(0));
					it("should have correct log", log.should.be("+0+1+2+3+4-0-1-2-3-4"));
				});
			});
			
			describe("Test Activate/Deactivate", {
				var onad = function(id:Entity, a:A, v:V) log += '+$v';
				var onrm = function(id:Entity, a:A, v:V) log += '-$v';
				
				beforeEach({
					if(!mvs.av.onAdded.contains(onad)) mvs.av.onAdded.push(onad);
					if(!mvs.av.onRemoved.contains(onrm)) mvs.av.onRemoved.push(onrm);
					for(i in 1...4) new Entity().add(new A(), new V(i));
				});
				
				describe("Initially", {
					it("should not be active", mvs.av.active.should.be(false));
					it("should not have entities", mvs.av.entities.length.should.be(0));
					it("should have on ad signals", mvs.av.onAdded.length.should.be(1));
					it("should have on rm signals", mvs.av.onRemoved.length.should.be(1));
					it("should have correct log", log.should.be(""));
					
					describe("Then activate", {
						beforeEach({
							mvs.av.activate();
						});
						it("should be active", mvs.av.active.should.be(true));
						it("should have entities", mvs.av.entities.length.should.be(3));
						it("should have on ad signals", mvs.av.onAdded.length.should.be(1));
						it("should have on rm signals", mvs.av.onRemoved.length.should.be(1));
						it("should have correct log", log.should.be("+1+2+3"));
						
						describe("Then deactivate", {
							beforeEach({
								mvs.av.deactivate();
							});
							it("should not be active", mvs.av.active.should.be(false));
							it("should not have entities", mvs.av.entities.length.should.be(0));
							it("should not have on ad signals", mvs.av.onAdded.length.should.be(0));
							it("should not have on rm signals", mvs.av.onRemoved.length.should.be(0));
							it("should have correct log", log.should.be("+1+2+3-1-2-3"));
						});
						
						describe("Then reset", {
							beforeEach({
								@:privateAccess mvs.av.reset();
							});
							it("should not be active", mvs.av.active.should.be(false));
							it("should not have entities", mvs.av.entities.length.should.be(0));
							it("should not have on ad signals", mvs.av.onAdded.length.should.be(0));
							it("should not have on rm signals", mvs.av.onRemoved.length.should.be(0));
							it("should have correct log", log.should.be("+1+2+3-1-2-3"));
						});
					});
				});
			});
		});
	}
}

class MatchingViewSystem extends echoes.System {
	public var a:View<A> = makeLinkedView();
	public var b:View<B> = makeLinkedView();
	
	public var ab:View<A, B> = makeLinkedView();
	public var bc:View<B, C> = makeLinkedView();
	
	public var abcd:View<A, B, C, D> = makeLinkedView();
	
	public var av:View<A, V> = makeLinkedView();
}

class IteratingViewSystem extends echoes.System {
	public var av:View<A, V> = makeLinkedView();
	
	public var f:Entity->A->V->Void = null;
	
	@:u function update(id:Entity, a:A, v:V) {
		if(f != null) {
			f(id, a, v);
		}
	}
}

class A {
	public function new() { };
}

class B {
	public function new() { };
}

abstract C(A) {
	public function new() this = new A();
}

abstract D(B) {
	public function new() this = new B();
}

class E extends A {
	public function new() super();
}

class V {
	public var val:Int;
	public function new(val) this.val = val;
	public function toString() return Std.string(val);
}
