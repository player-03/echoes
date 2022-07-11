import echoes.utils.Signal;

using buddy.Should;

class SignalTest extends buddy.BuddySuite {
	public function new() {
		describe("Signal", {
			var s:Signal<Int->O->Void>;
			var r:String;
			
			beforeEach({
				s = new Signal<Int->O->Void>();
				r = '';
			});
			
			describe("When add listener", {
				var f1 = function(i:Int, o:O) r += '1_$i$o';
				beforeEach({
					s.push(f1);
				});
				it("should be added", s.contains(f1).should.be(true));
				it("should have correct size", s.length.should.be(1));
				
				describe("When remove listener", {
					beforeEach({
						s.remove(f1);
					});
					it("should be removed", s.contains(f1).should.be(false));
					it("should have correct size", s.length.should.be(0));
					
					describe("When dispatch", {
						beforeEach({
							s.dispatch(1, new O('1'));
						});
						it("should not be dispatched", r.should.be(""));
					});
				});
				
				describe("When remove all of listeners", {
					beforeEach({
						s.resize(0);
					});
					it("should be removed", s.contains(f1).should.be(false));
					it("should have correct size", s.length.should.be(0));
					
					describe("When dispatch", {
						beforeEach({
							s.dispatch(1, new O('1'));
						});
						it("should not be dispatched", r.should.be(""));
					});
				});
				
				describe("When dispatch", {
					beforeEach({
						s.dispatch(1, new O('1'));
					});
					it("should be dispatched", r.should.be("1_11"));
				});
				
				describe("When add a second listener", {
					var f2 = function(i:Int, o:O) r += '2_$i$o';
					beforeEach({
						s.push(f2);
					});
					it("should be added", s.contains(f2).should.be(true));
					it("should have correct size", s.length.should.be(2));
					
					describe("When remove a second listener", {
						beforeEach({
							s.remove(f2);
						});
						it("should not be removed", s.contains(f1).should.be(true));
						it("should be removed", s.contains(f2).should.be(false));
						it("should have correct size", s.length.should.be(1));
						
						describe("When dispatch", {
							beforeEach({
								s.dispatch(1, new O('1'));
							});
							it("should not be dispatched", r.should.be("1_11"));
						});
					});
					
					describe("When remove all of listeners", {
						beforeEach({
							s.resize(0);
						});
						it("should be removed", s.contains(f1).should.be(false));
						it("should be removed", s.contains(f2).should.be(false));
						it("should have correct size", s.length.should.be(0));
						
						describe("When dispatch", {
							beforeEach({
								s.dispatch(1, new O('1'));
							});
							it("should not be dispatched", r.should.be(""));
						});
					});
					
					describe("When dispatch", {
						beforeEach({
							s.dispatch(1, new O('1'));
						});
						it("should be dispatched", r.should.be("1_112_11"));
					});
				});
			});
		});
	}
}

class O {
	private var val:String;
	public function new(val) this.val = val;
	public function toString() return val;
}
