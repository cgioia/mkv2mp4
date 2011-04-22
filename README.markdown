This is a command-line utility to convert a video in a [Matroska](http://www.matroska.org/) video container (MKV) to x264 in an MP4 container (M4V), ostensibly for viewing on an AppleTV or an Apple iPad.

The real magic comes in the form of extracting an [SSA/ASS](http://www.matroska.org/technical/specs/subtitles/ssa.html) subtitle track from the Matroska container, converting it to a format accepted by MP4 ([SRT-style subtitles](http://www.matroska.org/technical/specs/subtitles/srt.html)), and muxing it in to the newly converted MP4 file.

While technically this script will run in any Perl environment, reliance on SublerCLI (for subtitle muxing) currently makes it only usable on Mac OS X.

Usage
-----
`mkv2mp4.pl <mkvfile>...`

Prerequisites
-------------
[HandBrakeCLI](http://handbrake.fr/)  
[SublerCLI](http://code.google.com/p/subler/)  
[MKVToolnix](http://www.bunkus.org/videotools/mkvtoolnix/)
