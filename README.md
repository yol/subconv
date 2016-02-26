subconv - Ruby SCC (EIA-608) to WebVTT subtitle converter
=========================================================

This Ruby Gem provides conversion of subtitle files in the .scc (Scenarist Closed
Captions) format to the more modern WebVTT format that can be used in browsers
with HTML5 videos.

The processing is modeled after [https://dvcs.w3.org/hg/text-tracks/raw-file/default/608toVTT/608toVTT.html].

Installation
------------
	gem install subconv

Usage
-----
        $ subconv --help
        Usage: subconv [options] SCC-FILE
            -o, --out-file FILENAME          Write output to specified file instead of stdout
            -f, --fps FPS                    Assume given video fps for timecode calculation (default: 29.97)
            -c, --no-color                   Remove all color information from output
            -F, --no-flash                   Remove all flash (blinking) information from output
            -s, --simple-positions           Convert to simple top/bottom center-aligned captions
            -h, --help                       Show this help message and quit.

The API can also be used programmatically, the `bin/subconv` file is just an
example for this.

Supported features
------------------
* EIA-608 parsing and conversion to WebVTT
  * Pop-on captions
  * Full positioning
  * All special characters defined in the standard
  * All colors
  * Italics
  * Underline
  * Flash
* Optional removal of certain features during the conversion
  * Color
  * Flash
  * Conversion of fine position information to just top/bottom center

Note that with all features removed, most browsers can display the captions as-is,
but for the colors etc. to work you will need to include a stylesheet that defines
appropriate styles. The one used in the W3C report is packaged here in `dist/eia608.css`.
Even then, browsers currently do not correctly support numerous settings yet. Infamously,
Firefox can not apply classes/styles inside cues at all.

Unsupported features
--------------------
* Roll-up captions
* Paint-on captions
* EIA-708
