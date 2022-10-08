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

package OrganizePhotos;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    doAppendMetadata
    doCheckMd5
    doCollectTrash
    doFindDupeDirs
    doFindDupeFiles
    doMetadataDiff
    doRemoveEmpties
    doPurgeMd5
    doRestoreTrash
    doTest
    doVerifyMd5
);

# Local uses
use FileOp;
use FileTypes;
use OrPhDat;
use PathOp;
use View;

# Library uses
use Const::Fast qw(const);
##??use File::Glob qw(:globally :nocase);
use List::Util qw(any all max);
use Number::Bytes::Human ();
use POSIX ();

my $autoTrashDuplicatesFrom = [
    '/Volumes/CFexpress/',
    '/Volumes/MicroSD/',
    ];

use constant MATCH_UNKNOWN => 0;
use constant MATCH_NONE => 1;
use constant MATCH_FULL => 2;
use constant MATCH_CONTENT => 3;

our $filenameFilter = $FileTypes::mediaTypeFilenameFilter;

# API ==========================================================================
# EXPERIMENTAL
# Execute append-metadata verb
sub doAppendMetadata {
    my ($target, @sources) = @_;

    my @properties = qw(XPKeywords Rating Subject HierarchicalSubject LastKeywordXMP Keywords);

    # Extract current metadata in target
    my $etTarget = extractInfo($target);
    my $infoTarget = $etTarget->GetInfo(@properties);

    trace(View::VERBOSITY_MAX, "$target: ", Data::Dumper::Dumper($infoTarget));

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

        trace(View::VERBOSITY_MAX, "$source: ", Data::Dumper::Dumper($infoSource));

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
            if (lc $filename eq $FileTypes::trashDirName) {
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
            return grep { !-d or lc ne $FileTypes::trashDirName } @_; # skip trash
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
t#  Trash Number: move the specified item to $FileTypes::trashDirName
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
    trace(View::VERBOSITY_MAX, "Found @{[scalar keys %keyToFullPathList]} initial groups");
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
        comparePathWithExtOrder($a->[0]->{fullPath}, $b->[0]->{fullPath}, 1) 
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
        all { $_ == MATCH_FULL } @{$group->[$remainingIdx[0]]->{matches}}[@remainingIdx]) {
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
        my $result = $predicate->();
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
            return 0 if any { $lcfn eq $_ } ('.ds_store', 'thumbs.db', $FileTypes::md5Filename);
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
                # parent dir ignore it like trashable files (e.g. $FileTypes::md5Filename). If
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
            if (lc $filename eq $FileTypes::trashDirName) {
                movePath($fullPath, combinePath($vol, $dir));
            }
        },
        @globPatterns);
}

# API ==========================================================================
# EXPERIMENTAL
# Execute test verb - usually just a playground for testing and new ideas
sub doTest {
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

# ------------------------------------------------------------------------------
# Default behavior if isDirWanted is undefined for traverseFiles
sub defaultIsDirWanted {
    my ($fullPath, $rootFullPath, $filename) = @_;
    return (lc $filename ne $FileTypes::trashDirName);
}

# MODEL (File Operations) ------------------------------------------------------
# Default behavior if isDirWanted is undefined for traverseFiles
sub defaultIsFileWanted {
    my ($fullPath, $rootFullPath, $filename) = @_;
    return (lc $filename ne $FileTypes::md5Filename and $filename =~ /$filenameFilter/);
}

1;