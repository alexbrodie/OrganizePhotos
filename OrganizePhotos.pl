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
#    level like moveFile, traverseGlobPatterns, etc)
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
# * Switch File::Find::find to traverseGlobPatterns
# * Replace '.' with File::Spec->curdir()?
# * Cleanup print/trace/warn/die/carp/cluck/croak/confess including final endlines
# * Include zip and pdf files too
# * Tests covering at least the checkup verb code paths
# * Add wrapper around warn/carp/cluck similar to trace. Should we have a
#   halt/alert/inform/trace system for crashes/warnings/print statments/diagnositcs?
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

=item B<checkup> [-a] [-d] [-l] [-n] [glob patterns...]

=item B<collect-trash> [glob patterns...]

=item B<find-dupe-files> [-a] [-d] [-l] [-n] [glob patterns...]

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

    check-md5 [glob patterns...]
    find-dupe-files [-a | --always-continue] [glob patterns...]
    remove-empties [glob patterns...]
    collect-trash [glob patterns...]

=head3 Options

=over 24

=item B<-a, --always-continue>

Always continue

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

=item B<-a, --always-continue>

Always continue

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

use Class::Struct qw(struct);
use Data::Compare ();
use Data::Dumper ();
use DateTime::Format::HTTP;
use Digest::MD5;
use File::Copy ();
use File::Find ();
use File::Glob qw(:globally :nocase);
use File::Path ();
use File::Spec ();
use File::stat ();
use Getopt::Long ();
use Image::ExifTool;
use JSON;
use List::Util qw(any all);
use Pod::Usage;
if ($^O eq 'MSWin32') {
    use Win32::Console::ANSI; # must come before Term::ANSIColor
}
# TODO: be explicit with this and move usage to view layer
use Term::ANSIColor;

# Data structure that holds various details about a path
# to a file or directory
# TODO: these properties should probably be read-only. Might
# require writing our own class instead of using Class::Struct.
struct(PathDetails => [
    # The full absolute path which should be used for
    # most things except potentially display purposes.
    # This form is used for any die statements.
    absPath => '$',
    # The cwd that was the context when this was created,
    # which was used with rel2abs and abs2rel in creation
    # of absPath or relPath.
    # TODO: can we remove this and change relPath to disPath?
    base => '$',
    # The "friendly" relative path based on the context
    # in which this was created (see base). This should be
    # used primarily for display purposes, and absPath
    # for any actual file operations. This may be the
    # same as absPath in some cases (e.g. if base and
    # absPath are on different volumes).
    # This form is used for any print/trace/warn statements.
    relPath => '$',
    # The file or directory's volume which is equivalent
    # to splitpath(absPath)[0]. It is useful for catpath.
    volume => '$',
    # The file or directory's volume which is equivalent
    # to splitpath(absPath)[1]. It is useful for catpath
    # and splitdir.
    directories => '$',
    # The file or directory's name, including extension,
    # which is equivalent to splitpath(absPath)[2].  It is 
    # useful for catpath, and for basename and extension
    # checks.
    filename => '$',
]);

# Implementation version of getMd5 (useful when comparing older serialized
# results, such as canMakeMd5MetadataShortcut and isMd5VersionUpToDate)
my $getMd5Version = 4;

