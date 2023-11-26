#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package FileOp;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    trash_path
    trash_path_and_sidecars
    trash_path_with_root
    move_path
    ensure_parent_dir
    try_remove_empty_dir
    open_file
);

# Local uses
use FileTypes;
use PathOp;
use View;

# Library uses
use Const::Fast qw(const);
use File::Copy  qw(move);
use File::Path  qw(make_path);
use File::Spec  ();

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path and any sidecars (anything with the same path
# except for extension)
sub trash_path_and_sidecars {
    my ($path) = @_;
    trace( View::VERBOSITY_MAX, "trash_path_and_sidecars('$path');" );

    # TODO: check all for existance before performing any operations to
    # make file+sidecar opererations more atomic
    trash_path($_) for ( $path, get_sidecar_paths($path) );
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path by moving it to a .orphtrash subdir and moving
# its entry from the per-directory database file
sub trash_path {
    my ($path) = @_;
    trace( View::VERBOSITY_MAX, "trash_path('$path');" );

    # If it's an empty directory, just delete it. Trying to trash
    # a dir with no items proves problematic for future move-merges
    # and we wind up with a lot of orphaned empty containers.
    unless ( try_remove_empty_dir($path) ) {

        # Not an empty dir, so move to trash by inserting a .orphtrash
        # before the filename in the path, and moving it there
        move_path( $path, get_trash_path($path) );
    }
}

# MODEL (File Operations) ------------------------------------------------------
# Trash the specified path by moving it to root's .orphtrash
# subdir and moving its entry from the per-directory database file.
# root must be an ancestor of path. If it is the direct
# parent, this method behaves like trash_path.
#
# Example 1: (nested with intermediate .orphtrash)
#   trash_path_with_root('.../root/A/B/.orphtrash/C/D/.orphtrash', '.../root')
#   moves file to: '.../root/.orphtrash/A/B/C/D'
#
# Example 2: (degenerate trash_path case)
#   trash_path_with_root('.../root/foo', '.../root')
#   moves file to: '.../root/.orphtrash/foo'
#
# Example 3: (edge case)
#   trash_path_with_root('.../root/.orphtrash/.orphtrash/.orphtrash', '.../root')
#   moves file to: '.../root/.orphtrash'
sub trash_path_with_root {
    my ( $path, $root ) = @_;
    trace( View::VERBOSITY_MAX, "trash_path_with_root('$path', '$root');" );

    # Split the directories into pieces assuming root is a dir
    # Note the careful use of splitdir and catdir - splitdir can return
    # empty string entries in the array, notably at beginning and end
    # which can make manipulation of dir arrays tricky.
    my ( $main_vol, $main_dir, $main_filename ) = split_path($path);
    my ( $root_vol, $root_dir, $root_filename ) = split_path($root);

    # Example 1: main_dir_parts = ( ..., root, A, B, .orphtrash, C, D )
    my @main_dir_parts =
        File::Spec->splitdir( File::Spec->catdir( $main_dir, $main_filename ) );

    # Example N: root_dir_parts = ( ..., root )
    my @root_dir_parts =
        File::Spec->splitdir( File::Spec->catdir( $root_dir, $root_filename ) );

    # Verify @root_dir_parts is a prefix match for (i.e. ancestor of) @main_dir_parts
    my $prefix_death = sub {
        "Programmer error: root '$root' is not "
            . "a prefix for path '$path (@_)";
    };
    $main_vol eq $root_vol or die $prefix_death->('different volumes');
    @root_dir_parts < @main_dir_parts
        or die $prefix_death->('root is longer');
    for ( my $i = 0; $i < @root_dir_parts; $i++ ) {
        $root_dir_parts[$i] eq $main_dir_parts[$i]
            or die $prefix_death->(
            "'$root_dir_parts[$i]' ne '$main_dir_parts[$i]' at $i");
    }

    # Figure out post_root (path relative to root without
    # trash), and then append that to root's trash dir's path
    # Example 1: post_root = ( .orphtrash, A, B, C, D )
    # Example 2: post_root = ( .orphtrash, foo )
    # Example 3: post_root = ( .orphtrash )
    my @post_root = (
        $FileTypes::TRASH_DIR_NAME,
        grep { lc ne $FileTypes::TRASH_DIR_NAME }
            @main_dir_parts[ @root_dir_parts .. @main_dir_parts - 1 ]
    );

    # Example 1: post_root = ( .orphtrash, A, B, C ); new_filename = D
    # Example 2: post_root = ( .orphtrash ); new_filename = foo
    # Example 3: post_root = (); new_filename = .orphtrash
    my $new_filename = pop @post_root;

    # Example 1: new_dir = '.../root/.orphtrash/A/B/C'
    # Example 2: new_dir = '.../root/.orphtrash'
    # Example 3: new_dir = '.../root'
    my $new_dir = File::Spec->catdir( @root_dir_parts, @post_root );

    # Example 1: new_path = '.../root/.orphtrash/A/B/C/D'
    # Example 2: new_path = '.../root/.orphtrash/foo'
    # Example 3: new_path = '.../root/.orphtrash'
    my $new_path = combine_path( $main_vol, $new_dir, $new_filename );
    move_path( $path, $new_path );
}

# MODEL (File Operations) ------------------------------------------------------
# Move old_path to new_path doing a move-merge where
# necessary and possible. Does not overwrite existing files.
sub move_path {
    my ( $old_path, $new_path, $dry_run ) = @_;
    trace( View::VERBOSITY_MAX, "move_path('$old_path', '$new_path');" );
    return if $old_path eq $new_path;
    my $move_internal = sub {
        ensure_parent_dir( $new_path, $dry_run );

        # Move the file/dir
        trace( View::VERBOSITY_MAX, "move('$old_path', '$new_path');" );
        unless ($dry_run) {
            move( $old_path, $new_path )
                or die "Failed to move '$old_path' to '$new_path': $!";
        }

        # (caller is expected to print_crud with more context)
    };
    if ( -f $old_path ) {
        if ( -e $new_path ) {

            # If both are the per-directory database files, and new_path
            # exists, then cat old on to new, and delete old.
            my ( undef, undef, $old_filename ) = split_path($old_path);
            my ( undef, undef, $new_filename ) = split_path($new_path);
            if (    lc $old_filename eq $FileTypes::ORPHDAT_FILENAME
                and lc $new_filename eq $FileTypes::ORPHDAT_FILENAME )
            {
                unless ($dry_run) {
                    OrPhDat::append_orphdat_files( $new_path, $old_path );
                    unlink($old_path)
                        or die "Couldn't delete '$old_path': $!";
                }
                print_crud(
                    View::VERBOSITY_MEDIUM,
                    View::CRUD_DELETE,
                    "Deleted now-old cache at '@{[pretty_path($old_path)]}' after ",
                    "appending it to '@{[pretty_path($new_path)]}'\n"
                );
            }
            else {
                die "Can't overwrite '$new_path' with '$old_path'";
            }
        }
        else {
            $move_internal->();
            print_crud(
                View::VERBOSITY_LOW,
                View::CRUD_UPDATE,
                "Moved file '@{[pretty_path($old_path)]}' ",
                "to '@{[pretty_path($new_path)]}'\n"
            );
            unless ($dry_run) {
                OrPhDat::move_orphdat( $old_path, $new_path );
            }
        }
    }
    elsif ( -d _ ) {
        if ( -e $new_path ) {

            # Dest dir path already exists, need to move-merge.
            trace( View::VERBOSITY_MAX,
                "Move merge '$old_path' to '$new_path'" );
            -d _
                or die "Can't move a directory - file already exists "
                . "at destination ('$old_path' => '$new_path')";

            # Use readdir rather than File::Find::find here. This doesn't
            # do a lot of what File::Find::find does - by design. We don't
            # want a lot of that behavior, and don't care about most of
            # the rest (we only want one - not recursive, don't want to
            # change dir, don't support traversing symbolic links, etc.).
            opendir( my $dh, $old_path )
                or die "Couldn't open dir '$old_path': $!";
            my @filenames = grep { $_ ne '.' and $_ ne '..' } readdir($dh);
            closedir($dh);

            # The database file should be processed last as it is modified
            # as a side effect of moving its siblings
            @filenames = sort {
                ( lc $a eq $FileTypes::ORPHDAT_FILENAME )
                    <=> ( lc $b eq $FileTypes::ORPHDAT_FILENAME )
                    || lc $a cmp lc $b
                    || $a cmp $b
            } @filenames;
            for (@filenames) {
                my $old_child_path = File::Spec->canonpath(
                    File::Spec->catfile( $old_path, $_ ) );
                my $new_child_path = File::Spec->canonpath(
                    File::Spec->catfile( $new_path, $_ ) );

                # If we move the last media from a folder in previous iteration
                # of this loop, it can delete an empty Md5File via move_orphdat.
                next
                    if lc $_ eq $FileTypes::ORPHDAT_FILENAME
                    and !( -e $old_child_path );
                move_path( $old_child_path, $new_child_path, $dry_run );
            }

            # If we've emptied out $old_path my moving all its contents into
            # the already existing $new_path, we can safely delete it. If
            # not, this does nothing - also what we want.
            unless ($dry_run) {
                try_remove_empty_dir($old_path);
            }
        }
        else {

            # Dest dir doesn't exist, so we can just move the whole directory
            $move_internal->();
            print_crud(
                View::VERBOSITY_LOW,
                View::CRUD_UPDATE,
                "Moved directory '@{[pretty_path($old_path)]}'",
                " to '@{[pretty_path($new_path)]}'\n"
            );
        }
    }
    else {
        die "Programmer Error: unexpected type for object '$old_path'";
    }
}

# MODEL (File Operations) ------------------------------------------------------
sub ensure_parent_dir {
    my ( $path, $dry_run ) = @_;
    my $parent = parent_path($path);
    unless ( -d $parent ) {
        trace( View::VERBOSITY_MAX, "make_path('$parent');" );
        unless ($dry_run) {
            make_path($parent)
                or die "Failed to make directory '$parent': $!";
        }
        print_crud( View::VERBOSITY_MEDIUM, View::CRUD_CREATE,
            "Created dir '@{[pretty_path($parent)]}'\n" );
    }
}

# MODEL (File Operations) ------------------------------------------------------
# Removes the specified path if it's an empty directory and returns truthy.
# If it's not a directory or a directory with children, the do nothing
# and return falsy.
sub try_remove_empty_dir {
    my ($path) = @_;
    trace( View::VERBOSITY_MAX, "try_remove_empty_dir('$path');" );
    if ( -d $path and rmdir $path ) {
        print_crud(
            View::VERBOSITY_MEDIUM,
            View::CRUD_DELETE,
            "Deleted empty dir '@{[pretty_path($path)]}'\n"
        );
        return 1;
    }
    else {
        return 0;
    }
}

# MODEL (File Operations) ------------------------------------------------------
sub open_file {
    my ( $mode, $path ) = @_;
    trace( View::VERBOSITY_MAX, "open_file('$mode', '$path');" );
    open( my $fh, $mode, $path )
        or die "Couldn't open '$path' in $mode mode: $!";

    # TODO: Can we determine why and add a helpful error message. E.g. if in R/W
    # mode, maybe suggest they run one of the following
    #  $ chflags nouchg '$path'
    #  $ find <root_dir> -type f -name .orphdat -print -exec chflags nouchg {} \;
    return $fh;
}

1;
