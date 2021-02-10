import Util.*;
import haxe.io.Path;
import sys.io.File;

using StringTools;


/**
	- Performs commit bisection using precompiled binaries (macOS)
	- Customize testCommit() and state
**/
class Bisect {

	static function testCommit(hash: String) {
		Console.log('<cyan>Testing commit <b>$hash</b></>');
		var haxePath = getHaxeExe(hash);

		if (haxePath == null) {
			throw 'Failed to get prebuilt haxe';
		}

		cd(Util.haxeDir);
		
		cd('find-break/haxe-10112');
		exec('rm', ['-rf', 'bin']);

		// trying compiling js unit tests
		var haxeResult = process(haxePath, ['build.hxml']);

		if (haxeResult.exit != 0) {
			Console.examine(haxeResult);
		}

		return haxeResult.exit == 0;
	}

	static function main() {
		var state = try loadState() catch(e: Any) {
			// Console.error('Setup an initial state in the haxe file (good and bad commits)');
			// Console.error('Then edit testCommit() to suit your problem');
			// Console.error('Finally remove these messages and run!');
			// return;
			// for example:
			{
				bad:  '9182dfb',
				good: '0a01bda',
			}
		}

		Console.examine(state);

		var nightlyHashes = getNightlyUrls()
		// filter only development branch nightlies
		.filter(url -> url.contains('development'))
		.map(url -> {
			var hashPattern = ~/_([a-z0-9]{7})\.tar\.gz$/i;
			return if (hashPattern.match(url)) {
				hashPattern.matched(1).toLowerCase();
			} else null;
		})
		.filter(h -> h != null);

		function iterate() {
			var goodIndex = nightlyHashes.indexOf(state.good.substr(0, 7).toLowerCase());
			var badIndex = nightlyHashes.indexOf(state.bad.substr(0, 7).toLowerCase());
			if (goodIndex == -1) throw 'good hash ${state.good} not found';
			if (badIndex == -1) throw 'bad hash ${state.bad} not found';

			var midIndex = Math.round((goodIndex + badIndex) * 0.5);
			var midHash = nightlyHashes[midIndex];

			if (midIndex == goodIndex || midIndex == badIndex) {
				Console.log('DONE');
				return;
			}

			Console.examine(goodIndex, badIndex, midIndex, midHash);

			if (testCommit(midHash)) {
				Console.log('Hash is <green>good</> <b,green>$midHash</>');
				state.good = midHash;
			} else {
				Console.log('Hash is <red>bad</> <b,red>$midHash</>');
				state.bad = midHash;
			}

			saveState(state);

			iterate();
		}

		iterate();
	}

}