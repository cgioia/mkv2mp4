#!/usr/bin/env perl
# Name: ripsub
# Author: Chad Gioia <cgioia@gmail.com>
# Description: Extracts SRT or SSA/ASS subtitle tracks from Matroska media
#              containers. Converts SSA/ASS to SRT if necessary.
################################################################################
use strict;
use warnings;
use POSIX;
use File::Basename;

# Set our locale to Canada (French) so the decimal separator will be a comma.
setlocale( LC_NUMERIC, "fr_CA" );

foreach ( @ARGV )
{
   my $mkvfile = $_;
   next unless -e $mkvfile;

   my ($name, $path, $suffix) = fileparse( $mkvfile, qr/\.[^.]*/ );
   next unless $suffix eq ".mkv";

   my $mp4file = "$path$name.m4v";
   convertVideo( $mkvfile, $mp4file, "AppleTV" );
   unless ( -e $mp4file )
   {
      print STDERR "Unable to convert $mkvfile!\n";
      next;
   }

   my $subfile = extractSubtitles( $mkvfile );
   unless ( -e $subfile )
   {
      print STDERR "Unable to extract subtitles from $mkvfile!\n";
      next;
   }

   muxSubtitles( $mp4file, $subfile );
   unlink( $subfile );
}

################################################################################
# Subroutine:  extractSubtitles( $mkvfile )
# Description: Extract SRT subtitles from a Matroska video container.
# Return:      name of the SRT file
################################################################################
sub extractSubtitles
{
   my $mkvfile = shift;
   my $srtfile = undef;
   if ( $mkvfile =~ /\.mkv$/ )
   {
      my $info = `mkvmerge --identify "$mkvfile"`;
      if ( $info =~ /Track ID (\d+): subtitles \(S_TEXT\/UTF8\)/ )
      {
         $srtfile = tmpnam() . ".srt";
         system( "mkvextract tracks $mkvfile $1:$srtfile" );
      }
      elsif ( $info =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/ )
      {
         my $assfile = tmpnam() . ".ass";
         system( "mkvextract tracks $mkvfile $1:$assfile" );
         $srtfile = convertASSToSRT( $assfile );
         unlink( $assfile );
      }
   }
   return $srtfile;
}

################################################################################
# Subroutine:  convertASSToSRT( $assfile )
# Description: Convert SSA/ASS subtitles to the SRT format
# Return:      name of the SRT file
################################################################################
sub convertASSToSRT
{
   my $assfile = shift;
   my $srtfile = undef;
   if ( $assfile =~ /\.ass$/ )
   {
      $srtfile = tmpnam() . ".srt";

      open ASS, "<$assfile" or die $!;
      open SRT, ">$srtfile" or die $!;

      my %srtlines;
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
   return $srtfile;
}

################################################################################
# Subroutine:  muxSubtitles( $inputfile, $srtfile )
# Description: Mux an SRT subtitle script into the given MP4 file.
# Return:      nothing
################################################################################
sub muxSubtitles
{
   my ($inputfile, $srtfile) = @_;
   system( "SublerCLI -i $inputfile -s $srtfile" );
}

################################################################################
# Subroutine:  convertVideo( $inputfile, $outputfile, $preset )
# Description: Convert the given input using the specified preset.
# Return:      nothing
################################################################################
sub convertVideo
{
   my ($inputfile, $outputfile, $preset) = @_;
   system( "HandbrakeCLI -i $inputfile -o $outputfile --preset=\"$preset\"" );
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
