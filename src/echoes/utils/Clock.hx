package echoes.utils;

/**
 * A `Clock` determines how to split up chunks of time, and functions something
 * like an egg timer. You can add time to the clock using `addTime()`, at which
 * point it will split that time into smaller chunks (called "ticks"). To access
 * these ticks, iterate over the `Clock`.
 * 
 * ```haxe
 * var clock:Clock = new Clock();
 * clock.maxTickLength = 1 / 60;
 * clock.addTime(deltaTime);
 * 
 * for(tick in clock) {
 *     update(tick);
 * }
 * ```
 */
class Clock {
	/**
	 * The amount of time left on the `Clock`.
	 */
	public var time(default, null):Float = 0;
	
	/**
	 * `time` will be capped to this value.
	 */
	public var maxTime:Float = Math.POSITIVE_INFINITY;
	
	/**
	 * Prevents `time` from increasing, but doesn't prevent iterating over
	 * whatever time remains.
	 */
	public var paused:Bool = false;
	
	/**
	 * Once `time` falls below this value, the `Clock` will stop ticking. Any
	 * leftover time will be saved for later.
	 * 
	 * Setting `minTickLength` and `maxTickLength` to the same value creates a
	 * fixed tick length.
	 */
	public var minTickLength:Float = 1e-16;
	
	/**
	 * The maximum tick length. By default, tick length is equal to the
	 * remaining `time`, but this can make it shorter.
	 * 
	 * Setting `minTickLength` and `maxTickLength` to the same value creates a
	 * fixed tick length.
	 */
	public var maxTickLength:Float = Math.POSITIVE_INFINITY;
	
	/**
	 * Multiplies all added time. This can speed time up (if `timeScale > 1`),
	 * slow it down (if `0 < timeScale < 1`), or pause it (if `timeScale == 0`).
	 * Caution: negative values are not officially supported.
	 */
	public var timeScale:Float = 1;
	
	public inline function new() {
	}
	
	public function addTime(time:Float):Void {
		if(!paused) {
			this.time += time * timeScale;
			
			if(this.time > maxTime) {
				this.time = maxTime;
			}
		}
	}
	
	public function hasNext():Bool {
		return time >= minTickLength;
	}
	
	public function next():Float {
		var tick:Float = time > maxTickLength ? maxTickLength : time;
		time -= tick;
		return tick;
	}
}
