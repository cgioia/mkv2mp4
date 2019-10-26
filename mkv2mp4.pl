#!/usr/bin/env perl
# Name: mkv2mp4
# Author: Chad Gioia <cgioia@gmail.com>
# Description: Converts a Matroska video to MP4, and muxes in the subtitles.
################################################################################
use strict;
use warnings;
use POSIX qw(setlocale LC_NUMERIC);
use File::Basename qw(fileparse);
use File::Temp qw(tmpnam);

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

   # Convert the MKV to MP4.
   my $mp4file = "$path$name.m4v";
   convertVideo( $mkvfile, $mp4file ) unless -e $mp4file;
   next unless -e $mp4file;

   # If the Matroska video container has a subtitle track,
   # extract it and mux it into the converted MP4 file.
   my $subfile = extractSubtitles( $mkvfile );
   next unless defined $subfile and -e $subfile;
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
      elsif ( $info =~ /Track ID (\d+): subtitles (?:\(S_TEXT\/ASS\)|\(SubStationAlpha\))/ )
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

      # Open the ASS and SRT files for reading and writing, respectively.
      open ASS, "<$assfile" or die $!;
      open SRT, ">$srtfile" or die $!;

      # Some variables we'll need for parsing the INI-like ASS script.
      my %srtlines    = (); # Hash to hold the SRT script as it's being parsed
      my @format      = (); # The format of the dialogue
      my $inEvents    = 0;  # If we're in the [Events] section
      my $foundFormat = 0;  # If we've parsed out the format string
      my $startnum    = 0;  # The location of the start time
      my $endnum      = 0;  # The location of the end time
      my $textnum     = 0;  # The location of the dialogue text

      # Read the entire ASS file.
      print "Converting SSA/ASS subtitles to SRT format.\n";
      while ( <ASS> )
      {
         # Grab the interesting part of the script: the [Events] section
         # as defined in the SSA spec (v4.00+). For reference, see:
         # http://www.matroska.org/technical/specs/subtitles/ssa.html
         if ( /^\[Events\]$/ ) { $inEvents = 1; next; }

         # Watch to see when we leave the [Events] section.
         if ( $inEvents and /^\[/ ) { $inEvents = 0; next; }

         # Read the Format for the [Events] section, and store the
         # locations of the fields we're interested in.
         if ( $inEvents and not $foundFormat and /^Format: (.*)/ )
         {
            @format = split( /, /, $1 );
            for my $fmtnum ( 0 .. $#format )
            {
               $startnum = $fmtnum if $format[$fmtnum] eq "Start";
               $endnum   = $fmtnum if $format[$fmtnum] eq "End";
               $textnum  = $fmtnum if $format[$fmtnum] eq "Text";
            }
            $foundFormat = 1;
         }

         # We've looking for a valid line of dialogue.
         if ( $inEvents and $foundFormat and /^Dialogue: (.*)/ )
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
            # Skip the line if it already exists (e.g., duplicated in the ASS
            # script for styling purposes).
            my $curline = $srtlines{$timecode};
            next if defined $curline and $curline =~ /\Q$text\E/;
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
# Subroutine:  muxSubtitles( $mp4file, $srtfile )
# Description: Mux an SRT subtitle script into the given MP4 file.
# Return:      nothing
################################################################################
sub muxSubtitles
{
   my ($mp4file, $srtfile) = @_;
   print "Muxing subtitles into $mp4file.\n";
   system( "SublerCLI -dest \"$mp4file\" -source \"$srtfile\" -remove > /dev/null" );
}

################################################################################
# Subroutine:  convertVideo( $inputfile, $outputfile )
# Description: Convert the given input video file.
# Return:      nothing
################################################################################
sub convertVideo
{
   my ($inputfile, $outputfile) = @_;

   my $dopt = "--format mp4 --markers --large-file";
   my $vopt = "--encoder x264 --quality 20.0 --rate 29.97 --pfr";
   my $aopt = "--aencoder faac --ab 160";
   my $popt = "--maxWidth 1920 --loose-anamorphic";
   my $pset = "--preset Devices/Apple\\ 1080p60\\ Surround";
   my $io = "-i \"$inputfile\" -o \"$outputfile\" 2> /dev/null";

   print "Converting $inputfile.\n";
   # system( "HandBrakeCLI $dopt $vopt $aopt $popt $io" ); print "\n";
   # system( "HandBrakeCLI $pset $io" ); print "\n";
   # TODO: We probably don't need to run the H.264 video through Handbrake;
   # we can just copy it to the new container. However, some files are coming
   # out now with 10-bit color, which can't be decoded by Apple's hardware...
   # in which case we need to re-encode it anyways. It'd be great if we could
   # only convert the video when absolutely necessary, and copy it otherwise.
   system( "SublerCLI -source \"$inputfile\" -dest \"$outputfile\" > /dev/null 2>&1" );
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
   my $end   = sprintf( "%02d:%02d:%06.3f", split( /:/, $_[1], 3 ) );
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
      s/[<>]//g;                      # Remove angle brackets
      s/\{[^\}]*\\b1[^\}]*\}/<b>/g;   # Style override code to begin bold
      s/\{[^\}]*\\b0[^\}]*\}/<\/b>/g; # Style override code to end bold
      s/\{[^\}]*\\i1[^\}]*\}/<i>/g;   # Style override code to begin italics
      s/\{[^\}]*\\i0[^\}]*\}/<\/i>/g; # Style override code to end italics
      s/\{[^\}]*\\u1[^\}]*\}/<u>/g;   # Style override code to begin underline
      s/\{[^\}]*\\u0[^\}]*\}/<\/u>/g; # Style override code to end underline
      s/\{[^\}]*\}//g;                # Remove the other codes
      s/\s*(?:\\[Nn])+\s*/\n/g;       # Add newline and trim spaces
      s/\\[Tt]/        /g;            # Add eight spaces for a tab character
      s/\\[^NnTt]//g;                 # Remove all other escape sequences
      s/^\s+//g;                      # Remove leading whitespace
      s/\s+$//g;                      # Remove trailing whitespace
   }

   return $text;
}
