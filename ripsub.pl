#!/usr/bin/env perl
# Name: ripsub
# Author: Chad Gioia <cgioia@gmail.com>
# Description: Extracts SRT or SSA/ASS subtitle tracks from Matroska media
#              containers. Converts SSA/ASS to SRT if necessary.
################################################################################
use strict;
use warnings;
use File::Basename;

# Set our locale to Canada (French) so the decimal separator will be a comma.
use POSIX;
setlocale( LC_NUMERIC, "fr_CA" );

foreach ( @ARGV )
{
   # Get the name, path, and the suffix of the file. Use this to
   # create the names for the ASS and SRT files.
   my ($name, $path, $suffix) = fileparse( $_, qr/\.[^.]*/ );
   my $assfile = "$path$name.ass";
   my $srtfile = "$path$name.srt";

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
         push( @mkvargs, "$1:$srtfile" );
      }
      elsif ( $info =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/ )
      {
         push( @mkvargs, "$1:$assfile" );
      }
      else
      {
         die "Could not find subtitle track in $_";
      }

      # Make the system call.
      system( @mkvargs );

      # If we have the SRT file, we're done.
      next if -e "$srtfile";

      # If we're here, we need to convert the ASS script to SRT.
      # We'll need a hash to store the lines of dialogue for the SRT script.
      my %srtlines;

      # Open the ASS file for reading, and the SRT file for writing.
      open ASS, "<$assfile" or die $!;
      open SRT, ">$srtfile" or die $!;

      # Read in each line of the ASS file.
      while ( <ASS> )
      {
         # Grab the interesting part of the dialogue: the ten comma-separated
         # fields defined in the SSA spec (v4.00+). For reference, see:
         # http://www.matroska.org/technical/specs/subtitles/ssa.html
         if ( $_ =~ /^Dialogue: (.*)/ )
         {
            my @fields = split( /,/, $1, 10 );

            # Format the start and end times in an SRT format.
            my $timecode = formatTimeCode( $fields[1], $fields[2] );

            # Clean-up the subtitle text for SRT. Skip it if it turns out empty.
            my $text = cleanSubText( $fields[9] );
            next if $text eq "";

            # Store the text in the hash, using the timecode as the key. If
            # there is a duplicate timecode, we'll append on the next line.
            $srtlines{$timecode} .= $text . "\n";
         }
      }

      # Write the script to the SRT file, sorted by the timecode (key).
      my $count = 1;
      foreach my $key ( sort keys %srtlines )
      {
         print SRT $count++ . "\n" . $key . "\n" . $srtlines{$key} . "\n";
      }

      # Clean-up by closing the SRT and ASS file descriptors.
      close SRT;
      close ASS;
   }
}

################################################################################
# Subroutine:  formatTimeCode( $start, $end )
# Description: Format the start/end times with leading and trailing zeroes,
#              then split the times with the " --> " string as required by SRT.
# Return:      the formatted timecode
################################################################################
sub formatTimeCode
{
   my $start = sprintf( "%02d:%02d:%06.3f", split( /:/, $_[0], 3 ) );
   my $end = sprintf( "%02d:%02d:%06.3f", split( /:/, $_[1], 3 ) );
   return "$start --> $end";
}

################################################################################
# Subroutine:  cleanSubText( $text )
# Description: Do some cleanup on the subtitle text. Remove SSA style override
#              control codes, and replace ASCII newlines with actual newlines.
#              Maybe someday we can also insert SRT styles where applicable.
# Return:      the cleaned subtitle text
################################################################################
sub cleanSubText
{
   my $text = shift;
   foreach ( $text )
   {
      s/\{[^\}]*}//g; # Remove the codes (everything inside {}'s)
      s/\\[Nn]/\n/g;  # Add newlines where called for in the script
   }
   return $text;
}
