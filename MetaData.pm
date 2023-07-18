#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package MetaData;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    check_path_dates
    extract_info
    get_date_taken
    read_metadata
);

# Enable local lib
use File::Basename;
use Cwd qw(abs_path);
use lib dirname(abs_path(__FILE__));

# Local uses
use View;
use PathOp;

# Library uses
use DateTime::Format::HTTP ();
#use DateTime::Format::ISO8601 ();
use Image::ExifTool ();

# Gets the date the media was captured by parsing the file (and potentially
# sidecars) as DateTime
#
# Note on caching this value: this can change if this or any sidecars change,
# so make sure it is invalidated when sidecars are as well.
sub get_date_taken {
    my ($path, $exclude_sidecars) = @_;
    my $date_taken;
    eval {
        # For image types, ExifIFD:DateTimeOriginal does the trick, but that isn't
        # available for some types (video especially), so fall back to others.
        # A notable relevant distinction of similar named properties:
        # CreateDate: Quicktime metadata UTC date field related to the Media, 
        #             Track, and Modify variations (e.g. TrackModifyDate)
        # FileCreateDate: Windows-only file system property
        # CreationDate:
        # Photos.app 7.0 (macOS 12 Monterey) and Photos.app 6.0 (macOS 11 Big Sur) use the order
        # for mov, mp4: 1) Keys:CreationDate, 2) UserData:DateTimeOriginal (mp4 only),
        # 3) Quicktime:CreateDate, 4) MacOS:FileCreateDate
        my @tags = qw(ExifIFD:DateTimeOriginal Keys:CreationDate Quicktime:CreateDate);
        my $info = read_metadata($path, $exclude_sidecars,
                                { DateFormat => '%FT%T%z' }, \@tags);
        my $date_taken_raw;
        for my $tag (@tags) {
            if (exists $info->{$tag}) {
                $date_taken_raw = $info->{$tag};
                last;
            }
        }

        if ($date_taken_raw) {
            $date_taken = DateTime::Format::HTTP->parse_datetime($date_taken_raw);
        }
    };
    if (my $error = $@) {
        warn "Unavailable date taken for '@{[pretty_path($path)]}' with error:\n\t$error\n";
    }
    return $date_taken;
}

# Read metadata as an ExifTool hash for the specified path (and any
# XMP sidecar when appropriate). Similar in use to Image::ExifTool::ImageInfo
# except for the new $exclude_sidecars param and stricter argument order.
sub read_metadata {
    my ($path, $exclude_sidecars, @exiftool_args) = @_;
    my $et = extract_info($path, undef, @exiftool_args);
    my $info = $et->GetInfo(@exiftool_args);
    unless ($exclude_sidecars) {
        # If this file can't hold XMP (i.e. not JPEG or TIFF), look for
        # XMP sidecar
        # TODO: Should we exclude DNG here too?
        # TODO: How do we prevent things like FileSize from being overwritten
        #       by the XMP sidecar? read it first? exclude fields somehow (eg
        #       by "file" group)?
        #       (FileSize, FileModifyDate, FileAccessDate, FilePermissions)
        # TODO: move this logic to the $FILE_TYPES structure (add a 
        # useXmpSidecarForMetadata property or something)
        # TODO: for all these complaints, about hard coding let's just check if XMP is a sidecar
        if ($path !~ /\.(jpeg|jpg|tif|tiff|xmp)$/i) {
            # TODO: use path functions
            (my $xmp_path = $path) =~ s/[^.]*$/xmp/;
            if (-s $xmp_path) {
                $et = extract_info($xmp_path, $et, @exiftool_args);
                $info = { %{$et->GetInfo(@exiftool_args)}, %$info };
            }
        }
    }
    #my $keys = $et->GetTagList($info);
    return $info;
}

# Wrapper for Image::ExifTool::ExtractInfo with error handling
sub extract_info {
    my ($path, $et, @exiftool_args) = @_;
    unless ($et) {
        $et = new Image::ExifTool;
        # We do ISO 8601 dates by default
        $et->Options(DateFormat => '%FT%T%z');
    }
    trace(View::VERBOSITY_MEDIUM, "Image::ExifTool::ExtractInfo('$path');");
    $et->ExtractInfo($path, @exiftool_args) or die
        "Couldn't ExtractInfo for '$path': " . $et->GetValue('Error');
    print_crud(View::CRUD_READ, "  Extract meta of '@{[pretty_path($path)]}'");
    return $et;
}

sub check_path_dates {
    my ($path, $date) = @_;

    my ($year, $month, $day);
    my ($volume, $dir, $filename) = split_path($path);

    if ($date) {
        ($year, $month, $day) = ($date->year, $date->month, $date->day);
    } else {
        # If date isn't provided, try using one embedded at start of filename
        ($year, $month, $day) = $filename =~ /^(\d{4})[-_](\d\d)[-_](\d\d)\b/;
    }

    defined $year and $month > 0 and $day > 0 or return $path;

    my $yyyy = sprintf '%04d', $year;
    my $mm = sprintf '%02d', $month;
    my $dd = sprintf '%02d', $day;

    my @dir_parts = (split_dir($dir), $filename);
    for (@dir_parts) {
        s/^\d{4}$/$yyyy/;
        s/^\d{4}-\d\d$/$yyyy-$mm/;
        s/^\d{4}([-_])\d\d([-_])\d\d\b/$yyyy-$mm-$dd/;
    }

    my $new_filename = pop @dir_parts;
    my $new_dir = combine_dir(@dir_parts);
    my $new_path = combine_path($volume, $new_dir, $new_filename);
    return $new_path;
}

1;