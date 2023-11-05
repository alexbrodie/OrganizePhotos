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
);

# Local uses
use ContentHash;
use FileOp;
use FileTypes;
use PathOp;
use View;

# Library uses
use Const::Fast qw(const);
use Data::Compare ();
use File::stat ();
use JSON ();
use List::Util qw(any all);

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
    unless ($forceRecalc) {
        if (defined $cachedMd5Info) {
            my $cacheResult = checkCachedMd5Info($mediaPath, $addOnly, 'Caller', $cachedMd5Info, $newMd5InfoBase);
            # Caller supplied cached Md5Info is up to date
            return $cacheResult if $cacheResult;
        }
        if ($md5Path eq $cachedMd5Path) {
            $cachedMd5Info = $cachedMd5Set->{$md5Key};
            my $cacheResult = checkCachedMd5Info($mediaPath, $addOnly, 'Memory', $cachedMd5Info, $newMd5InfoBase);
            # Memory cache of Md5Info is up to date
            return $cacheResult if $cacheResult;
        } else {
            trace(View::VERBOSITY_HIGH, "Memory cache miss for '$mediaPath', cache was '$cachedMd5Path'");
        }
    }
    trace(View::VERBOSITY_MAX, "Opening cache '$md5Path' for '$mediaPath'");
    my ($md5File, $md5Set) = readOrCreateNewMd5File($md5Path);
    my $oldMd5Info = $md5Set->{$md5Key};
    unless ($forceRecalc) {
        my $cacheResult = checkCachedMd5Info($mediaPath, $addOnly, 'File', $oldMd5Info, $newMd5InfoBase);
        # File cache of Md5Info is up to date
        return $cacheResult if $cacheResult;
    }
    # No suitable cache, so fill in/finalize the Md5Info that we'll return
    my $newMd5Info;
    #eval {
        # TODO: consolidate opening file multiple times from stat and calculateMd5Info
        $newMd5Info = { %{calculateMd5Info($mediaPath)}, %$newMd5InfoBase };
    #};
    #if (my $error = $@) {
    #    # TODO: for now, skip but we'll want something better in the future
    #    warn Term::ANSIColor::colored("UNAVAILABLE MD5 for '@{[prettyPath($mediaPath)]}' with error:", 'red'), "\n\t$error\n";
    #    return undef; # Can't get the MD5
    #}
    # Do verification on the old persisted Md5Info and the new calculated Md5Info
    if (defined $oldMd5Info) {
        if ($oldMd5Info->{md5} eq $newMd5Info->{md5}) {
            # Matches last recorded hash, but still continue and call
            # setMd5InfoAndWriteMd5File to handle other bookkeeping
            # to ensure we get a cache hit and short-circuit next time.
            printWithIcon('(V)', 'green', "Verified MD5 for '@{[prettyPath($mediaPath)]}'");
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
    trace(View::VERBOSITY_MAX, 'findMd5s(...); with @globPatterns of', 
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
    trace(View::VERBOSITY_MAX, "writeMd5Info('$mediaPath', {...});");
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
    trace(View::VERBOSITY_MAX, "moveMd5Info('$oldMediaPath', " . 
                         (defined $newMediaPath ? "'$newMediaPath'" : 'undef') . ");");
    my ($oldMd5Path, $oldMd5Key) = getMd5PathAndMd5Key($oldMediaPath);
    unless (-e $oldMd5Path) {
        trace(View::VERBOSITY_MAX, "Can't move/remove Md5Info for '$oldMd5Key' from missing '$oldMd5Path'"); 
        return undef;
    }
    my ($oldMd5File, $oldMd5Set) = readMd5File('+<:crlf', $oldMd5Path);
    unless (exists $oldMd5Set->{$oldMd5Key}) {
        trace(View::VERBOSITY_MAX, "Can't move/remove missing Md5Info for '$oldMd5Key' from '$oldMd5Path'");
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
            $crudMessage = "Removed cache data for '@{[prettyPath($oldMediaPath)]}' (up to date " .
                           "data already exists for '@{[prettyPath($newMediaPath)]}')";
        } else {
            $newMd5Set->{$newMd5Key} = $newMd5Info;
            trace(View::VERBOSITY_MEDIUM, "Writing '$newMd5Path' after moving entry for '$newMd5Key' elsewhere");
            writeMd5File($newMd5Path, $newMd5File, $newMd5Set);
            $crudOp = View::CRUD_UPDATE;
            $crudMessage = "Moved cache data for '@{[prettyPath($oldMediaPath)]}' to '@{[prettyPath($newMediaPath)]}'";
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
    } else {
        # Empty files create trouble down the line (especially with move-merges)
        trace(View::VERBOSITY_MEDIUM, "Deleting '$oldMd5Path' after removing MD5 for '$oldMd5Key' (the last one)");
        close($oldMd5File);
        unlink($oldMd5Path) or die "Couldn't delete '$oldMd5Path': $!";
        printCrud(View::CRUD_DELETE, "  Deleted empty file '@{[prettyPath($oldMd5Path)]}'\n");
    }
    printCrud($crudOp, $crudMessage, "\n");
    return $oldMd5Info;
}

# MODEL (MD5) ------------------------------------------------------------------
# Moves Md5Info for a MediaPath to local trash. Returns the previous Md5Info
# value if it existed (or undef if not).
sub trashMd5Info {
    my ($mediaPath) = @_;
    trace(View::VERBOSITY_MAX, "trashMd5Info('$mediaPath');");
    my $trashPath = getTrashPath($mediaPath);
    ensureParentDirExists($trashPath);
    return moveMd5Info($mediaPath, $trashPath);
}

# MODEL (MD5) ------------------------------------------------------------------
# Removes Md5Info for a MediaPath from storage. Returns the previous Md5Info
# value if it existed (or undef if not).
sub deleteMd5Info {
    my ($mediaPath) = @_;
    trace(View::VERBOSITY_MAX, "deleteMd5Info('$mediaPath');");
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
        printCrud(View::CRUD_CREATE, "  Added $itemsAdded MD5s to '${\prettyPath($targetMd5Path)}' from ",
                  join ', ', map { "'${\prettyPath($_)}'" } @sourceMd5Paths);
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# This is a utility for updating Md5Info. It opens the Md5Path R/W and parses
# it. Returns the Md5File and Md5Set.
sub readOrCreateNewMd5File {
    my ($md5Path) = @_;
    trace(View::VERBOSITY_MAX, "readOrCreateNewMd5File('$md5Path');");
    if (-e $md5Path) {
        return readMd5File('+<:crlf', $md5Path);
    } else {
        # TODO: should mode here have :crlf on the end?
        my $fh = openOrDie('+>', $md5Path);
        printCrud(View::CRUD_CREATE, "  Created cache at '@{[prettyPath($md5Path)]}'\n");
        return ($fh, {});
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
            /^([^:]+):\s*($ContentHash::md5DigestPattern)$/ or die "Unexpected line in '$md5Path': $_";
            # We use version 0 here for the very old way before we went to
            # JSON when we added more info than just the full file MD5
            my $fullMd5 = lc $2;
            $md5Set->{lc $1} = { version => 0, filename => $1, 
                                 md5 => $fullMd5, full_md5 => $fullMd5 };
        }
    }
    updateMd5FileCache($md5Path, $md5Set);
    printCrud(View::CRUD_READ, "  Read cache from '@{[prettyPath($md5Path)]}'\n");
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
        trace(View::VERBOSITY_MEDIUM, "Writing '$md5Path' after updating value for key '$md5Key'");
        writeMd5File($md5Path, $md5File, $md5Set);
        if (defined $oldMd5Info) {
            printCrud(View::CRUD_UPDATE, "Updated cache entry for '@{[prettyPath($mediaPath)]}'\n");
        } else {
            printCrud(View::CRUD_CREATE, "Added cache entry for '@{[prettyPath($mediaPath)]}'\n");
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
    trace(View::VERBOSITY_MAX, 'writeMd5File(<..>, { hash of @{[ scalar keys %$md5Set ]} items });');
    seek($md5File, 0, 0) or die "Couldn't reset seek on file: $!";
    truncate($md5File, 0) or die "Couldn't truncate file: $!";
    if (%$md5Set) {
        print $md5File JSON->new->allow_nonref->pretty->canonical->encode($md5Set);
    } else {
        warn "Writing empty data to $md5Path";
    }
    updateMd5FileCache($md5Path, $md5Set);
    printCrud(View::CRUD_UPDATE, "  Wrote cache to '@{[prettyPath($md5Path)]}'\n");
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
sub makeMd5InfoBase  {
    my ($mediaPath) = @_;
    my $stats = File::stat::stat($mediaPath) or die "Couldn't stat '$mediaPath': $!";
    my (undef, undef, $filename) = File::Spec->splitpath($mediaPath);
    return { filename => $filename, size => $stats->size, mtime => $stats->mtime };
}

# MODEL (MD5) ------------------------------------------------------------------
# Returns a full Md5Info constructed from the cache if it can be used for the
# specified base-only Md5Info without bothering to calculateMd5Info. 
#sub canUseCachedMd5InfoForBase {
sub checkCachedMd5Info {
    my ($mediaPath, $addOnly, $cacheType, $cachedMd5Info, $currentMd5InfoBase) = @_;
    #trace(View::VERBOSITY_MAX, 'canUseCachedMd5InfoForBase(...);');
    unless (defined $cachedMd5Info) {
        # Note that this is assumed context from the caller, and not actually
        # something true based on this sub
        trace(View::VERBOSITY_HIGH, "$cacheType cache miss for '$mediaPath', lookup failed'");
        return undef;
    }

    if ($addOnly) {
        trace(View::VERBOSITY_MAX, "$cacheType cache hit for '$mediaPath' (add-only mode)");
    } else {
        my @delta = ();
        unless (isMd5InfoVersionUpToDate($mediaPath, $cachedMd5Info->{version})) {
            push @delta, 'version';
        }
        unless (lc $currentMd5InfoBase->{filename} eq lc $cachedMd5Info->{filename}) {
            push @delta, 'name';
        }
        unless (defined $cachedMd5Info->{size} and 
            $currentMd5InfoBase->{size} == $cachedMd5Info->{size}) {
            push @delta, 'size';
        }
        unless (defined $cachedMd5Info->{mtime} and 
            $currentMd5InfoBase->{mtime} == $cachedMd5Info->{mtime}) {
            push @delta, 'mtime';
        }
        if (@delta) {
            trace(View::VERBOSITY_HIGH, "$cacheType cache miss for '$mediaPath', different " . join('/', @delta));
            return undef;
        }
        trace(View::VERBOSITY_MAX, "$cacheType cache hit for '$mediaPath' with version/name/size/mtime match");
    }

    return { %{Storable::dclone($cachedMd5Info)}, %$currentMd5InfoBase };
}

1;