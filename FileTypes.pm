#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package FileTypes;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    getFileTypeInfo
    getMimeType
    getSidecarPaths
    getTrashPath
    comparePathWithExtOrder
);

# Local uses
use PathOp;
use View;

# Library uses
use Const::Fast qw(const);
use File::Spec;

# Filename only portion of the path to Md5File which stores
# Md5Info data for other files in the same directory
const our $md5Filename => '.orphdat';

# This subdirectory contains the trash for its parent
const our $trashDirName => '.orphtrash';

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
const my %fileTypes => (
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
        MIMETYPE => 'image/cr2' # Non-standard
    },
    CR3 => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/x-canon-cr3' # Non-standard
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
        MIMETYPE => 'image/nef' # Non-standard
    },
    #PDF => {
    #    MIMETYPE => 'application/pdf'
    #},
    PNG => {
        MIMETYPE => 'image/png'
    },
    PSB => {
        MIMETYPE => 'image/psb' # Non-standard
    },
    PSD => {
        MIMETYPE => 'image/photoshop'
    },
    RAF => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/raf' # Non-standard
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

const my $backupSuffix => qr/
    [._] (?i) (?:bak|original|\d{8}T\d{6}Z~) \d*
/x;

# Media file extensions
const our $mediaTypeFilenameFilter => qr/
    # Media extension
    (?: \. (?i) (?: @{[ join '|', keys %fileTypes ]}) )
    # Optional backup file suffix
    (?: $backupSuffix)?
$/x;

sub getFileTypeInfo {
    my ($ext, $property) = @_;
    if (defined $ext) {
        my $key = uc $ext;
        if (exists $fileTypes{$key}) {
            my $fileType = $fileTypes{$key};
            if (exists $fileType->{$property}) {
                return $fileType->{$property};
            }
        }
    }
    return undef;
}

# Gets the mime type from a path
sub getMimeType {
    my ($mediaPath) = @_;
    # If the file is a backup (has some "bak"/"original" suffix), 
    # we want to consider the real extension
    $mediaPath =~ s/$backupSuffix$//;
    my ($basename, $ext) = splitExt($mediaPath);
    return getFileTypeInfo($ext, 'MIMETYPE') || '';
}

# Provided a path, returns an array of sidecar files based on extension.
sub getSidecarPaths {
    my ($fullPath) = @_;
    if ($fullPath =~ /$backupSuffix$/) {
        # Associating sidecars with backups only creates problems
        # like multiple versions of a file sharing the same sidecar(s)
        return ();
    } else {
        # Using extension as a key, look up associated sidecar types (if any)
        # and return the paths to the other types which exist
        my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
        my ($basename, $ext) = splitExt($filename);
        my @sidecars = @{getFileTypeInfo($ext, 'SIDECARS') || []};
        @sidecars = map { combinePath($vol, $dir, catExt($basename, $_)) } @sidecars;
        return grep { -e } @sidecars;
    }
}

# Gets the local trash location for the specified path: the same filename
# in the .orphtrash subdirectory.
sub getTrashPath {
    my ($fullPath) = @_;
    my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
    my $trashDir = File::Spec->catdir($dir, $trashDirName);
    return combinePath($vol, $trashDir, $filename);
}

sub comparePathWithExtOrder {
    my ($fullPathA, $fullPathB, $reverseExtOrder) = @_;
    my ($volA, $dirA, $filenameA) = File::Spec->splitpath($fullPathA);
    my ($volB, $dirB, $filenameB) = File::Spec->splitpath($fullPathB);
    return compareDir($dirA, $dirB) ||
           compareFilenameWithExtOrder($filenameA, $filenameB, $reverseExtOrder);
}

sub compareDir {
    my ($dirA, $dirB) = @_;
    return 0 if $dirA eq $dirB; # optimization
    my @as = File::Spec->splitdir($dirA);
    my @bs = File::Spec->splitdir($dirB);
    for (my $i = 0;; $i++) {
        if ($i >= @as) {
            if ($i >= @bs) {
                return 0; # A and B both ran out, so they're equal
            } else {
                return -1; # A is ancestor of B, so A goes first
            }
        } else {
            if ($i >= @bs) {
                return 1; # B is ancestor of A, so B goes first
            } else {
                # Compare this generation - if not equal, then we
                # know the order, else move on to children
                my $c = lc $as[$i] cmp lc $bs[$i];
                return $c if $c;
            }
        }
    }
}

sub compareFilenameWithExtOrder {
    my ($filenameA, $filenameB, $reverseExtOrder) = @_;
    my ($basenameA, $extA) = splitExt($filenameA);
    my ($basenameB, $extB) = splitExt($filenameB);
    # Compare by basename first
    my $c = lc ($basenameA || '') cmp lc ($basenameB || '');
    return $c if $c;
    # Next by extorder
    my $direction = $reverseExtOrder ? -1 : 1;
    my $extOrderA = getFileTypeInfo($extA, 'EXTORDER') || 0;
    my $extOrderB = getFileTypeInfo($extB, 'EXTORDER') || 0;
    $c = $extOrderA <=> $extOrderB;
    return $direction * $c if $c;
    # And then just the extension as a string
    return $direction * (lc ($extA || '') cmp lc ($extB || ''));
}

1;