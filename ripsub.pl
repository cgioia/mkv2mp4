#!/usr/bin/perl
use File::Basename;

foreach ( @ARGV ) {
   ($subname) = basename($_) =~ /(?:\[.*?\])?([^\[\(]+)/;
   foreach ( $subname ) { s/^[\s_]+//; s/[\s_]+$//; s/_/ /g; }
   #$info = `mkvmerge --identify "$_"`;
   #($track) = $info =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/;
   ($track) = `mkvmerge -i "$_"` =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/;
   @args = ( "mkvextract", "tracks", $_, "$track:$subname.ass" );
   #system( @args );
   foreach (@args) { print "$_ "; }
   print "\n";
}
