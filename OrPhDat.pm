#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package OrPhDat;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    resolveMd5Info
    findMd5s
    writeMd5Info
    moveMd5Info
    trashMd5Info
    deleteMd5Info
    appendMd5Files
    calculateMd5Info
    getDateTaken
    readMetadata
    extractInfo
);

# Local uses
use FileOp;
use FileTypes;
use Isobmff;
use PathOp;
use View;

# Library uses
use Const::Fast qw(const);
use Data::Compare ();
use DateTime::Format::HTTP ();
#use DateTime::Format::ISO8601 ();
use Digest::MD5 ();
use File::stat ();
use Image::ExifTool ();
use JSON ();
use List::Util qw(any all);

# What we expect an MD5 hash to look like
const my $md5DigestPattern => qr/[0-9a-f]{32}/;

my $cachedMd5Path = '';
my $cachedMd5Set = {};

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
    $isFileWanted = \&OrganizePhotos::defaultIsFileWanted unless $isFileWanted;
    trace(View::VERBOSITY_ALL, 'findMd5s(...); with @globPatterns of', 
          (@globPatterns ? map { "\n\t'$_'" } @globPatterns : ' (current dir)'));
    traverseFiles(
        $isDirWanted,
        sub {  # isFileWanted
            my ($fullPath, $rootFullPath, $filename) = @_;
            return (lc $filename eq $FileTypes::md5Filename); # only process Md5File files
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
    my ($md5Path, $md5Key) = changeFilename($mediaPath, $FileTypes::md5Filename);
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
    my $trashPath = getTrashPath($mediaPath);
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
    # TODO: Should we validate filename is $FileTypes::md5Filename or do we care?
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
    # TODO: Should we validate filename is $FileTypes::md5Filename or do we care?
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
    # TODO: Should we validate filename is $FileTypes::md5Filename or do we care?
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

1;