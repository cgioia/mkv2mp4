#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use File::Slurp;

foreach ( @ARGV )
{
   # Get the name, path, and the suffix of the file.
   my ($name, $path, $suffix) = fileparse( $_, qr/\.[^.]*/ );

   # Only operate on Matroska video or subtitle containers.
   if ( $suffix =~ /^\.mk[vs]$/ )
   {
      # Find the track ID for the ASS subtitles.
      my $info = `mkvmerge --identify "$_"`;
      my ($track) = $info =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/;

      # Construct the system call to extract the subtitle track.
      my @mkvargs = ( "mkvextract", "tracks", $_, "$track:$path$name.ass" );

      # Make the system call.
      #system( @mkvargs );

      my @ass = read_file( "$path$name.ass" );
      my @dialogue = grep { /^Dialogue:/ } @ass;

      for my $linenum ( 1 .. @dialogue ) {
         #print "$linenum\n";
         my $curline = $dialogue[$linenum - 1];
         my ($marked, $start, $end, $style, $dname, $marginL, $marginR, $marginV, $effect, $text) = $curline =~ /^Dialogue: ([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)$/;
         print $linenum . "\n" . $start . " --> " . $end . "\n" . $text . "\n\n";
      }
   }
}
