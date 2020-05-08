This is a rough and dirty script used to find breaking changes to the haxe compiler

It does so by checking out pre-built nightly binaries

To use, drop this directory into your local clone of haxe, cd into `haxe-bisect-script` and run `haxe run.hxml`

The script is meant to be changed by hand, edit **Bisect.hx** to suit your own problem