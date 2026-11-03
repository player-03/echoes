package echoes.test;

/**
 * Helper functions for test cases.
 */
class Utils {
	/**
	 * Runs `Echoes.activeSystems` for `deltaTime` seconds, `count` times. The
	 * total duration is therefore `deltaTime * count`.
	 */
	public static function update(?deltaTime:Float = 1, ?count:Int = 1):Void {
		for(_ in 0...count) {
			Echoes.activeSystems.__update__(deltaTime);
		}
	}
}
