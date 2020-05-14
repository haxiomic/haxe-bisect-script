import Util.*;
import haxe.io.Path;
import sys.io.File;

using StringTools;


/**
	- Performs commit bisection using precompiled binaries (macOS)
	- Customize testCommit() and state
**/
class Bisect {

	static function main() {
		var state = try loadState() catch(e: Any) {
			Console.error('Setup an initial state in the haxe file (good and bad commits)');
			Console.error('Then edit testCommit() to suit your problem');
			Console.error('Finally remove these messages and run!');
			return;
			// for example:
			{
				bad:  'ab39d7af227ab200a5d3e3dab1ec796987b6ba28',
				good: '8bd1bac',
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

	static function testCommit(hash: String) {
		Console.log('<cyan>Testing commit <b>$hash</b></>');
		var haxePath = getHaxeExe(hash);

		if (haxePath == null) {
			throw 'Failed to get prebuilt haxe';
		}

		cd(Util.haxeDir);

		// throw away local changes
		exec('git', ['reset', 'HEAD', '--hard']);
		if (exec('git', ['checkout', hash]) != 0) {
			throw 'Failed to checkout <b>$hash</>';
		}

		// patch Printer.hx in std/ of downloaded haxe
		{
			var printerPath = Path.directory(haxePath) + '/std/haxe/macro/Printer.hx';
			var printerHx = File.getContent(printerPath);

			// replace 
			// public function printComplexType(ct:ComplexType) *** public function
			
			var startPattern = ~/public function printComplexType\(ct:ComplexType\)/gm;
			var endPattern = ~/public function/;

			startPattern.match(printerHx);
			endPattern.match(startPattern.matchedRight());
			var before = startPattern.matchedLeft();
			var after = endPattern.matchedRight();

			var newContent = before + replacement + '\tpublic function' +  after;

			Console.log('<yellow>Patching <b>$printerPath</b></>');

			File.saveContent(printerPath, newContent);
		}
		
		// remove -D analyzer-optimize
		// {
		// 	var compileEachPath = haxeDir + '/tests/unit/compile-each.hxml';
		// 	Console.log('<yellow>Patching <b>$compileEachPath</b></>');
		// 	File.saveContent(compileEachPath, File.getContent(compileEachPath).replace('-D analyzer-optimize', ''));
		// }

		cd('tests/unit');

		// trying compiling js unit tests
		var haxeResult = process(haxePath, ['compile-js.hxml']);

		if (haxeResult.exit != 0) {
			Console.examine(haxeResult);
		}

		return haxeResult.exit == 0;
	}

	static var replacement = "
	// @! PATCHED @!
	public function printComplexType(ct:ComplexType) {
		return switch (ct) {
			case TPath(tp): printTypePath(tp);
			case TFunction(args, ret):
				var wrapArgumentsInParentheses = switch args {
					// type `:(a:X) -> Y` has args as [TParent(TNamed(...))], i.e `a:X` gets wrapped in `TParent()`. We don't add parentheses to avoid printing `:((a:X)) -> Y`
					case [TParent(t)]: false;
					// this case catches a single argument that's a type-path, so that `X -> Y` prints `X -> Y` not `(X) -> Y`
					case [TPath(_) | TOptional(TPath(_))]: false;
					default: true;
				}
				var argStr = args.map(printComplexType).join(\", \");
				(wrapArgumentsInParentheses ? '($argStr)' : argStr) + \" -> \" + (

					/**
						@! this is the repro of the compiler issue:

						- The following expression should be equivalent to just `printComplexType(ret)` because the switch is redundant
						- When testing in simple examples everything works as expected
						- When compiling the unit tests (e.g. `haxe compile-js.hxml`), haxe fails with:
							`Cannot use Void as value`
						- If it's tweaked to compile it generates the wrong code on all targets
						- It doesn't seem to matter what we're switching on, so I've just used `true` for simplicity (see #9385 for original example)
					**/
					switch true {
						default: printComplexType(ret);
					}

				);
			case TAnonymous(fields): \"{ \" + [for (f in fields) printField(f) + \"; \"].join(\"\") + \"}\";
			case TParent(ct): \"(\" + printComplexType(ct) + \")\";
			case TOptional(ct): \"?\" + printComplexType(ct);
			case TNamed(n, ct): n + \":\" + printComplexType(ct);
			case TExtend(tpl, fields): '{> ${tpl.map(printTypePath).join(\" >, \")}, ${fields.map(printField).join(\", \")} }';
			case TIntersection(tl): tl.map(printComplexType).join(\" & \");
		}
	}

	// @! PATCHED @!

";

}