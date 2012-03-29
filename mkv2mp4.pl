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
use feature "switch";

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
   my $mp4file = "$path$name.m4v";

   # Use MKVToolNix to extract the tracks.
   my ($videofile, $audiofile, $subfile) = extractTracks( $mkvfile );

   # Mux the video and audio together.
   muxVideo( $mp4file, $videofile, $audiofile );
   unlink( $videofile ) if defined $videofile;
   unlink( $audiofile ) if defined $audiofile;

   # Mux the subtitles if necessary.
   next unless defined $subfile and -e $subfile;
   muxSubtitles( $mp4file, $subfile );
   unlink( $subfile );
}

################################################################################
# Subroutine:  convertSubToSRT( $subfile )
# Description: Convert subtitles to the SRT format
# Return:      name of the SRT file
################################################################################
sub convertSubToSRT
{
   my $subfile = shift;
   my $srtfile = undef;

   if ( $subfile =~ /\.ass$/ )
   {
      # Create a temporary file name for the SRT script.
      $srtfile = tmpnam() . ".srt";

      # Open the ASS and SRT files for reading and writing, respectively.
      open ASS, "<$subfile" or die $!;
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
            next if defined $curline and $curline =~ /$text/;
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
   elsif ( $subfile =~ /\.srt$/ )
   {
      # Nothing to do, just use the original file.
      $srtfile = $subfile;
   }

   return $srtfile;
}

################################################################################
# Subroutine:  muxSubtitles( $mp4file, $subfile )
# Description: Mux a subtitle script into the given MP4 file.
# Return:      nothing
################################################################################
sub muxSubtitles
{
   my ($mp4file, $subfile) = @_;

   # Convert the subtitles to SRT, if necessary.
   my $srtfile = convertSubToSRT( $subfile );

   # Get muxin'!
   print "Muxing subtitles into $mp4file.\n";
   system( "SublerCLI -o \"$mp4file\" -i \"$srtfile\" -r > /dev/null 2>&1" );

   # Clean up the SRT file we just created.
   unlink( $srtfile );
}

################################################################################
# Subroutine:  muxVideo( $mp4file, $videofile, $audiofile )
# Description: Mux the video and audio tracks to an MP4.
# Return:      nothing
################################################################################
sub muxVideo
{
   my ($mp4file, $videofile, $audiofile) = @_;

   # Quick sanity check: don't do anything if MP4 exists, or
   # if the track files don't exist.
   print "$mp4file\n";
   return if -e $mp4file;
   return unless defined $videofile and defined $audiofile;
   return unless -e $videofile and -e $audiofile;

   # Get muxin'!
   print "Muxing video into $mp4file.\n";
   system( "SublerCLI -o \"$mp4file\" -i \"$videofile\" > /dev/null 2>&1" );
   print "Muxing audio into $mp4file.\n";
   system( "SublerCLI -o \"$mp4file\" -i \"$audiofile\" > /dev/null 2>&1" );
}

################################################################################
# Subroutine:  extractTracks( $mkvfile )
# Description: Extract the raw data from the Matroska video container.
# Return:      names of the extracted video, audio, and subtitle files
################################################################################
sub extractTracks
{
   my $mkvfile = shift;
   my $vfile = undef;
   my $afile = undef;
   my $sfile = undef;

   # Only operate on Matroska video files.
   if ( $mkvfile =~ /\.mkv$/ )
   {
      # The track extraction strings to pass to mkvextract.
      my $vt = "";
      my $at = "";
      my $st = "";

      # Get the metadata information from this MKV file.
      print "Extracting tracks from $mkvfile.\n";
      my $info = `mkvmerge --identify "$mkvfile"`;

      # Determine track and extension for video.
      my ($vtid, $vttype) = $info =~ m!Track ID (\d+): video \(([^\)]+)\)!;
      if ( defined $vtid and defined $vttype )
      {
         given ( $vttype )
         {
            $vfile = tmpnam() . ".h264" when /V_MPEG4/;
            print "Unknown video type: $vttype\n";
            return;
         }
         $vt = "$vtid:$vfile";
      }

      # Determine track and extension for audio.
      my ($atid, $attype) = $info =~ m!Track ID (\d+): audio \(([^\)]+)\)!;
      if ( defined $atid and defined $attype )
      {
         given ( $attype )
         {
            $afile = tmpnam() . ".aac" when /A_AAC/;
            # $afile = tmpnam() . ".ac3" when /A_AC3/;
            print "Unknown audio type: $attype\n";
            return;
         }
         $at = "$atid:$afile";
      }

      # Determine track and extension for subtitles.
      my ($stid, $sttype) = $info =~ m!Track ID (\d+): subtitles \(([^\)]+)\)!;
      if ( defined $stid and defined $sttype )
      {
         given ( $sttype )
         {
            $sfile = tmpnam() . ".ass" when /S_TEXT\/ASS/;
            $sfile = tmpnam() . ".srt" when /S_TEXT\/UTF8/;
            print "Unknown subtitle type: $sttype\n";
            return;
         }
         $st = "$stid:$sfile";
      }

      # Extract the tracks from the Matroska container.
      system( "mkvextract tracks \"$mkvfile\" \"$vt\" \"$at\" \"$st\" > /dev/null" );
   }

   return ($vfile, $afile, $sfile);
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
      s/[<>]//g;                      # Remove angle brackets
      s/^\s+//g;                      # Remove leading whitespace
      s/\s+$//g;                      # Remove trailing whitespace
   }

   return $text;
}
