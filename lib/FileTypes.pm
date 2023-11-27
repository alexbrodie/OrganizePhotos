#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package FileTypes;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    get_file_type_info
    get_mime_type
    get_sidecar_paths
    get_trash_path
    compare_path_with_ext_order
    is_reserved_system_filename
    $ORPHDAT_FILENAME
    $TRASH_DIR_NAME
    $MEDIA_TYPE_FILENAME_FILTER
);

# Local uses
use PathOp;
use View;

# Library uses
use File::Spec;
use Readonly;

# Filename only portion of the path to Md5File which stores
# Md5Info data for other files in the same directory
Readonly our $ORPHDAT_FILENAME => '.orphdat';

# This subdirectory contains the trash for its parent
Readonly our $TRASH_DIR_NAME => '.orphtrash';

# A map of supported file extensions to several different aspects:
#
# SIDECARS
#   Map of extension to pointer to array of extensions of possible sidecars.
#   While JPG and HEIC may have MOV alongside them, we won't consider those
#   sidecars (at least for now) since in practice it gets a little weird if
#   one set of files has a MOV and the other doesn't. This is a bit different
#   from JPG sidecars of raw files or THM since those are redunant. Before
#   adding MOV back, we should update the dupe detection to compare the
#   sidecars as well rather than just the primary file. Sidecar associations
#   can't form cycles such that a sidecar of a sicecar ... of a sidecar is
#   not the original type.
#
#   The default if not specified (or the type is not known and is
#   missing from the list altogether) is an empty list.
#
# EXTORDER
#   Defines the sort order when displaying a group of duplicate files with
#   the lower values coming first. Typically the "primary" files are displayed
#   first and so have lower values. If a type is a sidecar of another, the
#   EXTORDER of the sidecar type must be strictly greater if it exists. Thus
#   this is also used to control processing order so that primary files are
#   handled before their sidecars - e.g. raf files are handled before jpg
#   sidecars.
#
#   The default if not specified (or the type is not known and is
#   missing from the list altogether) is zero.
#
#   TODO: verify this EXTORDER/SIDECAR claim, perhaps in tests somewhere. It
#   would also ensure the statement in SIDECARS that there are no cycles.
#
# MIMETYPE
#   The mime type of the file type (source: filext.com). For types without
#   a MIME type, we fabricate a "non-standard" one based on extension.
#
# TODO: flesh this out
# TODO: convert to Class::Struct
Readonly::Hash my %FILE_TYPES => (
    AVI => {
        MIMETYPE => 'video/x-msvideo'
    },
    CRW => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/crw'
    },
    CR2 => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/cr2'             # Non-standard
    },
    CR3 => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/x-canon-cr3'     # Non-standard
    },

    #ICNS => {
    #    MIMETYPE => 'image/x-icns'
    #},
    #ICO => {
    #    MIMETYPE => 'image/x-icon'
    #},
    JPEG => {
        MIMETYPE => 'image/jpeg'
    },
    JPG => {
        SIDECARS => [qw( AAE )],
        MIMETYPE => 'image/jpeg'
    },
    HEIC => {
        SIDECARS => [qw( XMP MOV )],
        EXTORDER => -1,
        MIMETYPE => 'image/heic'
    },
    M2TS => {
        MIMETYPE => 'video/mp2t'
    },
    M4V => {
        MIMETYPE => 'video/mp4v-es'
    },
    MOV => {
        MIMETYPE => 'video/quicktime'
    },
    MP3 => {
        MIMETYPE => 'audio/mpeg'
    },
    MP4 => {
        SIDECARS => [qw( LRV THM )],
        EXTORDER => -1,
        MIMETYPE => 'video/mp4v-es'
    },
    MPG => {
        MIMETYPE => 'video/mpeg'
    },
    MTS => {
        MIMETYPE => 'video/mp2t'
    },
    NEF => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/nef'             # Non-standard
    },

    #PDF => {
    #    MIMETYPE => 'application/pdf'
    #},
    PNG => {
        MIMETYPE => 'image/png'
    },
    PSB => {
        MIMETYPE => 'image/psb'    # Non-standard
    },
    PSD => {
        MIMETYPE => 'image/photoshop'
    },
    RAF => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/raf'             # Non-standard
    },
    TIF => {
        MIMETYPE => 'image/tiff'
    },
    TIFF => {
        MIMETYPE => 'image/tiff'
    },

    #ZIP => {
    #    MIMETYPE => 'application/zip'
    #}
);

Readonly::Scalar my $BACKUP_SUFFIX => qr{
    [._] (?i) (?:bak|original|\d{8}T\d{6}Z~) \d*
}sx;

