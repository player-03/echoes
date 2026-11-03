package;

import echoes.Echoes;

class Test extends utest.Test {
	private function teardown():Void {
		Echoes.reset();
		MethodCounter.reset();
	}
}
