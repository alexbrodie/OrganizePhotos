#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package FileOp;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    traverseFiles
    trashPath
    trashPathAndSidecars
    trashPathWithRoot
    movePath
    ensureParentDirExists
    tryRemoveEmptyDir
    openOrDie
);

# Local uses
use View;

# Library uses
use Const::Fast qw(const);
use File::Copy ();
use File::Find ();
use File::Path ();
use File::Spec ();

# TODO!! Consolidate $md5Filename and $trashDirName once we know where they should live

# Filename only portion of the path to Md5File which stores
# Md5Info data for other files in the same directory
const my $md5Filename => '.orphdat';

# This subdirectory contains the trash for its parent
const my $trashDirName => '.orphtrash';

# MODEL (File Operations) ------------------------------------------------------
# This is a wrapper over File::Find::find that offers a few benefits:
#  * Provides some common functionality such as glob handling
#  * Standardizes on bydepth and no_chdir which seems to be the best context
#    for authoring the callbacks
#  * Provide consistent and safely qualified path to callback, and eliminate
#    the params via nonhomogeneous globals pattern
#
# Unrolls globs and traverses directories and files breadth first.
#
# Returning false from isDirWanted prevents callback from being
# called on that directory and prevents further traversal such that descendants
# won't have calls to isDirWanted, isFileWanted, or callback.
#
# Returning false from isFileWanted prevents callback from being called for
# that file only.
#
# If isDirWanted is truthy for ancestor directories, and isFileWanted is
# truthy, then callback is called for a file.
#
# Once all decendant items have been been processed, callback is called
# for a directory.
#
# It's important to not do anything with a side effect in isDirWanted or 
# isFileWanted other than return 0 or 1 to specify whether these dirs or files
# should be processed. That method is called breadth first, such that
# traversal of a subtree can be short circuited. Then process is called
# depth first such that the process of a dir doesn't occur until all the
# subitems have been processed.
#
# Note that if glob patterns overlap, then some files might invoke the 
# callbacks more than once. For example, 
#   traverseFiles(..., 'Al*.jpg', '*ex.jpg');
# would match Alex.jpg twice, and invoke isFileWanted/callback twice as well.
sub traverseFiles {
    my ($isDirWanted, $isFileWanted, $callback, @globPatterns) = @_;
    $isDirWanted = \&OrganizePhotos::defaultIsDirWanted unless $isDirWanted;
    $isFileWanted = \&OrganizePhotos::defaultIsFileWanted unless $isFileWanted;
    # Record base now so that no_chdir doesn't affect rel2abs/abs2rel below
    # (and - bonus - just resolve and canonicalize once)
    my $curDir = File::Spec->curdir();
    my $baseFullPath = File::Spec->rel2abs($curDir);
    $baseFullPath = File::Spec->canonpath($baseFullPath);
    # the isDirWanted, isFileWanted, and callback methods take the same
    # params which share the following computations
    my $makeFullPath = sub {
        my ($partialPath) = @_;
        my $fullPath = File::Spec->rel2abs($partialPath, $baseFullPath);
        $fullPath = File::Spec->canonpath($fullPath);
        -e $fullPath or die
            "Programmer Error: enumerated file doesn't exist: '$fullPath'";
        return $fullPath;
    };
    # Returns 'f' if it's a wanted file, 'd' if it's a wanted dir
    # or falsy if not wanted
    my $isWanted = sub {
        my ($fullPath, $rootFullPath) = @_;
        my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
        if (-d $fullPath) {
            # Never peek inside of a .git folder or any folder
            # containing .orphignore (opt out mechanism)
            if (lc $filename eq '.git' or
                -e File::Spec->catfile($fullPath, '.orphignore')) {
                return '';
            }
            local $_ = undef; # prevent use in the isDirWanted
            return 'd' if $isDirWanted->($fullPath, $rootFullPath, $filename);
        } elsif (-f _) {
            # When MacOS copies files with alternate streams (e.g. from APFS)
            # to a volume that doesn't support it, they put the alternate
            # stream data in a file with the same path, but with a "._"
            # filename prefix. Though it's not a complete fix, for now, we'll
            # pretend these don't exist.
            if ($filename =~ /^\._/ or
                lc $filename eq '.orphignore') {
                return '';
            }
            local $_ = undef; # prevent use in the isFileWanted
            return 'f' if $isFileWanted->($fullPath, $rootFullPath, $filename);
        } else {
            die "Programmer Error: unknown object type for '$fullPath'";
        }
        return '';
    };
    # Method to be called for each directory found in globPatterns
    my $innerTraverse = sub {
        my ($rootPartialPath) = @_;
        my $rootFullPath = $makeFullPath->($rootPartialPath);
        my $myCaller = 'unknown';
        for (my $i = 2; $i < 16; $i++) {
            $myCaller = $1 and last if (caller($i))[3] =~ /^\w+::do(.*)/;
        }
        trace(View::VERBOSITY_LOW, "$myCaller is traversing '$rootPartialPath' ('$rootFullPath')");
        # Find::find's final wanted call for $rootFullPath doesn't have a 
        # matching preprocess call, so doing one up front for symetry with
        # all other pairs while also doing the other filtering we want.
        my $isWantedResult = $isWanted->($rootFullPath, $rootFullPath);
        if ($isWantedResult eq 'd') {
            my $preprocess = sub {
                my @dirs = ();
                my @files = ();
                for (@_) {
                    # Skip .. because it doesn't matter what we do, this isn't
                    # going to get passed to wanted, and it doesn't really make
                    # sense to traverse up in a recursive down enumeration. 
                    # Also, skip '.' because we would otherwise process each
                    # dir twice, and $rootFullPath once. This makes subdirs
                    # once and $rootFullPath not at all.
                    next if (($_ eq '.') or ($_ eq '..'));
                    # The values used here to compute the path relative
                    # to $baseFullPath matches the values of wanted's
                    # implementation, and both work the same whether
                    # no_chdir is set or not. 
                    my $fullPath = $makeFullPath->(
                        File::Spec->catfile($File::Find::dir, $_));
                    my $result = $isWanted->($fullPath, $rootFullPath);
                    if ($result eq 'd') {
                        push @dirs, $_;
                    } elsif ($result eq 'f') {
                        push @files, $_;
                    } elsif ($result) {
                        die "Programmer Error: unknown return value from isWanted: '$result'";
                    }
                }
                # Dirs first will be depth first traversal (nieces/nephews first).
                # Files first will be breadth first traversal (aunts/uncles first).
                # This is not the same as what bydepth does which deals in parents
                # and children.
                return (sort(@dirs), sort(@files));
            };
            my $wanted = sub {
                # The values used here to compute the path relative
                # to $baseFullPath matches the values of preprocess'
                # implementation, and both work the same whether
                # no_chdir is set or not.
                my $fullPath = $makeFullPath->($File::Find::name);
                local $_ = undef; # prevent use in callback
                $callback->($fullPath, $rootFullPath);
            };
            File::Find::find({ bydepth => 1, no_chdir => 1, 
                            preprocess => $preprocess,
                            wanted => $wanted }, $rootFullPath);
        } elsif ($isWantedResult eq 'f') {
            local $_ = undef; # prevent use in callback
            $callback->($rootFullPath, $rootFullPath);
        } elsif ($isWantedResult) {
            die "Programmer Error: unknown return value from isWanted: $isWantedResult";
        }
    };
    if (@globPatterns) {
        for my $globPattern (@globPatterns) {
            # TODO: Is this workaround to handle globbing with spaces for
            # Windows compatible with MacOS (with and without spaces)? Does it
            # work okay with single quotes in file/dir names on each platform?
            $globPattern = "'$globPattern'";
            $innerTraverse->($_) for glob $globPattern;
        }
    } else {
        # If no glob patterns are provided, just search current directory
        $innerTraverse->($curDir);
    }
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path and any sidecars (anything with the same path
# except for extension)
sub trashPathAndSidecars {
    my ($fullPath) = @_;
    trace(View::VERBOSITY_ALL, "trashPathAndSidecars('$fullPath');");
    # TODO: check all for existance before performing any operations to
    # make file+sidecar opererations more atomic
    trashPath($_) for ($fullPath, getSidecarPaths($fullPath));
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path by moving it to a .orphtrash subdir and moving
# its entry from the per-directory database file
sub trashPath {
    my ($fullPath) = @_;
    trace(View::VERBOSITY_ALL, "trashPath('$fullPath');");
    # If it's an empty directory, just delete it. Trying to trash
    # a dir with no items proves problematic for future move-merges
    # and we wind up with a lot of orphaned empty containers.
    unless (tryRemoveEmptyDir($fullPath)) {
        # Not an empty dir, so move to trash by inserting a .orphtrash
        # before the filename in the path, and moving it there
        movePath($fullPath, getTrashPathFor($fullPath));
    }
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified fullPath by moving it to rootFullPath's .orphtrash
# subdir and moving its entry from the per-directory database file.
# rootFullPath must be an ancestor of fullPath. If it is the direct
# parent, this method behaves like trashPath.
#
# Example 1: (nested with intermediate .orphtrash)
#   trashPathWithRoot('.../root/A/B/.orphtrash/C/D/.orphtrash', '.../root')
#   moves file to: '.../root/.orphtrash/A/B/C/D'
#
# Example 2: (degenerate trashPath case)
#   trashPathWithRoot('.../root/foo', '.../root')
#   moves file to: '.../root/.orphtrash/foo'
#
# Example 3: (edge case)
#   trashPathWithRoot('.../root/.orphtrash/.orphtrash/.orphtrash', '.../root')
#   moves file to: '.../root/.orphtrash'
sub trashPathWithRoot {
    my ($theFullPath, $rootFullPath) = @_;
    trace(View::VERBOSITY_ALL, "trashPathWithRoot('$theFullPath', '$rootFullPath');");
    # Split the directories into pieces assuming root is a dir
    # Note the careful use of splitdir and catdir - splitdir can return
    # empty string entries in the array, notably at beginning and end
    # which can make manipulation of dir arrays tricky.
    my ($theVol, $theDir, $theFilename) = File::Spec->splitpath($theFullPath);
    my ($rootVol, $rootDir, $rootFilename) = File::Spec->splitpath($rootFullPath);
    # Example 1: theDirs = ( ..., root, A, B, .orphtrash, C, D )
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
    # Example 1: postRoot = ( .orphtrash, A, B, C, D )
    # Example 2: postRoot = ( .orphtrash, foo )
    # Example 3: postRoot = ( .orphtrash )
    my @postRoot = ($trashDirName, grep { lc ne $trashDirName } @theDirs[@rootDirs .. @theDirs-1]);
    # Example 1: postRoot = ( .orphtrash, A, B, C ); newFilename = D
    # Example 2: postRoot = ( .orphtrash ); newFilename = foo
    # Example 3: postRoot = (); newFilename = .orphtrash
    my $newFilename = pop @postRoot;
    # Example 1: newDir = '.../root/.orphtrash/A/B/C'
    # Example 2: newDir = '.../root/.orphtrash'
    # Example 3: newDir = '.../root'
    my $newDir = File::Spec->catdir(@rootDirs, @postRoot);
    # Example 1: newFullPath = '.../root/.orphtrash/A/B/C/D'
    # Example 2: newFullPath = '.../root/.Trahs/foo'
    # Example 3: newFullPath = '.../root/.orphtrash'
    my $newFullPath = combinePath($theVol, $newDir, $newFilename);
    movePath($theFullPath, $newFullPath);
}

# MODEL (File Operations) ------------------------------------------------------
# Move oldFullPath to newFullPath doing a move-merge where
# necessary and possible
sub movePath {
    my ($oldFullPath, $newFullPath, $dryRun) = @_;
    trace(View::VERBOSITY_ALL, "movePath('$oldFullPath', '$newFullPath');");
    return if $oldFullPath eq $newFullPath;
    my $moveInternal = sub {
        ensureParentDirExists($newFullPath, $dryRun);
        # Move the file/dir
        trace(View::VERBOSITY_MEDIUM, "File::Copy::move('$oldFullPath', '$newFullPath');");
        unless ($dryRun) {
            File::Copy::move($oldFullPath, $newFullPath) or die
                "Failed to move '$oldFullPath' to '$newFullPath': $!";
        }
        # (caller is expected to printCrud with more context)
    };
    if (-f $oldFullPath) {
        if (-e $newFullPath) {
            # If both are the per-directory database files, and newFullPath
            # exists, then cat old on to new, and delete old.
            my (undef, undef, $oldFilename) = File::Spec->splitpath($oldFullPath);
            my (undef, undef, $newFilename) = File::Spec->splitpath($newFullPath);
            if (lc $oldFilename eq $md5Filename and lc $newFilename eq $md5Filename) {
                unless ($dryRun) {
                    appendMd5Files($newFullPath, $oldFullPath);
                    unlink($oldFullPath) or die "Couldn't delete '$oldFullPath': $!";
                }
                printCrud(View::CRUD_DELETE, "Deleted now-old '@{[prettyPath($oldFullPath)]}' after ",
                          "appending its MD5 information to '@{[prettyPath($newFullPath)]}'");
            } else {
                die "Can't overwrite '$newFullPath' with '$oldFullPath'";
            }
        } else {
            $moveInternal->();
            printCrud(View::CRUD_UPDATE, "Moved file at   '@{[prettyPath($oldFullPath)]}' ",
                      "to '@{[prettyPath($newFullPath)]}'\n");
            unless ($dryRun) {
                moveMd5Info($oldFullPath, $newFullPath);
            }
        }
    } elsif (-d _) {
        if (-e $newFullPath) { 
            # Dest dir path already exists, need to move-merge.
            trace(View::VERBOSITY_ALL, "Move merge '$oldFullPath' to '$newFullPath'");
            -d _ or die
                "Can't move a directory - file already exists " .
                "at destination ('$oldFullPath' => '$newFullPath')";
            # Use readdir rather than File::Find::find here. This doesn't
            # do a lot of what File::Find::find does - by design. We don't
            # want a lot of that behavior, and don't care about most of
            # the rest (we only want one - not recursive, don't want to
            # change dir, don't support traversing symbolic links, etc.). 
            opendir(my $dh, $oldFullPath) or die "Couldn't open dir '$oldFullPath': $!";
            my @filenames = grep { $_ ne '.' and $_ ne '..' } readdir($dh);
            closedir($dh);
            # The database file should be processed last as it is modified
            # as a side effect of moving its siblings
            @filenames = sort {
                (lc $a eq $md5Filename) <=> (lc $b eq $md5Filename) ||
                lc $a cmp lc $b ||
                $a cmp $b
            } @filenames;
            for (@filenames) {
                my $oldChildFullPath = File::Spec->canonpath(File::Spec->catfile($oldFullPath, $_));
                my $newChildFullPath = File::Spec->canonpath(File::Spec->catfile($newFullPath, $_));
                # If we move the last media from a folder in previous iteration
                # of this loop, it can delete an empty Md5File via moveMd5Info.
                next if lc $_ eq $md5Filename and !(-e $oldChildFullPath);
                movePath($oldChildFullPath, $newChildFullPath, $dryRun);
            }
            # If we've emptied out $oldFullPath my moving all its contents into
            # the already existing $newFullPath, we can safely delete it. If
            # not, this does nothing - also what we want.
            unless ($dryRun) {
                tryRemoveEmptyDir($oldFullPath);
            }
        } else {
            # Dest dir doesn't exist, so we can just move the whole directory
            $moveInternal->();
            printCrud(View::CRUD_UPDATE, "Moved directory '@{[prettyPath($oldFullPath)]}'",
                      " to '@{[prettyPath($newFullPath)]}'\n");
        }
    } else {
        die "Programmer Error: unexpected type for object '$oldFullPath'";
    }
}

# MODEL (File Operations) ------------------------------------------------------
sub ensureParentDirExists {
    my ($fullPath, $dryRun) = @_;
    my $parentFullPath = parentPath($fullPath);
    unless (-d $parentFullPath) {
        trace(View::VERBOSITY_MEDIUM, "File::Copy::make_path('$parentFullPath');");
        unless ($dryRun) {
            File::Path::make_path($parentFullPath) or die
                "Failed to make directory '$parentFullPath': $!";
        }
        printCrud(View::CRUD_CREATE, "Created dir     '@{[prettyPath($parentFullPath)]}'\n");
    }
}

# MODEL (File Operations) ------------------------------------------------------
# Removes the specified path if it's an empty directory and returns truthy.
# If it's not a directory or a directory with children, the do nothing
# and return falsy.
sub tryRemoveEmptyDir {
    my ($path) = @_;
    trace(View::VERBOSITY_ALL, "tryRemoveEmptyDir('$path');");
    if (-d $path and rmdir $path) {
        printCrud(View::CRUD_DELETE, "Deleted empty   '@{[prettyPath($path)]}'\n");
        return 1;
    } else {
        return 0;
    }
}

# MODEL (File Operations) ------------------------------------------------------
sub openOrDie {
    my ($mode, $path) = @_;
    trace(View::VERBOSITY_ALL, "openOrDie('$path');");
    open(my $fh, $mode, $path) or die "Couldn't open '$path' in $mode mode: $!";
    # TODO: Can we determine why and add a helpful error message. E.g. if in R/W
    # mode, maybe suggest they run one of the following
    #  $ chflags nouchg '$path'
    #  $ find <root_dir> -type f -name .orphdat -print -exec chflags nouchg {} \;
    return $fh;
}

1;
