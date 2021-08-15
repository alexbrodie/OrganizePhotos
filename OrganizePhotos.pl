#!/usr/bin/perl
#
# Commands to regenerate documentation:
#   pod2markdown OrganizePhotos.pl > README.md
#
# TODO LIST
#  * !! Fix bug where onsecutive sidecar MOV files for iPhone live photos in burst are recognized as content match
#  * !! when trashing a dupe, make sure not to trash sidecars that don't match
#  * glob in friendly sort order
#  * add prefix/coloring to operations output to differntate (move, trash, etc)
#  * look for zero duration videos (this hang's Lightroom's
#    DynamicLinkMediaServer which pegs the CPU and blocks Lr preventing any
#    video imports or other things requiring DLMS, e.g. purging video cache)
#  * get rid of texted photos (no metadata (e.g. camera make & model), small 
#    files)
#  * also report base name match when resolving groups
#  * getMd5: content only match for tiff
#  * undo support (z)
#  * get dates for HEIC. maybe just need to update ExifTools?
#  * should notice new MD5 in one dir and missing MD5 in another dir with
#    same file name for when files are moved outside of this script, e.g.
#    Lightroom imports from ToImport folder as move
#  * Offer to trash short sidecar movies with primary image tagged 'NoPeople'?
#  * Consolidate filename/ext handling, e.g. the regex \.([^.]*)$
#  * on enter in -l mode, print last command after pressing enter
#  * Consolidate formatting (view) options for file operations output
#  * Fix benign trash warning: 
#         Can't cd to (/some/path.) .Trash: No such file or directory
#  * Option for find-dupe-files to auto delete full duplicate files that match
#    some conditions, e.g.:
#       - MD5 match of another which doesn't hold the other conditions
#       - with subset (or no "user applied"?) metadata
#       - wrong folder
#       - is in a user suppiled expected dupe dir, e.g. 'ToImport'
#  * something much better than the (i/o/q) prompty for MD5 conflicts
#  * restore trash
#  * dedupe IMG_XXXX.HEIC and IMG_EXXXX.JPG
#  * ignore "resource fork" segments (files starting with "._" which can show
#    up when data is copied from HFS on MacOS to shared exFAT drive and viewed 
#    on Windows), and treat them sort of like sidecars (except, that we want
#    the resource fork of each sidecar in some cases - maybe it should be lower
#    level like moveFile, traverseFiles, etc)
#  * Make sure all file-system/path stuff goes through File:: stuff, not the perlfunc
#    stuff like: -X, glob, stat
#  * Get rid of relative paths more and clean up use of rel2abs/abs2rel, and make
#    File::Find::find callbacks take arguments rather than using File::Find::name
#    and $_ (including using -X and regexp without implicit $_ argument)
#  * Fix globbing on Windows. Currently at least spaces are delimiters, and surely
#    there are other characters. This causes arguments like
#    > perl OrganizePhotos.pl "Foo *.jpg"
#    to be treated as <Foo *.jpg> which is the same as (<Foo>, <*.jpg>) rather than
#    doing the cmd.exe shell expansion which would produce 'Foo 1.jpg', 'Foo 2.jpg', etc.
#  * Replace some hashes whose key sets never change with Class::Struct
#  * Standardize on naming for path pieces, e.g. have prefixes absPath (full absolute path),
#    relPath (full friendly relative path ... from somewhere, but maybe not to CWD),
#    volume (per splitpath), directories ($ per splitpath, and @ per splitdir), filename
#    (the name of the file or directory excluding volume or directory information but
#    including extenaion, and without trailing slash for directories except at root),
#    ext (the extension only of the file including the period, or the empty string if
#    no extension is present)
# * Switch from print to trace where appropriate
# * Namespace somehow for view/model/API/etc?
# * Add param types to sub declaration? 
# * Switch File::Find::find to traverseFiles
# * Replace '.' with File::Spec->curdir()?
# * Cleanup print/trace/warn/die/carp/cluck/croak/confess including final endlines
# * Include zip and pdf files too
# * Tests covering at least the checkup verb code paths
# * Add wrapper around warn/carp/cluck similar to trace. Should we have a
#   halt/alert/inform/trace system for crashes/warnings/print statments/diagnositcs?
# * Add a new restore-trash verb that searches for .Trash dirs and for each
#   one calls consolidateTrash(self, self) and movePath(self, parent)
# * readMd5File/writeMd5File should just do a Storable::dclone on the 
#   hashref it's returning or is passed to cache last md5Path/md5Set for caching
#   rather than only doing it in verifyOrGenerateMd5ForFile
# * Use constants for some of the standard paths like md5.txt, .Trash, thumbs.db, etc
# * Use Cwd instead of File::Spec?
# * Move all colored to view
#
=pod

=head1 NAME

OrganizePhotos - utilities for managing a collection of photos/videos

=head1 SYNOPSIS

# Help:
OrganizePhotos.pl -h

# Typical workflow:
# Import via Image Capture to local folder as originals (unmodified copy)
# Import that folder in Lightroom as move
OrganizePhotos.pl checkup /photos/root/dir
# Archive /photos/root/dir (see help)

=head1 DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

Metadata this program needs to persist are stored in md5.txt files in
the same directory as the files that data was generated for. If they 
are separated, the metadata will no longer be associated and the separated
media files will be treated as new. The expectation is that if files move,
the md5.txt file is also moved or copied.

Metadata operations are powered by Image::ExifTool.

The calling pattern for each command follows the pattern:

    OrganizePhotos <verb> [options...]

The following verbs are available:

=over 5

=item B<add-md5> [glob patterns...]

=item B<check-md5> [glob patterns...]

=item B<checkup> [-d] [-l] [-n] [glob patterns...]

=item B<collect-trash> [glob patterns...]

=item B<find-dupe-files> [-d] [-l] [-n] [glob patterns...]

=item B<metadata-diff> <files...>

=item B<remove-empties> [glob patterns...]

=item B<verify-md5> [glob patterns...]

=back

=head2 add-md5 [glob patterns...]

I<Alias: a5>

For each media file under the current directory that doesn't have a
MD5 computed, generate the MD5 hash and add to md5.txt file.

This does not modify media files or their sidecars, it only adds entries
to the md5.txt files.

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 append-metadata <dir>

I<Alias: am>

Not yet implemented

=head2 check-md5 [glob patterns...]

I<Alias: c5>

For each media file under the current directory, generate the MD5 hash
and either add to md5.txt file if missing or verify hashes match if
already present.

This method is read/write for MD5s, if you want to perform read-only
MD5 checks (i.e., don't write to md5.txt), then use verify-md5.

This does not modify media files or their sidecars, it only modifies
the md5.txt files.

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head3 Examples

    # Check or add MD5 for all CR2 files in the current directory
    $ OrganizePhotos.pl c5 *.CR2

=head2 checkup [glob patterns...]

I<Alias: c>

This command runs the following suggested suite of commands:

    check-md5 [options] [glob patterns...]
    find-dupe-files [options] [glob patterns...]
    remove-empties [options] [glob patterns...]
    collect-trash [options] [glob patterns...]

=head3 Options

=over 24

=item B<-d, --auto-diff>

Automatically do the 'd' diff command for every new group of files

=item B<-l, --default-last-action>

Enter repeats last command

=item B<-n, --by-name>

Search for items based on name rather than the default of MD5

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 collect-trash [glob patterns...]

I<Alias: ct>

Looks recursively for .Trash subdirectories under the current directory
and moves that content to the current directory's .Trash perserving
directory structure.

For example if we had the following trash:

    ./Foo/.Trash/1.jpg
    ./Foo/.Trash/2.jpg
    ./Bar/.Trash/1.jpg

After collection we would have:

    ./.Trash/Foo/1.jpg
    ./.Trash/Foo/2.jpg
    ./.Trash/Bar/1.jpg

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 find-dupe-files [  patterns...]

I<Alias: fdf>

Find files that have multiple copies under the current directory.

=head3 Options

=over 24

=item B<-d, --auto-diff>

Automatically do the 'd' diff command for every new group of files

=item B<-l, --default-last-action>

Enter repeats last command

=item B<-n, --by-name>

Search for items based on name rather than the default of MD5

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 metadata-diff <files...>

I<Alias: md>

Do a diff of the specified media files (including their sidecar metadata).

This method does not modify any file.

=head3 Options

=over 24

=item B<-x, --exclude-sidecars>

Don't include sidecar metadata for a file. For example, a CR2 file wouldn't 
include any metadata from a sidecar XMP which typically is the place where
user added tags like rating and keywords are placed.

=back

=head2 remove-empties [glob patterns...]

I<Alias: re>

Remove any subdirectories that are empty save an md5.txt file.

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=head2 verify-md5 [glob patterns...]

I<Alias: v5>

Verifies the MD5 hashes for all contents of all md5.txt files below
the current directory.

This method is read-only, if you want to add/update MD5s, use check-md5.

This method does not modify any file.

=head3 Options

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern.

=back

=begin comment

=head1 TODO

=head2 FindMisplacedFiles

Find files that aren't in a directory appropriate for their date

=head2 FindDupeFolders

Find the folders that represent the same date

=head2 FindMissingFiles

Finds files that may be missing based on gaps in sequential photos

=head2 FindScreenShots

Find files which are screenshots

=head2 FindOrphanedFiles

Find XMP or THM files that don't have a cooresponding main file

=head2 --if-modified-since

Flag for CheckMd5/VerifyMd5 to only check files created/modified since
the provided timestamp or timestamp at last MD5 check

=end comment

=head1 Related commands

=head2 Complementary ExifTool commands

    # Append all keyword metadata from SOURCE to DESTINATION
    exiftool -addTagsfromfile SOURCE -HierarchicalSubject -Subject DESTINATION

    # Shift all mp4 times, useful when clock on GoPro is reset to 1/1/2015 due to dead battery
    # Format is: offset='[y:m:d ]h:m:s' or more see https://sno.phy.queensu.ca/~phil/exiftool/Shift.html#SHIFT-STRING
    offset='4:6:24 13:0:0'
    exiftool "-CreateDate+=$offset" "-MediaCreateDate+=$offset" "-MediaModifyDate+=$offset" "-ModifyDate+=$offset" "-TrackCreateDate+=$offset" "-TrackModifyDate+=$offset" *.MP4 

=head2 Complementary Mac commands

    # Mirror SOURCE to TARGET
    rsync -ah --delete --delete-during --compress-level=0 --inplace --progress SOURCE TARGET

    # Move .Trash directories recursively to the trash
    find . -type d -iname '.Trash' -exec trash {} \;

    # Move all AAE and LRV files in the ToImport folder to trash
    find ~/Pictures/ToImport/ -type f -iname '*.AAE' -or -iname '*.LRV' -exec trash {} \;

    # Delete .DS_Store recursively (omit "-delete" to only print)
    find . -type f -name .DS_Store -print -delete

    # Delete zero byte md5.txt files (omit "-delete" to only print)
    find . -type f -iname md5.txt -empty -print -delete

    # Remove empty directories (omit "-delete" to only print)
    find . -type d -empty -print -delete

    # Remove the executable bit for media files
    find . -type f -perm +111 \( -iname "*.CRW" -or -iname "*.CR2"
        -or -iname "*.JPEG" -or -iname "*.JPG" -or -iname "*.M4V"
        -or -iname "*.MOV" -or -iname "*.MP4" -or -iname "*.MPG"
        -or -iname "*.MTS" -or -iname "*.NEF" -or -iname "*.RAF"
        -or -iname "md5.txt" \) -print -exec chmod -x {} \;

    # Remove downloaded-and-untrusted extended attribute for the current tree
    xattr -d -r com.apple.quarantine .

    # Find large-ish files
    find . -size +100MB

    # Display disk usage stats sorted by size decreasing
    du *|sort -rn

    # Find all HEIC files that have a JPG with the same base name
    find . -iname '*.heic' -execdir sh -c 'x="{}"; y=${x:0:${#x}-4}; [[ -n `find . -iname "${y}jpg"` ]] && echo "$PWD/$x"' \;

    # For each HEIC move some metadata from neighboring JPG to XMP sidecar
    # and trash the JPG. This is useful when you have both the raw HEIC from
    # iPhone and the converted JPG which holds the metadata and you want to
    # move it to the HEIC and just keep that. For example if you import once
    # as JPG, add metadata, and then re-import as HEIC.
    find . -iname '*.heic' -exec sh -c 'x="{}"; y=${x:0:${#x}-4}; exiftool -tagsFromFile ${y}jpg -Rating -Subject -HierarchicalSubject ${y}xmp; trash ${y}jpg' \;

    # For each small MOV file, look for pairing JPG or HEIC files and print
    # the path of the MOV files where the main image file is missing.
    find . -iname '*.mov' -size -6M -execdir sh -c 'x="{}"; y=${x:0:${#x}-3}; [[ -n `find . -iname "${y}jpg" -o -iname "${y}heic"` ]] || echo "$PWD/$x"' \;

    # Restore _original files (undo exiftool changes)
    find . -iname '*_original' -exec sh -c 'x={}; y=${x:0:${#x}-9}; echo mv $x $y' \;

=head2 Complementary PC commands

    # Mirror SOURCE to TARGET
    robocopy /MIR SOURCE TARGET

=head1 AUTHOR

Copyright 2017, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool>

=cut

use strict; 
use warnings;
use warnings FATAL => qw(uninitialized);

use Data::Compare ();
use Data::Dumper ();
use DateTime::Format::HTTP ();
use Digest::MD5 ();
use File::Copy ();
use File::Find ();
use File::Glob qw(:globally :nocase);
use File::Path ();
use File::Spec ();
use File::stat ();
use Getopt::Long ();
use Image::ExifTool ();
use JSON ();
use List::Util qw(any all uniqstr max);
use Pod::Usage ();
if ($^O eq 'MSWin32') {
    use Win32::Console::ANSI; # must come before Term::ANSIColor
}
# TODO: be explicit with this and move usage to view layer
use Term::ANSIColor;

# Implementation version of getMd5 (useful when comparing older serialized
# results, such as canMakeMd5MetadataShortcut and isMd5VersionUpToDate)
my $getMd5Version = 4;

# What we expect an MD5 hash to look like
my $md5DigestPattern = qr/[0-9a-f]{32}/;

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
# EXTORDER
#   Defines the sort order when displaying a group of duplicate files with
#   the lower values coming first. Typically the "primary" files are displayed
#   first and so have lower values. If a type is a sidecar of another, the
#   EXTORDER of the sidecar type must be strictly greater if it exists. Thus
#   this is also used to control processing order so that primary files are
#   handled before their sidecars - e.g. raf files are handled before jpg
#   sidecars
# TODO: verify this EXTORDER/SIDECAR claim, perhaps in tests somewhere. It would
# also ensure the statement in SIDECARS that there are no cycles.
#
# MIMETYPE
#   The mime type of the file type.
#   Reference: filext.com
#   For types without a MIME type, we fabricate a "non-standard" one
#   based on extension.
#
# TODO: flesh this out
# TODO: convert to Class::Struct
my %fileTypes = (
    AVI => {
        SIDECARS => [],
        EXTORDER => 0,
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
        MIMETYPE => 'image/cr3' # Non-standard
    },
    ICNS => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/x-icns'
    },
    ICO => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/x-icon'
    },
    JPEG => {
        SIDECARS => [],
        EXTORDER => 1,
        MIMETYPE => 'image/jpeg'
    },
    JPG => {
        SIDECARS => [],
        EXTORDER => 1,
        MIMETYPE => 'image/jpeg'
    },
    HEIC => {
        SIDECARS => [qw( XMP MOV )],
        EXTORDER => -1,
        MIMETYPE => 'image/heic'
    },
    M2TS => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/mp2t'
    },
    M4V => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/mp4v-es'
    },
    MOV => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/quicktime'
    },
    MP4 => {
        SIDECARS => [qw( LRV THM )],
        EXTORDER => 0,
        MIMETYPE => 'video/mp4v-es'
    },
    MPG => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/mpeg'
    },
    MTS => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/mp2t'
    },
    NEF => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/nef' # Non-standard
    },
    PDF => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'application/pdf'
    },
    PNG => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/png'
    },
    PSB => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/psb' # Non-standard
    },
    PSD => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/photoshop'
    },
    RAF => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/raf' # Non-standard
    },
    TIF => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/tiff'
    },
    TIFF => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/tiff'
    },
    ZIP => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'application/zip'
    }
);

