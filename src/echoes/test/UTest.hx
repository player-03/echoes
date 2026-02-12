package echoes.test;

#if utest

import haxe.macro.Expr;
import utest.ITest;
import utest.Runner;

/**
 * Helper functions for [utest](https://github.com/haxe-utest/utest).
 */
class UTest {
	//Called from test cases
	//======================
	
	/**
	 * Runs `Echoes.activeSystems` for `deltaTime` seconds, `count` times. The
	 * total duration is therefore `deltaTime * count`.
	 */
	public static function update(?deltaTime:Float = 1, ?count:Int = 1):Void {
		for(_ in 0...count) {
			Echoes.activeSystems.__update__(deltaTime);
		}
	}
	
	//Called from main
	//================
	
	/**
	 * Makes `runner` call `Echoes.reset()` in between tests.
	 */
	public static inline function resetBetweenTests(runner:Runner):Void {
		runner.onTestComplete.add(_ -> Echoes.reset());
	}
	
	/**
	 * Runs the given tests, calling `Echoes.reset()` after each one.
	 * @see `utest.UTest.run()`
	 */
	public static function run<T:ITest>(cases:Array<T>, ?callback:() -> Void):Void {
		final runner = new Runner();
		
		for(c in cases) {
			runner.addCase(c);
		}
		if(callback != null) {
			runner.onComplete.add(_ -> callback());
		}
		
		resetBetweenTests(runner);
		
		utest.ui.Report.create(runner);
		runner.run();
	}
	
	/**
	 * Runs all test cases from the given packages, including sub-packages,
	 * calling `Echoes.reset()` after each one.
	 * @param packages One or more dot paths as a string or field expression.
	 * Pass multiple arguments if needed, not an array.
	 * @see utest.Runner#addCases
	 */
	public static macro function runCases(packages:Array<Expr>):Expr {
		final cases:Array<Expr> = [for(p in packages)
			macro runner.addCases($p)];
		
		return macro {
			var runner = new utest.Runner();
			
			$b{ cases }
			
			echoes.test.UTest.resetBetweenTests(runner);
			
			utest.ui.Report.create(runner);
			runner.run();
		};
	}
}

#end
