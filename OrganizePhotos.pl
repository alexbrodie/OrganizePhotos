#!/usr/bin/perl
#
# TODO LIST
#
# Bugs:
# * Fix bug where consecutive sidecar MOV files for iPhone live photos in
#   burst are recognized as content match
# * When trashing a dupe, make sure not to trash sidecars that don't match
#
# Code health:
# * Tests covering at least the checkup verb code paths
# * Use constants for some of the standard paths like thumbs.db, etc
# * Replace some hashes whose key sets never change with Class::Struct
# * Move all colored to view
# * Namespace somehow for view/model/API/etc?
# * Use Cwd instead of File::Spec?
# * Standardize on naming for path pieces, e.g. have prefixes absPath (full
#   absolute path), relPath (full friendly relative path ... from somewhere,
#   but maybe not to CWD), volume (per splitpath), directories ($ per
#   splitpath, and @ per splitdir), filename (the name of the file or
#   directory excluding volume or directory including extenaion, and without
#   trailing slash for directories except at ext (the extension only of the
#   file including the period, or the empty string if no extension is present)
# * Add param types to sub declaration?
# * Add wrapper around warn/carp/cluck similar to trace. Should we have a
#   halt/alert/inform/trace system for crashes/warnings/print statments?
#
# New features:
# * Add orph flag to c5/c to force regeneration of md5 (don’t short circuit
#   test if date/size match the ones from the last generated md5)
# * Add command line flags for find-dupe-files/checkup to control and extend
#   generateFindDupeFilesAutoAction.
#     - Enable/disable
#     - Trash full/content dupes in ToImport/specified folder
#     - How to handle content dupes?
#         * Trash content dupe with subset (or no "user applied"?) metadata
#         * Trash older date modified (extra: allow date modified to be
#           latest of any sidecars for Raw + XMP)
#         * Consolidate metadata somehow?
#         * Trash one that's not in the right place, i.e. not in folder
#           starting with YYYY-MM-DD of date captured
# * Add an export-md5 verb to export all Md5Info data to a csv file
# * Add a trim-md5 verb to remove missing files from md5.txt files (and
#   add it to checkup?)
# * Add a new restore-trash verb that searches for .orphtrash dirs and for each
#   one calls consolidateTrash(self, self) and movePath(self, parent)
# * Find mis-homed media (date taken/captured != folder name)
# * calculateMd5Info: content only match for tiff
# * find-dupe-files undo support (z)
# * something much better than the (i/o/q) prompt for MD5 conflicts
# * ignore "resource fork" segments (files starting with "._" which can show
#   up when data is copied from HFS on MacOS to shared exFAT drive and viewed
#   on Windows), and treat them sort of like sidecars (except, that we want
#   the resource fork of each sidecar in some cases - maybe it should be lower
#   level like moveFile, traverseFiles, etc)
# * consider multiple factors for resolving dupe group, not just {md5}, also
#   existance, full_md5, size/mtime, filename, basename, extension. Possibly
#   weighted. And examine the similarity between each pair of items in the
#   group. Then sort by the sum of similarty value compared to all other items
#   to determine priority. Or something along those lines.
# * dedupe IMG_XXXX.HEIC and IMG_EXXXX.JPG
# * traverseFiles should skip any dir which contains a special (zero byte?)
#   unique file (named .orphignore?) and add documentation (e.g. put this in
#   the same dir as your lrcat file). Maybe if it's not zero byte, it can act
#   like .gitignore Or, alternately do a .rsync-filter style file instead of
#   .gitignore
# * look for zero duration videos (this hang's Lightroom's
#   DynamicLinkMediaServer which pegs the CPU and blocks Lr preventing any
#   video imports or other things requiring DLMS, e.g. purging video cache)#
# * get rid of texted photos (no metadata (e.g. camera make & model), small
#   files)
# * Verb to find paths that are messed up
#   - Don’t follow standard templates
#   - \w{4}[eE]\d{4}\.[a-zA-Z]{3,4}
#   - Have extra suffix, e.g. “filename (2).ext” or “filename.ext_bak”
#   - Dates in path and metadata don’t match
#   - Sidecar verification of some kind?

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

#use Carp ();
#$SIG{__DIE__} =  \&Carp::confess;
#$SIG{__WARN__} = \&Carp::confess;
use Const::Fast qw(const);
use Data::Compare ();
use Data::Dumper ();
use DateTime::Format::HTTP ();
#use DateTime::Format::ISO8601 ();
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
use Number::Bytes::Human ();
BEGIN { $Pod::Usage::Formatter = 'Pod::Text::Termcap'; }
use Pod::Usage ();
use POSIX ();

use File::Basename;
use Cwd qw(abs_path);
use lib dirname(abs_path(__FILE__));

use FileOp;
use View;

my $autoTrashDuplicatesFrom = [
    '/Volumes/CFexpress/',
    '/Volumes/MicroSD/',
    ];

# Filename only portion of the path to Md5File which stores
# Md5Info data for other files in the same directory
const my $md5Filename => '.orphdat';

# This subdirectory contains the trash for its parent
const my $trashDirName => '.orphtrash';

# What we expect an MD5 hash to look like
const my $md5DigestPattern => qr/[0-9a-f]{32}/;

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
const my $mediaType => qr/
    # Media extension
    (?: \. (?i) (?: @{[ join '|', keys %fileTypes ]}) )
    # Optional backup file suffix
    (?: $backupSuffix)?
$/x;

use constant MATCH_UNKNOWN => 0;
use constant MATCH_NONE => 1;
use constant MATCH_FULL => 2;
use constant MATCH_CONTENT => 3;

my $filenameFilter = $mediaType;
my $cachedMd5Path = '';
my $cachedMd5Set = {};

#===============================================================================
# Main entrypoint that parses command line a bit and routes to the 
# subroutines starting with "do"
sub main {
    #printjoin("\n\t", 'Processing command line options:', @ARGV), "\n";
    sub myGetOptions {
        my $filter = undef;
        Getopt::Long::GetOptions(
            'verbosity|v:+' => \$View::verbosity,
            'filter|f=s' => \$filter, 
            @_) or die "Error in command line, aborting.";
        if ($filter) {
            if ($filter eq 'all') {
                $filenameFilter = qr//;
            } elsif ($filter eq 'media') {
                $filenameFilter = $mediaType;
            } elsif ($filter =~ /^qr(.*)$/) {
                $filenameFilter = qr/$1/;
            } elsif ($filter =~ /^\.(.*)$/) {
                $filenameFilter = qr/\.(?i)(?:@{[ join '|', split '\.', $1 ]})$/;
            } else {
                die "Unknown filter: $filter\n";
            }
            trace(View::VERBOSITY_LOW, "Filter set to: ", $filenameFilter);
        }
        return @ARGV;
    }
    # Parse args (using GetOptions) and delegate to the doVerb methods...
    unless (@ARGV) {
        Pod::Usage::pod2usage();
    } elsif ($#ARGV == 0 and $ARGV[0] =~ /^-[?h]|help$/i) {
        Pod::Usage::pod2usage(-verbose => 2);
    } else {
        Getopt::Long::Configure('bundling');
        my $verb = shift @ARGV;
        if ($verb eq 'append-metadata' or $verb eq 'am') {
            my @args = myGetOptions();
            doAppendMetadata(@args);
        } elsif ($verb eq 'check-md5' or $verb eq 'c5') {
            my $addOnly = 0;
            my $forceRecalc = 0;
            my @args = myGetOptions(
                'add-only' => \$addOnly,
                'force-recalc' => \$forceRecalc);
            doCheckMd5($addOnly, $forceRecalc, @args);
        } elsif ($verb eq 'checkup' or $verb eq 'c') {
            my $addOnly = 0;
            my $autoDiff = 0;
            my $byName = 0;
            my $forceRecalc = 0;
            my $noDefaultLastAction = 0;
            my @args = myGetOptions(
                'add-only' => \$addOnly,
                'auto-diff|d' => \$autoDiff,
                'by-name|n' => \$byName,
                'no-default-last-action' => \$noDefaultLastAction);
            doCheckMd5($addOnly, $forceRecalc, @args);
            doFindDupeFiles($byName, $autoDiff, 
                            !$noDefaultLastAction, @args);
            doRemoveEmpties(@args);
            doPurgeMd5(@args);
            doCollectTrash(@args);
        } elsif ($verb eq 'collect-trash' or $verb eq 'ct') {
            my @args = myGetOptions();
            doCollectTrash(@args);
        } elsif ($verb eq 'find-dupe-dirs' or $verb eq 'fdd') {
            my @args = myGetOptions();
            @args and die "Unexpected parameters: @args\n";
            doFindDupeDirs();
        } elsif ($verb eq 'find-dupe-files' or $verb eq 'fdf') {
            my $autoDiff = 0;
            my $byName = 0;
            my $noDefaultLastAction = 0;
            my @args = myGetOptions(
                'auto-diff|d' => \$autoDiff,
                'by-name|n' => \$byName,
                'no-default-last-action' => \$noDefaultLastAction);
            doFindDupeFiles($byName, $autoDiff, 
                            !$noDefaultLastAction, @args);
        } elsif ($verb eq 'metadata-diff' or $verb eq 'md') {
            my $excludeSidecars = 0;
            my @args = myGetOptions(
                'exclude-sidecars|x' => \$excludeSidecars);
            doMetadataDiff($excludeSidecars, @args);
        } elsif ($verb eq 'purge-md5' or $verb eq 'p5') {
            my @args = myGetOptions();
            doPurgeMd5(@args);
        } elsif ($verb eq 'remove-empties' or $verb eq 're') {
            my @args = myGetOptions();
            doRemoveEmpties(@args);
        } elsif ($verb eq 'restore-trash' or $verb eq 'rt') {
            my @args = myGetOptions();
            doRestoreTrash(@args);
        } elsif ($verb eq 'test') {
            doTest(@ARGV);
        } elsif ($verb eq 'verify-md5' or $verb eq 'v5') {
            my @args = myGetOptions();
            doVerifyMd5(@args);
        } else {
            die "Unknown verb: $verb\n";
        }
    }
}