# What we expect an MD5 hash to look like
my $md5pattern = qr/[0-9a-f]{32}/;

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
    AVI     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/x-msvideo'
    },
    CRW     => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/crw'
    },
    CR2     => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/cr2' # Non-standard
    },
    CR3     => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/cr3' # Non-standard
    },
    JPEG    => {
        SIDECARS => [],
        EXTORDER => 1,
        MIMETYPE => 'image/jpeg'
    },
    JPG     => {
        SIDECARS => [],
        EXTORDER => 1,
        MIMETYPE => 'image/jpeg'
    },
    HEIC    => {
        SIDECARS => [qw( XMP MOV )],
        EXTORDER => -1,
        MIMETYPE => 'image/heic' # Non-standard
    },
    M4V     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/mp4v-es'
    },
    MOV     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/quicktime'
    },
    MP4     => {
        SIDECARS => [qw( LRV THM )],
        EXTORDER => 0,
        MIMETYPE => 'video/mp4v-es'
    },
    MPG     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/mpeg'
    },
    MTS     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'video/mts' # Non-standard
    },
    NEF     => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/nef' # Non-standard
    },
    PNG     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/png'
    },
    PSB     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/psb' # Non-standard
    },
    PSD     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/photoshop'
    },
    RAF     => {
        SIDECARS => [qw( JPEG JPG XMP )],
        EXTORDER => -1,
        MIMETYPE => 'image/raf' # Non-standard
    },
    TIF     => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/tiff'
    },
    TIFF    => {
        SIDECARS => [],
        EXTORDER => 0,
        MIMETYPE => 'image/tiff'
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

# For extra output
my $verbosity = 0;
use constant VERBOSITY_2 => 2;
use constant VERBOSITY_DEBUG => 99;

main();
exit 0;

#===============================================================================
# Main entrypoint that parses command line a bit and routes to the 
# subroutines starting with "do"
sub main {
    sub myGetOptions {
        Getopt::Long::GetOptions('verbosity|v=i' => \$verbosity, @_)
            or die "Error in command line, aborting.";

        # If we're at VERBOSITY_DEBUG, include stack traces
        if ($verbosity >= VERBOSITY_DEBUG) {
            use Carp::Always;
        }
    }

    # Parse args (using GetOptions) and delegate to the doVerb methods...
    unless (@ARGV) {
        pod2usage();        
    } elsif ($#ARGV == 0 and $ARGV[0] =~ /^-[?h]$/i) {
        pod2usage(-verbose => 2);
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
            my ($all, $autoDiff, $byName, $defaultLastAction);
            myGetOptions('always-continue|a' => \$all,
                         'auto-diff|d' => \$autoDiff,
                         'by-name|n' => \$byName,
                         'default-last-action|l' => \$defaultLastAction);
            doCheckMd5(@ARGV);
            doFindDupeFiles($all, $byName, $autoDiff, 
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
            my ($all, $autoDiff, $byName, $defaultLastAction);
            myGetOptions('always-continue|a' => \$all,
                         'auto-diff|d' => \$autoDiff,
                         'by-name|n' => \$byName,
                         'default-last-action|l' => \$defaultLastAction);
            doFindDupeFiles($all, $byName, $autoDiff, 
                            $defaultLastAction, @ARGV);
        } elsif ($verb eq 'metadata-diff' or $verb eq 'md') {
            my ($excludeSidecars);
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
            die "Unknown verb: '$rawVerb'\n";
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
    
    traverseGlobPatterns(
        sub { # isWanted
            my ($pathDetails) = @_;
            
            # Look at each directory (ignoring everything else). If it's .Trash
            # then callback will process the dir, else, we'll recurse looking
            # for more .Trash subdirs.
            return -d $pathDetails->absPath;
        },
        sub { # callback
            my ($pathDetails, $rootPathDetails) = @_;
            
            if (lc $pathDetails->filename eq '.trash') {
                # Convert root/bunch/of/dirs/.Trash to root/.Trash/bunch/of/dirs
                trashPathWithRoot($pathDetails, $rootPathDetails);
            }
        },
        @globPatterns);
}

# API ==========================================================================
# EXPERIMENTAL
# Execute find-dupe-dirs verb
sub doFindDupeDirs {

    # TODO: clean this up and use traverseGlobPatterns

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


# TODO: Move this elsewhere in the file/package (Model?)
# ------------------------------------------------------------------------------
sub buildDupeGroups {
    my ($byName, @globPatterns) = @_;

    # Create the initial groups
    my %keyToPathDetails = ();
    if ($byName) {
        # Make hash to list of like files with hash key based on file/dir name
        traverseGlobPatterns(
            sub { # isWanted
                my ($pathDetails) = @_;
                
                if (-d $pathDetails->absPath) {
                    # silently skip trash, traverse other dirs
                    return (lc $pathDetails->filename ne '.trash');
                } elsif (-f $pathDetails->absPath) {
                    # process media files
                    return ($pathDetails->filename =~ /$mediaType/);
                }
                
                die "Programmer Error: unknown object type for '${\$pathDetails->absPath}'";
            },
            sub { # callback
                my ($pathDetails) = @_;
                
                if (-f $pathDetails->absPath) {
                    trace(VERBOSITY_DEBUG, "buildDupeGroups processing '${\$pathDetails->relPath}'");
                    my $key = computeFileHashKeyByName($pathDetails);
                    push @{$keyToPathDetails{$key}}, $pathDetails;
                }
            },
            @globPatterns);
        
    } else {
        # Make hash to list of like files with MD5 as hash key
        findMd5s(sub {
            my ($pathDetails, $md5) = @_;
            if (-e $pathDetails->absPath) {
                push @{$keyToPathDetails{$md5}}, $pathDetails;
            } else {
                trace(VERBOSITY_2, "Path for MD5 is missing: '${\$pathDetails->relPath}'");
            }
        }, @globPatterns);
    }
    
    trace(VERBOSITY_DEBUG, "Found @{[scalar keys %keyToPathDetails]} initial groups");

    # Go through each element in the %keyToPathDetails map, and we'll 
    # want the ones with multiple things in the array of paths. If
    # there  are multiple paths for an element, sort the paths array
    # by decreasing importance (our best guess), and add it to the
    # @dupes collection for further processing.
    my @dupes = ();
    while (my ($key, $pathDetailsList) = each %keyToPathDetails) {
        if (@$pathDetailsList > 1) {
            push @dupes, [sort { comparePathWithExtOrder($a, $b) } @$pathDetailsList];
        }
    }

    # The 2nd level is properly sorted, now let's sort the groups
    # themselves - this will be the order in which the groups
    # are processed, so we want it extorder based as well.
    @dupes = sort { comparePathWithExtOrder($a->[0], $b->[0]) } @dupes;

    trace(VERBOSITY_DEBUG, "Found @{[scalar @dupes]} groups with multiple files");

    return \@dupes;
}

# TODO: Move this elsewhere in the file/package (Model?)
# ------------------------------------------------------------------------------
sub computeFileHashKeyByName {
    my ($pathDetails) = @_;

    my ($basename, $ext) = splitExt($pathDetails->filename);
    
    # Start with extension
    my $key = lc $ext . ';';

    # Add basename
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
        warn "Unknown filename format for '$basename' in '${\$pathDetails->relPath}'";
        $key .= lc $basename . ';';
    }
    
    my $nameKeyIncludesDir = 1;
    if ($nameKeyIncludesDir) {
        # parent dir should be similar (based on date format)
        my $dirRegex = qr/^
            # yyyy-mm-dd or yy-mm-dd or yyyymmdd or yymmdd
            (?:19|20)?(\d{2}) [-_]? (\d{2}) [-_]? (\d{2}) \b
            /x;

        my $dirKey = '';
        for (reverse File::Spec->splitdir($pathDetails->directories)) {
            if (/$dirRegex/) {
                $dirKey = lc "$1$2$3;";
                last;
            }
        }
    
        if ($dirKey) {
            $key .= $dirKey;
        } else {
            warn "Unknown directory format in '${\$pathDetails->relPath}'";
        }
    }

    return $key;
}

# TODO: break up this nearly 400 line behemoth
# API ==========================================================================
# Execute find-dupe-files verb
sub doFindDupeFiles {
    my ($all, $byName, $autoDiff, $defaultLastAction, @globPatterns) = @_;
    
    my $fast = 0; # avoid slow operations, potentially with less precision?
    
    my $dupeGroups = buildDupeGroups();
    
    # TODO: merge sidecars
    
    # Process each group of dupliates
    my $lastCommand = '';
    DUPES: for (my $dupeIndex = 0; $dupeIndex < @$dupeGroups; $dupeIndex++) {
        # Convert current element from an array of PathDetails to
        # an array (per file, in storted order) to array of hash
        # references with some metadata in the same (desired) order
        my @group = map {
            { pathDetails => $_, exists => -e $_->absPath }
        } @{$dupeGroups->[$dupeIndex]};
         
        # TODO: should this change to a "I suggest you ____, sir" approach?
        # If dupes are missing, we can auto-remove
        my $autoRemoveMissingDuplicates = 1;
        if ($autoRemoveMissingDuplicates) {
            # Remove the metadata for all missing files, and
            # keep track of what's still existing
            my @newGroup = ();
            for (@group) {
                if ($_->{exists}) {
                    push @newGroup, $_;
                } else {
                    removeMd5ForPath($_->{pathDetails}->absPath);
                }
            }
        
            # If there's still multiple in the group, continue
            # with what was left over, else move to next group
            next DUPES if @newGroup < 2;
            
            @group = @newGroup;
        }

        # Except when trying to be fast, calculate the MD5 match
        # TODO: get this pairwise and store it somehow for later
        # TODO: (hopefully for auto-delete)
        my $reco = '';
        unless ($fast) {
            # Want to tell if the files are identical, so we need hashes
            # TODO: if we're not doing this by name we can use the md5.txt file contents for  MD5 and other metadata
            $_->{exists} and $_ = { %$_, %{getMd5($_->{pathDetails}->absPath)} } for @group;
        
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
                $reco = colored('[Match: FULL]', 'bold blue on_white');
            } elsif ($md5Match) {
                $reco = '[Match: Content]';
            } else {
                $reco = colored('[Match: UNKNOWN]', 'bold red on_white');
            }
        }
        
        # See if we can use some heuristics to guess what should be
        # done in this case
        my $autoCommand;
        for (my $i = 0; $i < @group; $i++) {
            my $elt = $group[$i];

            if (!$elt->{exists} ||
                $elt->{pathDetails}->absPath =~ /[\/\\]ToImport[\/\\]/) {
                $autoCommand .= ';' if $autoCommand;
                $autoCommand .= "t$i";
            }
        }
        
        # If it's a short mov file next to a jpg or heic that's an iPhone,
        # then it's probably the live video portion from a burst shot. We
        # should just continue
        # TODO: ^^^^ that
        
        # Build base of prompt - indexed paths
        my @prompt = ('Resolving ', ($dupeIndex + 1), ' of ', scalar @$dupeGroups, ' ', $reco, "\n");
        for (my $i = 0; $i < @group; $i++) {
            my $elt = $group[$i];

            push @prompt, "  $i. ";

            my $path = $elt->{pathDetails}->absPath;
            push @prompt, coloredByIndex($path, $i);
            
            # Add file error suffix
            if ($elt->{exists}) {
                # Don't bother cracking the file to get metadata if we're in ignore all or fast mode
                push @prompt, getDirectoryError($path, $i) unless $all or $fast;                
            } else {
                push @prompt, ' ', colored('[MISSING]', 'bold red on_white');
            }
            
            push @prompt, "\n";
            
            # Collect all sidecars and add to prompt
            for (getSidecarPaths($path)) {
                push @prompt, '     ', coloredByIndex(colored($_, 'faint'), $i), "\n";
            }
        }

        # Just print that and move on if "Always continue" was
        # previously specified
        # TODO: is this actually useful?
        print @prompt and next if $all;
        
        # Default command is what happens if you hit enter with an empty string
        my $defaultCommand;
        if ($autoCommand) {
            $defaultCommand = $autoCommand;
        } elsif ($defaultLastAction) {
            $defaultCommand = $lastCommand;            
        }

        # Add input options to prompt
        push @prompt, "Diff, Continue, Always continue, Trash Number, Open Number (d/c/a";
        for my $x ('t', 'o') {
            push @prompt, '/', coloredByIndex("$x$_", $_) for (0..$#group);
        }
        push @prompt, ")? ";
        push @prompt, "[$defaultCommand] " if $defaultCommand;

        # TODO: somehow determine whether one is a superset of one or
        # TODO: more of the others (hopefully for auto-delete) 
        metadataDiff(undef, map { $_->{pathDetails}->absPath } @group) if $autoDiff;

        # If you want t automate something (e.g. do $autoCommand without
        # user confirmation), set that action here: 
        my $command;
        
        print colored("I suggest you $autoCommand", 'bold black on_red'), "\n" if $autoCommand;
        
        # Get input until something sticks...
        PROMPT: while (1) {
            print "\n", @prompt;
            
            # Prompt for action
            unless ($command) {
                chomp($command = lc <STDIN>);
                
                # If the user provided something, save that for next 
                # conflict's default
                $lastCommand = $command unless $command eq '';

                # Enter with empty string uses $defaultCommand
                $command = $defaultCommand if $defaultCommand and $command eq '';
            } else {
                print "$command\n";
            }
            
            # something like if -l turn on $defaultLastAction and next PROMPT
            
            my $itemCount = @group;
            for (split /;/, $command) {
                if ($_ eq 'd') {
                    # Diff
                    metadataDiff(undef, map { $_->{pathDetails}->absPath } @group);
                } elsif ($_ eq 'c') {
                    # Continue
                    last PROMPT;  # next group please
                } elsif ($_ eq 'a') {
                    # Always continue
                    $all = 1;
                    last PROMPT;  # next group please
                } elsif (/^t(\d+)$/) {
                    # Trash Number
                    if ($1 <= $#group && $group[$1]) {
                        if ($group[$1]->{exists}) {
                            trashPathAndSidecars($group[$1]->{pathDetails}->absPath);
                        } else {
                            # File we're trying to trash doesn't exist, 
                            # so just remove its metadata
                            removeMd5ForPath($group[$1]->{pathDetails}->absPath);
                        }

                        $group[$1] = undef;
                        $itemCount--;
                        last PROMPT if $itemCount < 2;
                    } else {
                        warn "$1 is out of range [0, $#group]";
                        last PROMPT; # next group please
                    }
                } elsif (/^o(\d+)$/i) {
                    # Open Number
                    if ($1 <= $#group) {
                        `open "$group[$1]->{pathDetails}->absPath"`;
                    }
                } elsif (/^m(\d+(?:,\d+)+)$/) {
                    # Merge 1,2,3,4,... into 0
                    my @matches = split ',', $1;
                    appendMetadata(map { $group[$_]->{pathDetails}->absPath } @matches);
                }
            }
            
            # Unless someone did a last PROMPT (i.e. "next group please"), restart this group
            redo DUPES;
        } # PROMPT
    } # DUPES
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

    traverseGlobPatterns(
        sub { # isWanted
            my ($pathDetails) = @_;

            if (-d $pathDetails->absPath) {
                # silently skip trash, traverse other dirs
                return (lc $pathDetails->filename ne '.trash');
            } elsif (-f $pathDetails->absPath) {
                # These files don't count - they're trashible, ignore them (by 
                # not processing) as if they didn't exist and let them get
                # cleaned up if the folder
                my $lcfn = lc $pathDetails->filename;
                return 0 if any { $lcfn eq $_ } ('.ds_store', 'thumbs.db', 'md5.txt');

                # TODO: exclude zero byte or hidden files as well?

                # Other files count
                return 1;
            }
            
            die "Programmer Error: unknown object type for '${\$pathDetails->absPath}'";
        },
        sub { # callback 
            my ($pathDetails, $rootPathDetails) = @_;

                if (-d $pathDetails->absPath) {
                    # at this point, all the sub-items should be processed, see how many
                    my $subItems = $dirSubItemsMap{$pathDetails->absPath};
                    trace(VERBOSITY_DEBUG, "Directory '${\$pathDetails->relPath}' contains @{[ $subItems || 0 ]} subitems");

                    # As part of a later verification check, we'll remove this dir
                    # from our map. Then if other sub-items are added after we process
                    # this parent dir right now, then we could have accidentally trashed
                    # a non-trashable dir. 
                    delete $dirSubItemsMap{$pathDetails->absPath};
                    
                    # If this dir is empty, then we'll want to trash it and have the
                    # parent dir ignore it like trashable files (e.g. md5.txt). If
                    # it's not trashable, then fall through to add this to its parent
                    # dir's list (to prevent the parent from being trashed).
                    unless ($subItems) {
                        trace(VERBOSITY_2, "Trashing '${\$pathDetails->relPath}'"); 
                        trashPath($pathDetails->absPath);
                        return;
                    }
                }
                
                # We don't mark the root item (file or dir) like all the subitems, because
                # we're not looking to remove the root's parent based on some partial knowledge
                # (e.g. if dir Alex has a lot of non-empty stuff in it and a child dir named
                # Quinn, then we wouldn't want to consider trashing Alex if we check only Quinn)
                if ($pathDetails->absPath ne $rootPathDetails->absPath) {
                    my $dir = File::Spec->catpath($pathDetails->volume, $pathDetails->directories, undef);
                    $dir = File::Spec->canonpath($dir);
                    $dirSubItemsMap{$dir}++;
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
        
        my $message = decode_json($1);
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
        my $et = new Image::ExifTool;
        $et->Options(DateFormat => '%FT%TZ');
        $et = extractInfo($filename, $et);
        my $info = $et->GetInfo(qw(
            DateTimeOriginal TimeZone TimeZoneCity DaylightSavings 
            Make Model SerialNumber));
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

        print <<EOM;
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
        my ($pathDetails, $expectedMd5) = @_;
        if (-e $pathDetails->absPath) {
            # File exists
            my $actualMd5 = getMd5($pathDetails->absPath)->{md5};
            if ($actualMd5 eq $expectedMd5) {
                # Hash match
                print "Verified MD5 for '${\$pathDetails->relPath}'\n";
            } else {
                # Has MIS-match, needs input
                warn "ERROR: MD5 mismatch for '${\$pathDetails->relPath}' ($actualMd5 != $expectedMd5)";
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
            # TODO: prompt to see if we should remove this via removeMd5ForPath
            warn "Missing file: '${\$pathDetails->relPath}'";
        }
    }, @globPatterns);
}

#-------------------------------------------------------------------------------
# Call verifyOrGenerateMd5ForFile for each media file in the glob patterns
sub verifyOrGenerateMd5ForGlob {
    my ($addOnly, @globPatterns) = @_;

    traverseGlobPatterns(
        sub { # isWanted
            my ($pathDetails) = @_;

            if (-d $pathDetails->absPath) {
                # silently skip trash, traverse other dirs
                return (lc $pathDetails->filename ne '.trash');
            } elsif (-f $pathDetails->absPath) {
                # process media files
                return 1 if ($pathDetails->filename =~ /$mediaType/);
                
                trace(VERBOSITY_2, sub {
                    # Don't show message for types that aren't meaningful in this
                    # context, occur a lot, and would just be a lot of noisy output
                    my $lowerName = lc $pathDetails->filename;
                    if (($lowerName ne 'md5.txt') and 
                        ($lowerName ne '.ds_store') and 
                        ($lowerName ne 'thumbs.db') and 
                        ($lowerName !~ /\.(?:thm|xmp)$/)) {
                        return "Skipping MD5 calculation for '${\$pathDetails->relPath}' (non-media file)";
                    }
                    return ();
                });

                # don't process non-media files
                return 0;
            }
            
            die "Programmer Error: unknown object type for '${\$pathDetails->absPath}'";
        },
        sub { # callback
            my ($pathDetails) = @_;
            
            if (-f $pathDetails->absPath) {
                verifyOrGenerateMd5ForFile($addOnly, $pathDetails);
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
    my ($addOnly, $pathDetails) = @_;

    my ($md5Path, $md5Key) = getMd5PathAndKey($pathDetails->absPath);
    
    # Get file stats for the file we're evaluating to reference and/or
    # update MD5.txt
    my $stats = File::stat::stat($pathDetails->absPath) 
        or die "Couldn't stat '${\$pathDetails->absPath}': $!";

    # Add stats metadata to be persisted to md5.txt
    my $actualMd5 = {
        size => $stats->size,
        mtime => $stats->mtime,
    };
    
    # Check cache from last call (this can often be called
    # repeatedly with files in same folder, so this prevents
    # unnecessary rereads)
    our ($lastMd5Path, $lastMd5Set);
    if ($lastMd5Path and $md5Path eq $lastMd5Path) {
        # Skip files whose date modified and file size haven't changed
        # TODO: unless force override if specified
        return if canMakeMd5MetadataShortcut($addOnly, $pathDetails, $lastMd5Set->{$md5Key}, $actualMd5);
    }
        
    # Read MD5.txt file to consult
    my ($fh, $expectedMd5Set) = openAndReadMd5File($md5Path);

    # Update cache
    $lastMd5Path = $md5Path;
    $lastMd5Set = $expectedMd5Set;

    # Target hash and metadata from cache and/or md5.txt
    my $expectedMd5 = $expectedMd5Set->{$md5Key};
        
    # Skip files whose date modified and file size haven't changed
    # TODO: unless force override if specified
    return if canMakeMd5MetadataShortcut($addOnly, $pathDetails, $expectedMd5, $actualMd5);

    # We can't skip this, so compute MD5 now
    eval {
        # TODO: consolidate opening file multiple times from stat and getMd5
        $actualMd5 = { %$actualMd5, %{getMd5($pathDetails->absPath)} };
    };
    if ($@) {
        # Can't get the MD5
        # TODO: for now, skip but we'll want something better in the future
        warn colored("UNAVAILABLE MD5 for '${\$pathDetails->relPath}' with error:", 'red'), "\n\t$@";
        return;
    }
    
    # actualMd5 and expectedMd5 should now be fully populated and 
    # ready for comparison
    if (defined $expectedMd5) {
        if ($expectedMd5->{md5} eq $actualMd5->{md5}) {
            # Matches last recorded hash, nothing to do'
            print colored("Verified    MD5 for '${\$pathDetails->relPath}'", 'green'), "\n";

            # If the MD5 data is a full match, then we don't have anything
            # else to do. If not (probably missing or updated metadata 
            # fields), then continue on where we'll re-write md5.txt.
            return if Data::Compare::Compare($expectedMd5, $actualMd5);
        } elsif ($expectedMd5->{full_md5} eq $actualMd5->{full_md5}) {
            # Full MD5 match and content mismatch. This should only be
            # expected when we change how to calculate content MD5s.
            # If that's the case (i.e. the expected version is not up to
            # date), then we should just update the MD5s. If it's not the
            # case, then it's unexpected and some kind of programer error.
            if (isMd5VersionUpToDate($pathDetails->absPath, $expectedMd5->{version})) {
                # TODO: switch this hacky crash output to better perl way
                # of generating tables
                die <<EOM;
Unexpected state: full MD5 match and content MD5 mismatch for
${\$pathDetails->absPath}
             version  full_md5                          md5
  Expected:  $expectedMd5->{version}        $expectedMd5->{full_md5}  $expectedMd5->{md5}
    Actual:  $actualMd5->{version}        $actualMd5->{full_md5}  $actualMd5->{md5}
EOM
            }
        } else {
            # Mismatch and we can update MD5, needs resolving...
            warn colored("MISMATCH OF MD5 for '${\$pathDetails->relPath}'", 'red'), 
                 " [$expectedMd5->{md5} vs $actualMd5->{md5}]\n";

            # Do user action prompt
            while (1) {
                print "Ignore, Overwrite, Quit (i/o/q)? ";
                chomp(my $in = lc <STDIN>);

                if ($in eq 'i') {
                    # Ignore the error and return
                    return;
                } elsif ($in eq 'o') {
                    # Exit loop to fall through to save actualMd5
                    last;
                } elsif ($in eq 'q') {
                    # User requested to terminate
                    exit 0;
                }
            }
        }
        
        # Write MD5
        print colored("UPDATING    MD5 for '${\$pathDetails->relPath}'", 'magenta'), "\n";
    } else {
        # It wasn't there, it's a new file, we'll add that
        print colored("ADDING      MD5 for '${\$pathDetails->relPath}'", 'blue'), "\n";
    }

    # Add/update MD5
    $expectedMd5Set->{$md5Key} = $actualMd5;

    # Update cache
    $lastMd5Path = $md5Path;
    $lastMd5Set = $expectedMd5Set;

    # Update MD5 file
    writeMd5FileToHandle($fh, $expectedMd5Set);   
}

#-------------------------------------------------------------------------------
# Print all the metadata values which differ in a set of paths
sub metadataDiff {
    my ($excludeSidecars, @paths) = @_;

    # Get metadata for all files
    my @items = map { (-e) ? readMetadata($_, $excludeSidecars) : {} } @paths;

    my @tagsToSkip = qw(
        CurrentIPTCDigest DocumentID DustRemovalData
        FileInodeChangeDate FileName HistoryInstanceID
        IPTCDigest InstanceID OriginalDocumentID
        PreviewImage RawFileName ThumbnailImage);

    # Collect all the keys which whose values aren't all equal
    my %keys = ();
    for (my $i = 0; $i < @items; $i++) {
        while (my ($key, $value) = each %{$items[$i]}) {
            no warnings 'experimental::smartmatch';
            unless (any { $_ eq $key } @tagsToSkip) {
                for (my $j = 0; $j < @items; $j++) {
                    if ($i != $j and
                        (!exists $items[$j]->{$key} or
                         $items[$j]->{$key} ne $value)) {
                        $keys{$key} = 1;
                        last;
                    }
                }
            }
        }
    }

    # Pretty print all the keys and associated values
    # which differ
    for my $key (sort keys %keys) {
        print colored("$key:", 'bold'), ' ' x (29 - length $key);
        for (my $i = 0; $i < @items; $i++) {
            my $message = $items[$i]->{$key} || colored('undef', 'faint');
            print coloredByIndex($message, $i), "\n", ' ' x 30;
        }
        print "\n";
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
    my ($path, $colorIndex) = @_;

    my $et = new Image::ExifTool;

    my @dateProps = qw(DateTimeOriginal MediaCreateDate);

    my $info = $et->ImageInfo($path, \@dateProps, {DateFormat => '%F'});

    my $date;
    for (@dateProps) {
        if (exists $info->{$_}) {
            $date = $info->{$_};
            last;
        }
    }

    my $errorColor = 'bright_white on_' . 
                     (defined $colorIndex ? colorByIndex($colorIndex) : 'red');

    if (!defined $date) {
        return ' ' . colored("** Can't find media's date! $errorColor **", $errorColor);
    }

    my $yyyy = substr $date, 0, 4;
    my $date2 = join '', $date =~ /^..(..)-(..)-(..)$/;
    my @dirs = File::Spec->splitdir((File::Spec->splitpath($path))[1]);
    if ($dirs[-3] eq $yyyy and
        $dirs[-2] =~ /^(?:$date|$date2)/) {
        # Falsy empty string when path is correct
        return '';
    } else {
        # Truthy error string
        return ' ' . colored("** Wrong dir! [$date] **", $errorColor);
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# For each item in each md5.txt file under [dir], invoke [callback]
# passing it full path and MD5 hash as arguments like
#      callback($absolutePath, $md5AsString)
sub findMd5s {
    my ($callback, @globPatterns) = @_;
    
    trace(VERBOSITY_2, 'Looking for md5.txt in', 
          (@globPatterns ? map { "\n\t'$_'" } @globPatterns : ' (unspecified)'));

    traverseGlobPatterns(
        sub { # isWanted
            my ($pathDetails) = @_;

            if (-d $pathDetails->absPath) {
                # silently skip trash, traverse other dirs
                return (lc $pathDetails->filename ne '.trash');
            } elsif (-f $pathDetails->absPath) {
                # only process md5.txt files
                return (lc $pathDetails->filename eq 'md5.txt');
            }
            
            die "Programmer Error: unknown object type for '${\$pathDetails->absPath}'";
        },
        sub { # callback
            my ($pathDetails) = @_;
            
            if (-f $pathDetails->absPath) {
                trace(VERBOSITY_2, "Found '${\$pathDetails->relPath}'");
                
                # Open the md5.txt file in read only mode
                open(my $fh, '<:crlf', $pathDetails->absPath)
                    or die "Couldn't open '${\$pathDetails->absPath}': $!";
            
                # Parse the file to get all the filename -> file info hash
                my $md5Set = readMd5FileFromHandle($fh);

                for (sort keys %$md5Set) {
                    my $md5 = $md5Set->{$_}->{md5};
                    my $otherPathDetails = changeFilename($pathDetails, $_);
                    $callback->($otherPathDetails, $md5);
                }
            }
        },
        @globPatterns);
}

# MODEL (MD5) ------------------------------------------------------------------
# Gets the path to the file containing the md5 information (the md5.txt file),
# and the key used to index into the contents of that file.
sub getMd5PathAndKey {
    my ($path) = @_;

    $path = File::Spec->rel2abs($path);
    my ($volume, $dir, $name) = File::Spec->splitpath($path);
    my $md5Path = File::Spec->catpath($volume, $dir, 'md5.txt');
    my $md5Key = lc $name;
    
    return ($md5Path, $md5Key);
}

# MODEL (MD5) ------------------------------------------------------------------
sub addMd5ForPath {
    my ($path, $md5) = @_;
    trace(VERBOSITY_DEBUG, "addMd5ForPath('$path', {..});");

    my ($md5Path, $md5Key) = getMd5PathAndKey($path);
    my ($fh, $md5Set) = openAndReadMd5File($md5Path);
    $md5Set->{md5Key} = $md5;
    writeMd5FileToHandle($fh, $md5Set);
 
    printFileOp("Added   $md5Key to   '$md5Path'\n");
}

# MODEL (MD5) ------------------------------------------------------------------
# Removes the computed MD5 hash and other file metadata for the specified path.
# Returns the data that was removed or undef if it wasn't there.
sub removeMd5ForPath {
    my ($path) = @_;

    my ($md5Path, $md5Key) = getMd5PathAndKey($path);
    if (open(my $fh, '+<:crlf', $md5Path)) {
        my $md5Set = readMd5FileFromHandle($fh);
        
        if (exists $md5Set->{$md5Key}) {
            my $md5 = $md5Set->{$md5Key};

            delete $md5Set->{$md5Key};            
            writeMd5FileToHandle($fh, $md5Set);
            
            # TODO: update the cache from the validate func?

            printFileOp("Removed $md5Key from '$md5Path'\n");

            return $md5;
        } else {
            trace(VERBOSITY_DEBUG, "$md5Key didn't exist in $md5Path");
            return undef;
        }
    } else {
        trace(VERBOSITY_DEBUG, "Couldn't open $md5Path");
        return undef;
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# This is a utility for updating MD5 information. It opens the MD5 file R/W,
# then parses and returns the handle and information in the file. The typical
# usage is to next modify to the MD5s data and call writeMd5FileToHandle.
sub openAndReadMd5File {
    my ($path) = @_;

    if (open(my $fh, '+<:crlf', $path)) {
        # Read existing contents
        return ($fh, readMd5FileFromHandle($fh));
    } else {
        # File doesn't exist, create RW
        open($fh, '+>', $path)
            or die "Couldn't open $path: $!";
        return ($fh, {});
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Deserialize a md5.txt file handle into a OM
sub readMd5FileFromHandle {
    my ($fh) = @_;
    trace(VERBOSITY_DEBUG, 'readMd5FileFromHandle(<..>)');
    
    # If the first char is a open curly brace, treat as JSON,
    # otherwise do the older simple name: md5 format parsing
    my $useJson = 0;
    while (<$fh>) {
        if (/^\s*([^\s])/) {
            $useJson = 1 if $1 eq '{';
            last;
        }
    }
    
    seek($fh, 0, 0)
        or die "Couldn't reset seek on file: $!";

    if ($useJson) {
        # Parse as JSON
        my $md5s = decode_json(join '', <$fh>);
        # TODO: Consider validating response - do a lc on  
        # TODO: filename/md5s/whatever, and verify vs $md5pattern???
        
        # If there's no version data, then it is version 1. We didn't
        # start storing version information until version 2.
        while (my ($key, $values) = each %$md5s) {
            $values->{version} = 1 unless exists $values->{version};
        }
        
        return $md5s;
    } else {
        # Parse as simple "name: md5" text
        my %md5s = ();    
        for (<$fh>) {
            /^([^:]+):\s*($md5pattern)$/ or
                warn "unexpected line in MD5: $_";

            # We use version 0 here for the very old way before we went to
            # JSON when we added more info than just the full file MD5
            my $fullMd5 = lc $2;
            $md5s{lc $1} = { version => 0, md5 => $fullMd5, full_md5 => $fullMd5 };
        }        

        return \%md5s;
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Serialize OM into a md5.txt file handle
sub writeMd5FileToHandle {
    my ($fh, $md5s) = @_;
    trace(VERBOSITY_DEBUG, 'writeMd5FileToHandle(<..>, { hash of @{[ scalar keys %$md5s ]} items })');    
    
    # Clear MD5 file
    seek($fh, 0, 0)
        or die "Couldn't reset seek on file: $!";
    truncate($fh, 0)
        or die "Couldn't truncate file: $!";

    # Update MD5 file
    my $useJson = 1;
    if ($useJson) {
        # JSON output
        print $fh JSON->new->allow_nonref->pretty->encode($md5s);
    } else {
        # Simple "name: md5" text output
        for (sort keys %$md5s) {
            print $fh lc $_, ': ', $md5s->{$_}->{md5}, "\n";
        }
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Check if we can shortcut based on metadata without evaluating MD5s
# TODO: should this be a nested function?
sub canMakeMd5MetadataShortcut {
    my ($addOnly, $pathDetails, $expectedMd5, $actualMd5) = @_;
    
    if (defined $expectedMd5) {
        if ($addOnly) {
            trace(VERBOSITY_2, "Skipping MD5 recalculation for '${\$pathDetails->relPath}' (add-only mode)");
            return 1;
        }
    
        if (defined $expectedMd5->{size} and 
            defined $expectedMd5->{mtime} and 
            isMd5VersionUpToDate($pathDetails->absPath, $expectedMd5->{version}) and
            $actualMd5->{size} == $expectedMd5->{size} and
            $actualMd5->{mtime} == $expectedMd5->{mtime}) {
            trace(VERBOSITY_2, "Skipping MD5 recalculation for '${\$pathDetails->relPath}' (same size/date-modified)");
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
    my ($path, $version) = @_;
    
    # NOTE: this is a good place to put a hack if you want to force 
    # regeneration of MD5s for file(s). Returning something falsy will 
    # cause check-md5 to recalc.
    
    my $type = getMimeType($path);
    if ($type eq 'image/jpeg') {
        # JPG is unchanged since version 1
        return ($version >= 1) ? 1 : 0;
    } elsif ($type eq 'video/mp4v-es') {
        # MP4 is unchanged since version 2
        return ($version >= 2) ? 1 : 0;
    } elsif ($type eq 'video/quicktime') {
        # MOV is unchanged since version 4
        return ($version >= 4) ? 1 : 0;
    } elsif ($type eq 'image/tiff') {
    } elsif ($type eq 'image/png') {
        # PNG is unchanged since version 3
        return ($version >= 3) ? 1 : 0;
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
    my ($path, $useCache) = @_;
    
    # TODO: use '${\$pathDetails->relPath}' instead of '$path' (which is absPath)
    trace(VERBOSITY_DEBUG, "Calculating MD5 for '$path'");
    
    # *** IMPORTANT NOTE ***
    # $getMd5Version should be incremented whenever the output of
    # this method changes in such a way that old values need to be
    # recalculated, and isMd5VersionUpToDate should be updated
    # accordingly.
    
    our %md5Cache;
    my $cacheKey = File::Spec->rel2abs($path);
    if ($useCache) {
        my $cacheResult = $md5Cache{$cacheKey};
        return $cacheResult if defined $cacheResult;
    }
    
    open(my $fh, '<:raw', $path)
        or die "Couldn't open $path: $!";
        
    my $fullMd5Hash = getMd5Digest($path, $fh);

    # TODO: should we catch exceptions for partial match computation
    # and only return the full hash? Currently we just skip the file
    # which seems worse
    my $partialMd5Hash = undef;
    eval {
        my $type = getMimeType($path);
        if ($type eq 'image/jpeg') {
            $partialMd5Hash = getJpgContentDataMd5($path, $fh);
        } elsif ($type eq 'video/mp4v-es') {
            $partialMd5Hash = getMp4ContentDataMd5($path, $fh);
        } elsif ($type eq 'video/quicktime') {
            $partialMd5Hash = getMovContentDataMd5($path, $fh);
        } elsif ($type eq 'image/tiff') {
            # TODO
        } elsif ($type eq 'image/png') {
            $partialMd5Hash = getPngContentDataMd5($path, $fh);
        }
    };
    if ($@) {
        # Can't get the partial MD5, so we'll just use the full hash
        warn "Unavailable content MD5 for '$path' with error:\n\t$@";
    }
    
    my $result = {
        version => $getMd5Version,
        md5 => $partialMd5Hash || $fullMd5Hash,
        full_md5 => $fullMd5Hash,
    };
    
    $md5Cache{$cacheKey} = $result;
    
    return $result;
}

# MODEL (MD5) ------------------------------------------------------------------
# Gets the mime type from a path for all types supported by $mediaType
# TODO: Should this be categorized as MP5 sub? Seems more generic like Metadata.
sub getMimeType {
    my ($path) = @_;

    # If the file is a backup (has some "bak"/"original" suffix), 
    # we want to consider the real extension
    $path =~ s/$backupSuffix$//;
    
    # Take the extension
    # TODO: use helper method to splitExt
    unless ($path =~ /\.([^.]*)$/) {
        return 'unknown';
    }
    
    my $type = uc $1;
    if (exists $fileTypes{$type}) {
        return $fileTypes{$type}->{MIMETYPE};
    } else {
        die "Unexpected file type $type for '$path'";        
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# If JPEG, skip metadata which may change and only hash pixel data
# and hash from Start of Scan [SOS] to end of file
sub getJpgContentDataMd5 {
    my ($path, $fh) = @_;

    # Read Start of Image [SOI]
    seek($fh, 0, 0)
        or die "Failed to reset seek for '$path': $!";
    read($fh, my $fileData, 2)
        or die "Failed to read SOI from '$path': $!";
    my ($soi) = unpack('n', $fileData);
    $soi == 0xffd8
        or die "JPG file didn't start with SOI marker: '$path'";

    # Read blobs until SOS
    my $tags = '';
    while (1) {
        read($fh, my $fileData, 4)
            or die "Failed to read from '$path' at @{[tell $fh]} after $tags: $!";

        my ($tag, $size) = unpack('nn', $fileData);
        
        # Take all the file after the SOS
        return getMd5Digest($path, $fh) if $tag == 0xffda;

        $tags .= sprintf("%04x,%04x;", $tag, $size);
        #printf("@%08x: %04x, %04x\n", tell($fh) - 4, $tag, $size);

        my $address = tell($fh) + $size - 2;
        seek($fh, $address, 0)
            or die "Failed to seek '$path' to $address: $!";
    }
}

# MODEL (MD5) ------------------------------------------------------------------
sub getMovContentDataMd5 {
    # For now, our approach is identical for MOV and MP4
    return getMp4ContentDataMd5(@_);
}

# MODEL (MD5) ------------------------------------------------------------------
sub getMp4ContentDataMd5 {
    my ($path, $fh) = @_;
    
    seek($fh, 0, 0)
        or die "Failed to reset seek for '$path': $!";
        
    # TODO: should we verify the first atom is ftyp? Do we care?
    
    # TODO: currently we're only doing the first 'mdat' atom's data. I'm
    # not sure if that's correct... can there be multiple mdat? Is pixel
    # data located elsewhere? Should we just opt out certain atoms rather
    # than opting in mdat?
    
    while (!eof($fh)) {
        my $seekStartOfAtom = tell($fh);
        
        # Read atom header
        read($fh, my $fileData, 8)
            or die "Failed to read MP4 atom from '$path' at @{[tell $fh]}: $!";
        my ($atomSize, $atomType) = unpack('NA4', $fileData);
            
        if ($atomSize == 0) {
            # 0 means the atom goes to the end of file
        
            # I think we want to take all the the mdat atom data?
            return getMd5Digest($path, $fh) if $atomType eq 'mdat'; 
            
            last;
        } else {
            my $dataSize = $atomSize - 8;
            
            if ($atomSize == 1) {
                # 1 means it's 64 bit size
                read($fh, $fileData, 8)
                    or die "Failed to read MP4 atom from '$path': $!";
                $atomSize = unpack('Q>', $fileData);
                $dataSize = $atomSize - 16;
            }
            
            $dataSize >= 0 
                or die "Unexpected size for MP4 atom '$atomType': $atomSize";
        
            # I think we want to take all the the mdat atom data?
            return getMd5Digest($path, $fh, $dataSize) if $atomType eq 'mdat'; 

            # Seek to start of next atom
            my $address = $seekStartOfAtom + $atomSize;
            seek($fh, $address, 0)
                or die "Failed to seek '$path' to $address: $!";
        }
    }
        
    return undef;
}

# MODEL (MD5) ------------------------------------------------------------------
sub getPngContentDataMd5 {
    my ($path, $fh) = @_;
    
    seek($fh, 0, 0)
        or die "Failed to reset seek for '$path': $!";
    read($fh, my $fileData, 8)
        or die "Failed to read PNG header from '$path': $!";
    my @actualHeader = unpack('C8', $fileData);

    # All PNGs start with this
    my @pngHeader = ( 137, 80, 78, 71, 13, 10, 26, 10 );
    Data::Compare::Compare(\@actualHeader, \@pngHeader)
        or die "PNG file didn't start with correct header: '$path'";

    my $md5 = new Digest::MD5;
        
    while (!eof($fh)) {
        # Read chunk header
        read($fh, $fileData, 8)
            or die "Failed to read PNG chunk from '$path' at @{[tell $fh]}: $!";
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
            addToMd5Digest($md5, $path, $fh, $size);
        }

        # Seek to start of next chunk (past header, data, and CRC)
        my $address = $seekStartOfData + $size + 4;
        seek($fh, $address, 0)
            or die "Failed to seek '$path' to $address: $!";
    }

    return resolveMd5Digest($md5);
}
    
# MODEL (MD5) ------------------------------------------------------------------
# Get/verify/canonicalize hash from a FILEHANDLE object
sub getMd5Digest {
    my ($path, $fh, $size) = @_;

    my $md5 = new Digest::MD5;
    addToMd5Digest($md5, $path, $fh, $size);
    return resolveMd5Digest($md5);
}
    
# MODEL (MD5) ------------------------------------------------------------------
sub addToMd5Digest {
    my ($md5, $path, $fh, $size) = @_;

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
                or die "Failed to read from '$path' at @{[tell $fh]}: $!";
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
    $hexdigest =~ /$md5pattern/
        or die "Unexpected MD5: $hexdigest";

    return $hexdigest;
}

# MODEL (Metadata) -------------------------------------------------------------
# Provided a path, returns an array of sidecar files based on extension.
sub getSidecarPaths {
    my ($path) = @_;

    # TODO: Consolidate backup regex
    if ($path =~ /$backupSuffix$/) {
        # For backups, we don't associate related files as sidecars
        return ();
    } else {
        # Using extension as a key, look up associated sidecar types (if any)
        my ($base, $ext) = splitExt($path);
        my $key = uc $ext;
        if (exists $fileTypes{$key}) {
            # Return the other types which exist
            # TODO: use path functions (do we need to add a catExt as reciprocal of splitExt
            # like we have splitpath and catpath)
            my @sidecars = map { "$base.$_" } @{$fileTypes{$key}->{SIDECARS}};
            @sidecars = grep { -e } @sidecars;
            return @sidecars;
        } else {
            # Unknown file type (based on extension)
            die "Unknown type '$key' to determine sidecars for '$path'"; 
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
# Wrapper for Image::ExifTool::ExtractInfo + GetInfo with error handling
sub extractInfo {
    my ($path, $et) = @_;
    
    $et = new Image::ExifTool unless $et;
    
    $et->ExtractInfo($path)
        or die "Couldn't ExtractInfo for '$path': " . $et->GetValue('Error');
        
    return $et;
}

# MODEL (PathDetails) ----------------------------------------------------------
sub makePathDetails {
    my ($absPath, $base, $relPath) = @_;

    # TODO: see if we can delay this calculation until needed. Might require
    # writing our own class instead of using Class::Struct.
    my ($volume, $directories, $filename) = File::Spec->splitpath($absPath);

    return PathDetails->new(
        absPath => $absPath,
        base => $base,
        relPath => $relPath,
        volume => $volume,
        directories => $directories,
        filename => $filename);
}

# MODEL (PathDetails) ----------------------------------------------------------
sub changeFilename {
    my ($pathDetails, $newFilename) = @_;

    my $absPath = File::Spec->catpath($pathDetails->volume, 
                                      $pathDetails->directories, 
                                      $newFilename);

    # TODO: try harder - do something with $pathDetails->relPath
    my $relPath = $absPath; 

    return makePathDetails($absPath,
                           $pathDetails->base,
                           $relPath);
}

# MODEL (PathDetails) ----------------------------------------------------------
sub comparePathWithExtOrder {
    my ($pathDetailsA, $pathDetailsB) = @_;

    return compareDirectories($pathDetailsA->directories, $pathDetailsB->directories) ||
           compareFilenameWithExtOrder($pathDetailsA->filename, $pathDetailsB->filename);
}

# MODEL (Path Operations) ------------------------------------------------------
sub compareDirectories {
    my ($directoriesA, $directoriesB) = @_;

    my @as = File::Spec->splitdir($directoriesA);
    my @bs = File::Spec->splitdir($directoriesB);
    for (my $i = 0;; $i++) {
        if ($i >= @as) {
            if ($i >= @bs) {
                # A and B both ran out, so they're equal
                return 0;
            } else {
                # A ran out, B didn't, so B is in subdir
                # of A, so A goes first
                return -1;
            }
        } else {
            if ($i >= @bs) {
                # B ran out, A didn't, so A is in subdir
                # of B, so B goes first
                return 1;
            } else {
                # Both have an i'th entry, so now we'll 
                # compare the names, and if they're
                # not equal, we know the order
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
            # Both known types, A comes first if
            # it has a lower extorder
            my $c = $fileTypes{uc $extA}->{EXTORDER} <=> $fileTypes{uc $extB}->{EXTORDER};
            return $c if $c;
        } else {
            # A is known, B is not, so A comes first
            return -1;
        }
    } else {
        if (defined $fileTypes{uc $extB}) {
            # Neither types are known, do nothing here
        } else {
            # B is known, A is not, so B comes first
            return 1;
        }
    }

    # And then just the extension as a string
    return lc $extA cmp lc $extB;
}

# MODEL (Path Operations) ------------------------------------------------------
# Splits the filename into basename and extension. (Both without a dot.)
sub splitExt {
    my ($path) = @_;
    
    my ($filename, $ext) = $path =~ /^(.*)\.([^.]*)/;
    # TODO: handle case without extension - if no re match then just return ($path, '')
    
    return ($filename, $ext);
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
#   traverseGlobPatterns(
#       sub { #isWanted
#           my ($pathDetails) = @_; 
#           return !(-d $pathDetails->absPath) or (lc $pathDetails->filename ne '.trash');
#       },
#       sub { # callback
#           my ($pathDetails) = @_; 
#           print("Processing '${\$pathDetails->relPath}'\n") if -f $absPath; 
#       });
#
# Note that if glob patterns overlap, then some files might invoke the 
# callbacks more than once. For example, 
#   traverseGlobPatterns(sub { ... }, sub {...}, 'Al*.jpg', '*ex.jpg');
# would match Alex.jpg twice, and invoke isWanted/callback twice as well.
sub traverseGlobPatterns {
    my ($isWanted, $callback, @globPatterns) = @_;

    # Record base now so that no_chdir doesn't affect rel2abs/abs2rel below
    my $base = File::Spec->rel2abs(File::Spec->curdir());
    
    # the isWanted and callback methods take the same params, that share
    # the following computations
    my $myMakePathDetails = sub {
        my ($relPath) = @_;

        $relPath = File::Spec->canonpath($relPath);
        my $absPath = File::Spec->rel2abs($relPath, $base);

        -e $absPath or die "Programmer Error: incorrect absPath calculation: $absPath";

        return makePathDetails($absPath, $base, $relPath);
    };

    # Method to be called for each directory found in globPatterns
    my $helper = sub {
        my ($rootDir) = @_;

        my $rootPathDetails = $myMakePathDetails->($rootDir);

        # The final wanted call for $rootDir doesn't have a matching preprocess call,
        # so force one up front for symetry with all other pairs.
        if (!$isWanted or $isWanted->($rootPathDetails, $rootPathDetails)) {
            File::Find::find({
                bydepth => 1,
                no_chdir => 1,
                preprocess => sub {
                    return grep {
                            # Skip .. because it doesn't matter what we do, this
                            # isn't going to get passed to wanted, and it doesn't
                            # really make sense to traverse up in a recursive down
                            # enumeration. Also, skip '.' because we would otherwise
                            # process each dir twice, and $rootDir once. This makes
                            # subdirs once and $rootDir not at all.
                            if (($_ ne '.') and ($_ ne '..')) {
                                if ($isWanted) {
                                    # The values used here to compute the full path to the file
                                    # relative to $base matches the values of wanted's implementation, 
                                    # and both work the same whether no_chdir is set or not, i.e. they 
                                    # only use values that are unaffected by no_chdir. 
                                    my $relPath = File::Spec->catfile($File::Find::dir, $_);
                                    my $pathDetails = $myMakePathDetails->($relPath);

                                    # prevent accedental use via implicit args in isWanted
                                    local $_ = undef;
                                    
                                    $isWanted->($pathDetails, $rootPathDetails);
                                } else {
                                    1; # process
                                }
                            } else {
                                0; # skip
                            }
                        } @_;
                },
                wanted => sub {
                    # The values used here to compute the full path to the file
                    # relative to $base matches the values of preprocess' implementation, 
                    # and both work the same whether no_chdir is set or not, i.e. they 
                    # only use values that are unaffected by no_chdir.
                    my $pathDetails = $myMakePathDetails->($File::Find::name);

                    # prevent accedental use via implicit args in callback
                    local $_ = undef;

                    $callback->($pathDetails, $rootPathDetails);
                }
            }, $rootDir);
        }
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
                    my $pathDetails = $myMakePathDetails->($_);

                    # prevent accedental use via implicit args in isWanted/callback
                    local $_ = undef;

                    if (!$isWanted or $isWanted->($pathDetails, $pathDetails)) {
                        $callback->($pathDetails, $pathDetails);
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
    my ($path) = @_;
    trace(VERBOSITY_DEBUG, "trashPathAndSidecars('$path');");

    # TODO: check all for existance before performing any operations to
    # make file+sidecar opererations more atomic
    trashPath($_) for ($path, getSidecarPaths($path));
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path by moving it to a .Trash subdir and moving
# its entry from the md5.txt file
sub trashPath {
    my ($path) = @_;
    #trace(VERBOSITY_DEBUG, "trashPath('$path');");

    my ($volume, $dir, $name) = File::Spec->splitpath($path);
    my $trashDir = File::Spec->catpath($volume, $dir, '.Trash');
    my $trashPath = File::Spec->catfile($trashDir, $name);

    movePath($path, $trashPath);
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path by moving it to rootPathDetails's .Trash subdir
# and moving its entry from the md5.txt file
sub trashPathWithRoot {
    my ($pathDetails, $rootPathDetails) = @_;

    # Split the directories into pieces assuming root is a dir    
    my @pathDirs = File::Spec->splitdir($pathDetails->directories);
    my @rootDirs = File::Spec->splitdir(File::Spec->catdir($rootPathDetails->directories, $rootPathDetails->filename));

    # Verify @rootDirs is a prefix match for (i.e. ancestor of) $pathDirs
    $pathDetails->volume eq $rootPathDetails->volume
        or die "Programmer error: root is is not a prefix for path (different volumes)";
    @rootDirs < @pathDirs 
        or die "Programmer error: root is is not a prefix for path (root is longer)";
    for (my $i = 0; $i < @rootDirs; $i++) {
        $rootDirs[$i] eq $pathDirs[$i] 
            or die "Programmer error: root is not prefix for path ('$rootDirs[$i]' ne '$pathDirs[$i]' at $i)";
    }

    # Figure out postRoot (pathDetails relative to rootPathDetails without trash),
    # and then append that to rootPathDetails's trash dir's path
    my @postRoot = grep { lc ne '.trash' } @pathDirs[@rootDirs .. @pathDirs-1];
    my $newFilename = pop @postRoot;
    my $newDirectories = File::Spec->catdir(@rootDirs, '.Trash', @postRoot);
    my $newAbsPath = File::Spec->catpath($pathDetails->volume, $newDirectories, $newFilename);

    movePath($pathDetails->absPath, $newAbsPath);
}

# MODEL (File Operations) ------------------------------------------------------
# Move [oldPath] to [newPath]
sub movePath {
    my ($oldPath, $newPath) = @_;
    trace(VERBOSITY_DEBUG, "movePath('$oldPath', '$newPath');");

    my $moveInternal = sub {
        # Ensure parent dir exists
        my $parent = File::Spec->catpath((File::Spec->splitpath($newPath))[0,1]);
        -d $parent or File::Path::make_path($parent)
            or die "Failed to make directory '$parent': $!";

        # Move the file/dir
        File::Copy::move($oldPath, $newPath)
            or die "Failed to move '$oldPath' to '$newPath': $!";
    };

    if (-f $oldPath) {
        -e $newPath
            and die "I can't overwrite files moving '$oldPath' to '$newPath')";

        $moveInternal->($oldPath, $newPath);
        my $md5 = removeMd5ForPath($oldPath);
        addMd5ForPath($newPath, $md5) if $md5;

        printFileOp("Moved file '$oldPath' => '$newPath'\n");
    } elsif (-d $oldPath) {
        if (-e $newPath) {
            # Dest dir path already exists, need to move-merge.

            # TODO: BUGBUG: this needs some cleanup and debugging. 
            # I'm not sure this actually works for example when doing 
            # a multi-level move-merge

            -d $newPath
                or die "Can't move a directory - file already exists at destination ('$oldPath' => '$newPath')";

            # Walk through all the sub-items in the dir $oldPath breadth first
            # so that we try to move parent dirs that don't already have something
            # at the destination before going and trying to move their sub-items
            # one at a time.
            File::Find::find({
                wanted => sub {
                    if ($_ ne '.') {
                        movePath($File::Find::name,
                                File::Spec->catfile($newPath, $_));
                    }
                }
            }, $oldPath);

            # TODO: If we've emptied out $oldPath my moving all its contents into
            # the already existing $newPath, can we safely delete it? Or do we
            # just be conservative and lazy and let doRemoveEmpties handle it?
        } else {
            # Dest dir doesn't exist, so we can just move the whole directory
            $moveInternal->($oldPath, $newPath);

            printFileOp("Moved dir  '$oldPath' => '$newPath'\n");
        }
    } else {
        die "Programmer Error: unexpected type for object $oldPath";
    }
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
    return $colors[$colorIndex % scalar @colors];
}

# VIEW -------------------------------------------------------------------------
sub printFileOp(@) {
    print map { colored("! $_", 'bright_cyan'), "\n" } split /\n/, join '', @_;
}

# VIEW -------------------------------------------------------------------------
sub trace($@) {
    my ($level, @args) = @_;

    if ($level <= $verbosity) {
        # If the only arg we were passed is a code reference (in order to
        # defer potentially expensive calculation), call it to generate the
        # trace statements.
        @args = $args[0]->() if @args == 1 and ref $args[0] eq 'CODE';

        if (@args) {
            # TODO: color coding by trace level
            my ($package, $filename, $line) = caller;
            print colored(sprintf("T%02d@%04d", $level, $line), 'bold white on_bright_black'), 
                  join("\n" . (' ' x 8), map { colored(' ' . $_, 'bold bright_black') } split /\n/, join '', @args),
                  "\n";
        }
    }
}

