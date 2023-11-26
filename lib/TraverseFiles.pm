#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package TraverseFiles;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    default_is_dir_wanted
    default_is_file_wanted
    traverse_files
);

# Local uses
use FileTypes;
use PathOp;
use View;

# Library uses
use Const::Fast qw(const);
use File::Find  ();
use File::Spec  ();

our $filenameFilter = $FileTypes::MEDIA_TYPE_FILENAME_FILTER;

# Default implementation for traverse_files's isDirWanted param
sub default_is_dir_wanted {
    my ( $path, $root_path, $filename ) = @_;
    return ( lc $filename ne $FileTypes::TRASH_DIR_NAME );
}

# Default implementation for traverse_files's isDirWanted param
sub default_is_file_wanted {
    my ( $path, $root_path, $filename ) = @_;
    return ( lc $filename ne $FileTypes::ORPHDAT_FILENAME
            and $filename =~ /$filenameFilter/ );
}

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
# Returning false from is_dir_wanted prevents callback from being
# called on that directory and prevents further traversal such that descendants
# won't have calls to is_dir_wanted, is_file_wanted, or callback.
#
# Returning false from is_file_wanted prevents callback from being called for
# that file only.
#
# If is_dir_wanted is truthy for ancestor directories, and is_file_wanted is
# truthy, then callback is called for a file.
#
# Once all decendant items have been been processed, callback is called
# for a directory.
#
# It's important to not do anything with a side effect in is_dir_wanted or
# is_file_wanted other than return 0 or 1 to specify whether these dirs or files
# should be processed. That method is called breadth first, such that
# traversal of a subtree can be short circuited. Then process is called
# depth first such that the process of a dir doesn't occur until all the
# subitems have been processed.
#
# Note that if glob patterns overlap, then some files might invoke the
# callbacks more than once. For example,
#   traverse_files(..., 'Al*.jpg', '*ex.jpg');
# would match Alex.jpg twice, and invoke is_file_wanted/callback twice as well.
sub traverse_files {
    my ( $is_dir_wanted, $is_file_wanted, $callback, @glob_patterns ) = @_;
    $is_dir_wanted
        or die "Programmer Error: expected \$is_dir_wanted argument";
    $is_file_wanted
        or die "Programmer Error: expected \$is_file_wanted argument";
    $callback or die "Programmer Error: expected \$callback argument";

    # Record base now so that no_chdir doesn't affect rel2abs/abs2rel below
    # (and - bonus - just resolve and canonicalize once)
    my $current_dir = File::Spec->curdir();
    my $base_path   = File::Spec->rel2abs($current_dir);
    $base_path = File::Spec->canonpath($base_path);
    my $my_caller = 'unknown';
    for ( my $i = 1; $i < 16; $i++ ) {
        $my_caller = $1 and last if ( caller($i) )[3] =~ /^\w+::do_?(.*)/;
    }

    # the is_dir_wanted, is_file_wanted, and callback methods take the same
    # params which share the following computations
    my $make_full_path = sub {
        my ($partial_path) = @_;
        my $full_path = File::Spec->rel2abs( $partial_path, $base_path );
        $full_path = File::Spec->canonpath($full_path);
        -e $full_path
            or die
            "Programmer Error: enumerated file doesn't exist: '$full_path'";
        return $full_path;
    };

    # Returns 'f' if it's a wanted file, 'd' if it's a wanted dir
    # or falsy if not wanted
    my $is_wanted = sub {
        my ( $path, $root ) = @_;
        my ( $vol, $dir, $filename ) = split_path($path);
        if ( -d $path ) {

            # Never peek inside of a .git folder or any folder
            # containing .orphignore (opt out mechanism)
            if ( lc $filename eq '.git'
                or -e File::Spec->catfile( $path, '.orphignore' ) )
            {
                return '';
            }
            local $_ = undef;    # prevent use in the is_dir_wanted
            if ( $is_dir_wanted->( $path, $root, $filename ) ) {

                # \033[K == "erase to end of line"
                # \033[1A == "move cursor up 1 line"
                print
                    "$my_caller is traversing '@{[pretty_path($path)]}'...\033[K\n\033[1A";
                return 'd';
            }
        }
        elsif ( -f _ ) {

            # When MacOS copies files with alternate streams (e.g. from APFS)
            # to a volume that doesn't support it, they put the alternate
            # stream data in a file with the same path, but with a "._"
            # filename prefix. Though it's not a complete fix, for now, we'll
            # pretend these don't exist.
            if ( $filename =~ /^\._/
                or lc $filename eq '.orphignore' )
            {
                return '';
            }
            local $_ = undef;    # prevent use in the is_file_wanted
            if ( $is_file_wanted->( $path, $root, $filename ) ) {
                return 'f';
            }
        }
        else {
            die "Programmer Error: unknown object type for '$path'";
        }
        return '';
    };

    # Method to be called for each directory found in glob_patterns
    my $inner_traverse = sub {
        my ($root_partial_path) = @_;
        my $root = $make_full_path->($root_partial_path);
        print_crud( View::VERBOSITY_LOW, View::CRUD_READ,
            "$my_caller is traversing '$root_partial_path' ('$root')" );

        # Find::find's final wanted call for $root doesn't have a
        # matching preprocess call, so doing one up front for symetry with
        # all other pairs while also doing the other filtering we want.
        my $is_wanted_result = $is_wanted->( $root, $root );
        if ( $is_wanted_result eq 'd' ) {
            my $preprocess = sub {
                my @dirs  = ();
                my @files = ();
                for (@_) {

                    # Skip .. because it doesn't matter what we do, this isn't
                    # going to get passed to wanted, and it doesn't really make
                    # sense to traverse up in a recursive down enumeration.
                    # Also, skip '.' because we would otherwise process each
                    # dir twice, and $root once. This makes subdirs
                    # once and $root not at all.
                    next if ( ( $_ eq '.' ) or ( $_ eq '..' ) );

                    # The values used here to compute the path relative
                    # to $base_path matches the values of wanted's
                    # implementation, and both work the same whether
                    # no_chdir is set or not.
                    my $path = $make_full_path->(
                        File::Spec->catfile( $File::Find::dir, $_ ) );
                    my $result = $is_wanted->( $path, $root );
                    if ( $result eq 'd' ) {
                        push @dirs, $_;
                    }
                    elsif ( $result eq 'f' ) {
                        push @files, $_;
                    }
                    elsif ($result) {
                        die
                            "Programmer Error: unknown return value from is_wanted: '$result'";
                    }
                }

                # Dirs first will be depth first traversal (nieces/nephews first).
                # Files first will be breadth first traversal (aunts/uncles first).
                # This is not the same as what bydepth does which deals in parents
                # and children.
                return ( sort(@dirs), sort(@files) );
            };
            my $wanted = sub {

                # The values used here to compute the path relative
                # to $base_path matches the values of preprocess'
                # implementation, and both work the same whether
                # no_chdir is set or not.
                my $path = $make_full_path->($File::Find::name);
                local $_ = undef;    # prevent use in callback
                $callback->( $path, $root );
            };
            File::Find::find(
                {
                    bydepth    => 1,
                    no_chdir   => 1,
                    preprocess => $preprocess,
                    wanted     => $wanted
                },
                $root
            );
        }
        elsif ( $is_wanted_result eq 'f' ) {
            local $_ = undef;    # prevent use in callback
            $callback->( $root, $root );
        }
        elsif ($is_wanted_result) {
            die
                "Programmer Error: unknown return value from is_wanted: $is_wanted_result";
        }
    };
    if (@glob_patterns) {
        for my $pattern (@glob_patterns) {

            # TODO: Is this workaround to handle globbing with spaces for
            # Windows compatible with MacOS (with and without spaces)? Does it
            # work okay with single quotes in file/dir names on each platform?
            $pattern = "'$pattern'";
            $inner_traverse->($_) for glob $pattern;
        }
    }
    else {

        # If no glob patterns are provided, just search current directory
        $inner_traverse->($current_dir);
    }
}

1;
