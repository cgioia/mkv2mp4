#!/usr/bin/env perl
# Name: mkv2mp4
# Author: Chad Gioia <cgioia@gmail.com>
# Description: Converts a Matroska video to MP4, and muxes in the subtitles.
################################################################################
use strict;
use warnings;
use POSIX;
use File::Basename;

# Set our locale to Canada (French) so the decimal separator will be a comma.
setlocale( LC_NUMERIC, "fr_CA" );

foreach ( @ARGV )
{
   # Make sure we were passed a readable file.
   my $mkvfile = $_;
   next unless -e $mkvfile;

   # Now make sure it's a Matroska video before continuing.
   my ($name, $path, $suffix) = fileparse( $mkvfile, qr/\.[^.]*/ );
   next unless $suffix eq ".mkv";

   # Use HandbrakeCLI to convert the MKV to MP4 using the AppleTV preset.
   my $mp4file = "$path$name.m4v";
   convertVideo( $mkvfile, $mp4file, "AppleTV" );
   unless ( -e $mp4file )
   {
      print STDERR "Unable to convert $mkvfile!\n";
      next;
   }

   # If the Matroska video container has a subtitle track,
   # extract it and mux it into the converted MP4 file.
   my $subfile = extractSubtitles( $mkvfile );
   unless ( defined $subfile and -e $subfile ) { next; }
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

   # Only operate on Matroska video files.
   if ( $mkvfile =~ /\.mkv$/ )
   {
      # Get the metadata information from this MKV file.
      my $info = `mkvmerge --identify "$mkvfile"`;

      # Look for the SRT track.
      if ( $info =~ /Track ID (\d+): subtitles \(S_TEXT\/UTF8\)/ )
      {
         # Create a temporary file name for the SRT script and extract.
         $srtfile = tmpnam() . ".srt";
         print "Extracting SRT subtitles from $mkvfile.\n";
         system( "mkvextract tracks \"$mkvfile\" \"$1:$srtfile\" > /dev/null" );
      }
      # SRT track wasn't found, so look for an SSA/ASS track.
      elsif ( $info =~ /Track ID (\d+): subtitles \(S_TEXT\/ASS\)/ )
      {
         # Create a temporary file name for the ASS script and extract.
         my $assfile = tmpnam() . ".ass";
         print "Extracting SSA/ASS subtitles from $mkvfile.\n";
         system( "mkvextract tracks \"$mkvfile\" \"$1:$assfile\" > /dev/null" );

         # Convert the ASS script to SRT, and delete the unnecessary file.
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

   # Only operate on ASS subtitle files.
   if ( $assfile =~ /\.ass$/ )
   {
      # Create a temporary file name for the SRT script.
      $srtfile = tmpnam() . ".srt";

      # Define a hash to hold the SRT script while we're reading the ASS file.
      my %srtlines = ();

      # Open the ASS and SRT files for reading and writing, respectively.
      open ASS, "<$assfile" or die $!;
      open SRT, ">$srtfile" or die $!;

      # Some variables we'll need for parsing the INI-like ASS script.
      my @format = ();     # The format of the dialogue
      my $inEvents = 0;    # If we're in the [Events] section
      my $foundFormat = 0; # If we've parsed out the format string
      my $startnum = 0;    # The location of the start time
      my $endnum = 0;      # The location of the end time
      my $textnum = 0;     # The location of the dialogue text

      # Read the entire ASS file.
      print "Converting SSA/ASS subtitles to SRT format.\n";
      while ( <ASS> )
      {
         # Grab the interesting part of the script: the [Events] section
         # as defined in the SSA spec (v4.00+). For reference, see:
         # http://www.matroska.org/technical/specs/subtitles/ssa.html
         if ( $_ =~ /^\[Events\]$/ )
         {
            $inEvents = 1;
            next;
         }

         # We just left the [Events] section.
         if ( $inEvents and $_ =~ /^\[/ )
         {
            $inEvents = 0;
            next;
         }

         # Read the Format for the [Events] section, and store the
         # locations of the fields we're interested in.
         if ( $inEvents and not $foundFormat and $_ =~ /^Format: (.*)/ )
         {
            @format = split( /, /, $1 );
            for my $fmtnum ( 0 .. $#format )
            {
               $startnum = $fmtnum if $format[$fmtnum] eq "Start";
               $endnum = $fmtnum if $format[$fmtnum] eq "End";
               $textnum = $fmtnum if $format[$fmtnum] eq "Text";
            }
            $foundFormat = 1;
         }

         # We've looking for a valid line of dialogue.
         if ( $inEvents and $foundFormat and $_ =~ /^Dialogue: (.*)/ )
         {
            # Split the line of dialog up according to the format.
            my @fields = split( /,/, $1, @format );

            # Clean-up the subtitle text for SRT. Skip it if it turns out empty.
            my $text = cleanSubText( $fields[$textnum] );
            next if $text eq "";

            # Format the start and end times in an SRT format.
            my $timecode = formatTimeCode( $fields[$startnum],
                                           $fields[$endnum] );

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

      # Clean up by closing the ASS and SRT file descriptors.
      close ASS;
      close SRT;
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
   print "Muxing subtitles into $inputfile.\n";
   system( "SublerCLI -i \"$inputfile\" -s \"$srtfile\" > /dev/null" );
}

################################################################################
# Subroutine:  convertVideo( $inputfile, $outputfile, $preset )
# Description: Convert the given input using the specified preset.
# Return:      nothing
################################################################################
sub convertVideo
{
   my ($inputfile, $outputfile, $preset) = @_;

   # Handbrake likes to put a lot of junk out to STDERR. Do not want.
   print "Converting $inputfile to $outputfile using \"$preset\" preset.\n";
   system( "HandbrakeCLI -i \"$inputfile\" -o \"$outputfile\" --preset=\"$preset\" > /dev/null 2>&1" );
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
# Return:      the cleaned subtitle text
################################################################################
sub cleanSubText
{
   my $text = shift;

   foreach ( $text )
   {
      s/\{[^\}]*\}//g; # Remove the codes (everything inside {}'s)
      s/\\[Nn]/\n/g;  # Add newlines where called for in the script
   }

   return $text;
}