my $backupSuffix = qr/
    [._] (?i) (?:bak|original) \d*
    /x;

# Media file extensions
my $mediaType = qr/
    # Media extension
    (?: \. (?i) (?: @{[ join '|', keys %fileTypes ]}))
    # Backup file
    (?: $backupSuffix)?
    $/x;

use constant MATCH_UNKNOWN => 0;
use constant MATCH_NONE => 1;
use constant MATCH_FULL => 2;
use constant MATCH_CONTENT => 3;

# For extra output
my $verbosity = 0;
use constant VERBOSITY_2 => 2;
use constant VERBOSITY_DEBUG => 99;

use constant CRUD_UNKNOWN => 0;
use constant CRUD_CREATE => 1;
use constant CRUD_READ => 2;
use constant CRUD_UPDATE => 3;
use constant CRUD_DELETE => 4;

my $cachedMd5Path = '';
my $cachedMd5Set = {};

main();
exit 0;

#===============================================================================
# Main entrypoint that parses command line a bit and routes to the 
# subroutines starting with "do"
sub main {
    sub myGetOptions {
        Getopt::Long::GetOptions('verbosity|v=i' => \$verbosity, @_)
            or die "Error in command line, aborting.";
    }

    # Parse args (using GetOptions) and delegate to the doVerb methods...
    unless (@ARGV) {
        Pod::Usage::pod2usage();
    } elsif ($#ARGV == 0 and $ARGV[0] =~ /^-[?h]|help$/i) {
        Pod::Usage::pod2usage(-verbose => 2);
    } else {
        Getopt::Long::Configure('bundling');
        my $rawVerb = shift @ARGV;
        my $verb = lc $rawVerb;
        if ($verb eq 'add-md5' or $verb eq 'a5') {
            myGetOptions();
            doAddMd5(@ARGV);
        } elsif ($verb eq 'append-metadata' or $verb eq 'am') {
            myGetOptions();
            doAppendMetadata(@ARGV);
        } elsif ($verb eq 'check-md5' or $verb eq 'c5') {
            myGetOptions();
            doCheckMd5(@ARGV);
        } elsif ($verb eq 'checkup' or $verb eq 'c') {
            my ($autoDiff, $byName, $defaultLastAction) = (0, 0, 0);
            myGetOptions('auto-diff|d' => \$autoDiff,
                         'by-name|n' => \$byName,
                         'default-last-action|l' => \$defaultLastAction);
            doCheckMd5(@ARGV);
            doFindDupeFiles( $byName, $autoDiff, 
                            $defaultLastAction, @ARGV);
            doRemoveEmpties(@ARGV);
            doCollectTrash(@ARGV);
        } elsif ($verb eq 'collect-trash' or $verb eq 'ct') {
            myGetOptions();
            doCollectTrash(@ARGV);
        } elsif ($verb eq 'find-dupe-dirs' or $verb eq 'fdd') {
            myGetOptions();
            @ARGV and die "Unexpected parameters: @ARGV";
            doFindDupeDirs();
        } elsif ($verb eq 'find-dupe-files' or $verb eq 'fdf') {
            my ($autoDiff, $byName, $defaultLastAction) = (0, 0, 0);
            myGetOptions('auto-diff|d' => \$autoDiff,
                         'by-name|n' => \$byName,
                         'default-last-action|l' => \$defaultLastAction);
            doFindDupeFiles($byName, $autoDiff, 
                            $defaultLastAction, @ARGV);
        } elsif ($verb eq 'metadata-diff' or $verb eq 'md') {
            my ($excludeSidecars) = (0);
            myGetOptions('exclude-sidecars|x' => \$excludeSidecars);
            doMetadataDiff($excludeSidecars, @ARGV);
        } elsif ($verb eq 'remove-empties' or $verb eq 're') {
            myGetOptions();
            doRemoveEmpties(@ARGV);
        } elsif ($verb eq 'test') {
            doTest(@ARGV);
        } elsif ($verb eq 'verify-md5' or $verb eq 'v5') {
            myGetOptions();
            doVerifyMd5(@ARGV);
        } else {
            die "Unknown verb: '$rawVerb'";
        }
    }
}

# API ==========================================================================
# Execute add-md5 verb
sub doAddMd5 {
    verifyOrGenerateMd5ForGlob(1, @_);
}

# API ==========================================================================
# EXPERIMENTAL
# Execute append-metadata verb
sub doAppendMetadata {
    appendMetadata(@_);
}

# API ==========================================================================
# Execute check-md5 verb
sub doCheckMd5 {
    verifyOrGenerateMd5ForGlob(0, @_);
}

# API ==========================================================================
# Execute collect-trash verb
sub doCollectTrash {
    my (@globPatterns) = @_;
    traverseFiles(
        sub { # isWanted
            my ($fullPath) = @_;
            return -d $fullPath;
        },
        sub { # callback
            my ($fullPath, $rootFullPath) = @_;
            my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
            if (lc $filename eq '.trash') {
                # Convert root/bunch/of/dirs/.Trash to root/.Trash/bunch/of/dirs
                trashPathWithRoot($fullPath, $rootFullPath);
            }
        },
        @globPatterns);
}

# API ==========================================================================
# EXPERIMENTAL
# Execute find-dupe-dirs verb
sub doFindDupeDirs {

    # TODO: clean this up and use traverseFiles

    my %keyToPaths = ();
    File::Find::find({
        preprocess => sub {
            return grep { !-d or lc ne '.trash' } @_; # skip trash
        },
        wanted => sub {
            if (-d and (/^(\d\d\d\d)-(\d\d)-(\d\d)\b/
                or /^(\d\d)-(\d\d)-(\d\d)\b/
                or /^(\d\d)(\d\d)(\d\d)\b/)) {

                my $y = $1 < 20 ? $1 + 2000 : $1 < 100 ? $1 + 1900 : $1;
                push @{$keyToPaths{lc "$y-$2-$3"}}, File::Spec->rel2abs($_);
            }
        }
    }, '.');

    #while (my ($key, $paths) = each %keyToPaths) {
    for my $key (sort keys %keyToPaths) {
        my $paths = $keyToPaths{$key};
        if (@$paths > 1) {
            print "$key:\n";
            print "\t$_\n" for @$paths;
        }
    }
}

# TODO: Move this elsewhere in the file/package
# ------------------------------------------------------------------------------
sub buildFindDupeFilesDupeGroups {
    my ($byName, @globPatterns) = @_;

    # Create the initial groups in various ways with key that is opaque
    # and ignored from the outside
    my %keyToFullPathList = ();
    if ($byName) {
        # Hash key based on file/dir name
        traverseFiles(
            \&wantNonTrashMedia,
            sub { # callback
                my ($fullPath) = @_;
                if (-f $fullPath) {
                    my $key = computeFindDupeFilesHashKeyByName($fullPath);
                    push @{$keyToFullPathList{$key}}, $fullPath;
                }
            },
            @globPatterns);
    } else {
        # Hash key is MD5
        findMd5s(
            sub {
                my ($fullPath, $md5) = @_;
                push @{$keyToFullPathList{$md5}}, $fullPath;
            }, 
            @globPatterns);
    }

    trace(VERBOSITY_DEBUG, "Found @{[scalar keys %keyToFullPathList]} initial groups");

    # Go through each element in the %keyToFullPathList map, and we'll 
    # want the ones with multiple things in the array of paths. If
    # there  are multiple paths for an element, sort the paths array
    # by decreasing importance (our best guess), and add it to the
    # @dupes collection for further processing.
    my @dupes = ();
    while (my ($key, $fullPathList) = each %keyToFullPathList) {
        if (@$fullPathList > 1) {
            push @dupes, [sort { comparePathWithExtOrder($a, $b) } @$fullPathList];
        }
    }

    # The 2nd level is properly sorted, now let's sort the groups
    # themselves - this will be the order in which the groups
    # are processed, so we want it extorder based as well.
    @dupes = sort { comparePathWithExtOrder($a->[0], $b->[0]) } @dupes;

    trace(VERBOSITY_DEBUG, "Found @{[scalar @dupes]} groups with multiple files");

    return \@dupes;
}

# TODO: Move this elsewhere in the file/package
# ------------------------------------------------------------------------------
sub computeFindDupeFilesHashKeyByName {
    my ($fullPath) = @_;

    my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
    my ($basename, $ext) = splitExt($filename);

    # 1. Start with extension
    my $key = lc $ext . ';';

    # 2. Add basename
    my $nameRegex = qr/^
        (
            # things like DCF_1234
            [a-zA-Z\d_]{4} \d{4} |
            # things like 2009-08-11 12_31_45
            \d{4} [-_] \d{2} [-_] \d{2} [-_\s] 
            \d{2} [-_] \d{2} [-_] \d{2}
        ) \b /x;

    if ($basename =~ /$nameRegex/) {
        # This is an understood filename format, so just take
        # the root so that we can ignore things like "Copy (2)"
        $key .= lc $1 . ';';
    } else {
        # Unknown file format, just use all of basename? It's not
        # nothing, but will only work with exact filename matches
        warn "Unknown filename format for '$basename' in '@{[prettyPath($fullPath)]}'";
        $key .= lc $basename . ';';
    }

    #. Directory info
    my $nameKeyIncludesDir = 1;
    if ($nameKeyIncludesDir) {
        # parent dir should be similar (based on date format)
        my $dirRegex = qr/^
            # yyyy-mm-dd or yy-mm-dd or yyyymmdd or yymmdd
            (?:19|20)?(\d{2}) [-_]? (\d{2}) [-_]? (\d{2}) \b
            /x;

        my $dirKey = '';
        for (reverse File::Spec->splitdir($dir)) {
            if (/$dirRegex/) {
                $dirKey = lc "$1$2$3;";
                last;
            }
        }

        if ($dirKey) {
            $key .= $dirKey;
        } else {
            warn "Unknown directory format in '@{[prettyPath($fullPath)]}'";
        }
    }

    return $key;
}

