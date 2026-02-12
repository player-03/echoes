package;

import echoes.test.UTest;

class Main {
	public static function main():Void {
		UTest.run([
			new BasicFunctionalityTest(),
			new AdvancedFunctionalityTest(),
			new EdgeCaseTest()
		]);
	}
}
