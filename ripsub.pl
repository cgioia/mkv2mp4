#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use File::Slurp;

# Set our locale to Canada (French) so our decimal separator will be a comma.
use POSIX;
setlocale( LC_NUMERIC, "fr_CA" );

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

      # Find all the lines of dialogue in the ASS script.
      # They're the only ones we need for SRT.
      my @dialogue = grep { /^Dialogue:/ } read_file( "$path$name.ass" );

      # Create the SRT file with the same name.
      open SRT, ">$path$name.srt" or die $!;

      # Loop over each line of dialogue.
      # Start at 1 so we can use the index in the script.
      for my $linenum ( 1 .. @dialogue ) {
         # Need to account for the array being indexed starting at 0.
         my $curline = $dialogue[$linenum - 1];

         # Extract all ten fields of the dialogue section
         # according to the SSA spec v4.00+.
         my ($marked, $start, $end, $style, $charname, $marginL, $marginR, $marginV, $effect, $text) = $curline =~ /^Dialogue: ([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)$/;

         #my ($starthr, $startmin, $startsec) = split( /:/, $start );
         #my ($endhr, $endmin, $endsec) = split( /:/, $end );

         $start = sprintf( "%02d:%02d:%02.3f", split( /:/, $start ) );
         $end = sprintf( "%02d:%02d:%02.3f", split( /:/, $end ) );

         # A bit of cleanup on the subtitle text. Remove style override
         # control codes, and replace "\N" with actual newlines.
         foreach ( $text ) {
            s/\{[^\}]*}//g;
            s/\\[Nn]/\n/g;
         }

         # Remove any trailing newlines.
         chomp ($linenum, $start, $end, $text);

         # Print this line of dialogue to the SRT file.
         print SRT $linenum . "\n" . "$start --> $end" . "\n" . $text . "\n\n";
      }

      # Clean-up by closing the SRT file descriptor.
      close SRT;
   }
}
