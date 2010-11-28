#!/usr/bin/env perl
# Name: ripsub
# Author: Chad Gioia <cgioia@gmail.com>
use strict;
use warnings;
use File::Basename;
use File::Slurp;

# Set our locale to Canada (French) so the decimal separator will be a comma.
use POSIX;
setlocale( LC_NUMERIC, "fr_CA" );

foreach ( @ARGV )
{
   # Get the name, path, and the suffix of the file.
   my ($name, $path, $suffix) = fileparse( $_, qr/\.[^.]*/ );

   # Only operate on Matroska video or subtitle containers.
   if ( $suffix =~ /^\.mk[vs]$/ )
   {
      # Construct the system call to extract the subtitle track.
      my @mkvargs = ( "mkvextract", "tracks", $_ );

      # Find the track ID for the subtitles. If SRT subtitles are present,
      # excellent! If not, there's probably some SSA/ASS subtitles we can use.
      my $info = `mkvmerge --identify "$_"`;
      if ( $info =~ /Track ID (\d+): subtitles \(S_TEXT\/UTF8\)/ )
      {
         push( @mkvargs, "$1:$path$name.srt" );
      }
      elsif ( $info =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/ )
      {
         push( @mkvargs, "$1:$path$name.ass" );
      }
      else
      {
         die "Could not find subtitle track in $_";
      }

      # Make the system call.
      system( @mkvargs );

      # If we have an SRT file, we're done. Otherwise, ensure we have
      # an ASS file before attempting to convert it.
      next if -e "$path$name.srt";
      die "Unable to extract subtitle track from $_" unless -e "$path$name.ass";

      # Find all the lines of dialogue in the ASS script.
      # They're the only ones we need for SRT.
      my @dialogue = grep { /^Dialogue:/ } read_file( "$path$name.ass" );

      # Create the SRT file with the same name.
      open SRT, ">$path$name.srt" or die $!;

      # Loop over each line of dialogue.
      # Start at 1 so we can use the index in the script.
      for my $linenum ( 1 .. @dialogue )
      {
         # Grab the interesting part of the line: the ten comma-separated
         # fields defined in the SSA spec (v4.00+). For reference, see:
         # http://www.matroska.org/technical/specs/subtitles/ssa.html
         my ($line) = $dialogue[$linenum - 1] =~ /^Dialogue: (.*)/;
         my @fields = split( /,/, $line, 10 );

         # Format the start/end times with leading and trailing zeroes.
         my $start = formatTimeCode( $fields[1] );
         my $end = formatTimeCode( $fields[2] );

         # A bit of cleanup on the subtitle text. Remove style override
         # control codes ({}), and replace ASCII newlines with actual newlines.
         my $text = cleanSubText( $fields[9] );

         # Finally, print this line of dialogue to the SRT file.
         print SRT $linenum . "\n" . "$start --> $end" . "\n" . $text . "\n\n";
      }

      # Clean-up by closing the SRT file descriptor.
      close SRT;
   }
}

sub formatTimeCode
{
   my $time = shift;
   my $ftime = sprintf( "%02d:%02d:%06.3f", split( /:/, $time, 3 ) );
   return $ftime;
}

sub cleanSubText
{
   my $text = shift;
   foreach ( $text )
   {
      s/\{[^\}]*}//g;
      s/\\[Nn]/\n/g;
   }
   return $text;
}