# TODO: Move this elsewhere in the file/package
# ------------------------------------------------------------------------------
sub buildFindDupeFilesPrompt {
    my ($group, $fast, $matchType, $autoCommand, $defaultCommand, $progressNumber, $progressCount) = @_;

    # Build base of prompt - indexed paths
    my @prompt = ();

    # Main heading for group
    push @prompt, 'Resolving duplicate group ', $progressNumber, ' of ', $progressCount, ' ';
    if ($matchType == MATCH_FULL) {
        push @prompt, colored('[Match: FULL]', 'bold blue on_white');
    } elsif ($matchType == MATCH_CONTENT) {
        push @prompt, '[Match: Content]';
    } else {
        push @prompt, colored('[Match: UNKNOWN]', 'bold red on_white');
    }
    push @prompt, "\n";

    # The list of all files in the group
    for (my $i = 0; $i < @$group; $i++) {
        my $elt = $group->[$i];

        push @prompt, '  ', colored(coloredByIndex("$i. ", $i), 'bold');
        push @prompt, coloredByIndex(prettyPath($elt->{fullPath}), $i);

        # Add file error suffix
        if ($elt->{exists}) {
            # Don't bother cracking the file to get metadata if we're in fast mode
            # TODO: this file access and computation doesn't seem to belong here
            unless ($fast) {
                if (my $err = getDirectoryError($elt->{fullPath})) {
                    push @prompt, ' ', colored("** $err **", 'bright_white on_' . colorByIndex($i));
                }
            }
        } else {
            push @prompt, ' ', colored('[MISSING]', 'bold red on_white');
        }

        push @prompt, "\n";

        # Collect all sidecars and add to prompt
        for (getSidecarPaths($elt->{fullPath})) {
            push @prompt, '     ', coloredByIndex(colored(prettyPath($_), 'faint'), $i), "\n";
        }
    }

    #push @prompt, colored("I suggest you $autoCommand", 'bold black on_red'), "\n" if $autoCommand;

    # Returns either something like 'x0/x1' or 'x0/.../x42'
    my $getMultiCommandOption = sub {
        my ($prefix) = @_;

        if (@$group <= 3) {
            return join '/', map { coloredByIndex("$prefix$_", $_) } (0..$#$group);
        } else {
            return coloredByIndex("${prefix}0", 0) . '/.../' . 
                   coloredByIndex("$prefix$#$group", $#$group);
        }
    };

    # Input options
    push @prompt, 'Choose action(s): ?/c/d/', $getMultiCommandOption->('o'), 
                  '/q/', $getMultiCommandOption->('t'), ' ';
    if ($defaultCommand) {
        my @dcs = split(';', $defaultCommand);
        @dcs = map { /^\w+(\d+)$/ ? coloredByIndex($_, $1) : $_ } @dcs;
        push @prompt, '[', join(';', @dcs), '] ';
    }

    return join '', @prompt;
}

# TODO: break up this nearly 400 line behemoth
# API ==========================================================================
# Execute find-dupe-files verb
sub doFindDupeFiles {
    my ($byName, $autoDiff, $defaultLastAction, @globPatterns) = @_;

    my $fast = 0; # avoid slow operations, potentially with less precision?

    my $dupeGroups = buildFindDupeFilesDupeGroups($byName, @globPatterns);

    # TODO: merge sidecars

    # Process each group of duplicates
    my $lastCommand = '';
    DUPEGROUP: for (my $dupeGroupsIdx = 0; $dupeGroupsIdx < @$dupeGroups; $dupeGroupsIdx++) {
        # Convert current element from an array of full paths to
        # an array (per file, in storted order) to array of hash
        # references with some metadata in the same (desired) order
        my @group = map {
            { fullPath => $_, exists => -e $_ }
        } @{$dupeGroups->[$dupeGroupsIdx]};

        # TODO: we do a lot of file reads here that maybe could be consolidated?
        #   * Image::ExifTool::ExtractInfo in getDirectoryError once per file per DUPEGROUP:
        #   * Image::ExifTool::ExtractInfo once per file per metadataDiff
        #   * getMd5 file read

        # TODO: Should we sort groups so that missing files are at the end?
        # It's supposed to be sorted by importance. We would need to do that
        # before starting to build $autoCommand

        # TODO: should this change to a "I suggest you ____, sir" approach?
        # If dupes are missing, we can auto-remove. I think that's done. Can
        # we remove the below, and just use the $command = $autoCommand down
        # before the PROMPT loop? 
        my $autoRemoveMissingDuplicates = 0;
        if ($autoRemoveMissingDuplicates) {
            # Remove the metadata for all missing files, and
            # keep track of what's still existing
            my @newGroup = ();
            for (@group) {
                if ($_->{exists}) {
                    push @newGroup, $_;
                } else {
                    removeMd5ForMediaPath($_->{fullPath});
                }
            }

            # If there's still multiple in the group, continue
            # with what was left over, else move to next group
            next DUPEGROUP if @newGroup < 2;

            @group = @newGroup;
        }

        # TODO: my $matchType = getFindDupeFilesMatchType(\@group);

        # Except when trying to be fast, calculate the MD5 match
        # TODO: get this pairwise and store it somehow for later
        # TODO: (hopefully for auto-delete)
        my $matchType = MATCH_UNKNOWN;
        unless ($fast) {
            # Want to tell if the files are identical, so we need hashes
            # TODO: if we're not doing this by name we can use the md5.txt file contents for  MD5 and other metadata
            # if we can do a metadata shortcut (i.e. md5.txt is up to date)
            $_->{exists} and $_ = { %$_, %{getMd5($_->{fullPath})} } for @group;

            my $fullMd5Match = 1;
            my $md5Match = 1;

            # If all the primary MD5s are the same report IDENTICAL
            # If any are missing, should be complete mismatch
            my $md5 = $group[0]->{md5} || 'x';
            my $fullMd5 = $group[0]->{full_md5} || 'x';
            for (my $i = 1; $i < @group; $i++) {
                $md5Match = 0 if $md5 ne ($group[$i]->{md5} || 'y');
                $fullMd5Match = 0 if $fullMd5 ne ($group[$i]->{full_md5} || 'y');
            }

            if ($fullMd5Match) {
                $matchType = MATCH_FULL;
            } elsif ($md5Match) {
                $matchType = MATCH_CONTENT;
            } else {
                $matchType = MATCH_NONE;
            }
        }

        # TODO: my $autoCommand = getFindDupeFilesAutoCommands(\@group, ...);

        # See if we can use some heuristics to guess what should be
        # done for this group
        my @autoCommands = ();

        # Figure out what's trashable, starting with any missing files
        my @remainingIdx = grep { $group[$_]->{exists} } (0..$#group);

        # If there are still multiple items remove anything that's
        # in temp locations like staging areas (if it leaves anything)
        if (@remainingIdx > 1) {
            my @idx = grep { 
                $group[$_]->{fullPath} !~ /[\/\\]ToImport[\/\\]/
            } @remainingIdx;
            @remainingIdx = @idx if @idx;
        }

        # If full match, just take the first (most important)
        @remainingIdx = ($remainingIdx[0]) if $matchType == MATCH_FULL;

        # Now take everything that isn't in @reminingIdx and suggest trash it
        my @isTrashable = map { 1 } (0..$#group);
        $isTrashable[$_] = 0 for @remainingIdx;
        for (my $i = 0; $i < @group; $i++) {
            push @autoCommands, "t$i" if $isTrashable[$i];
        }

        # If it's a short mov file next to a jpg or heic that's an iPhone,
        # then it's probably the live video portion from a burst shot. We
        # should just continue
        # TODO: ^^^^ that

        my $autoCommand = join ';', uniqstr sort @autoCommands;

        # Default command is what happens if you hit enter with an empty string
        my $defaultCommand;
        if ($autoCommand) {
            $defaultCommand = $autoCommand;
        } elsif ($defaultLastAction) {
            $defaultCommand = $lastCommand;
        }

        my $prompt = buildFindDupeFilesPrompt(
            \@group, $fast, $matchType, $autoCommand, $defaultCommand, 
            $dupeGroupsIdx + 1, scalar @$dupeGroups);

        # TODO: somehow determine whether one is a superset of one or
        # TODO: more of the others (hopefully for auto-delete) 
        metadataDiff(undef, map { $_->{fullPath} } @group) if $autoDiff;

        # If you want t automate something (e.g. do $defaultCommand without
        # user confirmation), set that action here: 
        my $command;

        # Get input until something sticks...
        PROMPT: while (1) {
            # Prompt for command(s)
            print $prompt;
            unless ($command) {
                chomp($command = lc <STDIN>);
                if ($command) {
                    # If the user provided something, save that for next 
                    # conflict's default
                    $lastCommand = $command;
                } elsif ($defaultCommand) {
                    # Enter with empty string uses $defaultCommand
                    $command = $defaultCommand;
                }
            } else {
                print "$command\n";
            }

            # TODO: processFindDupeFilesCommands(\@group, $command)

            # Process the command(s)
            my $itemCount = @group;
            for (split /;/, $command) {
                if ($_ eq '?') {
                    print <<'EOM';
?   Help: shows this help message
c   Continue: go to the next group
d   Diff: perform metadata diff of this group
o#  Open Number: open the specified item
q   Quit: exit the application
t#  Trash Number: move the specified item to .Trash
EOM
                } elsif ($_ eq 'c') {
                    # Continue
                    last PROMPT;  # next group please
                } elsif ($_ eq 'd') {
                    # Diff
                    metadataDiff(undef, map { $_->{fullPath} } @group);
                } elsif (/^m(\d+(?:,\d+)+)$/) {
                    # Merge 1,2,3,4,... into 0
                    my @matches = split ',', $1;
                    appendMetadata(map { $group[$_]->{fullPath} } @matches);
                } elsif (/^o(\d+)$/) {
                    # Open Number
                    if ($1 > $#group) {
                        warn "$1 is out of range [0, $#group]";
                    } elsif (!defined $group[$1]) {
                        warn "$1 has already been trashed";
                    } else {
                        system("\"$group[$1]->{fullPath}\"");
                    }
                } elsif ($_ eq 'q') {
                    # Quit
                    exit 0;
                } elsif (/^t(\d+)$/) {
                    # Trash Number
                    if ($1 > $#group) {
                        warn "$1 is out of range [0, $#group]";
                    } elsif (!defined $group[$1]) {
                        warn "$1 has already been trashed";
                    } else {
                        if ($group[$1]->{exists}) {
                            trashPathAndSidecars($group[$1]->{fullPath});
                        } else {
                            # File we're trying to trash doesn't exist, 
                            # so just remove its metadata
                            removeMd5ForMediaPath($group[$1]->{fullPath});
                        }

                        $group[$1] = undef;
                        $itemCount--;
                        last PROMPT if $itemCount < 2;
                    }
                } else {
                    warn "Unrecognized command: '$_'";
                }
            } 
            # This is the end of command processing if no one told us to go to
            # the next group (i.e. last PROMPT). Before re-processing this group
            # (i.e. redo DUPEGROUP), remove anything from the source that we
            # undef'ed in in working collection @group while processing commands.
            for (my $i = $#group; $i >= 0; $i--) {
                splice @{$dupeGroups->[$dupeGroupsIdx]}, $i unless defined $group[$i];
            }
            redo DUPEGROUP;
        } # PROMPT 
    } # DUPEGROUP
}

# API ==========================================================================
# Execute metadata-diff verb
sub doMetadataDiff {
    my ($excludeSidecars, @paths) = @_;
    metadataDiff($excludeSidecars, @paths);
}

# API ==========================================================================
# Execute remove-empties verb
sub doRemoveEmpties {
    my (@globPatterns) = @_;

    # Map from directory absolute path to sub-item count
    my %dirSubItemsMap = ();

    traverseFiles(
        sub { # isWanted
            my ($fullPath) = @_;

            my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
            my $lcfn = lc $filename;
            if (-d $fullPath) {
                # silently skip trash, traverse other dirs
                return ($lcfn ne '.trash');
            } elsif (-f $fullPath) {
                # These files don't count - they're trashible, ignore them (by 
                # not processing) as if they didn't exist and let them get
                # cleaned up if the folder
                return 0 if any { $lcfn eq $_ } ('.ds_store', 'thumbs.db', 'md5.txt');

                # TODO: exclude zero byte or hidden files as well?

                # Other files count
                return 1;
            }

            die "Programmer Error: unknown object type for '$fullPath'";
        },
        sub { # callback 
            my ($fullPath, $rootFullPath) = @_;

                if (-d $fullPath) {
                    # at this point, all the sub-items should be processed, see how many
                    my $subItems = $dirSubItemsMap{$fullPath};
                    #trace(VERBOSITY_DEBUG, "Directory '$fullPath' contains @{[ $subItems || 0 ]} subitems");

                    # As part of a later verification check, we'll remove this dir
                    # from our map. Then if other sub-items are added after we process
                    # this parent dir right now, then we could have accidentally trashed
                    # a non-trashable dir. 
                    delete $dirSubItemsMap{$fullPath};

                    # If this dir is empty, then we'll want to trash it and have the
                    # parent dir ignore it like trashable files (e.g. md5.txt). If
                    # it's not trashable, then fall through to add this to its parent
                    # dir's list (to prevent the parent from being trashed).
                    unless ($subItems) {
                        trashPath($fullPath);
                        return;
                    }
                }

                # We don't mark the root item (file or dir) like all the subitems, because
                # we're not looking to remove the root's parent based on some partial knowledge
                # (e.g. if dir Alex has a lot of non-empty stuff in it and a child dir named
                # Quinn, then we wouldn't want to consider trashing Alex if we check only Quinn)
                if ($fullPath ne $rootFullPath) {
                    my $parentFullPath = parentPath($fullPath);
                    $dirSubItemsMap{$parentFullPath}++;
                }
        },
        @globPatterns);

    if (%dirSubItemsMap) {
        # See notes in above callback 
        die "Programmer Error: unprocessed items in doRemoveEmpties map";
    }
}

# API ==========================================================================
# EXPERIMENTAL
# Execute test verb - usually just a playground for testing and new ideas
sub doTest {
    my @colors = qw(black red green yellow blue magenta cyan white);
    my @colorLabels = qw(Blk Red Grn Yel Blu Mag Cyn Wht);
    #@colors = map { $_, "bright_$_" } @colors;
    @colors = (@colors, map { "bright_$_" } @colors);

    # Windows cmd.exe behavior:
    #   bold: makes foreground bright (e.g. converts blue to bright_blue)
    #   dard=faint: no effect (like many systems)
    #   italic: no effect (like many systems)
    #   underline=underscore: makes background bright (e.g. converts on_blue to on_bright_blue)
    #   blink: no effect (like many systems)
    #   reverse: flips foreground and background colors
    #   concealed: text doesn't render
    # So none of that really matters here

    print "\n", ' ' x 38, '_' x 13, 'Bright', '_' x 13, "\n      ", (map { "$_ "} @colorLabels) x 2, "\n";
    for (my $i = 0; $i < @colors; $i++) {
        print(' ', ($i < @colorLabels ? '  ' : substr(' Bright ', $i - @colorLabels, 1) . '|'), $colorLabels[$i % @colorLabels]);
        for my $bg (@colors) {
            print colored(' XO ', $colors[$i % @colors] . ' on_' . $bg);
        }
        print "\n";
    }
}
sub doTest2 {
    my ($filename) = @_;

    -s $filename
        or die "$filename doesn't exist";

    # Look for a QR code
    my @results = `qrscan '$filename'`;
    trace(VERBOSITY_DEBUG, "qrscan: ", Data::Dumper::Dumper(@results));

    # Parse QR codes
    my $messageDate;
    for (@results) {
        /^Message:\s*(\{.*\})/
            or die "Unexpected qrscan output: $_";

        my $message = JSON::decode_json($1);
        trace(VERBOSITY_DEBUG, "message: ", Data::Dumper::Dumper($message));

        if (exists $message->{date}) {
            my $date = $message->{date};
            !$messageDate or $messageDate eq $date
                or die "Two different dates detected: $messageDate, $date";
            $messageDate = $date
        }
    }

    if ($messageDate) {
        # Get file metadata
        my @props = qw(DateTimeOriginal TimeZone TimeZoneCity DaylightSavings 
                       Make Model SerialNumber);
        trace(VERBOSITY_2, "Image::ExifTool::ImageInfo('$filename', ...);");
        my $info = Image::ExifTool::ImageInfo($filename, \@props, {DateFormat => '%FT%TZ'});
        trace(VERBOSITY_DEBUG, "$filename: ", Data::Dumper::Dumper($info));

        my $metadataDate = $info->{DateTimeOriginal};
        trace(VERBOSITY_DEBUG, "$messageDate vs $metadataDate");

        # The metadata date is an absolute time (the local time where
        # it was taken without any time zone information). The message
        # date is the date specified in the QR code of the image which
        # (when using the iOS app) is the full date/time of the device
        # (local time with time zone). So if we want to compare them
        # we have to just use the local time portion (and ignore the
        # time zone), assuming that the camera and the iOS device were
        # in the same time zone at the time of capture. So, remove the
        # time zone.
        $messageDate =~ s/([+-][\d:]*)$/Z/;
        my $messageTimeZone = $1;
        trace(VERBOSITY_DEBUG, "$messageDate vs $metadataDate");

        $messageDate = DateTime::Format::HTTP->parse_datetime($messageDate);
        $metadataDate = DateTime::Format::HTTP->parse_datetime($metadataDate);

        my $diff = $messageDate->subtract_datetime($metadataDate);

        trace(VERBOSITY_DEBUG, "$messageDate - $messageDate = ", Data::Dumper::Dumper($diff));

        my $days = ($diff->is_negative ? -1 : 1) * 
            ($diff->days + ($diff->hours + ($diff->minutes + $diff->seconds / 60) / 60) / 24);

        print <<"EOM";
Make            : $info->{Make}
Model           : $info->{Model}
SerialNumber    : $info->{SerialNumber}
FileDateTaken   : $metadataDate
FileTimeZone    : $info->{TimeZone}
QRDateTaken     : $messageDate
QRTimeZone      : $messageTimeZone
QR-FileDays     : $days
QR-FileHours    : @{[$days * 24]}
EOM
    }
}

# API ==========================================================================
# Execute verify-md5 verb
sub doVerifyMd5 {
    my (@globPatterns) = @_;

    # TODO: this verification code is really old (i think it is still
    # based on V1 md5.txt file, back when it was actually a text file)
    # can we combine it with or reuse somehow verifyOrGenerateMd5ForFile?

    my $all = 0;
    findMd5s(sub {
        my ($fullPath, $expectedMd5) = @_;
        if (-e $fullPath) {
            # File exists
            my $actualMd5 = getMd5($fullPath)->{md5};
            if ($actualMd5 eq $expectedMd5) {
                # Hash match
                print "Verified MD5 for '@{[prettyPath($fullPath)]}'\n";
            } else {
                # Has MIS-match, needs input
                warn "ERROR: MD5 mismatch for '@{[prettyPath($fullPath)]}' ($actualMd5 != $expectedMd5)";
                unless ($all) {
                    while (1) {
                        print "Ignore, ignore All, Quit (i/a/q)? ";
                        chomp(my $in = lc <STDIN>);

                        if ($in eq 'i') {
                            last;
                        } elsif ($in eq 'a') {
                            $all = 1;
                            last;
                        } elsif ($in eq 'q') {
                            exit 0;
                        }
                    }
                }
            }
        } else {
            # File doesn't exist
            # TODO: prompt to see if we should remove this via removeMd5ForMediaPath
            warn "Missing file: '@{[prettyPath($fullPath)]}'";
        }
    }, @globPatterns);
}

#-------------------------------------------------------------------------------
# Call verifyOrGenerateMd5ForFile for each media file in the glob patterns
sub verifyOrGenerateMd5ForGlob {
    my ($addOnly, @globPatterns) = @_;
    traverseFiles(
        \&wantNonTrashMedia,
        sub { # callback
            my ($fullPath) = @_;
            if (-f $fullPath) {
                verifyOrGenerateMd5ForFile($addOnly, $fullPath);
            }
        },
        @globPatterns);
}

#-------------------------------------------------------------------------------
# If the file's md5.txt file has a MD5 for the specified [path], this
# verifies it matches the current MD5.
#
# If the file's md5.txt file doesn't have a MD5 for the specified [path],
# this adds the [path]'s current MD5 to it.
sub verifyOrGenerateMd5ForFile {
    my ($addOnly, $fullPath) = @_;
    my ($md5Path, $md5Key) = getMd5PathAndMd5Key($fullPath);
    my $newMd5Info = makeMd5InfoBase($fullPath);

    # Check cache from last call (this can often be called
    # repeatedly with files in same folder, so this prevents
    # unnecessary rereads)
    # TODO: unless force override if specified
    if ($md5Path eq $cachedMd5Path and
        canMakeMd5MetadataShortcut($addOnly, $fullPath, $cachedMd5Set->{$md5Key}, $newMd5Info)) {
        return $cachedMd5Set->{$md5Key}; # return memory cache of Md5Info
    }

    # Read MD5.txt file to consult
    my ($md5File, $md5Set) = readOrCreateNewMd5File($md5Path);

    # Target hash and metadata from cache and/or md5.txt
    my $oldMd5Info = $md5Set->{$md5Key};

    # Skip files whose date modified and file size haven't changed
    # TODO: unless force override if specified
    if (canMakeMd5MetadataShortcut($addOnly, $fullPath, $oldMd5Info, $newMd5Info)) {
        return $oldMd5Info; # return md5.txt cache of Md5Info
    }

    # We can't skip this, so compute MD5 now
    eval {
        # TODO: consolidate opening file multiple times from stat and getMd5
        $newMd5Info = { %$newMd5Info, %{getMd5($fullPath)} };
    };
    if (my $error = $@) {
        # Can't get the MD5
        # TODO: for now, skip but we'll want something better in the future
        warn colored("UNAVAILABLE MD5 for '@{[prettyPath($fullPath)]}' with error:", 'red'), "\n\t$error\n";
        return undef;
    }

    # newMd5Info and oldMd5Info should now be fully populated and 
    # ready for comparison
    if (defined $oldMd5Info) {
        if ($oldMd5Info->{md5} eq $newMd5Info->{md5}) {
            # Matches last recorded hash, but still continue and call
            # setMd5InfoAndWriteMd5File to handle other bookkeeping
            print colored("Verified MD5 for '@{[prettyPath($fullPath)]}'", 'green'), "\n";
        } elsif ($oldMd5Info->{full_md5} eq $newMd5Info->{full_md5}) {
            # Full MD5 match and content mismatch. This should only be
            # expected when we change how to calculate content MD5s.
            # If that's the case (i.e. the expected version is not up to
            # date), then we should just update the MD5s. If it's not the
            # case, then it's unexpected and some kind of programer error.
            if (isMd5VersionUpToDate($fullPath, $oldMd5Info->{version})) {
                die <<"EOM";
Unexpected state: full MD5 match and content MD5 mismatch for
$fullPath
             version  full_md5                          md5
  Expected:  $oldMd5Info->{version}        $oldMd5Info->{full_md5}  $oldMd5Info->{md5}
    Actual:  $newMd5Info->{version}        $newMd5Info->{full_md5}  $newMd5Info->{md5}
EOM
            } else {
                trace(VERBOSITY_2, "Content MD5 calculation has changed, updating version ",
                      "$oldMd5Info->{version} to $newMd5Info->{version} for '$fullPath'");
            }
        } else {
            # Mismatch and we can update MD5, needs resolving...
            warn colored("MISMATCH OF MD5 for '@{[prettyPath($fullPath)]}'", 'red'), 
                 " [$oldMd5Info->{md5} vs $newMd5Info->{md5}]\n";

            # Do user action prompt
            while (1) {
                print "Ignore, Overwrite, Quit (i/o/q)? ";
                chomp(my $in = lc <STDIN>);

                if ($in eq 'i') {
                    # Ignore the error and return
                    return;
                } elsif ($in eq 'o') {
                    # Exit loop to fall through to save newMd5Info
                    last;
                } elsif ($in eq 'q') {
                    # User requested to terminate
                    exit 0;
                } else {
                    warn "Unrecognized command: '$in'";
                }
            }
        }
    }

    setMd5InfoAndWriteMd5File($fullPath, $newMd5Info, $md5Path, $md5Key, $md5File, $md5Set);
    return $newMd5Info;
}

#-------------------------------------------------------------------------------
# Print all the metadata values which differ in a set of paths
sub metadataDiff {
    my ($excludeSidecars, @paths) = @_;
    # Get metadata for all files
    my @items = map { (-e) ? readMetadata($_, $excludeSidecars) : {} } @paths;
    my @tagsToSkip = qw(CurrentIPTCDigest DocumentID DustRemovalData 
        FileInodeChangeDate FileName HistoryInstanceID IPTCDigest InstanceID
        OriginalDocumentID PreviewImage RawFileName ThumbnailImage);
    # Collect all the keys which whose values aren't all equal
    my %keysHash = ();
    for (my $i = 0; $i < @items; $i++) {
        while (my ($key, $value) = each %{$items[$i]}) {
            unless (any { $_ eq $key } @tagsToSkip) {
                for (my $j = 0; $j < @items; $j++) {
                    if ($i != $j and
                        (!exists $items[$j]->{$key} or
                         $items[$j]->{$key} ne $value)) {
                        $keysHash{$key} = 1;
                        last;
                    }
                }
            }
        }
    }
    # Pretty print all the keys and associated values which differ
    my @keys = sort keys %keysHash;
    my $indentLen = 3 + max map { length } @keys; 
    for my $key (@keys) {
        for (my $i = 0; $i < @items; $i++) {
            my $message = $items[$i]->{$key} || colored('undef', 'faint');
            if ($i == 0) {
                print colored("$key", 'bold'), '.' x ($indentLen - length $key);
            } else {
                print ' ' x $indentLen;
            }
            print coloredByIndex($message, $i), "\n";
        }
    }
}

#-------------------------------------------------------------------------------
# EXPERIMENTAL
sub appendMetadata {
    my ($target, @sources) = @_;

    my @properties = qw(XPKeywords Rating Subject HierarchicalSubject LastKeywordXMP Keywords);

    # Extract current metadata in target
    my $etTarget = extractInfo($target);
    my $infoTarget = $etTarget->GetInfo(@properties);

    trace(VERBOSITY_DEBUG, "$target: ", Data::Dumper::Dumper($infoTarget));

    my $rating = $infoTarget->{Rating};
    my $oldRating = $rating;

    my %keywordTypes = ();
    for (qw(XPKeywords Subject HierarchicalSubject LastKeywordXMP Keywords)) {
        my $old = $infoTarget->{$_};
        $keywordTypes{$_} = {
            OLD => $old, 
            NEW => {map { $_ => 1 } split /\s*,\s*/, ($old || '')}
        };
    }

    for my $source (@sources) {
        # Extract metadata in source to merge in
        my $etSource = extractInfo($source);
        my $infoSource = $etSource->GetInfo(@properties);

        trace(VERBOSITY_DEBUG, "$source: ", Data::Dumper::Dumper($infoSource));

        # Add rating if we don't already have one
        unless (defined $rating) {
            $rating = $infoSource->{Rating};
        }

        # For each field, loop over each component of the source's value
        # and add it to the set of new values
        while (my ($name, $value) = each %keywordTypes) {
            for (split /\s*,\s*/, $infoSource->{$name}) {
                $value->{NEW}->{$_} = 1;
            }
        }
    }

    my $dirty = 0;

    # Update rating if it's changed
    if (defined $rating and (!defined $oldRating or $rating ne $oldRating)) {
        print "Rating: ", 
            defined $oldRating ? $oldRating : "(null)", 
            " -> $rating\n";
        $etTarget->SetNewValue('Rating', $rating)
            or die "Couldn't set Rating";
        $dirty = 1;
    }

    while (my ($name, $value) = each %keywordTypes) {
        my $old = $value->{OLD};
        my $new = join ', ', sort keys %{$value->{NEW}};
        if (($old || '') ne $new) {
            print "$name: ",
                defined $old ? "\"$old\"" : "(null)",
                " -> \"$new\"\n";
            $etTarget->SetNewValue($name, $new)
                or die "Couldn't set $name";
            $dirty = 1;
        }
    }

    # Write file if metadata is dirty
    if ($dirty) {
        # Compute backup path
        my $backup = "${target}_bak";
        for (my $i = 2; -s $backup; $i++) {
            $backup =~ s/_bak\d*$/_bak$i/;
        }

        # Make backup
        File::Copy::copy($target, $backup)
            or die "Couldn't copy $target to $backup: $!";

        # Update metadata in target file
        my $write = $etTarget->WriteInfo($target);
        if ($write == 1) {
            # updated
            print "Updated $target\nOriginal backed up to $backup\n";
        } elsif ($write == 2) {
            # noop
            print "$target was already up to date\n";
        } else {
            # failure
            die "Couldn't WriteInfo for $target";
        }
    }
}

#-------------------------------------------------------------------------------
# If specified media [path] is in the right directory, returns the falsy
# empty string. If it is in the wrong directory, a short truthy error
# string for display (colored by [colorIndex]) is returned.
sub getDirectoryError {
    my ($path) = @_;

    my @props = qw(DateTimeOriginal MediaCreateDate);

    # TODO: should this use readMetadata to pick up date taken from XMP?
    # or can we store this with Md5Info?
    trace(VERBOSITY_2, "Image::ExifTool::ImageInfo('$path', ...);");
    my $info = Image::ExifTool::ImageInfo($path, \@props, {DateFormat => '%F'});
    printCrud(CRUD_READ, "Read metadata for '@{[prettyPath($path)]}' to get media date");

    my $date;
    for (@props) {
        if (exists $info->{$_}) {
            $date = $info->{$_};
            last;
        }
    }

    return 'Can\'t find media date' if !defined $date;

    my $yyyy = substr $date, 0, 4;
    my $date2 = join '', $date =~ /^..(..)-(..)-(..)$/;
    my @dirs = File::Spec->splitdir((File::Spec->splitpath($path))[1]);
    if ($dirs[-3] eq $yyyy and
        $dirs[-2] =~ /^(?:$date|$date2)/) {
        return ''; # No error
    } else {
        return "Wrong dir for item with data $date";
    }
}

# When dealing with MD5 related data, we have these naming conventions:
# MediaPath..The path to the media file for which MD5 data is calculated (not
#            just path as to differentiate from Md5Path).
# Md5Path....The path to the md5.txt file which contains Md5Info data
#            for media items in that folder which is serialized to/from
#            a Md5Set.
# Md5File....A file handle to a Md5Path, or more generally in comments
#            just to refer to the actual filesystem object for a Md5Path
#            or its contents.
# Md5Set.....A hash of Md5Key => Md5Info which can be stored in Md5File
# Md5Key.....The key used to lookup a Md5Info in a Md5Set.
# Md5Info....A collection of metadata pertaining to a MediaPath (and possibly
#            its sidecar files)
# Md5Digest..The result when computing the MD5 for chunk(s) of data of
#            the form $md5DigestPattern.

# MODEL (MD5) ------------------------------------------------------------------
# For each item in each md5.txt file in [globPatterns], invoke [callback]
# passing it full path and MD5 hash as arguments like
#      callback($fullPath, $md5)
sub findMd5s {
    my ($callback, @globPatterns) = @_;
    trace(VERBOSITY_DEBUG, 'findMd5s(...); with @globPatterns of', 
          (@globPatterns ? map { "\n\t'$_'" } @globPatterns : ' (current dir)'));
    traverseFiles(
        sub { # isWanted
            my ($fullPath) = @_;
            my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
            if (-d $fullPath) {
                return (lc $filename ne '.trash'); # process non-trash dirs
            } elsif (-f $fullPath) {
                return (lc $filename eq 'md5.txt'); # only process md5.txt files
            }
            die "Programmer Error: unknown object type for '$fullPath'";
        },
        sub { # callback
            my ($fullPath) = @_;
            if (-f $fullPath) {
                my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
                my (undef, $md5Set) = readMd5File('<:crlf', $fullPath);
                for (sort keys %$md5Set) {
                    my $otherFullPath = changeFilename($fullPath, $_);
                    $callback->($otherFullPath, $md5Set->{$_}->{md5});
                }
            }
        },
        @globPatterns);
}

# MODEL (MD5) ------------------------------------------------------------------
# Gets the Md5Path, Md5Key for a MediaPath.
sub getMd5PathAndMd5Key {
    my ($mediaPath) = @_;
    my ($md5Path, $md5Key) = changeFilename($mediaPath, 'md5.txt');
    return ($md5Path, lc $md5Key);
}

# MODEL (MD5) ------------------------------------------------------------------
# Stores Md5Info for a MediaPath. If the the provided data is undef, removes
# existing information via removeMd5ForMediaPath. Returns the previous Md5Info
# value if it existed (or undef if not).
sub writeMd5Info {
    my ($mediaPath, $newMd5Info) = @_;
    trace(VERBOSITY_DEBUG, "writeMd5Info('$mediaPath', {...});");
    return removeMd5ForMediaPath($mediaPath) unless $newMd5Info;
    my ($md5Path, $md5Key) = getMd5PathAndMd5Key($mediaPath);
    my ($md5File, $md5Set) = readOrCreateNewMd5File($md5Path);
    return setMd5InfoAndWriteMd5File($mediaPath, $newMd5Info, $md5Path, $md5Key, $md5File, $md5Set);
}

# MODEL (MD5) ------------------------------------------------------------------
# Removes Md5Info for a MediaPath from storage. Returns the previous Md5Info
# value if it existed (or undef if not).
sub deleteMd5Info {
    my ($mediaPath) = @_;
    trace(VERBOSITY_DEBUG, "removeMd5ForMediaPath('$mediaPath');");
    my ($md5Path, $md5Key) = getMd5PathAndMd5Key($mediaPath);
    unless (-e $md5Path) {
        trace(VERBOSITY_DEBUG, "Non-existant '$md5Path' means we can't remove MD5 for '$md5Key'");
        return undef;
    }
    my ($md5File, $md5Set) = readMd5File('+<:crlf', $md5Path);
    unless (exists $md5Set->{$md5Key}) {
        trace(VERBOSITY_DEBUG, "Leaving '$md5Path' alone since it doesn't contain MD5 for '$md5Key'");
        return undef;
    }
    my $oldMd5Info = $md5Set->{$md5Key};
    delete $md5Set->{$md5Key};
    # TODO: Should this if/else code move to writeMd5File/setMd5InfoAndWriteMd5File such
    #       that any time someone tries to write an empty hashref, it deletes the file?
    if (%$md5Set) {
        trace(VERBOSITY_2, "Writing '$md5Path' after removing MD5 for '$md5Key'");
        writeMd5File($md5Path, $md5File, $md5Set);
        printCrud(CRUD_DELETE, "Removed MD5 for '@{[prettyPath($mediaPath)]}'\n");
    } else {
        # Empty files create trouble down the line (especially with move-merges)
        trace(VERBOSITY_2, "Deleting '$md5Path' after removing MD5 for '$md5Key' (the last one)");
        close($md5File);
        unlink($md5Path) or die "Couldn't delete '$md5Path': $!";
        printCrud(CRUD_DELETE, "Removed MD5 for '@{[prettyPath($1)]}', ",
                  " and deleted empty '@{[prettyPath($md5Path)]}'\n");
    }
    return $oldMd5Info;
}

# MODEL (MD5) ------------------------------------------------------------------
# Takes a list of Md5Paths, and stores the concatinated Md5Info to the first
# specified file. Dies without writing anything on key collisions.
sub appendMd5Files {
    my ($targetMd5Path, @sourceMd5Paths) = @_;
    my ($targetMd5File, $targetMd5Set) = readOrCreateNewMd5File($targetMd5Path);
    my $oldTargetMd5SetCount = scalar keys %$targetMd5Set;
    my $dirty = 0;
    for my $sourceMd5Path (@sourceMd5Paths) {
        my (undef, $sourceMd5Set) = readMd5File('<:crlf', $sourceMd5Path);
        while (my ($key, $sourceMd5Info) = each %$sourceMd5Set) {
            if (exists $targetMd5Set->{$key}) {
                my $targetMd5Info = $targetMd5Set->{$key};
                Data::Compare::Compare($sourceMd5Info, $targetMd5Info) or die
                    "Can't append MD5 info to '$targetMd5Path'" .
                    " due to key collision for $key";
            } else {
                $targetMd5Set->{$key} = $sourceMd5Info;
                $dirty = 1;
            }
        }
    }
    if ($dirty) {
        die "Not yet implemented";
        trace(VERBOSITY_2, "Writing '$targetMd5Path' after appending data from ",
              scalar @sourceMd5Paths, " files");
        writeMd5File($targetMd5Path, $targetMd5File, $targetMd5Set);
        my $itemsAdded = (scalar keys %$targetMd5Set) - $oldTargetMd5SetCount;
        printCrud(CRUD_CREATE, "Added $itemsAdded entries to '${\prettyPath($targetMd5Path)}' from\n",
                  map { "  '${\prettyPath($_)}'\n" } @sourceMd5Paths);
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# This is a utility for updating Md5Info. It opens the Md5Path R/W and parses
# it. Returns the Md5File and Md5Set.
sub readOrCreateNewMd5File {
    my ($md5Path) = @_;
    trace(VERBOSITY_DEBUG, "readOrCreateNewMd5File('$md5Path');");
    if (-e $md5Path) {
        return readMd5File('+<:crlf', $md5Path);
    } else {
        # TODO: should mode here have :crlf on the end?
        return (openOrDie('+>', $md5Path), {});
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Low level helper routine to open a Md5Path and deserialize into a OM (Md5Set)
# which can be read, modified, and/or passed to writeMd5File or methods built 
# on that. Returns the Md5File and Md5Set.
sub readMd5File {
    my ($openMode, $md5Path) = @_;
    trace(VERBOSITY_2, "readMd5File('$openMode', '$md5Path');");
    # TODO: Should we validate filename is md5.txt or do we care?
    my $md5File = openOrDie($openMode, $md5Path);
    # If the first char is a open curly brace, treat as JSON,
    # otherwise do the older simple "name: md5\n" format parsing
    my $useJson = 0;
    while (<$md5File>) {
        if (/^\s*([^\s])/) {
            $useJson = 1 if $1 eq '{';
            last;
        }
    }
    seek($md5File, 0, 0) or die "Couldn't reset seek on file: $!";
    my $md5Set;
    if ($useJson) {
        $md5Set = JSON::decode_json(join '', <$md5File>);
        # TODO: Consider validating parsed content - do a lc on
        #       filename/md5s/whatever, and verify vs $md5DigestPattern???
        # If there's no version data, then it is version 1. We didn't
        # start storing version information until version 2.
        while (my ($key, $values) = each %$md5Set) {
            $values->{version} = 1 unless exists $values->{version};
        }
    } else {
        # Parse as simple "name: md5" text
        for (<$md5File>) {
            /^([^:]+):\s*($md5DigestPattern)$/ or die "Unexpected line in '$md5Path': $_";
            # We use version 0 here for the very old way before we went to
            # JSON when we added more info than just the full file MD5
            my $fullMd5 = lc $2;
            $md5Set->{lc $1} = { version => 0, md5 => $fullMd5, full_md5 => $fullMd5 };
        }
    }
    updateMd5FileCache($md5Path, $md5Set);
    printCrud(CRUD_READ, "Read MD5 info from '@{[prettyPath($md5Path)]}'\n");
    return ($md5File, $md5Set);
}

# MODEL (MD5) ------------------------------------------------------------------
# Lower level helper routine that updates a MD5 info, and writes it to the file
# if necessary. The $md5File and $md5Set params should be the existing data
# (like is returned from readOrCreateNewMd5File or readMd5File). The md5Key and
# newMd5Info represent the new data. Returns the previous md5Info value. 
sub setMd5InfoAndWriteMd5File {
    my ($mediaPath, $newMd5Info, $md5Path, $md5Key, $md5File, $md5Set) = @_;
    my $oldMd5Info = $md5Set->{$md5Key};
    unless ($oldMd5Info and Data::Compare::Compare($oldMd5Info, $newMd5Info)) {
        $md5Set->{$md5Key} = $newMd5Info;
        trace(VERBOSITY_2, "Writing '$md5Path' after setting MD5 for '$md5Key'");
        writeMd5File($md5Path, $md5File, $md5Set);
        if (defined $oldMd5Info) {
            printCrud(CRUD_UPDATE, "Updated MD5 for '@{[prettyPath($mediaPath)]}'\n");
        } else {
            printCrud(CRUD_CREATE, "Added MD5 for '@{[prettyPath($mediaPath)]}'\n");
        }
    }
    return $oldMd5Info;
}

# MODEL (MD5) ------------------------------------------------------------------
# Lowest level helper routine to serialize OM into a md5.txt file handle.
# Caller is expected to printCrud with more context if this method returns
# successfully.
sub writeMd5File {
    my ($md5Path, $md5File, $md5Set) = @_;
    # TODO: write this out as UTF8 using :encoding(UTF-8):crlf (or :utf8:crlf?)
    #       and writing out the "\x{FEFF}" BOM. Not sure how to do that in
    #       a fully cross compatable way (older file versions as well as
    #       Windows/Mac compat)
    trace(VERBOSITY_DEBUG, 'writeMd5File(<..>, { hash of @{[ scalar keys %$md5Set ]} items });');
    seek($md5File, 0, 0) or die "Couldn't reset seek on file: $!";
    truncate($md5File, 0) or die "Couldn't truncate file: $!";
    if (%$md5Set) {
        print $md5File JSON->new->allow_nonref->pretty->encode($md5Set);
    } else {
        warn "Writing empty data to md5.txt";
    }
    updateMd5FileCache($md5Path, $md5Set);
}

# MODEL (MD5) ------------------------------------------------------------------
sub updateMd5FileCache {
    my ($md5Path, $md5Set) = @_;
    $cachedMd5Path = $md5Path;
    $cachedMd5Set = Storable::dclone($md5Set);
}

# MODEL (MD5) ------------------------------------------------------------------
# Makes the base of a md5Info hash that can be used with
# canMakeMd5MetadataShortcut or added to the results of getMd5 to produce
# a full md5Info.
sub makeMd5InfoBase {
    my ($mediaPath) = @_;
    my $stats = File::stat::stat($mediaPath) or die "Couldn't stat '$mediaPath': $!";
    return { size => $stats->size, mtime => $stats->mtime };
}

# MODEL (MD5) ------------------------------------------------------------------
# Check if we can shortcut based on metadata without evaluating MD5s
# TODO: should this be a nested function?
sub canMakeMd5MetadataShortcut {
    my ($addOnly, $fullPath, $oldMd5Info, $newMd5Info) = @_;
    trace(VERBOSITY_DEBUG, 'canMakeMd5MetadataShortcut(...);');
    if (defined $oldMd5Info) {
        if ($addOnly) {
            trace(VERBOSITY_DEBUG, "Skipping MD5 recalculation for '$fullPath' (add-only mode)");
            return 1;
        }
        if (defined $oldMd5Info->{size} and 
            defined $oldMd5Info->{mtime} and 
            isMd5VersionUpToDate($fullPath, $oldMd5Info->{version}) and
            $newMd5Info->{size} == $oldMd5Info->{size} and
            $newMd5Info->{mtime} == $oldMd5Info->{mtime}) {
            trace(VERBOSITY_DEBUG, "Skipping MD5 recalculation for '$fullPath' (same size/date-modified)");
            return 1;
        }
    }
    return 0;
}

# MODEL (MD5) ------------------------------------------------------------------
# The data returned by getMd5 is versioned, but not all version changes are
# meaningful for every type of file. This method determines if the provided
# version is equivalent to the current version for the specified file type.
sub isMd5VersionUpToDate {
    my ($mediaPath, $version) = @_;
    trace(VERBOSITY_DEBUG, "isMd5VersionUpToDate('$mediaPath', $version);");
    my $type = getMimeType($mediaPath);
    if ($type eq 'image/jpeg') {
        return ($version >= 1) ? 1 : 0; # unchanged since V1
    } elsif ($type eq 'video/mp4v-es') {
        return ($version >= 2) ? 1 : 0; # unchanged since V1
    } elsif ($type eq 'video/quicktime') {
        return ($version >= 4) ? 1 : 0; # unchanged since V4
    } elsif ($type eq 'image/png') {
        return ($version >= 3) ? 1 : 0; # unchanged since V3
    }
    # This type just does whole file MD5 (the original implementation)
    return 1;
}

# MODEL (MD5) ------------------------------------------------------------------
# Calculates and returns the MD5 digest of a file.
# properties:
#   md5: primary MD5 comparison (excludes volitile data from calculation)
#   full_md5: full MD5 calculation for exact match
sub getMd5 {
    my ($mediaPath) = @_;
    trace(VERBOSITY_2, "getMd5('$mediaPath');");
    #!!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE
    #!!!   $getMd5Version should be incremented whenever the output of this
    #!!!   method changes in such a way that old values need to be recalculated,
    #!!!   and isMd5VersionUpToDate should be updated accordingly.
    #!!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE
    my $fh = openOrDie('<:raw', $mediaPath);
    my $fullMd5Hash = getMd5Digest($mediaPath, $fh);
    # If we fail to generate a partial match, just warn and use the full file
    # MD5 rather than letting the exception loose and just skipping the file.
    my $partialMd5Hash = undef;
    eval {
        my $type = getMimeType($mediaPath);
        if ($type eq 'image/jpeg') {
            $partialMd5Hash = getJpgContentDataMd5($mediaPath, $fh);
        } elsif ($type eq 'video/mp4v-es') {
            $partialMd5Hash = getMp4ContentDataMd5($mediaPath, $fh);
        } elsif ($type eq 'video/quicktime') {
            $partialMd5Hash = getMovContentDataMd5($mediaPath, $fh);
        } elsif ($type eq 'image/tiff') {
            # TODO
        } elsif ($type eq 'image/png') {
            $partialMd5Hash = getPngContentDataMd5($mediaPath, $fh);
        }
    };
    if (my $error = $@) {
        # Can't get the partial MD5, so we'll just use the full hash
        warn "Unavailable content MD5 for '@{[prettyPath($mediaPath)]}' with error:\n\t$error\n";
    }
    printCrud(CRUD_READ, "Computed MD5 hash of '@{[prettyPath($mediaPath)]}'",
              ($partialMd5Hash ? ", including content only hash" : ''), "\n");
    return {
        version => $getMd5Version,
        md5 => $partialMd5Hash || $fullMd5Hash,
        full_md5 => $fullMd5Hash,
    };
}

# MODEL (MD5) ------------------------------------------------------------------
# Gets the mime type from a path for all types supported by $mediaType
# TODO: Should this be categorized as MP5 sub? Seems more generic like Metadata.
sub getMimeType {
    my ($mediaPath) = @_;
    # If the file is a backup (has some "bak"/"original" suffix), 
    # we want to consider the real extension
    $mediaPath =~ s/$backupSuffix$//;
    my ($basename, $ext) = splitExt($mediaPath);
    my $key = uc $ext;
    exists $fileTypes{$key} or die "Unexpected file type $key for '$mediaPath'";
    return $fileTypes{$key}->{MIMETYPE};
}

# MODEL (MD5) ------------------------------------------------------------------
# If JPEG, skip metadata which may change and only hash pixel data
# and hash from Start of Scan [SOS] to end of file
sub getJpgContentDataMd5 {
    my ($mediaPath, $fh) = @_;
    # Read Start of Image [SOI]
    seek($fh, 0, 0) or die "Failed to reset seek for '$mediaPath': $!";
    read($fh, my $fileData, 2) or die "Failed to read SOI from '$mediaPath': $!";
    my ($soi) = unpack('n', $fileData);
    $soi == 0xffd8 or die "JPG file didn't start with SOI marker: '$mediaPath'";
    # Read blobs until SOS
    my $tags = '';
    while (1) {
        read($fh, my $fileData, 4) or die
            "Failed to read from '$mediaPath' at @{[tell $fh]} after $tags: $!";
        my ($tag, $size) = unpack('nn', $fileData);
        # Take all the file after the SOS
        return getMd5Digest($mediaPath, $fh) if $tag == 0xffda;
        # Else, skip past this tag
        $tags .= sprintf("%04x,%04x;", $tag, $size);
        my $address = tell($fh) + $size - 2;
        seek($fh, $address, 0) or die "Failed to seek '$mediaPath' to $address: $!";
    }
}

# MODEL (MD5) ------------------------------------------------------------------
sub getMovContentDataMd5 {
    # For now, our approach is identical for MOV and MP4
    return getMp4ContentDataMd5(@_);
}

# MODEL (MD5) ------------------------------------------------------------------
sub getMp4ContentDataMd5 {
    my ($mediaPath, $fh) = @_;
    seek($fh, 0, 0) or die "Failed to reset seek for '$mediaPath': $!";
    # TODO: should we verify the first atom is ftyp? Do we care?
    # TODO: currently we're only doing the first 'mdat' atom's data. I'm
    # not sure if that's correct... can there be multiple mdat? Is pixel
    # data located elsewhere? Should we just opt out certain atoms rather
    # than opting in mdat?
    while (!eof($fh)) {
        my $seekStartOfAtom = tell($fh);
        # Read atom header
        read($fh, my $fileData, 8) or die
            "Failed to read MP4 atom from '$mediaPath' at $seekStartOfAtom: $!";
        my ($atomSize, $atomType) = unpack('NA4', $fileData);
        if ($atomSize == 0) {
            # 0 means the atom goes to the end of file
            # I think we want to take all the the mdat atom data?
            return getMd5Digest($mediaPath, $fh) if $atomType eq 'mdat'; 
            last;
        }
        my $dataSize = $atomSize - 8;
        if ($atomSize == 1) {
            # 1 means it's 64 bit size
            read($fh, $fileData, 8) or die
                "Failed to read MP4 atom from '$mediaPath': $!";
            $atomSize = unpack('Q>', $fileData);
            $dataSize = $atomSize - 16;
        }
        $dataSize >= 0 or die "Bad size for MP4 atom '$atomType': $atomSize";
        # I think we want to take all the the mdat atom data?
        return getMd5Digest($mediaPath, $fh, $dataSize) if $atomType eq 'mdat'; 
        # Seek to start of next atom
        my $address = $seekStartOfAtom + $atomSize;
        seek($fh, $address, 0) or die "Failed to seek '$mediaPath' to $address: $!";
    }
    return undef;
}

# MODEL (MD5) ------------------------------------------------------------------
sub getPngContentDataMd5 {
    my ($mediaPath, $fh) = @_;
    seek($fh, 0, 0) or die "Failed to reset seek for '$mediaPath': $!";
    read($fh, my $fileData, 8) or die "Failed to read PNG header from '$mediaPath': $!";
    my @actualHeader = unpack('C8', $fileData);
    my @pngHeader = ( 137, 80, 78, 71, 13, 10, 26, 10 );
    Data::Compare::Compare(\@actualHeader, \@pngHeader) or die
        "PNG file didn't start with correct header: '$mediaPath'";
    my $md5 = new Digest::MD5;
    while (!eof($fh)) {
        # Read chunk header
        read($fh, $fileData, 8) or die
            "Failed to read PNG chunk from '$mediaPath' at @{[tell $fh]}: $!";
        my ($size, $type) = unpack('NA4', $fileData);
        my $seekStartOfData = tell($fh);
        # TODO: Check that 'IHDR' chunk comes first and 'IEND' last?
        if ($type eq 'tEXt' or $type eq 'zTXt' or $type eq 'iTXt') {
            # This is a text field, so not pixel data
            # TODO: should we only skip the type 'iTXt' and subtype
            # 'XML:com.adobe.xmp'? 
        } else {
            # The type and data should be enough - don't need size or CRC
            # BUGBUG - this seems slightly wrong in that if things move around
            # and mean the same thing the MD5s will change even though the
            # contents haven't meaningfully changed, and can result in us
            # falsely reporting that there have been non-metadata changes
            # (i.e. pixel data) changes to the file.
            $md5->add($type);
            addToMd5Digest($md5, $mediaPath, $fh, $size);
        }
        # Seek to start of next chunk (past header, data, and CRC)
        my $address = $seekStartOfData + $size + 4;
        seek($fh, $address, 0) or die "Failed to seek '$mediaPath' to $address: $!";
    }
    return resolveMd5Digest($md5);
}

# MODEL (MD5) ------------------------------------------------------------------
# Get/verify/canonicalize hash from a FILEHANDLE object
sub getMd5Digest {
    my ($mediaPath, $fh, $size) = @_;
    my $md5 = new Digest::MD5;
    addToMd5Digest($md5, $mediaPath, $fh, $size);
    return resolveMd5Digest($md5);
}

# MODEL (MD5) ------------------------------------------------------------------
sub addToMd5Digest {
    my ($md5, $mediaPath, $fh, $size) = @_;
    unless ($size) {
        $md5->addfile($fh);
    } else {
        # There's no addfile with a size limit, so we roll our own
        # by reading in chunks and adding one at a time (since $size
        # might be huge and we don't want to read it all into memory)
        my $chunkSize = 1024;
        for (my $remaining = $size; $remaining > 0; $remaining -= $chunkSize) {
            my $readSize = $chunkSize < $remaining ? $chunkSize : $remaining;
            read($fh, my $fileData, $readSize)
                or die "Failed to read from '$mediaPath' at @{[tell $fh]}: $!";
            $md5->add($fileData);
        }
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Extracts, verifies, and canonicalizes resulting MD5 digest
# from a Digest::MD5.
sub resolveMd5Digest {
    my ($md5) = @_;
    my $hexdigest = lc $md5->hexdigest;
    $hexdigest =~ /$md5DigestPattern/ or die "Unexpected MD5: $hexdigest";
    return $hexdigest;
}

# MODEL (Metadata) -------------------------------------------------------------
# Provided a path, returns an array of sidecar files based on extension.
sub getSidecarPaths {
    my ($fullPath) = @_;
    if ($fullPath =~ /$backupSuffix$/) {
        # Associating sidecars with backups only creates problems
        # like multiple versions of a file sharing the same sidecar(s)
        return ();
    } else {
        # Using extension as a key, look up associated sidecar types (if any)
        my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
        my ($basename, $ext) = splitExt($filename);
        my $key = uc $ext;
        if (exists $fileTypes{$key}) {
            # Return the other types which exist
            # TODO: use path functions (do we need to add a catExt as
            # reciprocal of splitExt like we have splitpath and catpath)
            my @sidecars = @{$fileTypes{$key}->{SIDECARS}};
            @sidecars = map { combinePath($vol, $dir, "$basename.$_") } @sidecars;
            return grep { -e } @sidecars;
        } else {
            # Unknown file type (based on extension)
            die "Unknown type '$key' to determine sidecars for '$fullPath'"; 
        }
    }
}

# MODEL (Metadata) -------------------------------------------------------------
# Read metadata as an ExifTool hash for the specified path (and any
# XMP sidecar when appropriate)
sub readMetadata {
    my ($path, $excludeSidecars) = @_;
    my $et = extractInfo($path);
    my $info = $et->GetInfo();
    unless ($excludeSidecars) {
        # If this file can't hold XMP (i.e. not JPEG or TIFF), look for
        # XMP sidecar
        # TODO: Should we exclude DNG here too?
        # TODO: How do we prevent things like FileSize from being overwritten
        #       by the XMP sidecar? read it first? exclude fields somehow (eg
        #       by "file" group)?
        #       (FileSize, FileModifyDate, FileAccessDate, FilePermissions)
        # TODO: move this logic to the $fileTypes structure (add a 
        # useXmpSidecarForMetadata property or something)
        # TODO: for all these complaints, about hard coding let's just check if XMP is a sidecar
        if ($path !~ /\.(jpeg|jpg|tif|tiff|xmp)$/i) {
            # TODO: use path functions
            (my $xmpPath = $path) =~ s/[^.]*$/xmp/;
            if (-s $xmpPath) {
                $et = extractInfo($xmpPath, $et);
                $info = { %{$et->GetInfo()}, %$info };
            }
        }
    }
    #my $keys = $et->GetTagList($info);
    return $info;
}

# MODEL (Metadata) -------------------------------------------------------------
# Wrapper for Image::ExifTool::ExtractInfo with error handling
sub extractInfo {
    my ($path, $et) = @_;
    $et = new Image::ExifTool unless $et;
    trace(VERBOSITY_2, "Image::ExifTool::ExtractInfo('$path');");
    $et->ExtractInfo($path) or die
        "Couldn't ExtractInfo for '$path': " . $et->GetValue('Error');
    printCrud(CRUD_READ, "Read metadata for '@{[prettyPath($path)]}'");
    return $et;
}

# MODEL (Path Operations) ------------------------------------------------------
sub comparePathWithExtOrder {
    my ($fullPathA, $fullPathB) = @_;
    my ($volA, $dirA, $filenameA) = File::Spec->splitpath($fullPathA);
    my ($volB, $dirB, $filenameB) = File::Spec->splitpath($fullPathB);
    return compareDir($dirA, $dirB) ||
           compareFilenameWithExtOrder($filenameA, $filenameB);
}

# MODEL (Path Operations) ------------------------------------------------------
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

# MODEL (Path Operations) ------------------------------------------------------
sub compareFilenameWithExtOrder {
    my ($filenameA, $filenameB) = @_;
    my ($basenameA, $extA) = splitExt($filenameA);
    my ($basenameB, $extB) = splitExt($filenameB);
    # Compare by basename first
    my $c = lc $basenameA cmp lc $basenameB;
    return $c if $c;
    # Next by extorder
    if (defined $fileTypes{uc $extA}) {
        if (defined $fileTypes{uc $extB}) {
            # Both known types, so ncreasing by extorder if they're different
            my $c = $fileTypes{uc $extA}->{EXTORDER} <=> $fileTypes{uc $extB}->{EXTORDER};
            return $c if $c;
        } else {
            return -1; # A is known, B is not, so A comes first
        }
    } else {
        if (defined $fileTypes{uc $extB}) {
            # Neither types are known, do nothing here
        } else {
            return 1; # B is known, A is not, so B comes first
        }
    }
    # And then just the extension as a string
    return lc $extA cmp lc $extB;
}

# MODEL (Path Operations) ------------------------------------------------------
sub parentPath {
    my ($path) = @_;
    return changeFilename($path, undef);
}

# MODEL (Path Operations) ------------------------------------------------------
sub changeFilename {
    my ($path, $newFilename) = @_;
    my ($vol, $dir, $oldFilename) = File::Spec->splitpath($path);
    my $newPath = combinePath($vol, $dir, $newFilename);
    return wantarray ? ($newPath, $oldFilename) : $newPath;
}

# MODEL (Path Operations) ------------------------------------------------------
# Experience shows that canonpath should follow catpath. This wrapper
# combines the two.
sub combinePath {
    return File::Spec->canonpath(File::Spec->catpath(@_));
}

# MODEL (Path Operations) ------------------------------------------------------
# Splits the filename into basename and extension. (Both without a dot.) It
# is usually used like the following example
#       my ($vol, $dir, $filename) = File::Spec->splitpath($path);
#       my ($basename, $ext) = splitExt($filename);
sub splitExt {
    my ($path) = @_;
    my ($filename, $ext) = $path =~ /^(.*)\.([^.]*)/;
    # TODO: handle case without extension - if no re match then just return ($path, '')
    return ($filename, $ext);
}

# MODEL (File Operations) ------------------------------------------------------
# Implementation for traverseFiles' isWanted that causes processing
# of non-trash media files.
sub wantNonTrashMedia {
    my ($fullPath) = @_;
    my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
    if (-d $fullPath) {
        return (lc $filename ne '.trash'); # process non-trash dirs
    } elsif (-f $fullPath) {
        return ($filename =~ /$mediaType/); # process media files
    }
    die "Programmer Error: unknown object type for '$fullPath'";
}

# MODEL (File Operations) ------------------------------------------------------
# This is a wrapper over File::Find::find that offers a few benefits:
#  * Provides some common functionality such as glob handling
#  * Standardizes on bydepth and no_chdir which seems to be the best context
#    for authoring the callbacks
#  * Provide consistent and type safe path object to callback, and eliminate
#    the params via nonhomogeneous globals pattern
#
# Unrolls globs and traverses directories and files recursively for everything
# that yields a truthy call to isWanted, and calls callback for each file or
# directory that is to be processed.
#
# Returning false from isWanted for a file prevents callback from being called.
# Returning false from isWanted for a directory prevents callback from being
# called on that directory and prevents further traversal such that descendants
# won't have calls to isWanted or callback.
#
# Don't do anything in isWanted other than return 0 or 1 to specify whether 
# these dirs or files should be processed. That method is called breadth first,
# such that traversal of a subtree can be short circuited. Then process is
# called depth first such that the process of a dir doesn't occur until all
# the subitems have been processed. 
#
# Example: if you wanted to report all the friendly names of all files that 
# aren't in a .Trash directory, you'd do:
#   traverseFiles(
#       sub { #isWanted
#           my ($fullPath) = @_; 
#           return !(-d $fullPath) 
#               or (lc File::Spec::splitpath($fullPath)[2] ne '.trash');
#       },
#       sub { # callback
#           my ($fullPath) = @_; 
#           print("Processing '@{[prettyPath($fullPath)]}'\n") if -f $fullPath; 
#       });
#
# Note that if glob patterns overlap, then some files might invoke the 
# callbacks more than once. For example, 
#   traverseFiles(sub { ... }, sub {...}, 'Al*.jpg', '*ex.jpg');
# would match Alex.jpg twice, and invoke isWanted/callback twice as well.
sub traverseFiles {
    my ($isWanted, $callback, @globPatterns) = @_;
    # Record base now so that no_chdir doesn't affect rel2abs/abs2rel below
    # (and - bonus - just resolve and canonicalize once)
    my $baseFullPath = File::Spec->rel2abs(File::Spec->curdir());
    $baseFullPath = File::Spec->canonpath($baseFullPath);
    # the isWanted and callback methods take the same params, that share
    # the following computations
    my $makeFullPath = sub {
        my ($partialPath) = @_;
        my $fullPath = File::Spec->rel2abs($partialPath, $baseFullPath);
        $fullPath = File::Spec->canonpath($fullPath);
        -e $fullPath or die
            "Programmer Error: enumerated file doesn't exist: '$fullPath'";
        return $fullPath;
    };
    # Method to be called for each directory found in globPatterns
    my $helper = sub {
        my ($rootDir) = @_;
        my $rootFullPath = $makeFullPath->($rootDir);
        # The final wanted call for $rootDir doesn't have a matching preprocess
        # call, so force one up front for symetry with all other pairs.
        return if $isWanted and !$isWanted->($rootFullPath, $rootFullPath);
        my $preprocess = sub {
            return grep {
                # Skip .. because it doesn't matter what we do, this isn't going
                # to get passed to wanted, and it doesn't really make sense to
                # traverse up in a recursive down enumeration. Also, skip '.'
                # because we would otherwise process each dir twice, and $rootDir
                # once. This makes subdirs once and $rootDir not at all.
                # When MacOS copies files with alternate streams (e.g. from APFS)
                # to a volume that doesn't support it, they put the alternate
                # stream data in a file with the same path, but with a "._"
                # filename prefix. Though it's not a complete fix, for now, we'll
                # pretend these don't exist.
                if (($_ eq '.') or ($_ eq '..') or /^\._/) {
                    0; # skip
                } elsif ($isWanted) {
                    # The values used here to compute the path 
                    # relative to $baseFullPath matches the values of wanted's
                    # implementation, and both work the same whether no_chdir is
                    # set or not. 
                    my $fullPath = $makeFullPath->(
                        File::Spec->catfile($File::Find::dir, $_));
                    local $_ = undef; # prevent use in isWanted
                    $isWanted->($fullPath, $rootFullPath);
                } else {
                    1; # process
                }
            } @_;
        };
        my $wanted = sub {
            # The values used here to compute the path 
            # relative to $baseFullPath matches the values of preprocess' 
            # implementation, and both work the same whether no_chdir is
            # set or not.
            my $fullPath = $makeFullPath->($File::Find::name);
            local $_ = undef; # prevent use in callback
            $callback->($fullPath, $rootFullPath);
        };
        File::Find::find({ bydepth => 1, no_chdir => 1, preprocess => $preprocess,
                         wanted => $wanted }, $rootFullPath);
    };
    if (@globPatterns) {
        for my $globPattern (@globPatterns) {
            # TODO: Is this workaround to handle globbing with spaces for
            # Windows compatible with MacOS (with and without spaces)? Does it
            # work okay with single quotes in file/dir names on each platform?
            $globPattern = "'$globPattern'";
            for (glob $globPattern) {
                if (-d) {
                    $helper->($_);
                } elsif (-f) {
                    my $fullPath = $makeFullPath->($_);
                    local $_ = undef; # prevent use in isWanted/callback
                    if (!$isWanted or $isWanted->($fullPath, $fullPath)) {
                        $callback->($fullPath, $fullPath);
                    }
                } else {
                    die "Don't know how to deal with glob result '$_'";
                }
            }
        }
    } else {
        # If no glob patterns are provided, just search current directory
        $helper->(File::Spec->curdir());
    }
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path and any sidecars (anything with the same path
# except for extension)
sub trashPathAndSidecars {
    my ($fullPath) = @_;
    trace(VERBOSITY_DEBUG, "trashPathAndSidecars('$fullPath');");
    # TODO: check all for existance before performing any operations to
    # make file+sidecar opererations more atomic
    trashPath($_) for ($fullPath, getSidecarPaths($fullPath));
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path by moving it to a .Trash subdir and moving
# its entry from the md5.txt file
sub trashPath {
    my ($fullPath) = @_;
    trace(VERBOSITY_DEBUG, "trashPath('$fullPath');");
    # If it's an empty directory, just delete it. Trying to trash
    # a dir with no items proves problematic for future move-merges
    # and we wind up with a lot of orphaned empty containers.
    unless (tryRemoveEmptyDir($fullPath)) {
        # Not an empty dir, so move to trash by inserting a .Trash
        # before the filename in the path, and moving it there
        my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
        my $trashDir = File::Spec->catdir($dir, '.Trash');
        my $newFullPath = combinePath($vol, $trashDir, $filename);
        movePath($fullPath, $newFullPath);
    }
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified fullPath by moving it to rootFullPath's .Trash
# subdir and moving its entry from the md5.txt file. rootFullPath must
# be an ancestor of fullPath. If it is the direct parent, this method
# behaves like trashPath.
#
# Example 1: (nested with intermediate .Trash)
#   trashPathWithRoot('.../root/A/B/.Trash/C/D/.Trash', '.../root')
#   moves file to: '.../root/.Trash/A/B/C/D'
#
# Example 2: (degenerate trashPath case)
#   trashPathWithRoot('.../root/foo', '.../root')
#   moves file to: '.../root/.Trash/foo'
#
# Example 3: (edge case)
#   trashPathWithRoot('.../root/.Trash/.Trash/.Trash', '.../root')
#   moves file to: '.../root/.Trash'
sub trashPathWithRoot {
    my ($theFullPath, $rootFullPath) = @_;
    trace(VERBOSITY_DEBUG, "trashPathWithRoot('$theFullPath', '$rootFullPath');");
    # Split the directories into pieces assuming root is a dir
    # Note the careful use of splitdir and catdir - splitdir can return
    # empty string entries in the array, notably at beginning and end
    # which can make manipulation of dir arrays tricky.
    my ($theVol, $theDir, $theFilename) = File::Spec->splitpath($theFullPath);
    my ($rootVol, $rootDir, $rootFilename) = File::Spec->splitpath($rootFullPath);
    # Example 1: theDirs = ( ..., root, A, B, .Trash, C, D )
    my @theDirs = File::Spec->splitdir(File::Spec->catdir($theDir, $theFilename));
    # Example N: rootDirs = ( ..., root )
    my @rootDirs = File::Spec->splitdir(File::Spec->catdir($rootDir, $rootFilename));
    # Verify @rootDirs is a prefix match for (i.e. ancestor of) @theDirs
    my $prefixDeath = sub {
        "Programmer error: root '$rootFullPath' is not " .
        "a prefix for path '$theFullPath (@_)" };
    $theVol eq $rootVol or die
        $prefixDeath->('different volumes');
    @rootDirs < @theDirs or die
        $prefixDeath->('root is longer');
    for (my $i = 0; $i < @rootDirs; $i++) {
        $rootDirs[$i] eq $theDirs[$i] or die
            $prefixDeath->("'$rootDirs[$i]' ne '$theDirs[$i]' at $i");
    }
    # Figure out postRoot (theFullPath relative to rootFullPath without 
    # trash), and then append that to rootFullPath's trash dir's path
    # Example 1: postRoot = ( .Trash, A, B, C, D )
    # Example 2: postRoot = ( .Trash, foo )
    # Example 3: postRoot = ( .Trash )
    my @postRoot = ('.Trash', grep { lc ne '.trash' } @theDirs[@rootDirs .. @theDirs-1]);
    # Example 1: postRoot = ( .Trash, A, B, C ); newFilename = D
    # Example 2: postRoot = ( .Trash ); newFilename = foo
    # Example 3: postRoot = (); newFilename = .Trash
    my $newFilename = pop @postRoot;
    # Example 1: newDir = '.../root/.Trash/A/B/C'
    # Example 2: newDir = '.../root/.Trash'
    # Example 3: newDir = '.../root'
    my $newDir = File::Spec->catdir(@rootDirs, @postRoot);
    # Example 1: newFullPath = '.../root/.Trash/A/B/C/D'
    # Example 2: newFullPath = '.../root/.Trahs/foo'
    # Example 3: newFullPath = '.../root/.Trash'
    my $newFullPath = combinePath($theVol, $newDir, $newFilename);
    movePath($theFullPath, $newFullPath);
}

# MODEL (File Operations) ------------------------------------------------------
# Move oldFullPath to newFullPath doing a move-merge where
# necessary and possible
sub movePath {
    my ($oldFullPath, $newFullPath) = @_;
    trace(VERBOSITY_DEBUG, "movePath('$oldFullPath', '$newFullPath');");
    return if $oldFullPath eq $newFullPath;
    my $moveInternal = sub {
        # Ensure parent dir exists
        my $newParentFullPath = parentPath($newFullPath);
        unless (-d $newParentFullPath) {
            trace(VERBOSITY_2, "File::Copy::make_path('$newParentFullPath');");
            File::Path::make_path($newParentFullPath) or die
                "Failed to make directory '$newParentFullPath': $!";
            printCrud(CRUD_CREATE, "Created dir '@{[prettyPath($newParentFullPath)]}'\n");
        }
        # Move the file/dir
        trace(VERBOSITY_2, "File::Copy::move('$oldFullPath', '$newFullPath');");
        File::Copy::move($oldFullPath, $newFullPath) or die
            "Failed to move '$oldFullPath' to '$newFullPath': $!";
        # (caller is expected to printCrud with more context)
    };
    if (-f $oldFullPath) {
        if (-e $newFullPath) {
            # If both are md5.txt files, and newFullPath exists, 
            # then cat old on to new, and delete old.
            my (undef, undef, $oldFilename) = File::Spec->splitpath($oldFullPath);
            my (undef, undef, $newFilename) = File::Spec->splitpath($newFullPath);
            if (lc $oldFilename eq 'md5.txt' and lc $newFilename eq 'md5.txt') {
                appendMd5Files($newFullPath, $oldFullPath);
                unlink($oldFullPath) or die "Couldn't delete '$oldFullPath': $!";
                printCrud(CRUD_DELETE, "Deleted '@{[prettyPath($oldFullPath)]}' after ",
                          "appending MD5 information to '@{[prettyPath($newFullPath)]}'");
            } else {
                die "Can't overwrite '$newFullPath' with '$oldFullPath'";
            }
        } else {
            $moveInternal->();
            my $md5Info = deleteMd5Info($oldFullPath);
            writeMd5Info($newFullPath, $md5Info) if $md5Info;
            printCrud(CRUD_UPDATE, "Moved file '@{[prettyPath($oldFullPath)]}' ",
                      "to '@{[prettyPath($newFullPath)]}'\n");
        }
    } elsif (-d $oldFullPath) {
        if (-e $newFullPath) { 
            # Dest dir path already exists, need to move-merge.
            trace(VERBOSITY_DEBUG, "Move merge '$oldFullPath' to '$newFullPath'");
            -d $newFullPath or die
                "Can't move a directory - file already exists " .
                "at destination ('$oldFullPath' => '$newFullPath')";
            # Use readdir rather than File::Find::find here. This doesn't
            # do a lot of what File::Find::find does - by design. We don't
            # want a lot of that behavior, and don't care about most of
            # the rest (we only want one - not recursive, don't want to
            # change dir, don't support traversing symbolic links, etc.). 
            opendir(my $dh, $oldFullPath) or die "Couldn't open dir '$oldFullPath': $!";
            my @filenames = readdir($dh);
            closedir($dh);
            for (@filenames) {
                next if $_ eq '.' or $_ eq '..';
                my $oldChildFullPath = File::Spec->canonpath(File::Spec->catfile($oldFullPath, $_));
                my $newChildFullPath = File::Spec->canonpath(File::Spec->catfile($newFullPath, $_));
                # If we move the last media from a folder in previous iteration
                # of this loop, it can delete an empty Md5File via deleteMd5Info.
                next if lc $_ eq 'md5.txt' and !(-e $oldChildFullPath);
                movePath($oldChildFullPath, $newChildFullPath); 
            }
            # If we've emptied out $oldFullPath my moving all its contents into
            # the already existing $newFullPath, we can safely delete it. If
            # not, this does nothing - also what we want.
            tryRemoveEmptyDir($oldFullPath);
        } else {
            # Dest dir doesn't exist, so we can just move the whole directory
            $moveInternal->();
            printCrud(CRUD_UPDATE, "Moved dir '@{[prettyPath($oldFullPath)]}'",
                      " to '@{[prettyPath($newFullPath)]}'\n");
        }
    } else {
        die "Programmer Error: unexpected type for object '$oldFullPath'";
    }
}

# MODEL (File Operations) ------------------------------------------------------
# Removes the specified path if it's an empty directory and returns truthy.
# If it's not a directory or a directory with children, the do nothing
# and return falsy.
sub tryRemoveEmptyDir {
    my ($path) = @_;
    trace(VERBOSITY_DEBUG, "tryRemoveEmptyDir('$path');");
    if (-d $path and rmdir $path) {
        printCrud(CRUD_DELETE, "Deleted empty dir '@{[prettyPath($path)]}'\n");
        return 1;
    } else {
        return 0;
    }
}

# MODEL (File Operations) ------------------------------------------------------
sub openOrDie {
    my ($mode, $path) = @_;
    trace(VERBOSITY_DEBUG, "openOrDie('$path');");
    open(my $fh, $mode, $path) or die "Couldn't open '$path' in $mode mode: $!";
    return $fh;
}

# VIEW -------------------------------------------------------------------------
# Colorizes text for diffing purposes
# [message] - Text to color
# [colorIndex] - Index for a color class
sub coloredByIndex {
    my ($message, $colorIndex) = @_;
    return colored($message, colorByIndex($colorIndex));
}

# VIEW -------------------------------------------------------------------------
# Returns a color name (usable with colored()) based on an index
# [colorIndex] - Index for a color class
sub colorByIndex {
    my ($colorIndex) = @_;
    my @colors = ('green', 'red', 'blue', 'yellow', 'magenta', 'cyan');
    return 'bright_' . $colors[$colorIndex % scalar @colors];
}

# VIEW -------------------------------------------------------------------------
# Returns a form of the specified path prettified for display/reading
sub prettyPath {
    my ($path) = @_;
    $path = File::Spec->abs2rel($path);
    return $path;
}

# VIEW -------------------------------------------------------------------------
# This should be called when any crud operations have been performed
sub printCrud {
    my $type = shift @_;
    my ($icon, $color) = ('', '');
    if ($type == CRUD_CREATE) {
        ($icon, $color) = ('(+)', 'cyan');
    } elsif ($type == CRUD_READ) {
        ($icon, $color) = ('(<)', 'yellow');
    } elsif ($type == CRUD_UPDATE) {
        ($icon, $color) = ('(>)', 'blue');
    } elsif ($type == CRUD_DELETE) {
        ($icon, $color) = ('(X)', 'magenta');
    }
    printWithIcon($icon, $color, @_);
}

# VIEW -------------------------------------------------------------------------
sub trace {
    my ($level, @args) = @_;
    if ($level <= $verbosity) {
        my ($package, $filename, $line) = caller;
        my $icon = sprintf("T%02d@%04d", $level, $line);
        printWithIcon($icon, 'bright_black', @args);
    }
}

# VIEW -------------------------------------------------------------------------
sub printWithIcon {
    my ($icon, $color, @statements) = @_;
    my @lines = map { colored($_, $color) } split /\n/, join '', @statements;
    $lines[0]  = colored($icon, "black on_$color") . ' ' . $lines[0];
    $lines[$_] = (' ' x length $icon) . ' ' . $lines[$_] for 1..$#lines;
    print map { ($_, "\n") } @lines;
}