# Media file extensions
Readonly::Scalar our $MEDIA_TYPE_FILENAME_FILTER => qr{
    # Media extension
    (?: \. (?i) (?: @{[ join '|', keys %FILE_TYPES ]}) )
    # Optional backup file suffix
    (?: $BACKUP_SUFFIX)?
$}sx;

sub get_file_type_info {
    my ( $ext, $property ) = @_;
    if ( defined $ext ) {
        my $key = uc $ext;
        $key =~ s{^\.}{};
        if ( exists $FILE_TYPES{$key} ) {
            my $file_type = $FILE_TYPES{$key};
            if ( exists $file_type->{$property} ) {
                return $file_type->{$property};
            }
        }
    }
    return;
}

# Gets the mime type from a path
sub get_mime_type {
    my ($path) = @_;

    # If the file is a backup (has some "bak"/"original" suffix),
    # we want to consider the real extension
    $path =~ s/$BACKUP_SUFFIX$//;
    my ( $basename, $ext ) = split_ext($path);
    return get_file_type_info( $ext, 'MIMETYPE' ) || '';
}

# Provided a path, returns an array of sidecar files based on extension.
sub get_sidecar_paths {
    my ($path) = @_;
    if ( $path =~ /$BACKUP_SUFFIX$/ ) {

        # Associating sidecars with backups only creates problems
        # like multiple versions of a file sharing the same sidecar(s)
        return ();
    }
    else {
        # Using extension as a key, look up associated sidecar types (if any)
        # and return the paths to the other types which exist
        my ( $vol, $dir, $filename ) = split_path($path);
        my ( $basename, $ext ) = split_ext($filename);
        my @sidecars = @{ get_file_type_info( $ext, 'SIDECARS' ) || [] };
        @sidecars =
            map { combine_path( $vol, $dir, combine_ext( $basename, $_ ) ) }
            @sidecars;
        return grep { -e } @sidecars;
    }
}

# Gets the local trash location for the specified path: the same filename
# in the .orphtrash subdirectory.
sub get_trash_path {
    my ($path) = @_;
    my ( $vol, $dir, $filename ) = split_path($path);
    my $trash_dir = File::Spec->catdir( $dir, $TRASH_DIR_NAME );
    return combine_path( $vol, $trash_dir, $filename );
}

sub compare_path_with_ext_order {
    my ( $path_a, $path_b, $reverse_ext_order ) = @_;
    my ( $vol_a,  $dir_a,  $filename_a )        = split_path($path_a);
    my ( $vol_b,  $dir_b,  $filename_b )        = split_path($path_b);
    return compare_dir( $dir_a, $dir_b )
        || compare_filename_with_ext_order( $filename_a, $filename_b,
        $reverse_ext_order );
}

sub compare_dir {
    my ( $dir_a, $dir_b ) = @_;
    return 0 if $dir_a eq $dir_b;    # optimization
    my @as = File::Spec->splitdir($dir_a);
    my @bs = File::Spec->splitdir($dir_b);
    for ( my $i = 0;; $i++ ) {
        if ( $i >= @as ) {
            if ( $i >= @bs ) {
                return 0;    # A and B both ran out, so they're equal
            }
            else {
                return -1;    # A is ancestor of B, so A goes first
            }
        }
        else {
            if ( $i >= @bs ) {
                return 1;     # B is ancestor of A, so B goes first
            }
            else {
                # Compare this generation - if not equal, then we
                # know the order, else move on to children
                my $c = lc $as[$i] cmp lc $bs[$i];
                return $c if $c;
            }
        }
    }
}

sub compare_filename_with_ext_order {
    my ( $filename_a, $filename_b, $reverse_ext_order ) = @_;
    my ( $basename_a, $ext_a ) = split_ext($filename_a);
    my ( $basename_b, $ext_b ) = split_ext($filename_b);

    # Compare by basename first
    my $c = lc( $basename_a || '' ) cmp lc( $basename_b || '' );
    return $c if $c;

    # Next by extorder
    my $direction   = $reverse_ext_order ? -1 : 1;
    my $ext_order_a = get_file_type_info( $ext_a, 'EXTORDER' );
    my $ext_order_b = get_file_type_info( $ext_b, 'EXTORDER' );
    $c = ( $ext_order_a || 0 ) <=> ( $ext_order_b || 0 );
    return $direction * $c if $c;

    # And then just the extension as a string
    return $direction * ( lc( $ext_a || '' ) cmp lc( $ext_b || '' ) );
}

# Returns true if the provided filename is one of the reserved
# system filenames (and should then be ignored)
sub is_reserved_system_filename {
    my ($filename) = @_;
    $filename = lc $filename;
    return ( $filename eq '.ds_store' )
        || ( $filename eq 'thumbs.db' );
}

1;
