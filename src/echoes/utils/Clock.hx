package echoes.utils;

/**
 * A `Clock` determines how to split up chunks of time, allowing you to
 * customize how many times a `SystemList` will update in a row, and the length
 * of each update.
 * 
 * ```haxe
 * //`maxTime` limits the length of a single update, which can be useful to
 * //avoid calculating an ultra-long update after the app is suspended.
 * systemList.clock.maxTime = 0.5;
 * 
 * //Setting both `minTickLength` and `maxTickLength` to a single value creates
 * //a fixed timestep, which helps make physics simulations more reliable.
 * systemList.clock.setFixedTimestep(1 / 60);
 * 
 * //While paused, the `SystemList` won't update.
 * systemList.paused = true; //Equivalent to `systemList.clock.paused = true`.
 * ```
 * 
 * A `SystemList` will update its own clock, but if you create your own
 * instance, you can add time using `addTime()`. This acts like winding an egg
 * timer. Once time is added, the clock will "tick" until it runs out.
 * 
 * ```haxe
 * var clock:Clock = new Clock();
 * clock.maxTickLength = 1 / 60;
 * clock.addTime(0.75);
 * 
 * //To make the clock tick, iterate over it.
 * for(tick in clock) {
 *     update(tick);
 * }
 * ```
 * 
 * Caution: it's possible to set most variables to negative values, but this is
 * unsupported and may cause infinite loops or other unwanted behavior.
 */
class Clock {
	/**
	 * The maximum tick length. By default, tick length is equal to the
	 * remaining `time`, but this can make it shorter.
	 * 
	 * Setting `minTickLength` and `maxTickLength` to the same value creates a
	 * fixed tick length.
	 */
	public var maxTickLength:Float = Math.POSITIVE_INFINITY;
	
	/**
	 * `time` will be capped to this value.
	 */
	public var maxTime:Float = Math.POSITIVE_INFINITY;
	
	/**
	 * Once `time` falls below this value, the `Clock` will stop ticking. Any
	 * leftover time will be saved for later.
	 * 
	 * Setting `minTickLength` and `maxTickLength` to the same value creates a
	 * fixed tick length.
	 */
	public var minTickLength:Float = 1e-16;
	
	/**
	 * Prevents `time` from increasing, but doesn't prevent iterating over
	 * whatever time remains.
	 */
	public var paused:Bool = false;
	
	/**
	 * The amount of time left on the `Clock`, in seconds.
	 * 
	 * To calculate [the blending factor](https://www.gafferongames.com/post/fix_your_timestep/#the-final-touch)
	 * described in "Fix Your Timestep!", divide `time` by `minTickLength`.
	 */
	public var time(default, null):Float = 0;
	
	/**
	 * Multiplies all added time. This can speed time up (if `timeScale > 1`),
	 * slow it down (if `0 < timeScale < 1`), or pause it (if `timeScale == 0`).
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
	
	public inline function hasNext():Bool {
		return time >= minTickLength;
	}
	
	public function next():Float {
		var tick:Float = time > maxTickLength ? maxTickLength : time;
		time -= tick;
		return tick;
	}
	
	/**
	 * Sets `minTickLength` and `maxTickLength` to the given value, ensuring
	 * that every time this clock ticks, the tick will be the same length.
	 */
	public inline function setFixedTickLength(fixedTickLength:Float):Void {
		minTickLength = maxTickLength = fixedTickLength;
	}
}