# API ==========================================================================
# EXPERIMENTAL
# Execute append-metadata verb
sub doAppendMetadata {
    my ($target, @sources) = @_;

    my @properties = qw(XPKeywords Rating Subject HierarchicalSubject LastKeywordXMP Keywords);

    # Extract current metadata in target
    my $etTarget = extractInfo($target);
    my $infoTarget = $etTarget->GetInfo(@properties);

    trace(View::VERBOSITY_ALL, "$target: ", Data::Dumper::Dumper($infoTarget));

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

        trace(View::VERBOSITY_ALL, "$source: ", Data::Dumper::Dumper($infoSource));

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

# API ==========================================================================
# Execute check-md5 verb
sub doCheckMd5 {
    my ($addOnly, $forceRecalc, @globPatterns) = @_;
    traverseFiles(
        undef, # isDirWanted
        undef, # isFileWanted
        sub {  # callback
            my ($fullPath, $rootFullPath) = @_;
            -f $fullPath and resolveMd5Info($fullPath, $addOnly, $forceRecalc);
        },
        @globPatterns);
}

# API ==========================================================================
# Execute collect-trash verb
sub doCollectTrash {
    my (@globPatterns) = @_;
    traverseFiles(
        sub {  # isDirWanted
            return 1;
        },
        sub {  # isFileWanted
            return 0;
        },
        sub {  # callback
            my ($fullPath, $rootFullPath) = @_;
            my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
            if (lc $filename eq $trashDirName) {
                # Convert root/bunch/of/dirs/.orphtrash to root/.orphtrash/bunch/of/dirs
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
            return grep { !-d or lc ne $trashDirName } @_; # skip trash
        },
        wanted => sub {
            if (-d and (/^(\d\d\d\d)-(\d\d)-(\d\d)\b/
                or /^(\d\d)-(\d\d)-(\d\d)\b/
                or /^(\d\d)(\d\d)(\d\d)\b/)) {

                my $y = $1 < 20 ? $1 + 2000 : $1 < 100 ? $1 + 1900 : $1;
                push @{$keyToPaths{"$y-$2-$3"}}, File::Spec->rel2abs($_);
            }
        }
    }, File::Spec->curdir());
    #while (my ($key, $paths) = each %keyToPaths) {
    for my $key (sort keys %keyToPaths) {
        my $paths = $keyToPaths{$key};
        if (@$paths > 1) {
            print "$key:\n";
            print "\t$_\n" for @$paths;
        }
    }
}

# API ==========================================================================
# Execute find-dupe-files verb
sub doFindDupeFiles {
    my ($byName, $autoDiff, $defaultLastAction, @globPatterns) = @_;
    my $dupeGroups = buildFindDupeFilesDupeGroups($byName, @globPatterns);
    my $lastCommand = '';
    DUPEGROUP: for (my $dupeGroupsIdx = 0; $dupeGroupsIdx < @$dupeGroups; $dupeGroupsIdx++) {
        print "\n";
        while (1) {
            my $group = $dupeGroups->[$dupeGroupsIdx];
            populateFindDupeFilesDupeGroup($group);
            # Auto command is what happens without any user input
            my $command = generateFindDupeFilesAutoAction($group);
            # Default command is what happens if you hit enter with an empty string
            # (ignored if there's an auto command).
            my $defaultCommand = $defaultLastAction ? $lastCommand : undef;
            
            # Main heading for group
            my $prompt = "Resolving duplicate group @{[$dupeGroupsIdx + 1]} " .
                         "of @{[scalar @$dupeGroups]}\n";
            $prompt .= buildFindDupeFilesPrompt($group, $defaultCommand);
            doMetadataDiff(0, map { $_->{fullPath} } @$group) if $autoDiff;
            # Prompt for command(s)
            if ($command) {
                print $prompt, $command, "\n";
            } else {
                until ($command) {
                    print $prompt, "\a";
                    chomp($command = <STDIN>);
                    if ($command) {
                        # If the user provided something, save that for next 
                        # conflict's default (the next DUPEGROUP)
                        $lastCommand = $command;
                    } elsif ($defaultCommand) {
                        $command = $defaultCommand;
                    }
                }
            }
            my $usage = <<"EOM";
?   Help: shows this help message
c   Continue: go to the next group
d   Diff: perform metadata diff of this group
o#  Open Number: open the specified item
q   Quit: exit the application
t#  Trash Number: move the specified item to $trashDirName
EOM
            # Process the command(s)
            my $itemCount = @$group;
            for (split /;/, $command) {
                if ($_ eq '?') {
                    print $usage;
                } elsif ($_ eq 'c') {
                    next DUPEGROUP;
                } elsif ($_ eq 'd') {
                    doMetadataDiff(0, map { $_->{fullPath} } @$group);
                } elsif (/^f(\d+)$/) {
                    if ($1 > $#$group) {
                        warn "$1 is out of range [0, $#$group]";
                    } elsif (!defined $group->[$1]) {
                        warn "$1 has already been trashed";
                    } elsif ($^O eq 'MSWin32') {
                        system("explorer.exe /select,\"$group->[$1]->{fullPath}\"");
                    } elsif ($^O eq 'darwin') {
                        system("open -R \"$group->[$1]->{fullPath}\"");
                    } else {
                        warn "Don't know how to open a folder on $^O\n";
                    }
                } elsif (/^m(\d+(?:,\d+)+)$/) {
                    doAppendMetadata(map { $group->[$_]->{fullPath} } split ',', $1);
                } elsif (/^o(\d+)$/) {
                    if ($1 > $#$group) {
                        warn "$1 is out of range [0, $#$group]";
                    } elsif (!defined $group->[$1]) {
                        warn "$1 has already been trashed";
                    } else {
                        system("open \"$group->[$1]->{fullPath}\"");
                    }
                } elsif ($_ eq 'q') {
                    exit 0;
                } elsif (/^t(\d+)$/) {
                    if ($1 > $#$group) {
                        warn "$1 is out of range [0, $#$group]";
                    } elsif (!defined $group->[$1]) {
                        warn "$1 has already been trashed";
                    } else {
                        if ($group->[$1]->{exists}) {
                            trashPathAndSidecars($group->[$1]->{fullPath});
                        } else {
                            trashMd5Info($group->[$1]->{fullPath});
                        }
                        $group->[$1] = undef;
                        $itemCount--;
                        # TODO: rather than maintaining itemCount, maybe just
                        # dynmically calc: (scalar grep { defined $_ } @$group)
                        (scalar grep { defined $_ } @$group) == $itemCount
                            or die "Programmer Error: bad itemCount calc";
                        next DUPEGROUP if $itemCount < 2;
                    }
                } else {
                    warn "Unrecognized command: '$_'";
                    print $usage;
                }
            } 
        } # while (1)
    } # DUPEGROUP
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
# Builds a list of dupe groups where each group is a list of hashes that
# initially only contain the fullPath. Lists are sorted descending by 
# importance. So the return will be of the form:
#   [
#       [ 
#           { fullPath => '/first/group/first.file' },
#           { fullPath => '/first/group/second.file' }
#       ],
#       [
#           { fullPath => '/second/group/first.file' },
#           { fullPath => '/second/group/second.file' }
#       ]
#   ]
# In addition to fullPath, a cachedMd5Info property may be added if
# available.
sub buildFindDupeFilesDupeGroups {
    my ($byName, @globPatterns) = @_;
    # Create the initial groups in various ways with key that is opaque
    # and ignored from the outside
    my %keyToFullPathList = ();
    if ($byName) {
        # Hash key based on file/dir name
        traverseFiles(
            undef, # isDirWanted
            undef, # isFileWanted
            sub {  # callback
                my ($fullPath, $rootFullPath) = @_;
                if (-f $fullPath) {
                    my $key = computeFindDupeFilesHashKeyByName($fullPath);
                    push @{$keyToFullPathList{$key}}, { fullPath => $fullPath };
                }
            },
            @globPatterns);
    } else {
        # Hash key is MD5
        findMd5s(
            undef, # isDirWanted
            undef, # isFileWanted
            sub {  # callback
                my ($fullPath, $md5Info) = @_;
                push @{$keyToFullPathList{$md5Info->{md5}}}, 
                    { fullPath => $fullPath, cachedMd5Info => $md5Info };
            }, 
            @globPatterns);
    }
    trace(View::VERBOSITY_ALL, "Found @{[scalar keys %keyToFullPathList]} initial groups");
    # Go through each element in the %keyToFullPathList map, and we'll 
    # want the ones with multiple things in the array of paths. If
    # there  are multiple paths for an element, sort the paths array
    # by decreasing importance (our best guess), and add it to the
    # @dupes collection for further processing.
    my @dupes = ();
    my $fileCount = 0;
    while (my ($key, $fullPathList) = each %keyToFullPathList) {
        $fileCount += @$fullPathList;
        if (@$fullPathList > 1) {
            my @group = sort { 
                comparePathWithExtOrder($a->{fullPath}, $b->{fullPath}) 
            } @$fullPathList;
            push @dupes, \@group;
        }
    }
    # The 2nd level is properly sorted, now let's sort the groups
    # themselves - this will be the order in which the groups
    # are processed, so we want it extorder based as well.
    @dupes = sort { 
        comparePathWithExtOrder($a->[0]->{fullPath}, $b->[0]->{fullPath}) 
    } @dupes;
    trace(View::VERBOSITY_LOW, "Found $fileCount files and @{[scalar @dupes]} groups of duplicate files");
    return \@dupes;
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
# Adds the following properties to a group created by 
# buildFindDupeFilesDupeGroups:
#   exists: cached result of -e check
#   md5Info: Md5Info data
#   dateTaken: a DateTime value obtained via getDateTaken
#   matches: array of MATCH_* values of comparison with other group elements
sub populateFindDupeFilesDupeGroup {
    my ($group) = @_;
    my $fast = 0; # avoid slow operations, potentially with less precision?
    @$group = grep { defined $_ } @$group;
    for my $elt (@$group) {
        $elt->{exists} = -e $elt->{fullPath};
        if ($fast or !$elt->{exists}) {
            delete $elt->{md5Info};
            delete $elt->{dateTaken};
        } else {
            $elt->{md5Info} = resolveMd5Info($elt->{fullPath}, 0, 0,
                exists $elt->{md5Info} ? $elt->{md5Info} : $elt->{cachedMd5Info});
            $elt->{dateTaken} = getDateTaken($elt->{fullPath});
        }
        $elt->{sidecars} = $elt->{exists} ? [getSidecarPaths($elt->{fullPath})] : [];
    }
    for (my $i = 0; $i < @$group; $i++) {
        $group->[$i]->{matches}->[$i] = MATCH_FULL;
        my ($iFullMd5, $iContentMd5) = @{$group->[$i]->{md5Info}}{qw(full_md5 md5)};
        for (my $j = $i + 1; $j < @$group; $j++) {
            my ($jFullMd5, $jContentMd5) = @{$group->[$j]->{md5Info}}{qw(full_md5 md5)};
            my $matchType = MATCH_UNKNOWN;
            if ($iFullMd5 and $jFullMd5) {
                if ($iFullMd5 eq $jFullMd5) {
                    $matchType = MATCH_FULL;
                } else {
                    $matchType = MATCH_NONE;
                }
            }
            if ($matchType != MATCH_FULL) {
                if ($iContentMd5 and $jContentMd5) {
                    if ($iContentMd5 eq $jContentMd5) {
                        $matchType = MATCH_CONTENT;
                    } else {
                        $matchType = MATCH_NONE;
                    }
                }
            }
            $group->[$i]->{matches}->[$j] = $matchType;
            $group->[$j]->{matches}->[$i] = $matchType;
        }
    }
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
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
    # 3. Directory info
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
                $dirKey =  "$1$2$3;";
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

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
# Computes zero or more commands that should be auto executed for the
# provided fully populated group. 
sub generateFindDupeFilesAutoAction {
    my ($group) = @_;
    my @autoCommands = ();
    # Figure out what's trashable, starting by excluding missing files
    my @remainingIdx = grep { $group->[$_]->{exists} } (0..$#$group);
    filterIndicies($group, \@remainingIdx, sub {
        # Don't auto trash things with sidecars
        return 1 if @{$_->{sidecars}};
        $_->{fullPath} !~ /[\/\\]ToImport[\/\\]/
    });
    if (@remainingIdx > 1 &&
        all { $_ eq MATCH_FULL } @{$group->[$remainingIdx[0]]->{matches}}[@remainingIdx]) {
        # We have several things left that are all exact matches with no sidecars
        filterIndicies($group, \@remainingIdx, sub {
            # Don't auto trash things with sidecars
            return 1 if @{$_->{sidecars}};
            # Discard versions of files in folder with wrong date
            my $date = $_->{dateTaken};
            if ($date) {
                if ($_->{fullPath} =~ /(\d{4})-(\d\d)-(\d\d).*[\/\\]/) {
                    if ($1 == $date->year && $2 == $date->month && $3 == $date->day) {
                         # Date is in the path
                         return 1;
                    } else {
                        # A different date is in the path
                        return 0;
                    }
                } else {
                    # Path doesn't have date in it
                    return 0;
                }
            } else {
                # Item has no date
                return 0;
            }
        });
        # Discard -2, -3 versions of files
        filterIndicies($group, \@remainingIdx, sub {
            # Don't auto trash things with sidecars
            return 1 if @{$_->{sidecars}};
            for ($_->{fullPath}) {
                return 0 if /-\d+\.\w+$/;
                return 0 if /\s\(\d+\)\.\w+$/;
            }
            return 1;
        });
    }
    # Now take everything that isn't in @reminingIdx and suggest trash it
    my @isTrashable = map { 1 } (0..$#$group);
    $isTrashable[$_] = 0 for @remainingIdx;
    for (my $i = 0; $i < @$group; $i++) {
        push @autoCommands, "t$i" if $isTrashable[$i];
    }
    # If it's a short mov file next to a jpg or heic that's an iPhone,
    # then it's probably the live video portion from a burst shot. We
    # should just continue
    my $isShortMovieSidecar = sub {
        my ($basename, $ext) = splitExt($_->{fullPath});
        return 0 if defined $ext and lc $ext ne 'mov';
        return 0 unless exists $_->{md5Info} and exists $_->{md5Info}->{size};
        my $altSize = -s catExt($basename, 'heic');
        $altSize = -s catExt($basename, 'jpg') unless defined $altSize;
        return 0 unless defined $altSize;
        return 2 * $altSize >= $_->{md5Info}->{size};
    };
    if (all { $isShortMovieSidecar->() } @{$group}[@remainingIdx]) {
        push @autoCommands, 'c';
    }
    # Appending continue command will auto skip to the next for full auto mode
    #push @autoCommands, 'c';
    return join ';', @autoCommands;
}

# ------------------------------------------------------------------------------
# generateFindDupeFilesAutoAction helper subroutine
sub filterIndicies {
    my ($dataArrayRef, $indiciesArrayRef, $predicate) = @_;
    my @idx = grep { 
        local $_ = $dataArrayRef->[$_];
        #print "Filtering $_->{fullPath}... ";
        my $result = $predicate->();
        #print $result ? "Yes\n" : "No\n";
        $result
     } @$indiciesArrayRef;
    @$indiciesArrayRef = @idx if @idx;
}

# ------------------------------------------------------------------------------
# doFindDupeFiles helper subroutine
sub buildFindDupeFilesPrompt {
    my ($group, $defaultCommand) = @_;
    # Build base of prompt - indexed paths
    my @prompt = ();
    # The list of all files in the group
    my @paths = map { prettyPath($_->{fullPath}) } @$group;
    # Start by building the header row, the formats for other rows follows this
    # Matches
    my $delim = ' ';
    push @prompt, ' ' x @$group, $delim;
    # Index
    my $indexFormat = "\%@{[length $#$group]}s.";
    push @prompt, sprintf($indexFormat, '#'), $delim;
    # Filename
    my $lengthBeforePath = length join '', @prompt;
    my $maxPathLength = max(64 - $lengthBeforePath, map { length } @paths);
    my $pathFormat = "\%-${maxPathLength}s";
    push @prompt, sprintf($pathFormat, 'File name' . ('_' x ($maxPathLength - 9))), $delim;
    # Metadata
    my $metadataFormat = "|$delim%-19s$delim|$delim%-19s$delim|$delim%s";
    push @prompt, sprintf($metadataFormat, 'Taken______________', 'Modified___________', 'Size');
    push @prompt, "\n";
    for (my $i = 0; $i < @$group; $i++) {
        my $elt = $group->[$i];
        my $path = $paths[$i];
        # Matches
        for my $matchType (@{$elt->{matches}}) {
            if ($matchType == MATCH_FULL) {
                push @prompt, Term::ANSIColor::colored('F', 'black on_green');
            } elsif ($matchType == MATCH_CONTENT) {
                push @prompt, Term::ANSIColor::colored('C', 'black on_yellow');
            } elsif ($matchType == MATCH_NONE) {
                push @prompt, Term::ANSIColor::colored('X', 'black on_red');
            } else {
                push @prompt, '?';
            }
        }
        push @prompt, $delim;
        # Index
        push @prompt, coloredByIndex(sprintf($indexFormat, $i), $i), $delim;
        # Filename
        push @prompt, coloredByIndex(sprintf($pathFormat, $path), $i), $delim;
        # Metadata
        my ($mtime, $size);
        if (my $md5Info = $elt->{md5Info}) {
            $mtime = $md5Info->{mtime};
            $size = $md5Info->{size};
        }
        my $dateTaken = $elt->{dateTaken} ? $elt->{dateTaken}->strftime('%F %T') : '?';
        $mtime = $mtime ? POSIX::strftime('%F %T', localtime $mtime) : '?';
        $size = $size ? Number::Bytes::Human::format_bytes($size) : '?';
        push @prompt, sprintf($metadataFormat, $dateTaken, $mtime, $size);
        # Missing warning
        unless ($elt->{exists}) {
            push @prompt, $delim, Term::ANSIColor::colored(
                '[MISSING]', 'bold red on_white');
        }
        # Wrong dir warning
        if ($elt->{dateTaken}) {
            my ($vol, $dir, $filename) = File::Spec->splitpath($elt->{fullPath});
            my $parentDir = List::Util::first { $_ } reverse File::Spec->splitdir($dir);
            if ($parentDir =~ /^(\d{4})-(\d\d)-(\d\d)/) {
                if ($1 != $elt->{dateTaken}->year ||
                    $2 != $elt->{dateTaken}->month ||
                    $3 != $elt->{dateTaken}->day) {
                    push @prompt, $delim, Term::ANSIColor::colored(
                        '[WRONG DIR]', 'bold red on_white');
                }
            }
        }
        push @prompt, "\n";
        # Collect all sidecars and add to prompt
        for (@{$elt->{sidecars}}) {
            push @prompt, 
                ' ' x $lengthBeforePath, 
                coloredByIndex(coloredBold(prettyPath($_)), $i), 
                "\n";
        }
    }
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

# API ==========================================================================
# Execute metadata-diff verb
sub doMetadataDiff {
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
            my $message = $items[$i]->{$key} || coloredFaint('undef');
            if ($i == 0) {
                print coloredBold($key), '.' x ($indentLen - length $key);
            } else {
                print ' ' x $indentLen;
            }
            print coloredByIndex($message, $i), "\n";
        }
    }
}

# API ==========================================================================
# Execute remove-empties verb
sub doRemoveEmpties {
    my (@globPatterns) = @_;
    # Map from directory absolute path to sub-item count
    my %dirSubItemsMap = ();
    traverseFiles(
        undef, # isDirWanted
        sub {  # isFileWanted
            my ($fullPath, $rootFullPath, $filename) = @_;
            # These files don't count - they're trashible, ignore them (by 
            # not processing) as if they didn't exist and let them get
            # cleaned up if the folder gets trashed
            my $lcfn = lc $filename;
            return 0 if any { $lcfn eq $_ } ('.ds_store', 'thumbs.db', $md5Filename);
            # TODO: exclude zero byte or hidden files as well?
            return 1; # Other files count
        },
        sub {  # callback 
            my ($fullPath, $rootFullPath) = @_;
            if (-d $fullPath) {
                # at this point, all the sub-items should be processed, see how many
                my $subItemCount = $dirSubItemsMap{$fullPath};
                # As part of a later verification check, we'll remove this dir
                # from our map. Then if other sub-items are added after we process
                # this parent dir right now, then we could have accidentally trashed
                # a non-trashable dir. 
                delete $dirSubItemsMap{$fullPath};
                # If this dir is empty, then we'll want to trash it and have the
                # parent dir ignore it like trashable files (e.g. $md5Filename). If
                # it's not trashable, then fall through to add this to its parent
                # dir's list (to prevent the parent from being trashed).
                unless ($subItemCount) {
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
# Execute purge-md5 verb
sub doPurgeMd5 {
    my (@globPatterns) = @_;
    # Note that this is O(N^2) because it was easier to reuse already
    # written and tested code (especially on the error paths and atomic-ness).
    # To make this O(N) we'd want to unroll the findMd5s method, in the loop
    # over all the keys just move the apprpriate Md5Info to a temp hash, do a
    # single append of the collected Md5Info to .orphtrash/.orphdat (similar 
    # to appendMd5Files), and then write back out the pruned .orphdat.
    findMd5s(
        undef, # isDirWanted
        sub { # isFileWanted
            return 1; # skip all filters for this
        },
        sub {  #callback
            my ($fullPath, $md5Info) = @_;
            trashMd5Info($fullPath) unless -e $fullPath;
        }, @globPatterns);
}

# API ==========================================================================
# Execute restore-trash verb
sub doRestoreTrash {
    my (@globPatterns) = @_;
    traverseFiles(
        sub {  # isDirWanted
            return 1;
        },
        sub {  # isFileWanted
            return 0;
        },
        sub {  # callback
            my ($fullPath, $rootFullPath) = @_;
            my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
            if (lc $filename eq $trashDirName) {
                movePath($fullPath, combinePath($vol, $dir));
            }
        },
        @globPatterns);
    }

# API ==========================================================================
# EXPERIMENTAL
# Execute test verb - usually just a playground for testing and new ideas
sub doTest {
    # Prints JSON representation of ISOBMFF file
    for my $mediaPath (@_) {
        print "$mediaPath:\n";
        my $fh = openOrDie('<:raw', $mediaPath);
        my $ftyp = readIsobmffFtyp($mediaPath, $fh);
        my $bmff = { b_ftyp => $ftyp };
        parseIsobmffBox($mediaPath, $fh, $bmff);
        print JSON->new->allow_nonref->pretty->canonical->encode($bmff);
    }
}

# API ==========================================================================
# Execute verify-md5 verb
sub doVerifyMd5 {
    my (@globPatterns) = @_;
    # TODO: this verification code is really old, based on V0 Md5File (back when
    # it was actually a plain text file), before the check-md5 verb (when it was
    # add/verify twostep), and predates any source history (back when we were all
    # using Source Depot and couldn't easily set up a repo for a new codebase).
    # Before the git and json wave took over MS and well before Mac compat, c2007?
    # Can we delete it, rewrite it, or combine-with/reuse resolveMd5Info? I haven't
    # used add-md5 or verify-md5 for many years at this point - the only marginal
    # value is that it can be better at finding orphaned Md5Info data.
    my $all = 0;
    findMd5s(
        undef, # isDirWanted
        undef, # isFileWanted
        sub {  #callback
            my ($fullPath, $md5Info) = @_;
            if (-e $fullPath) {
                # File exists
                my $expectedMd5 = $md5Info->{md5};
                my $actualMd5 = calculateMd5Info($fullPath)->{md5};
                if ($actualMd5 eq $expectedMd5) {
                    # Hash match
                    print "Verified MD5 for '@{[prettyPath($fullPath)]}'\n";
                } else {
                    # Has MIS-match, needs input
                    warn "ERROR: MD5 mismatch for '@{[prettyPath($fullPath)]}' ($actualMd5 != $expectedMd5)";
                    unless ($all) {
                        while (1) {
                            print "Ignore, ignore All, Quit (i/a/q)? ", "\a";
                            chomp(my $in = <STDIN>);
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
                # TODO: prompt to see if we should remove this via deleteMd5Info
                warn "Missing file: '@{[prettyPath($fullPath)]}'";
            }
        }, @globPatterns);
}

# MODEL ------------------------------------------------------------------------
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

# When dealing with MD5 related data, we have these naming conventions:
# MediaPath..The path to the media file for which MD5 data is calculated (not
#            just path as to differentiate from Md5Path).
# Md5Path....The path to the file which contains Md5Info data for media
#            items in that folder which is serialized to/from a Md5Set.
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
# This high level MD5 method is used to retrieve, calculate, verify, and cache
# Md5Info for a file. It is the primary method to get MD5 data for a file.
#
# The default behavior is to try to lookup the Md5Info from caches and return
# that value if up to date. If there's a cache miss or the cache is stale (i.e.
# the file has been modified since the last time this was called), the new
# Md5Info is calculated, verified, and the cache updated.
#
# Returns the current Md5Info for the file, or undef if
#   a) the MD5 can't be computed (e.g. can't open the file to hash it)
#   b) there's a conflict and the user chooses to skip resolving (for now)
#
# The default behavior explained above is altered by parameters:
#
# addOnly:
#   When this mode is true it causes the method to exit early if *any* cached
#   info is available whether it is up to date or not. If that cached Md5Info
#   is available, the MediaFile is not accessed, the MD5 is not computed, and 
#   the cached value is returned without any verification. Note that if a 
#   cachedMd5Info parameter is provided, this method will always simply return
#   that value.
#
# cachedMd5Info:
#   Caller supplied cached Md5Info value that this method will check to see
#   if it is up to date and return that value if so (in the same way and
#   together with the other caches). This is useful for ensuring Md5Info is up
#   to date even if operations have taken place since originally retrieved.
sub resolveMd5Info {
    my ($mediaPath, $addOnly, $forceRecalc, $cachedMd5Info) = @_;
    # First try to get suitable Md5Info from various cache locations
    # without opening or hashing the MediaFile
    my ($md5Path, $md5Key) = getMd5PathAndMd5Key($mediaPath);
    my $newMd5InfoBase = makeMd5InfoBase($mediaPath);
    if (!$forceRecalc and 
        canUseCachedMd5InfoForBase($mediaPath, $addOnly, $cachedMd5Info, $newMd5InfoBase)) {
        # Caller supplied cached Md5Info is up to date
        return { %{Storable::dclone($cachedMd5Info)}, %$newMd5InfoBase };
    }
    if (!$forceRecalc and 
        $md5Path eq $cachedMd5Path and
        canUseCachedMd5InfoForBase($mediaPath, $addOnly, $cachedMd5Set->{$md5Key}, $newMd5InfoBase)) {
        # memory cache of Md5Info is up to date
        return { %{Storable::dclone($cachedMd5Set->{$md5Key})}, %$newMd5InfoBase };
    }
    my ($md5File, $md5Set) = readOrCreateNewMd5File($md5Path);
    my $oldMd5Info = $md5Set->{$md5Key};
    if (!$forceRecalc and 
        canUseCachedMd5InfoForBase($mediaPath, $addOnly, $oldMd5Info, $newMd5InfoBase)) {
        # Md5File cache of Md5Info is up to date
        return { %$oldMd5Info, %$newMd5InfoBase };
    }
    # No suitable cache, so fill in/finalize the Md5Info that we'll return
    my $newMd5Info;
    eval {
        # TODO: consolidate opening file multiple times from stat and calculateMd5Info
        $newMd5Info = { %{calculateMd5Info($mediaPath)}, %$newMd5InfoBase };
    };
    if (my $error = $@) {
        # TODO: for now, skip but we'll want something better in the future
        warn Term::ANSIColor::colored("UNAVAILABLE MD5 for '@{[prettyPath($mediaPath)]}' with error:", 'red'), "\n\t$error\n";
        return undef; # Can't get the MD5
    }
    # Do verification on the old persisted Md5Info and the new calculated Md5Info
    if (defined $oldMd5Info) {
        if ($oldMd5Info->{md5} eq $newMd5Info->{md5}) {
            # Matches last recorded hash, but still continue and call
            # setMd5InfoAndWriteMd5File to handle other bookkeeping
            # to ensure we get a cache hit and short-circuit next time.
            print Term::ANSIColor::colored("Verified MD5 for '@{[prettyPath($mediaPath)]}'", 'green'), "\n";
        } elsif ($oldMd5Info->{full_md5} eq $newMd5Info->{full_md5}) {
            # Full MD5 match and content mismatch. This should only be
            # expected when we change how to calculate content MD5s.
            # If that's the case (i.e. the expected version is not up to
            # date), then we should just update the MD5s. If it's not the
            # case, then it's unexpected and some kind of programer error.
            if (isMd5InfoVersionUpToDate($mediaPath, $oldMd5Info->{version})) {
                die <<"EOM";
Unexpected state: full MD5 match and content MD5 mismatch for
$mediaPath
             version  full_md5                          md5
  Expected:  $oldMd5Info->{version}        $oldMd5Info->{full_md5}  $oldMd5Info->{md5}
    Actual:  $newMd5Info->{version}        $newMd5Info->{full_md5}  $newMd5Info->{md5}
EOM
            } else {
                trace(View::VERBOSITY_MEDIUM, "Content MD5 calculation has changed, upgrading from version ",
                      "$oldMd5Info->{version} to $newMd5Info->{version} for '$mediaPath'");
            }
        } else {
            # Mismatch and we can update MD5, needs resolving...
            # TODO: This doesn't belong here in the model, it should be moved
            warn Term::ANSIColor::colored("MISMATCH OF MD5 for '@{[prettyPath($mediaPath)]}'", 'red'), 
                 " [$oldMd5Info->{md5} vs $newMd5Info->{md5}]\n";
            while (1) {
                print <<"EOM", "i/o/s/q? ", "\a"; 
[I]gnore changes and used cached value
[O]verwrite cached value with new data
[S]kip using either conflicting value
[Q]uit
EOM
                chomp(my $in = <STDIN>);
                if ($in eq 'i') {
                    # Ignore newMd5Info, so we don't want to return that. Return
                    # what is/was in the cache.
                    return { %$oldMd5Info, %$newMd5InfoBase };
                } elsif ($in eq 'o') {
                    last;
                } elsif ($in eq 's') {
                    return undef;
                } elsif ($in eq 'q') {
                    exit 0;
                } else {
                    warn "Unrecognized command: '$in'";
                }
            }
        }
    }
    setMd5InfoAndWriteMd5File($mediaPath, $newMd5Info, $md5Path, $md5Key, $md5File, $md5Set);
    return $newMd5Info;
}

# MODEL (MD5) ------------------------------------------------------------------
# For each item in each per-directory database file in [globPatterns], 
# invoke [callback] passing it full path and MD5 hash as arguments like
#      callback($fullPath, $md5)
sub findMd5s {
    my ($isDirWanted, $isFileWanted, $callback, @globPatterns) = @_;
    $isFileWanted = \&defaultIsFileWanted unless $isFileWanted;
    trace(View::VERBOSITY_ALL, 'findMd5s(...); with @globPatterns of', 
          (@globPatterns ? map { "\n\t'$_'" } @globPatterns : ' (current dir)'));
    traverseFiles(
        $isDirWanted,
        sub {  # isFileWanted
            my ($fullPath, $rootFullPath, $filename) = @_;
            return (lc $filename eq $md5Filename); # only process Md5File files
        },
        sub {  # callback
            my ($fullPath, $rootFullPath) = @_;
            if (-f $fullPath) {
                my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
                my (undef, $md5Set) = readMd5File('<:crlf', $fullPath);
                for my $md5Key (sort { $md5Set->{$a}->{filename} cmp $md5Set->{$b}->{filename} } keys %$md5Set) {
                    my $md5Info = $md5Set->{$md5Key};
                    my $otherFilename = $md5Info->{filename};
                    my $otherFullPath = changeFilename($fullPath, $otherFilename);
                    if ($isFileWanted->($otherFullPath, $rootFullPath, $otherFilename)) {
                        $callback->($otherFullPath, $md5Info);
                    }
                }
            }
        },
        @globPatterns);
}

# MODEL (MD5) ------------------------------------------------------------------
# Gets the Md5Path, Md5Key for a MediaPath.
sub getMd5PathAndMd5Key {
    my ($mediaPath) = @_;
    my ($md5Path, $md5Key) = changeFilename($mediaPath, $md5Filename);
    return ($md5Path, lc $md5Key);
}

# MODEL (MD5) ------------------------------------------------------------------
# Stores Md5Info for a MediaPath. If the the provided data is undef, removes
# existing information via deleteMd5Info. Returns the previous Md5Info
# value if it existed (or undef if not).
sub writeMd5Info {
    my ($mediaPath, $newMd5Info) = @_;
    trace(View::VERBOSITY_ALL, "writeMd5Info('$mediaPath', {...});");
    if ($newMd5Info) {
        my ($md5Path, $md5Key) = getMd5PathAndMd5Key($mediaPath);
        my ($md5File, $md5Set) = readOrCreateNewMd5File($md5Path);
        return setMd5InfoAndWriteMd5File($mediaPath, $newMd5Info, $md5Path, $md5Key, $md5File, $md5Set);
    } else {
        return deleteMd5Info($mediaPath);
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Moves a Md5Info for a file from one directory's storage to another. 
sub moveMd5Info {
    my ($oldMediaPath, $newMediaPath) = @_;
    trace(View::VERBOSITY_ALL, "moveMd5Info('$oldMediaPath', " . 
                         (defined $newMediaPath ? "'$newMediaPath'" : 'undef') . ");");
    my ($oldMd5Path, $oldMd5Key) = getMd5PathAndMd5Key($oldMediaPath);
    unless (-e $oldMd5Path) {
        trace(View::VERBOSITY_ALL, "Can't move/remove Md5Info for '$oldMd5Key' from missing '$oldMd5Path'"); 
        return undef;
    }
    my ($oldMd5File, $oldMd5Set) = readMd5File('+<:crlf', $oldMd5Path);
    unless (exists $oldMd5Set->{$oldMd5Key}) {
        trace(View::VERBOSITY_ALL, "Can't move/remove missing Md5Info for '$oldMd5Key' from '$oldMd5Path'");
        return undef;
    }
    # For a move we do a copy then a delete, but show it as a single CRUD
    # operation. The logging info will be built up during the copy phase
    # and then logged after deleting.
    my ($crudOp, $crudMessage);
    my $oldMd5Info = $oldMd5Set->{$oldMd5Key};
    if ($newMediaPath) {
        my (undef, undef, $newFilename) = File::Spec->splitpath($newMediaPath);
        my $newMd5Info = { %$oldMd5Info, filename => $newFilename };
        # The code for the remainder of this scope is very similar to 
        #   writeMd5Info($newMediaPath, $newMd5Info);
        # but with additional cases considered and improved context in traces
        my ($newMd5Path, $newMd5Key) = getMd5PathAndMd5Key($newMediaPath);
        ($oldMd5Path ne $newMd5Path) or die "Not yet supported";
        my ($newMd5File, $newMd5Set) = readOrCreateNewMd5File($newMd5Path);
        # The code for the remainder of this scope is very similar to 
        #   setMd5InfoAndWriteMd5File($newMediaPath, $newMd5Info, $newMd5Path, $newMd5Key, $newMd5File, $newMd5Set);
        # but with additional cases considered and improved context in traces
        my $existingMd5Info = $newMd5Set->{$newMd5Key};
        if ($existingMd5Info and Data::Compare::Compare($existingMd5Info, $newMd5Info)) {
            # Existing Md5Info at target is identical, so target is up to date already
            $crudOp = View::CRUD_DELETE;
            $crudMessage = "Removed MD5 for '@{[prettyPath($oldMediaPath)]}' (up to date " .
                           "MD5 already exists for '@{[prettyPath($newMediaPath)]}')";
        } else {
            $newMd5Set->{$newMd5Key} = $newMd5Info;
            trace(View::VERBOSITY_MEDIUM, "Writing '$newMd5Path' after moving MD5 for '$newMd5Key'");
            writeMd5File($newMd5Path, $newMd5File, $newMd5Set);
            $crudOp = View::CRUD_UPDATE;
            $crudMessage = "Moved MD5 for   '@{[prettyPath($oldMediaPath)]}' to '@{[prettyPath($newMediaPath)]}'";
            if (defined $existingMd5Info) {
                $crudMessage = "$crudMessage overwriting existing value";
            }
        }
    } else {
        # No new media path, this is a delete only
        $crudOp = View::CRUD_DELETE;
        $crudMessage = "Removed MD5 for '@{[prettyPath($oldMediaPath)]}'";
    }
    # TODO: Should this if/else code move to writeMd5File/setMd5InfoAndWriteMd5File such
    #       that any time someone tries to write an empty hashref, it deletes the file?
    delete $oldMd5Set->{$oldMd5Key};
    if (%$oldMd5Set) {
        trace(View::VERBOSITY_MEDIUM, "Writing '$oldMd5Path' after removing MD5 for '$oldMd5Key'");
        writeMd5File($oldMd5Path, $oldMd5File, $oldMd5Set);
        printCrud($crudOp, $crudMessage, "\n");
    } else {
        # Empty files create trouble down the line (especially with move-merges)
        trace(View::VERBOSITY_MEDIUM, "Deleting '$oldMd5Path' after removing MD5 for '$oldMd5Key' (the last one)");
        close($oldMd5File);
        unlink($oldMd5Path) or die "Couldn't delete '$oldMd5Path': $!";
        printCrud($crudOp, $crudMessage, "\n");
        printCrud(View::CRUD_DELETE, "Deleted empty   '@{[prettyPath($oldMd5Path)]}'\n");
    }
    return $oldMd5Info;
}

# MODEL (MD5) ------------------------------------------------------------------
# Moves Md5Info for a MediaPath to local trash. Returns the previous Md5Info
# value if it existed (or undef if not).
sub trashMd5Info {
    my ($mediaPath) = @_;
    trace(View::VERBOSITY_ALL, "trashMd5Info('$mediaPath');");
    my $trashPath = getTrashPathFor($mediaPath);
    ensureParentDirExists($trashPath);
    return moveMd5Info($mediaPath, $trashPath);
}

# MODEL (MD5) ------------------------------------------------------------------
# Removes Md5Info for a MediaPath from storage. Returns the previous Md5Info
# value if it existed (or undef if not).
sub deleteMd5Info {
    my ($mediaPath) = @_;
    trace(View::VERBOSITY_ALL, "deleteMd5Info('$mediaPath');");
    return moveMd5Info($mediaPath);
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
        while (my ($md5Key, $sourceMd5Info) = each %$sourceMd5Set) {
            if (exists $targetMd5Set->{$md5Key}) {
                my $targetMd5Info = $targetMd5Set->{$md5Key};
                Data::Compare::Compare($sourceMd5Info, $targetMd5Info) or die
                    "Can't append MD5 info from '$sourceMd5Path' to '$targetMd5Path'" .
                    " due to key collision for '$md5Key'";
            } else {
                $targetMd5Set->{$md5Key} = $sourceMd5Info;
                $dirty = 1;
            }
        }
    }
    if ($dirty) {
        trace(View::VERBOSITY_MEDIUM, "Writing '$targetMd5Path' after appending data from ",
              scalar @sourceMd5Paths, " files");
        writeMd5File($targetMd5Path, $targetMd5File, $targetMd5Set);
        my $itemsAdded = (scalar keys %$targetMd5Set) - $oldTargetMd5SetCount;
        printCrud(View::CRUD_CREATE, "Added $itemsAdded MD5s to '${\prettyPath($targetMd5Path)}' from ",
                  join ', ', map { "'${\prettyPath($_)}'" } @sourceMd5Paths);
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# This is a utility for updating Md5Info. It opens the Md5Path R/W and parses
# it. Returns the Md5File and Md5Set.
sub readOrCreateNewMd5File {
    my ($md5Path) = @_;
    trace(View::VERBOSITY_ALL, "readOrCreateNewMd5File('$md5Path');");
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
    trace(View::VERBOSITY_MEDIUM, "readMd5File('$openMode', '$md5Path');");
    # TODO: Should we validate filename is $md5Filename or do we care?
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
    my $md5Set = {};
    if ($useJson) {
        $md5Set = JSON::decode_json(join '', <$md5File>);
        # TODO: Consider validating parsed content - do a lc on
        #       filename/md5s/whatever, and verify vs $md5DigestPattern???
        # If there's no version data, then it is version 1. We didn't
        # start storing version information until version 2.
        while (my ($key, $values) = each %$md5Set) {
            # Populate missing values so we don't have to handle sparse data everywhere
            $values->{version} = 1 unless exists $values->{version};
            $values->{filename} = $key unless exists $values->{filename};
        }
    } else {
        # Parse as simple "name: md5" text
        for (<$md5File>) {
            /^([^:]+):\s*($md5DigestPattern)$/ or die "Unexpected line in '$md5Path': $_";
            # We use version 0 here for the very old way before we went to
            # JSON when we added more info than just the full file MD5
            my $fullMd5 = lc $2;
            $md5Set->{lc $1} = { version => 0, filename => $1, 
                                 md5 => $fullMd5, full_md5 => $fullMd5 };
        }
    }
    updateMd5FileCache($md5Path, $md5Set);
    printCrud(View::CRUD_READ, "Read MD5s from  '@{[prettyPath($md5Path)]}'\n");
    return ($md5File, $md5Set);
}

# MODEL (MD5) ------------------------------------------------------------------
# Lower level helper routine that updates a MD5 info, and writes it to the file
# if necessary. The $md5File and $md5Set params should be the existing data
# (like is returned from readOrCreateNewMd5File or readMd5File). The md5Key and
# newMd5Info represent the new data. Returns the previous md5Info value. 
sub setMd5InfoAndWriteMd5File {
    my ($mediaPath, $newMd5Info, $md5Path, $md5Key, $md5File, $md5Set) = @_;
    # TODO: Should we validate filename is $md5Filename or do we care?
    my $oldMd5Info = $md5Set->{$md5Key};
    unless ($oldMd5Info and Data::Compare::Compare($oldMd5Info, $newMd5Info)) {
        $md5Set->{$md5Key} = $newMd5Info;
        trace(View::VERBOSITY_MEDIUM, "Writing '$md5Path' after setting MD5 for '$md5Key'");
        writeMd5File($md5Path, $md5File, $md5Set);
        if (defined $oldMd5Info) {
            printCrud(View::CRUD_UPDATE, "Updated MD5 for '@{[prettyPath($mediaPath)]}'\n");
        } else {
            printCrud(View::CRUD_CREATE, "Added MD5 for   '@{[prettyPath($mediaPath)]}'\n");
        }
    }
    return $oldMd5Info;
}

# MODEL (MD5) ------------------------------------------------------------------
# Lowest level helper routine to serialize OM into a file handle.
# Caller is expected to printCrud with more context if this method returns
# successfully.
sub writeMd5File {
    my ($md5Path, $md5File, $md5Set) = @_;
    # TODO: write this out as UTF8 using :encoding(UTF-8):crlf (or :utf8:crlf?)
    #       and writing out the "\x{FEFF}" BOM. Not sure how to do that in
    #       a fully cross compatable way (older file versions as well as
    #       Windows/Mac compat)
    # TODO: Should we validate filename is $md5Filename or do we care?
    trace(View::VERBOSITY_ALL, 'writeMd5File(<..>, { hash of @{[ scalar keys %$md5Set ]} items });');
    seek($md5File, 0, 0) or die "Couldn't reset seek on file: $!";
    truncate($md5File, 0) or die "Couldn't truncate file: $!";
    if (%$md5Set) {
        print $md5File JSON->new->allow_nonref->pretty->canonical->encode($md5Set);
    } else {
        warn "Writing empty data to $md5Path";
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
# or added to the results of calculateMd5Info to produce
# a full md5Info.
#   filename:   the filename (only) of the path
#   size:       size of the file in bytes
#   mtime:      the mtime of the file
sub makeMd5InfoBase {
    my ($mediaPath) = @_;
    my $stats = File::stat::stat($mediaPath) or die "Couldn't stat '$mediaPath': $!";
    my (undef, undef, $filename) = File::Spec->splitpath($mediaPath);
    return { filename => $filename, size => $stats->size, mtime => $stats->mtime };
}

# MODEL (MD5) ------------------------------------------------------------------
# Returns true if the cached full Md5Info can be used for the specified
# base-only Md5Info without bothering to calculateMd5Info. 
sub canUseCachedMd5InfoForBase {
    my ($mediaPath, $addOnly, $cachedMd5Info, $currentMd5InfoBase) = @_;
    #trace(View::VERBOSITY_ALL, 'canUseCachedMd5InfoForBase(...);');
    if (defined $cachedMd5Info) {
        if ($addOnly) {
            trace(View::VERBOSITY_ALL, "Skipping MD5 recalculation for '$mediaPath' (add-only mode)");
            return 1;
        }
        if (defined $cachedMd5Info->{size} and 
            defined $cachedMd5Info->{mtime} and 
            lc $currentMd5InfoBase->{filename} eq lc $cachedMd5Info->{filename} and
            isMd5InfoVersionUpToDate($mediaPath, $cachedMd5Info->{version}) and
            $currentMd5InfoBase->{size} == $cachedMd5Info->{size} and
            $currentMd5InfoBase->{mtime} == $cachedMd5Info->{mtime}) {
            trace(View::VERBOSITY_ALL, "Skipping MD5 recalculation for '$mediaPath' (same size/date-modified)");
            return 1;
        }
    }
    return 0;
}

# MODEL (MD5) ------------------------------------------------------------------
# The data returned by calculateMd5Info is versioned, but not all version 
# changes are meaningful for every type of file. This method determines if
# the provided version is equivalent to the current version for the specified
# file type.
sub isMd5InfoVersionUpToDate {
    my ($mediaPath, $version) = @_;
    #trace(View::VERBOSITY_ALL, "isMd5InfoVersionUpToDate('$mediaPath', $version);");
    my $type = getMimeType($mediaPath);
    if ($type eq 'image/heic') {
        return ($version >= 6) ? 1 : 0; # unchanged since V5
    } elsif ($type eq 'image/jpeg') {
        return ($version >= 1) ? 1 : 0; # unchanged since V1
    } elsif ($type eq 'video/mp4v-es') {
        return ($version >= 2) ? 1 : 0; # unchanged since V2
    } elsif ($type eq 'image/png') {
        return ($version >= 3) ? 1 : 0; # unchanged since V3
    } elsif ($type eq 'video/quicktime') {
        return ($version >= 4) ? 1 : 0; # unchanged since V4
    } elsif ($type eq 'image/tiff') {
        # TODO
    }
    # This type just does whole file MD5 (the original implementation)
    return 1;
}

# MODEL (MD5) ------------------------------------------------------------------
# Calculates and returns the MD5 digest(s) of a file.
# Returns these properties as a hashref which when combined with 
# makeMd5InfoBase comprise a full Md5Info):
#   version:  $calculateMd5InfoVersion
#   md5:      primary MD5 comparison (excludes volitile data from calculation)
#   full_md5: full MD5 calculation for exact match
sub calculateMd5Info {
    my ($mediaPath) = @_;
    trace(View::VERBOSITY_MEDIUM, "getMd5('$mediaPath');");
    #!!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE
    #!!!   $calculateMd5InfoVersion should be incremented whenever the output
    #!!!   of this method changes in such a way that old values need to be 
    #!!!   recalculated, and isMd5InfoVersionUpToDate should be updated accordingly.
    #!!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE
    const my $calculateMd5InfoVersion => 6;
    my $fh = openOrDie('<:raw', $mediaPath);
    my $fullMd5Hash = getMd5Digest($mediaPath, $fh);
    seek($fh, 0, 0) or die "Failed to reset seek for '$mediaPath': $!";
    # If we fail to generate a partial match, just warn and use the full file
    # MD5 rather than letting the exception loose and just skipping the file.
    my $partialMd5Hash = undef;
    eval {
        my $type = getMimeType($mediaPath);
        if ($type eq 'image/heic') {
            $partialMd5Hash = getHeicContentMd5($mediaPath, $fh);
        } elsif ($type eq 'image/jpeg') {
            $partialMd5Hash = getJpgContentMd5($mediaPath, $fh);
        } elsif ($type eq 'video/mp4v-es') {
            $partialMd5Hash = getMp4ContentMd5($mediaPath, $fh);
        } elsif ($type eq 'image/png') {
            $partialMd5Hash = getPngContentMd5($mediaPath, $fh);
        } elsif ($type eq 'video/quicktime') {
            $partialMd5Hash = getMovContentMd5($mediaPath, $fh);
        } elsif ($type eq 'image/tiff') {
            # TODO
        }
    };
    if (my $error = $@) {
        # Can't get the partial MD5, so we'll just use the full hash
        warn "Unavailable content MD5 for '@{[prettyPath($mediaPath)]}' with error:\n\t$error\n";
    }
    printCrud(View::CRUD_READ, "Computed MD5 of '@{[prettyPath($mediaPath)]}'",
              ($partialMd5Hash ? ", including content only hash" : ''), "\n");
    return {
        version => $calculateMd5InfoVersion,
        md5 => $partialMd5Hash || $fullMd5Hash,
        full_md5 => $fullMd5Hash,
    };
}

# MODEL (MD5) ------------------------------------------------------------------
# Gets the mime type from a path
sub getMimeType {
    my ($mediaPath) = @_;
    # If the file is a backup (has some "bak"/"original" suffix), 
    # we want to consider the real extension
    $mediaPath =~ s/$backupSuffix$//;
    my ($basename, $ext) = splitExt($mediaPath);
    return getFileTypeInfo($ext, 'MIMETYPE') || '';
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# The ISO/IEC Base Media File Format (ISOBMFF) is a container format that was
# adopted from QuickTime and is used by: MP4 (.mp4, .m4a, .m4p, .m4b, .m4r,
# .m4v), .3gp, .3g2, .mj2, .dvb, .dcf, .m21, .f4v, HEIF (.heif, .heifs, .heic,
# .heics, .avci, .avcs, .avif, .avifs). It entails a series of nested boxes
# starting with "ftyp".
# 
# This function takes a file handle with seek position at the start of a
# box, reads the header, sets the seek to the start of data, and returns
# a hashref containing:
#
# __begin_pos : non-negative integer specifying the seek position of the start
#       of the box which is the same as the seek of the file handle when
#       passed to this method
# __data_pos : positive integer specifying the seek position of the
#       beginning of the data
# __data_size : non-negative integer specifying the size of the box's data
#       in bytes, or missing if there's no end (i.e. continues to end of
#       parent container)
# __end_pos : positive integer specifying the seek position immediately
#       following the box, or missing if there's no end (i.e. continues to
#       the end of its parent container)
# __type : FourCC string specifying the box type
#
# Here the '__' prefix is used for box header data. Fields within the data
# of the box are intended to have the 'f_' prefix (e.g. f_version), and
# child boxes with the 'b_' prefix (e.g. b_hdlr).
sub readIsobmffBoxHeader {
    my ($mediaPath, $fh) = @_;
    my $startPos = tell($fh);
    read($fh, my $fileData, 8) or die
        "Failed to read ISOBMFF box header from '$mediaPath' at $startPos: $!";
    my ($boxSize, $type) = unpack('Na4', $fileData);
    my $headerSize = 8;
    if ($boxSize == 1) {
        # 1 means it's 64 bit size
        read($fh, $fileData, 8) or die
            "Failed to read ISOBMFF box extended size from '$mediaPath': $!";
        $boxSize = unpack('Q>', $fileData);
        $headerSize += 8;
    }
    my %box = (
        __type => $type,
        __begin_pos => $startPos,
        __data_pos => $startPos + $headerSize );
    # Box size of zero means that it goes to the EOF in which case
    # we don't have a data size or end of box position either
    if ($boxSize != 0) {
        $boxSize >= $headerSize or die 
            "Bad size for ISOBMFF box '$type': $boxSize";
        # Note that any of these can be computed from the other, so
        # only one is necessary, but all are added for convinence
        %box = ( %box,
            __data_size => $boxSize - $headerSize,
            __end_pos => $startPos + $boxSize );
    }
    return \%box;
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Reads the File Type Box (ftyp) which should be the first box in an
# ISOBMFF file. The returns a hashref with the general box header data
# from readIsobmffBoxHeader as well as:
#
# major_brand : string specifying the best use of the file, e.g. "qt" or "heic"
# minor_version : the integer version of major_brand
# compatible_brands : array of strings specifying other brands that the
#       file is compliant with
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub readIsobmffFtyp {
    my ($mediaPath, $fh) = @_;
    my $box = readIsobmffBoxHeader($mediaPath, $fh);
    $box->{__type} eq 'ftyp' or die
        "box type was not ftyp as expected: $box->{type}";
    my $size = $box->{__data_size};
    $size >= 8 && ($size % 4) == 0 or die
        "ftyp box data was unexpected size $size";
    read($fh, my $fileData, $size) or die
        "failed to read ISOBMFF box data from '$mediaPath': $!";
    my ($majorBrand, $minorVersion, @compatibleBrands) = unpack('a4N(a4)*', $fileData);
    return { %$box,
        f_major_brand => $majorBrand,
        f_minor_version => $minorVersion,
        f_compatible_brands => \@compatibleBrands };
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Gets a short name for a box suitable for adding context alongside a filename
# for diagnostics such as traces and die statements.
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub getIsobmffBoxDiagName {
    my ($mediaPath, $box) = @_;
    return sprintf "'%s' %s@[0x%08x-0x%08x)", $mediaPath, @{$box}{qw(__type __begin_pos __end_pos)};
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Helper routine for parseIsobmffBox to read and interpret ISOBMFF box data
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub unpackIsobmffBoxData {
    my ($mediaPath, $fh, $box, $format, $size) = @_;
    my $pos = tell($fh);
    $box->{__data_pos} <= $pos or die 
        "seek position $pos is before start of box data in " . getIsobmffBoxDiagName($mediaPath, $box);
    if (exists $box->{__data_size}) {
        my $maxRead = $box->{__data_pos} + $box->{__data_size} - $pos;
        if (defined $size) {
            $size <= $maxRead or die
                "can't read $size bytes at $pos from " . getIsobmffBoxDiagName($mediaPath, $box) . ": only $maxRead bytes left in box";
        } else {
            $size = $maxRead;
        }
    } elsif (!defined $size) {
        # i'm not sure we need to handle this case
        die "don't (yet) know how to do sizeless read and unpack in unbounded box for " . getIsobmffBoxDiagName($mediaPath, $box);
    }
    my $bytesRead = read($fh, my $fileData, $size);
    defined $bytesRead and $bytesRead == $size or die
        "failed to read $size bytes at $pos from " . getIsobmffBoxDiagName($mediaPath, $box) . ": $!";
    return unpack($format, $fileData);
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Helper routine for parseIsobmffBox that parses ISOBMFF box data version
# and flags which come at the beginning of "full" boxes' data.
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub readIsobmffBoxVersionAndFlags {
    my ($mediaPath, $fh, $box, $maxSupportedVersion) = @_;
    my ($version, @flagsBytes) = unpackIsobmffBoxData($mediaPath, $fh, $box, 'C4', 4);
    my $flags = $flagsBytes[0] << 16 | $flagsBytes[1] << 8 | $flagsBytes[2];
    $box->{f_version} = $version;
    $box->{f_flags} = $flags;
    !defined $maxSupportedVersion or $version <= $maxSupportedVersion or die
        "unsupported version $version for " . getIsobmffBoxDiagName($mediaPath, $box);
    return ($version, $flags);
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Helper routine for parseIsobmffBox that parses a series of children
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub parseIsobmffBoxChildren {
    my ($mediaPath, $fh, $parent, $count, $parseChildBox) = @_;
    $parseChildBox = \&parseIsobmffBox unless $parseChildBox;
    my @childrenArray = ();
    my %childrenHash = ();
    while ((!defined $count) || ($count-- > 0)) {
        # Deserialize and verify header
        my $child = readIsobmffBoxHeader($mediaPath, $fh);
        if (exists $child->{__end_pos}) {
            !defined $parent->{__end_pos} or $child->{__end_pos} <= $parent->{__end_pos} or die
                "box extended past parent end ($parent->{__end_pos}) for " . getIsobmffBoxDiagName($mediaPath, $child);
        } elsif (exists $parent->{__end_pos}) {
            $child->{__end_pos} = $parent->{__end_pos};
        }
        # Deserialize data
        $parseChildBox->($mediaPath, $fh, $child);
        push @childrenArray, $child;
        push @{$childrenHash{$child->{__type}}}, $child;
        # Advance to next box or terminate loop
        last unless exists $child->{__end_pos};
        seek($fh, $child->{__end_pos}, 0) or die 
            "failed to seek to $child->{__end_pos} for " . getIsobmffBoxDiagName($mediaPath, $child) . ": $!";
        if (exists $parent->{__end_pos}) {
            last if $child->{__end_pos} >= $parent->{__end_pos};
        } else {
            last if eof($fh);
        }
    }
    $count and die 
        "failed to read all child boxes, $count still remain for" . getIsobmffBoxDiagName($mediaPath, $parent);
    # TODO - let caller specify whether to use by type hash and/or by array?
    $parent->{b} = \@childrenArray;
    while (my ($k, $v) = each %childrenHash) {
        $parent->{"b_$k"} = (@$v == 1) ? $v->[0] : $v;
    }
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Deserialize an ISOBMFF file and creates data structure representation
#
# mediaPath : the path to the file being deserialized, mostly for use in
#       error messages and diagnostics
# fh : an open readable file handle with seek set to the beginning of the
#       first box to be processed
# box : the parent container to put the results (a tree of boxes with 
#       properties and child boxes); on the first call this should be
#       an empty hashref that serves as sort of header node
#
# Usage:
#       my $fh = openOrDie('<:raw', $mediaPath);
#       my $ftyp = readIsobmffFtyp($mediaPath, $fh);
#       # (Add verification of $ftyp's brand/version here.)
#       my $bmff = { b_ftyp => $ftyp };
#       parseIsobmffBox($mediaPath, $fh, $bmff);
#       # (Process box data here, e.g. get the primary's 'ifde' box.)
#       my $id = $bmff->{b_meta}->{b_pitm}->{f_item_id};
#       my ($infe) = grep { $_->{f_item_id} == $id } @{$bmff->{b_meta}->{b_iinf}->{b_infe}};
#
# NB: this does not work for QTFF (i.e. .mov) because the format of
# data are not identical between boxes in each - for example 'meta'
# contains version/flags in ISOBMFF but not QTFF.
sub parseIsobmffBox {
    my ($mediaPath, $fh, $box) = @_;
    # By default when reading child boxes we just recurisvely process
    # but some boxes might need to customize reading of their children
    # with some extra context based logic. So they can override this:
    my $processChildBox = sub {
        my ($child) = @_;
        parseIsobmffBox($mediaPath, $fh, $child);
    };
    unless (my $type = $box->{__type}) {
        parseIsobmffBoxChildren($mediaPath, $fh, $box);
    } elsif ($type eq 'dinf') { # -------------------- Data Information --- dinf
        parseIsobmffBoxChildren($mediaPath, $fh, $box);
    } elsif ($type eq 'dref') { # ---------------------- Data Reference --- dref
        readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 0);
        parseIsobmffBoxChildren($mediaPath, $fh, $box, unpackIsobmffBoxData($mediaPath, $fh, $box, 'N', 4));
    } elsif ($type eq 'hdlr') { # ------------------- Handler Reference --- hdlr
        readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 0);
        @{$box}{qw(f_handler_type)} = unpackIsobmffBoxData($mediaPath, $fh, $box, 'x4a4', 8);
    } elsif ($type eq 'idat') { # --------------------------- Item Data --- idat
        # This blob of data can be referenced if iloc's construction_method is
        # idat_offset (1). There's no pre-structured data to be parsed.
    } elsif ($type eq 'iinf') { # -------------------- Item Information --- iinf
        readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 0);
        parseIsobmffBoxChildren($mediaPath, $fh, $box, unpackIsobmffBoxData($mediaPath, $fh, $box, 'n', 2));
    } elsif ($type eq 'iloc') { # ----------------------- Item Location --- iloc
        # The fields offset_size, length_size, base_offset_size, index_size,
        # item_count, and extent_count are intermediate values only used to 
        # parse other values within this box and so provide little use other
        # than distraction and overhead if retained
        my ($version, $flags) = readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 2);
        my @values = unpackIsobmffBoxData($mediaPath, $fh, $box, 'C2', 2);
        my $offsetSize = $values[0] >> 4;
        my $lengthSize = $values[0] & 0xf;
        my $baseOffsetSize = $values[1] >> 4;
        my $indexSize = 0;
        if ($version == 1 or $version == 2) {
            $indexSize = $values[1] & 0xf;
        }
        my $itemCount = 0;
        if ($version < 2) {
            $itemCount = unpackIsobmffBoxData($mediaPath, $fh, $box, 'n', 2);
        } elsif ($version == 2) {
            $itemCount  = unpackIsobmffBoxData($mediaPath, $fh, $box, 'N', 4);
        }
        my $readIntegerSized = sub {
            my ($byteSize) = @_;
            if ($byteSize == 0) {
                return 0;
            } elsif ($byteSize == 4) {
                return (unpackIsobmffBoxData($mediaPath, $fh, $box, 'N', 4))[0];
            } elsif ($byteSize == 8) {
                return (unpackIsobmffBoxData($mediaPath, $fh, $box, 'Q>', 8))[0];
            } else {
                die "unexpected integer size $byteSize for " . getIsobmffBoxDiagName($mediaPath, $box);
            }
        };
        my @items = ();
        for (my $i = 0; $i < $itemCount; $i++) {
            my %item = ();
            if ($version < 2) {
                @item{qw(item_id)} = unpackIsobmffBoxData($mediaPath, $fh, $box, 'n', 2);
            } elsif ($version == 2) {
                @item{qw(item_id)} = unpackIsobmffBoxData($mediaPath, $fh, $box, 'N', 4);
            }
            if ($version == 1 or $version == 2) {
                @item{qw(construction_method)} = unpackIsobmffBoxData($mediaPath, $fh, $box, 'n', 2);
            }
            @item{qw(data_reference_index)} = unpackIsobmffBoxData($mediaPath, $fh, $box, 'n', 2);
            $item{base_offset} = $readIntegerSized->($baseOffsetSize);
            my $extentCount = unpackIsobmffBoxData($mediaPath, $fh, $box, 'n', 2);
            my @extents = ();
            for (my $j = 0; $j < $extentCount; $j++) {
                my %extent = ();
                $extent{extent_index} = $readIntegerSized->($indexSize) if $indexSize;
                $extent{extent_offset} = $readIntegerSized->($offsetSize);
                $extent{extent_length} = $readIntegerSized->($lengthSize);
                push @extents, \%extent;
            }
            $item{extents} = \@extents;
            push @items, \%item;
        }
        $box->{f_items} = \@items;
    } elsif ($type eq 'infe') { # --------------------- Item Info Entry --- infe
        my ($version, $flags) = readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 3);
        if ($version < 2) {
            @{$box}{qw(f_item_id f_item_protection_index f_item_name f_content_type f_content_encoding)} =
                unpackIsobmffBoxData($mediaPath, $fh, $box, 'nnZ*Z*Z*');
        } else {
            @{$box}{qw(f_item_id f_item_protection_index f_item_type)} = ($version == 2)
                ? unpackIsobmffBoxData($mediaPath, $fh, $box, 'nna4', 8)
                : unpackIsobmffBoxData($mediaPath, $fh, $box, 'Nna4', 10);
            if ($box->{f_item_type} eq 'mime') {
                @{$box}{qw(f_item_name f_content_type f_content_encoding)} = 
                    unpackIsobmffBoxData($mediaPath, $fh, $box, 'Z*Z*Z*');
            } elsif ($box->{f_item_type} eq 'uri ') {
                @{$box}{qw(f_item_name f_item_uri_type)} = 
                    unpackIsobmffBoxData($mediaPath, $fh, $box, 'Z*Z*');
            } else {
                @{$box}{qw(f_item_name)} = unpackIsobmffBoxData($mediaPath, $fh, $box, 'Z*');
            }
        }
    } elsif ($type eq 'iprp') { # --------------------- Item Properties --- iprp
        # TODO - I can't find documentation for this, skip for now
    } elsif ($type eq 'iref') { # ---------------------- Item Reference --- iref
        my ($version, $flags) = readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 1);
        my $idFormat = ($version == 0) ? 'n': 'N';
        parseIsobmffBoxChildren($mediaPath, $fh, $box, undef, sub {
            my ($mediaPath, $fh, $child) = @_;
            my @values = unpackIsobmffBoxData($mediaPath, $fh, $child, "$idFormat n/$idFormat");
            $child->{f_from_item_id} = shift @values;
            $child->{f_to_item_id} = [ @values ];
        });
    } elsif ($type eq 'mdat') { # -------------------------- Media Data --- mdat
        # This blob of data is referenced elsewhere (e.g. iloc) and has no
        # pre-structured data to be parsed.
    } elsif ($type eq 'meta') { # ---------------------------- Metadata --- meta
        # TODO - it seems like Apple QTFF (ftyp->major_brand = 'qt  ') 'meta' 
        # atom is missing version/flags and ISO BMFF 'meta' box has version/flags? 
        readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 0);
        parseIsobmffBoxChildren($mediaPath, $fh, $box);
    } elsif ($type eq 'moov') { # ------------------------------- Movie --- moov
        parseIsobmffBoxChildren($mediaPath, $fh, $box);
    } elsif ($type eq 'pitm') { # ------------------------ Primary Item --- pitm
        readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 0);
        @{$box}{qw(f_item_id)} = unpackIsobmffBoxData($mediaPath, $fh, $box, 'n', 2);
    } elsif ($type eq 'url ') { # ----------------------- Data Entry Url --- url 
        readIsobmffBoxVersionAndFlags($mediaPath, $fh, $box, 0);
        # TODO - Then optional string?
        #$box->{f_location} = 
    } elsif ($type ne 'free' and $type ne 'skip' and $type ne 'wide') {
        # free, skip, wide are just ignorable padding
        print STDERR "Unknown box type '$type' for ", getIsobmffBoxDiagName($mediaPath, $box), "\n";
    }
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Given a deserialized ISOBMFF file and a set of item IDs, looks up the
# direct and indirect references in the meta/iref box to build a set of
# all referenced item IDs.
#
# NB: this does not work for QTFF
sub resolveIsobmffIref {
    my ($bmff) = shift;
    my %refs = ();
    my $irefs = $bmff->{b_meta}->{b_iref}->{b};
    for (my @queue = grep { $refs{$_}++ == 0 } @_; @queue > 0;) {
        my $itemId = shift @queue;
        for (grep { $_->{f_from_item_id} == $itemId } @$irefs) {
            push @queue, grep { $refs{$_}++ == 0 } @{$_->{f_to_item_id}};
        }
    }
    return sort { $a <=> $b } map { $_+0 } keys %refs;
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Gets an ordered list of pos/size data that specifies the data ranges
# for the primary data item.
#
# NB: this does not work for QTFF
sub getIsobmffPrimaryDataExtents {
    my ($mediaPath, $bmff) = @_;
    # Get the primary ID (from meta/pitm) and lookup all IDs that it
    # references (using meta/iref), and loop over all the extents for
    # those IDs (using meta/iloc's items).
    my @extents = ();
    my $iloc = $bmff->{b_meta}->{b_iloc};
    for my $id (resolveIsobmffIref($bmff, $bmff->{b_meta}->{b_pitm}->{f_item_id})) {
        for my $item (grep { $id == $_->{item_id} } @{$iloc->{f_items}}) {
            $item->{data_reference_index} == 0 or die
                "only iloc data_reference_index of 'this file' (0) is currently supported for " . 
                getIsobmffBoxDiagName($mediaPath, $iloc);
            my $method = $item->{construction_method};
            if ($method == 0) { # 0 is 'file_offset'
                for (@{$item->{extents}}) {
                    my $pos = $item->{base_offset} + $_->{extent_offset};
                    my $size = $_->{extent_length};
                    # TODO - verify this is inside of mdat?
                    push @extents, { pos => $pos, size => $size };
                }
            } elsif ($method == 1) { # 1 is 'idat_offset'
                my $idat = $bmff->{b_meta}->{b_idat};
                my $baseOffset = $idat->{__data_pos} + $item->{base_offset};
                for (@{$item->{extents}}) {
                    my $pos = $baseOffset + $_->{extent_offset};
                    my $size = $_->{extent_length};
                    ($idat->{__data_pos} <= $pos && 
                     $pos + $size <= $idat->{__data_pos} + $idat->{__data_size}) or die
                        "extent range of pos=$pos, size=$size out of idat bounds " .
                        "pos=$idat->{__data_pos}, size=$idat->{__data_size} for  " . 
                        getIsobmffBoxDiagName($mediaPath, $iloc);
                    push @extents, { pos => $pos, size => $size };
                }
            } else {
                die "only iloc construction_method of file_offset (0) or idat_offset (0) " .
                    "currently supported for " . getIsobmffBoxDiagName($mediaPath, $iloc);
            }
        }
    }
    # Join contiguous spans of extents, but don't do anything fancy with
    # overlapping things or reordering to force joins - we want it to be
    # as identical to original as possible
    for (my $i = 1; $i < @extents; $i++) {
        my ($x, $y) = @extents[$i - 1, $i];
        if ($x->{pos} + $x->{size} == $y->{pos}) {
            $x->{size} += $y->{size};
            splice @extents, $i--, 1;
        }
    }
    return @extents;
}

# MODEL (ISOBMFF, MD5) ---------------------------------------------------------
# Reads a file as if it were an ISOBMFF file of the specified brand,
# and returns the MD5 digest of the data in the mdat box.
sub getIsobmffMdatMd5 {
    my ($mediaPath, $fh) = @_;
    my $ftyp = readIsobmffFtyp($mediaPath, $fh);
    my $majorBrand = $ftyp->{f_major_brand};
    # 'isom' means the first version of ISO Base Media, and is not supposed to
    # ever be a major brand, but it happens. Try to handle a little bit.
    if ($majorBrand eq 'isom') {
        my @compatible = grep { $_ ne 'isom' } @{$ftyp->{f_compatible_brands}};
        $majorBrand = $compatible[0] if @compatible == 1;
    } 
    # This works for both Apple QTFF and ISO BMFF (i.e. mov, mp4, heic)
    unless (any { $majorBrand eq $_ } ('mp41', 'mp42', 'qt  ', 'heic')) {
        my $brand = "'$ftyp->{f_major_brand}'";
        if (@{$ftyp->{f_compatible_brands}}) {
            $brand = $brand . ' (\'' . join('\', \'', @{$ftyp->{f_compatible_brands}}) . '\')';
        }
        die "unexpected brand $brand for " . getIsobmffBoxDiagName($mediaPath, $ftyp);
    }
    until (eof($fh)) {
        my $box = readIsobmffBoxHeader($mediaPath, $fh);
        if ($box->{__type} eq 'mdat') {
            return getMd5Digest($mediaPath, $fh, $box->{__data_size});
        }
        last unless exists $box->{__end_pos};
        seek($fh, $box->{__end_pos}, 0) or die 
            "failed to seek '$mediaPath' to $box->{__end_pos}: $!";
    }
    return undef;
}

# MODEL (ISOBMFF, MD5) ---------------------------------------------------------
sub getIsobmffPrimaryItemDataMd5 {
    my ($mediaPath, $fh) = @_;
    my $ftyp = readIsobmffFtyp($mediaPath, $fh);
    # This only works for ISO BMFF, not Apple QTFF (i.e. mp3, heic)
    any { $ftyp->{f_major_brand} eq $_ } ('mp41', 'mp42', 'heic') or die
        "unexpected brand for " . getIsobmffBoxDiagName($mediaPath, $ftyp);
    my $bmff = { b_ftyp => $ftyp };
    parseIsobmffBox($mediaPath, $fh, $bmff);
    my $md5 = new Digest::MD5;
    for (getIsobmffPrimaryDataExtents($mediaPath, $bmff)) {
        seek($fh, $_->{pos}, 0) or die 
            "Failed to seek '$mediaPath' to $_->{pos}: $!";
        addToMd5Digest($md5, $mediaPath, $fh, $_->{size});
    }
    return resolveMd5Digest($md5);
}
    
# MODEL (MD5) ------------------------------------------------------------------
sub getHeicContentMd5 {
    return getIsobmffPrimaryItemDataMd5(@_);
}

# MODEL (MD5) ------------------------------------------------------------------
# If JPEG, skip metadata which may change and only hash pixel data
# and hash from Start of Scan [SOS] to end of file
sub getJpgContentMd5 {
    my ($mediaPath, $fh) = @_;
    # Read Start of Image [SOI]
    read($fh, my $fileData, 2) or die "Failed to read JPEG SOI from '$mediaPath': $!";
    my ($soi) = unpack('n', $fileData);
    $soi == 0xffd8 or die "File didn't start with JPEG SOI marker: '$mediaPath'";
    # Read blobs until SOS
    my $tags = '';
    while (1) {
        read($fh, my $fileData, 4) or die
            "Failed to read JPEG tag header from '$mediaPath' at @{[tell $fh]} after $tags: $!";
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
sub getMovContentMd5 {
    return getIsobmffMdatMd5(@_);
}

# MODEL (MD5) ------------------------------------------------------------------
sub getMp4ContentMd5 {
    return getIsobmffMdatMd5(@_);
}

# MODEL (MD5) ------------------------------------------------------------------
sub getPngContentMd5 {
    my ($mediaPath, $fh) = @_;
    read($fh, my $fileData, 8) or die "Failed to read PNG header from '$mediaPath': $!";
    my @actualHeader = unpack('C8', $fileData);
    my @pngHeader = ( 137, 80, 78, 71, 13, 10, 26, 10 );
    Data::Compare::Compare(\@actualHeader, \@pngHeader) or die
        "File didn't start with PNG header: '$mediaPath'";
    my $md5 = new Digest::MD5;
    while (!eof($fh)) {
        # Read chunk header
        read($fh, $fileData, 8) or die
            "Failed to read PNG chunk header from '$mediaPath' at @{[tell $fh]}: $!";
        my ($size, $type) = unpack('Na4', $fileData);
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
    unless (defined $size) {
        $md5->addfile($fh);
    } else {
        # There's no addfile with a size limit, so we roll our own
        # by reading in chunks and adding one at a time (since $size
        # might be huge and we don't want to read it all into memory)
        my $chunkSize = 1024;
        for (my $remaining = $size; $remaining > 0; $remaining -= $chunkSize) {
            my $readSize = $chunkSize < $remaining ? $chunkSize : $remaining;
            read($fh, my $fileData, $readSize)
                or die "Failed to read $readSize bytes from '$mediaPath' at @{[tell $fh]}: $!";
            $md5->add($fileData);
        }
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Extracts, verifies, and canonicalizes resulting MD5 digest
# final result from a Digest::MD5.
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
        # and return the paths to the other types which exist
        my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
        my ($basename, $ext) = splitExt($filename);
        my @sidecars = @{getFileTypeInfo($ext, 'SIDECARS') || []};
        @sidecars = map { combinePath($vol, $dir, catExt($basename, $_)) } @sidecars;
        return grep { -e } @sidecars;
    }
}

# MODEL (Metadata) -------------------------------------------------------------
# Gets the date the media was captured by parsing the file (and potentially
# sidecars) as DateTime
#
# Note on caching this value: this can change if this or any sidecars change,
# so make sure it is invalidated when sidecars are as well.
sub getDateTaken {
    my ($path, $excludeSidecars) = @_;
    my $dateTaken;
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
        my $info = readMetadata($path, $excludeSidecars, 
                                { DateFormat => '%FT%T%z' }, \@tags);
        for my $tag (@tags) {
            $dateTaken = $info->{$tag} and last if exists $info->{$tag};
        }
    };
    if (my $error = $@) {
        warn "Unavailable date taken for '@{[prettyPath($path)]}' with error:\n\t$error\n";
    }
    return $dateTaken ? DateTime::Format::HTTP->parse_datetime($dateTaken) : undef;
}

# MODEL (Metadata) -------------------------------------------------------------
# Read metadata as an ExifTool hash for the specified path (and any
# XMP sidecar when appropriate). Similar in use to Image::ExifTool::ImageInfo
# except for the new $excludeSidecars param and stricter argument order.
sub readMetadata {
    my ($path, $excludeSidecars, @exifToolArgs) = @_;
    my $et = extractInfo($path, undef, @exifToolArgs);
    my $info = $et->GetInfo(@exifToolArgs);
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
                $et = extractInfo($xmpPath, $et, @exifToolArgs);
                $info = { %{$et->GetInfo(@exifToolArgs)}, %$info };
            }
        }
    }
    #my $keys = $et->GetTagList($info);
    return $info;
}

# MODEL (Metadata) -------------------------------------------------------------
# Wrapper for Image::ExifTool::ExtractInfo with error handling
sub extractInfo {
    my ($path, $et, @exifToolArgs) = @_;
    unless ($et) {
        $et = new Image::ExifTool;
        # We do ISO 8601 dates by default
        $et->Options(DateFormat => '%FT%T%z');
    }
    trace(View::VERBOSITY_MEDIUM, "Image::ExifTool::ExtractInfo('$path');");
    $et->ExtractInfo($path, @exifToolArgs) or die
        "Couldn't ExtractInfo for '$path': " . $et->GetValue('Error');
    printCrud(View::CRUD_READ, "Extract meta of '@{[prettyPath($path)]}'");
    return $et;
}

# MODEL (Path Operations) ------------------------------------------------------
# Gets the local trash location for the specified path: the same filename
# in the .orphtrash subdirectory.
sub getTrashPathFor {
    my ($fullPath) = @_;
    my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
    my $trashDir = File::Spec->catdir($dir, $trashDirName);
    return combinePath($vol, $trashDir, $filename);
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
    my $c = lc ($basenameA || '') cmp lc ($basenameB || '');
    return $c if $c;
    # Next by extorder
    my $extOrderA = getFileTypeInfo($extA, 'EXTORDER') || 0;
    my $extOrderB = getFileTypeInfo($extB, 'EXTORDER') || 0;
    $c = $extOrderA <=> $extOrderB;
    return $c if $c;
    # And then just the extension as a string
    return lc ($extA || '') cmp lc ($extB || '');
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
# The inverse of splitExt, this combines a basename and extension into a
# filename.
sub catExt {
    my ($basename, $ext) = @_;
    if ($ext) {
        return $basename ? "$basename.$ext" : ".$ext";
    } else {
        return $basename;
    }
}

# MODEL (Path Operations) ------------------------------------------------------
# Splits the filename into basename and extension. (Both without a dot.) It
# is usually used like the following example
#       my ($vol, $dir, $filename) = File::Spec->splitpath($path);
#       my ($basename, $ext) = splitExt($filename);
sub splitExt {
    my ($path) = @_;
    my ($basename, $ext) = $path =~ /^(.*)\.([^.]*)/;
    # TODO: handle case without extension - if no re match then just return ($path, '')
    return ($basename, $ext);
}

# MODEL (File Operations) ------------------------------------------------------
# Default behavior if isDirWanted is undefined for traverseFiles
sub defaultIsDirWanted {
    my ($fullPath, $rootFullPath, $filename) = @_;
    return (lc $filename ne $trashDirName);
}

# MODEL (File Operations) ------------------------------------------------------
# Default behavior if isDirWanted is undefined for traverseFiles
sub defaultIsFileWanted {
    my ($fullPath, $rootFullPath, $filename) = @_;
    return (lc $filename ne $md5Filename and $filename =~ /$filenameFilter/);
}

main();
1;

__END__

Commands to regenerate documentation:
  cpanm Pod::Markdown
  pod2markdown OrganizePhotos.pl > README.md

=head1 NAME

OrganizePhotos - utilities for managing a collection of photos/videos

=head1 SYNOPSIS

    OrganizePhotos -h
    OrganizePhotos check-md5|c5 [--add-only] [glob patterns...]
    OrganizePhotos checkup|c [--add-only] [--auto-diff|-d] [--by-name|-n]
        [--no-default-last-action] [glob patterns...]
    OrganizePhotos collect-trash|ct [glob patterns...]
    OrganizePhotos find-dupe-files|fdf [--auto-diff|-d] [--by-name|-n]
        [--no-default-last-action] [glob-patterns...]
    OrganizePhotos metadata-diff|md [--exclude-sidecars|-x] [glob-patterns...]
    OrganizePhotos purge-md5|p5 [glob-patterns...]
    OrganizePhotos remove-empties|re [glob-patterns...]
    OrganizePhotos restore-trash|rt [glob-patterns...]

=head1 DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

Metadata this program needs to persist are stored in database files in
the same directory as the files that data was generated for. If they 
are separated, the metadata will no longer be associated and the separated
media files will be treated as new. The expectation is that if files move,
the per-directory database file is also moved or copied.

Metadata operations are powered by L<C<Image::ExifTool>>.

The calling pattern for each command follows the pattern:

    OrganizePhotos <verb> [options...]

Options are managed with L<C<Getopt::Long>>, and thus may appear anywhere
after the verb, with remaining arguments being used as input for the verb.
Most verbs' non-option arguments are glob patterns describing which files
to operate on.

The following verbs are available:

=head2 B<C<check-md5>> I<(C<c5>)>

For each media file under the current directory, generate the MD5 hash
and either add to the database if missing or verify hashes match if
already present.

This method is read/write for per-directory database files. If you want
to perform read-only MD5 checks (i.e., don't write to the database), 
then use the C<verify-md5> verb.

This does not modify media files or their sidecars, it only modifies
the per-directory database files.

=head3 Options & Arguments

=over 24

=item B<C<--add-only>>

Only operate on files that haven't had their MD5 computed and stored
yet. This option means that no existing MD5s will be verified.

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Check or add MD5 for several types of video files in the
    # current directory
    $ OrganizePhotos c5 *.mp4 *.m4v *.mov

=head2 B<C<checkup>> I<(C<c>)>

This command runs the following suggested suite of commands:

    check-md5 [--add-only] [glob patterns]
    find-dupe-files [--auto-diff|d] [--by-name|n]
        [--no-default-last-action] [glob patterns]
    remove-empties [glob patterns]
    prune-md5 [glob patterns]
    collect-trash [glob patterns]

=head3 Options & Arguments

=over 24

=item B<C<--add-only>>

Only operate on files that haven't had their MD5 computed and stored
yet. This option means that no existing MD5s will be verified.

=item B<C<-d>>, B<C<--auto-diff>>

Automatically do the C<d> diff command for every new group of files

=item B<C<--no-default-last-action>>

Don't use the last action as the default action (what is used if an
empty command is specified, i.e. you just press Enter). Enter without
entering a command will re-prompt.

=item B<C<-n>>, B<C<--by-name>>

Search for duplicates based on name rather than the default of MD5.

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Performs a checkup of directory foo doing auto-diff during
    # the find-dupe-files phase
    $ OrganizePhotos c foo -d

    # These next 4 together are equivalent to the previous statement 
    $ OrganizePhotos c5 foo
    $ OrganizePhotos fdf --auto-diff foo 
    $ OrganizePhotos re foo
    $ OrganizePhotos ct foo

    # Find all the duplicate windows binaries under the bin dir
    $ OrganizePhotos c -fqr"\.(?:(?i)dll|exe|scr)$" bin

=head2 B<C<collect-trash>> I<(C<ct>)>

Looks recursively for C<.orphtrash> subdirectories under the current directory
and moves that content to the current directory's C<.orphtrash> perserving
directory structure.

For example if we had the following trash:

    ./Foo/.orphtrash/1.jpg
    ./Foo/.orphtrash/2.jpg
    ./Bar/.orphtrash/3.jpg
    ./Bar/Baz/.orphtrash/4.jpg

After collection we would have:

    ./.orphtrash/Foo/1.jpg
    ./.orphtrash/Foo/2.jpg
    ./.orphtrash/Bar/3.jpg
    ./.orphtrash/Bar/Baz/4.jpg

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Collect trash in directories starting with Do, e.g.
    # Documents/.orphtrash, Downloads/.orphtrash, etc.
    $ OrganizePhotos ct Do*

=head2 B<C<find-dupe-files>> I<(C<fdf>)>

Find files that have multiple copies under the current directory,
and walks through a series of interactive prompts for resolution.

=head3 Options & Arguments

=over 24

=item B<C<-d>>, B<C<--auto-diff>> 

Automatically do the C<d> diff command for every new group of files

=item B<C<--no-default-last-action>>

Don't use the last action as the default action (what is used if an
empty command is specified, i.e. you just press Enter). Enter without
entering a command will re-prompt.

=item B<C<-n>>, B<C<--by-name>>

Search for duplicates based on name rather than the default of MD5.

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Find duplicate files across Alpha and Bravo directories
    $ OrganizePhotos fdf Alpha Bravo

=head2 B<C<metadata-diff>> I<(C<md>)>

Do a diff of the specified media files (including their sidecar metadata).

This method does not modify any file.

=head3 Options & Arguments

=over 24

=item B<C<-x>>, B<C<--exclude-sidecars>>

Don't include sidecar metadata for a file. For example, a CR2 file wouldn't 
include any metadata from a sidecar XMP which typically is the place where
user added tags like rating and keywords are placed.

=item B<files>

Specifies which files to diff

=back

=head3 Examples

    # Do a three way diff between the metadata in the JPGs
    $ OrganizePhotos md one.jpg two.jpg three.jpg

=head2 B<C<purge-md5>> I<(C<p5>)>

Trash database entries that reference files that no longer exist at the
location where they were indexed, presumably because they were moved
or deleted.

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Trash all orphaned MD5 data under the current directory
    $ OrganizePhotos p5

=head2 B<C<remove-empties>> I<(C<re>)>

Trash any subdirectories that are empty except for disposable files.
Disposable files include .DS_Store, thumbs.db, and our per-directory
database files.

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Removes empty directories that are descendants of directories
    # in the current directory that have 'abc' in their name
    $ OrganizePhotos re *abc*

=head2 B<C<restore-trash>> I<(C<rt>)>

Put any trash generated by this app back

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Restores all trash under the Foo directory
    $ OrganizePhotos rt Foo

=head2 B<C<verify-md5>> I<(C<v5>)>

Verifies the MD5 hashes for all contents of all database files below
the current directory.

This method is read-only, if you want to add/update MD5s, use C<check-md5>.

This method does not modify any file.

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Verifies the MD5 for all MP4 files in the current directory
    $ OrganizePhotos v5 *.mp4

=begin comment

=head1 TODO

=head2 AppendMetadata

Find files that aren't in a directory appropriate for their date

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

    # Make all md5.txt files writable
    find . -type f -name md5.txt -print -exec chflags nouchg {} \;

    # Move all AAE and LRV files in the ToImport folder to trash
    find ~/Pictures/ToImport/ -type f -iname '*.AAE' -or -iname '*.LRV' -exec trash {} \;

    # Delete .DS_Store recursively (omit "-delete" to only print)
    find . -type f -name .DS_Store -print -delete

    # Delete zero byte md5.txt files (omit "-delete" to only print)
    find . -type f -iname md5.txt -empty -print -delete

    # Rename all md5.txt files to .orphdat
    find . -type f -iname md5.txt -exec zsh -c 'mv -v $1 ${1:h}/.orphdat' _ {} \;

    # Remove empty directories (omit "-delete" to only print)
    find . -type d -empty -print -delete

    # Remove the executable bit for media files
    find . -type f -perm +111 \( -iname "*.CRW" -or -iname "*.CR2"
        -or -iname "*.JPEG" -or -iname "*.JPG" -or -iname "*.M4V"
        -or -iname "*.MOV" -or -iname "*.MP4" -or -iname "*.MPG"
        -or -iname "*.MTS" -or -iname "*.NEF" -or -iname "*.RAF"
        \) -print -exec chmod -x {} \;

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

=head3 Complementary cross platform commands

    # Strip YYYY-MM-DD- prefix from filenames
    perl -MFile::Copy -e 'for (@ARGV) { /^\d{4}-\d\d-\d\d-(.*)/ and move($_, $1) }' * 

=end comment

=head1 AUTHOR

Copyright 2017, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

=over

=item L<C<Image::ExifTool>>

=item L<C<Getopt::Long>>

=back

=cut
