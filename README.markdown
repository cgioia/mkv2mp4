Description
-----------
This is a command-line utility to convert (using HandBrake) Matroska video (MKV) to MP4 (M4V), ostensibly for viewing on an AppleTV or an Apple iPad.

The real magic comes in the form of extracting an SSA/ASS subtitle track from the Matroska container, converting it to a format accepted by MP4 (SRT-style subtitles), and muxing it in to the newly converted MP4 file.

While technically this script will run in any Perl environment, reliance on SublerCLI (for subtitle muxing) currently makes it only usable on Mac OS X.

Usage
-----
mkv2mp4.pl \<mkvfile\>...

Prerequisites
-------------
[HandBrakeCLI](http://handbrake.fr/)  
[SublerCLI](http://code.google.com/p/subler/)  
[MKVToolnix](http://www.bunkus.org/videotools/mkvtoolnix/)
