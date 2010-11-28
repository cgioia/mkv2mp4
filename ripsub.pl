#!/usr/bin/perl

foreach ( @ARGV ) {
   ($subname) = $_ =~ /(?:\[.*?\])([^\[\(]+)/;
   foreach ( $subname ) { s/^[\s_]+//; s/[\s_]+$//; s/\s/_/g; }
   $info = `mkvmerge --identify '$_'`;
   ($track) = $info =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/;
   system( "mkvextract tracks '$_' $track:$subname.ass" );
}
