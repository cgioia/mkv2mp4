#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;

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
      system( @mkvargs );
   }
}
