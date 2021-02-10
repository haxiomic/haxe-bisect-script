import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using Lambda;
using StringTools;

typedef State = {
	var bad: String;
	var good: String;
}

class Util {

	static public final stateFilePath = 'bisect-state.json';
	static public final initialCwd = sys.FileSystem.absolutePath(Sys.getCwd());
	static public final downloadDir = Path.join([initialCwd, 'downloads']);
	static public final haxeDir = Path.join([initialCwd, '../']);

	static var pageCached = null;
	static public function getNightlyUrls() {
		var page = if (pageCached == null) {
			pageCached = runInDir(downloadDir, () -> {
				exec('wget', ['-N', '-q', 'https://build.haxe.org/builds/haxe/mac/']);
				// older here: https://hxbuilds.s3.us-east-1.amazonaws.com/builds/haxe/mac/index.html
				File.getContent('index.html');
			});
		} else pageCached;
		if (page == null) {
			Console.error('Failed to get page');
			return null;
		}
		var r = ~/href="([^"]+)"/igm;
		var urls = new Array<String>();
		r.map(page, (r) -> {urls.push(r.matched(1).toLowerCase()); '$';});
		return urls;
	}

	static public function getNightlyFilename(hash: String) {
		// find matching url
		var shortHash = hash.substr(0, 7).toLowerCase();
		return getNightlyUrls().find(u -> {
			u.contains(shortHash);
		});
	}

	static public function getHaxeExe(hash: String) {
		return runInDir(downloadDir, () -> {
			// download haxe build for this hash
			var nightlyFilename = getNightlyFilename(hash);

			if (nightlyFilename == null) {
				Console.error('Failed to find download for <b>$hash</>');
				return null;
			}

			if (!FileSystem.exists(nightlyFilename)) {
				Console.log('Downloading <b>$nightlyFilename</b>');
				var url = 'https://build.haxe.org/builds/haxe/mac/$nightlyFilename';
				exec('wget', [url]);
			}

			// unpack
			var unzipDir = Path.withoutExtension(Path.withoutExtension(nightlyFilename));
			exec('mkdir', ['-p', unzipDir]);
			exec('tar', ['-xzf', nightlyFilename, '-C', unzipDir]);

			// get haxe exe
			// find haxe_2019-09-12_4.0_bugfix_4a74534 -name "haxe" -type f -maxdepth 2
			var p = new Process('find', [unzipDir, '-name', 'haxe', '-type', 'f', '-maxdepth', '2']);
			var haxePath = if (p.exitCode(true) == 0) {
				FileSystem.absolutePath(p.stdout.readAll().toString().trim());
			} else throw 'find failed';

			return haxePath;
		});
	}

	static public function runInDir<T>(dir: String, fn: () -> T): T {
		touchDirectoryPath(dir);
		var originalCwd = Path.normalize(Sys.getCwd());
		if (originalCwd != Path.normalize(dir)) {
			cd(dir);
		}
		var ret = fn();
		if (Path.normalize(Sys.getCwd()) != originalCwd) {
			cd(originalCwd);
		}
		return ret;
	}

	static public function exec(cmd: String, ?args: Array<String>) {
		if (args == null) args = [];
		Console.log('Exec: <b>$cmd ${args.join(' ')}</>');
		var c = Sys.command(cmd, args);
		if (c != 0) {
			Console.log('<b,red>\t -> exit: $c</>');
		}
		return c;
	}

	static public function process(cmd: String, ?args: Array<String>) {
		if (args == null) args = [];

		Console.log('Process: <b>$cmd ${args.join(' ')}</>');

		var p = new Process(cmd, args);
		var c = p.exitCode(true);

		if (c != 0) {
			Console.log('<b,red>\t -> exit: $c</>');
		}

		return {
			stdout: p.stdout.readAll().toString(),
			stderr: p.stderr.readAll().toString(),
			exit: c,
		}
	}

	static public function cd(dir: String) {
		Console.log('cd(<b>$dir</>)');
		Sys.setCwd(dir);
	}

	static public function loadState(): State {
		return runInDir(initialCwd, () -> {
			Console.log('Trying to load state from <b>${Path.join([Sys.getCwd(), stateFilePath])}</>');
			haxe.Json.parse(File.getContent(stateFilePath));
		});
	}

	static public function saveState(state: State) {
		runInDir(initialCwd, () -> {
			Console.log('Saving state to <b>${Path.join([Sys.getCwd(), stateFilePath])}</>');
			File.saveContent(stateFilePath, haxe.Json.stringify(state, null, '\t'));
		});
	}

	/**
		Ensures directory structure exists for a given path
		(Same behavior as mkdir -p)
		@throws Any
	**/
	static public function touchDirectoryPath(path: String) {
		var directories = Path.normalize(path).split('/');
		var currentDirectories = [];
		for (directory in directories) {
			currentDirectories.push(directory);
			var currentPath = currentDirectories.join('/');
			if (currentPath == '/') continue;
			if (FileSystem.isDirectory(currentPath)) continue;
			if (!FileSystem.exists(currentPath)) {
				FileSystem.createDirectory(currentPath);
			} else {
				throw 'Could not create directory $currentPath because a file already exists at this path';
			}
		}
	}

}