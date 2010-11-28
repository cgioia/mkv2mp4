#!/usr/bin/perl
use warnings;
use File::Basename;

foreach ( @ARGV ) {
   ($name, $path, $suffix) = fileparse( $_, qr/\.[^.]*/ );
   if ( $suffix eq ".mkv" ) {
      ($subname) = $name =~ /(?:\[.*?\])?([^\[\(]+)/;
      foreach ( $subname ) { s/^[\s_]+//; s/[\s_]+$//; s/_/ /g; }
      $info = `mkvmerge --identify "$_"`;
      ($track) = $info =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/;
      @args = ( "mkvextract", "tracks", $_, "$track:$subname.ass" );
      #system( @args );
      foreach (@args) { print "$_ "; }
      print "\n";
   }
}
