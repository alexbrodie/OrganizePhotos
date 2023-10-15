#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package OrPhDat;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    resolve_orphdat
    find_orphdat
    write_orphdat
    move_orphdat
    trash_orphdat
    delete_orphdat
    append_orphdat_files
    make_orphdat_base
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

my $CACHED_ORPHDAT_PATH = '';
my $CACHED_ORPHDAT_SET = {};

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
#            the form $MD5_DIGEST_PATTERN.

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
# add_only:
#   When this mode is true it causes the method to exit early if *any* cached
#   info is available whether it is up to date or not. If that cached Md5Info
#   is available, the MediaFile is not accessed, the MD5 is not computed, and 
#   the cached value is returned without any verification. Note that if a 
#   cached_orphdat parameter is provided, this method will always simply return
#   that value.
#
# force_recalc:
#   If truthy, this prevents the use of cached information (including the
#   caller supplied cached_orphdat). The hash is always calculated,
#   resolved, and caches updated.
#
# cached_orphdat:
#   Caller supplied cached Md5Info value that this method will check to see
#   if it is up to date and return that value if so (in the same way and
#   together with the other caches). This is useful for ensuring Md5Info is up
#   to date even if operations have taken place since originally retrieved.
sub resolve_orphdat {
    my ($path, $add_only, $force_recalc, $cached_orphdat) = @_;
    trace(View::VERBOSITY_MAX, "resolve_orphdat('$path', $add_only, $force_recalc, ", 
        defined $cached_orphdat ? '{...}' : 'undef', ');');
    # First try to get suitable Md5Info from various cache locations
    # without opening or hashing the MediaFile
    my ($orphdat_path, $orphdat_key) = get_orphdat_path_and_key($path);
    my $new_orphdat_base = make_orphdat_base($path);
    unless ($force_recalc) {
        if (defined $cached_orphdat) {
            my $cache_result = check_cached_orphdat(
                $path, $add_only, 'Caller', 
                $cached_orphdat, $new_orphdat_base);
            # Caller supplied cached Md5Info is up to date
            return $cache_result if $cache_result;
        }
        if ($orphdat_path eq $CACHED_ORPHDAT_PATH) {
            $cached_orphdat = $CACHED_ORPHDAT_SET->{$orphdat_key};
            my $cache_result = check_cached_orphdat(
                $path, $add_only, 'Memory', 
                $cached_orphdat, $new_orphdat_base);
            # Memory cache of Md5Info is up to date
            return $cache_result if $cache_result;
        } else {
            trace(View::VERBOSITY_HIGH, "Memory cache miss for '$path', cache was '$CACHED_ORPHDAT_PATH'");
        }
    }
    trace(View::VERBOSITY_HIGH, "Opening cache '$orphdat_path' for '$path'");
    my ($orphdat_file, $orphdat_set) = read_or_create_orphdat_file($orphdat_path);
    my $old_orphdat = $orphdat_set->{$orphdat_key};
    unless ($force_recalc) {
        my $cache_result = check_cached_orphdat(
            $path, $add_only, 'File', 
            $old_orphdat, $new_orphdat_base);
        # File cache of Md5Info is up to date
        return $cache_result if $cache_result;
    }
    # No suitable cache, so fill in/finalize the Md5Info that we'll return
    # TODO: consolidate opening file multiple times from stat and calculate_hash
    my $hash_result = calculate_hash($path);
    my $new_orphdat = { %$hash_result, %$new_orphdat_base };
    # Do verification on the old persisted Md5Info and the new calculated Md5Info
    if (defined $old_orphdat) {
        if ($old_orphdat->{md5} eq $new_orphdat->{md5}) {
            # Matches last recorded hash, but still continue and call
            # set_orphdat_and_write_file to handle other bookkeeping
            # to ensure we get a cache hit and short-circuit next time.
            trace(View::VERBOSITY_HIGH, "Verified MD5 for '@{[pretty_path($path)]}'");
        } elsif ($old_orphdat->{full_md5} eq $new_orphdat->{full_md5}) {
            # Full MD5 match and content mismatch. This should only be
            # expected when we change how to calculate content MD5s.
            # If that's the case (i.e. the expected version is not up to
            # date), then we should just update the MD5s. If it's not the
            # case, then it's unexpected and some kind of programer error.
            if (is_hash_version_current($path, $old_orphdat->{version})) {
                die <<"EOM";
Unexpected state: full MD5 match and content MD5 mismatch for
$path
             version  full_md5                          md5
  Expected:  $old_orphdat->{version}        $old_orphdat->{full_md5}  $old_orphdat->{md5}
    Actual:  $new_orphdat->{version}        $new_orphdat->{full_md5}  $new_orphdat->{md5}
EOM
            } else {
                trace(View::VERBOSITY_MEDIUM, "Content MD5 calculation has changed, upgrading from version ",
                      "$old_orphdat->{version} to $new_orphdat->{version} for '$path'");
            }
        } else {
            # Mismatch and we can update MD5, needs resolving...
            # TODO: This doesn't belong here in the model, it should be moved
            my @prompt = ( 
                Term::ANSIColor::colored("MISMATCH OF MD5 for '@{[pretty_path($path)]}'", 'red'), 
                "\n",
                "Ver  Full MD5                          Content MD5                       Date Modified        Size\n");
            for ($old_orphdat, $new_orphdat)
            {
                push @prompt, sprintf("%3d  %-16s  %-16s  %-19s  %s\n",
                    $_->{version}, $_->{full_md5}, $_->{md5}, 
                    POSIX::strftime('%F %T', localtime $_->{mtime}), 
                    Number::Bytes::Human::format_bytes($_->{size}));
            }
            push @prompt, <<EOM;
[I]gnore new calculated hash and use cached value
[O]verwrite cached value with new data
[S]kip using either conflicting value
[Q]uit
EOM
            print @prompt;
            while (1) {
                print "i/o/s/q? ", "\a"; 
                chomp(my $in = <STDIN>);
                if ($in eq 'i') {
                    # Ignore new_orphdat (including skipping persisting), so we 
                    # don't want to return that. Return what is/was in the cache.
                    return { %$old_orphdat, %$new_orphdat_base };
                } elsif ($in eq 'o') {
                    # Persist and use new_orphdat
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
    set_orphdat_and_write_file($path, $new_orphdat, $orphdat_path, $orphdat_key, $orphdat_file, $orphdat_set);
    return $new_orphdat;
}

# MODEL (MD5) ------------------------------------------------------------------
# For each item in each per-directory database file in [glob_patterns], 
# invoke [callback] passing it full path and MD5 hash as arguments like
#      callback($path, $orphdat)
# TODO: add support for files (not just dirs) in the glob pattern
sub find_orphdat {
    my ($is_dir_wanted, $is_file_wanted, $callback, @glob_patterns) = @_;
    $is_dir_wanted or die "Programmer Error: expected \$is_dir_wanted argument";
    $is_file_wanted or die "Programmer Error: expected \$is_file_wanted argument";
    $callback or die  "Programmer Error: expected \$callback argument";
    trace(View::VERBOSITY_MAX, 'find_orphdat(...); with @glob_patterns of', 
          (@glob_patterns ? map { "\n\t'$_'" } @glob_patterns : ' (current dir)'));
    traverse_files(
        $is_dir_wanted,
        sub {  # is_file_wanted
            my ($path, $root, $filename) = @_;
            return (lc $filename eq $FileTypes::ORPHDAT_FILENAME); # only process Md5File files
        },
        sub {  # callback
            my ($path, $root) = @_;
            if (-f $path) {
                my ($vol, $dir, $filename) = split_path($path);
                my (undef, $orphdat_set) = read_orphdat_file('<', $path);
                for my $orphdat_key (sort { $orphdat_set->{$a}->{filename} cmp $orphdat_set->{$b}->{filename} } keys %$orphdat_set) {
                    my $orphdat = $orphdat_set->{$orphdat_key};
                    my $other_filename = $orphdat->{filename};
                    my $other_path = change_filename($path, $other_filename);
                    if ($is_file_wanted->($other_path, $root, $other_filename)) {
                        $callback->($other_path, $orphdat);
                    }
                }
            }
        },
        @glob_patterns);
}

# MODEL (MD5) ------------------------------------------------------------------
# Gets the Md5Path, Md5Key for a MediaPath.
sub get_orphdat_path_and_key {
    my ($path) = @_;
    my ($orphdat_path, $orphdat_key) = change_filename($path, $FileTypes::ORPHDAT_FILENAME);
    return ($orphdat_path, lc $orphdat_key);
}

# MODEL (MD5) ------------------------------------------------------------------
# Stores Md5Info for a MediaPath. If the the provided data is undef, removes
# existing information via delete_orphdat. Returns the previous Md5Info
# value if it existed (or undef if not).
sub write_orphdat {
    my ($path, $new_orphdat) = @_;
    trace(View::VERBOSITY_MAX, "write_orphdat('$path', {...});");
    if ($new_orphdat) {
        my ($orphdat_path, $orphdat_key) = get_orphdat_path_and_key($path);
        my ($orphdat_file, $orphdat_set) = read_or_create_orphdat_file($orphdat_path);
        return set_orphdat_and_write_file($path, $new_orphdat, $orphdat_path, $orphdat_key, $orphdat_file, $orphdat_set);
    } else {
        return delete_orphdat($path);
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Moves a Md5Info for a file from one directory's storage to another. 
sub move_orphdat {
    my ($source_path, $target_path) = @_;
    trace(View::VERBOSITY_MAX, "move_orphdat('$source_path', " . 
                         (defined $target_path ? "'$target_path'" : 'undef') . ");");
    my ($source_orphdat_path, $source_orphdat_key) = get_orphdat_path_and_key($source_path);
    unless (-e $source_orphdat_path) {
        trace(View::VERBOSITY_HIGH, "Can't move/remove Md5Info for '$source_orphdat_key' from missing '$source_orphdat_path'"); 
        return undef;
    }
    my ($source_orphdat_file, $source_orphdat_set) = read_orphdat_file('+<', $source_orphdat_path);
    unless (exists $source_orphdat_set->{$source_orphdat_key}) {
        trace(View::VERBOSITY_HIGH, "Can't move/remove missing Md5Info for '$source_orphdat_key' from '$source_orphdat_path'");
        return undef;
    }
    # For a move we do a copy then a delete, but show it as a single CRUD
    # operation. The logging info will be built up during the copy phase
    # and then logged after deleting.
    my ($crud_op, $crud_msg);
    my $source_orphdat = $source_orphdat_set->{$source_orphdat_key};
    if ($target_path) {
        my (undef, undef, $target_filename) = split_path($target_path);
        my $new_orphdat = { %$source_orphdat, filename => $target_filename };
        # The code for the remainder of this scope is very similar to 
        #   write_orphdat($target_path, $new_orphdat);
        # but with additional cases considered and improved context in traces
        my ($target_orphdat_path, $target_orphdat_key) = get_orphdat_path_and_key($target_path);
        my ($target_orphdat_file, $target_orphdat_set);
        if ($source_orphdat_path eq $target_orphdat_path) {
            $target_orphdat_set = $source_orphdat_set;
        } else {
            ($target_orphdat_file, $target_orphdat_set) = read_or_create_orphdat_file($target_orphdat_path);
        }
        # The code for the remainder of this scope is very similar to 
        #   set_orphdat_and_write_file($target_path, $new_orphdat, $target_orphdat_path, $target_orphdat_key, $target_orphdat_file, $target_orphdat_set);
        # but with additional cases considered and improved context in traces
        my $existing_orphdat = $target_orphdat_set->{$target_orphdat_key};
        if ($existing_orphdat and Data::Compare::Compare($existing_orphdat, $new_orphdat)) {
            # Existing Md5Info at target is identical, so target is up to date already
            $crud_op = View::CRUD_DELETE;
            $crud_msg = "Removed cache data for '@{[pretty_path($source_path)]}' (up to date " .
                        "data already exists for '@{[pretty_path($target_path)]}')";
        } else {
            $target_orphdat_set->{$target_orphdat_key} = $new_orphdat;
            if ($target_orphdat_file) {
                trace(View::VERBOSITY_HIGH, "Writing '$target_orphdat_path' after moving entry for '$target_orphdat_key' elsewhere");
                write_orphdat_file($target_orphdat_path, $target_orphdat_file, $target_orphdat_set);
            }
            $crud_op = View::CRUD_UPDATE;
            $crud_msg = "Moved cache data for '@{[pretty_path($source_path)]}' to '@{[pretty_path($target_path)]}'";
            if (defined $existing_orphdat) {
                $crud_msg = "$crud_msg overwriting existing value";
            }
        }
    } else {
        # No target path, this is a delete only
        $crud_op = View::CRUD_DELETE;
        $crud_msg = "Removed MD5 for '@{[pretty_path($source_path)]}'";
    }
    # TODO: Should this if/else code move to write_orphdat_file/set_orphdat_and_write_file such
    #       that any time someone tries to write an empty hashref, it deletes the file?
    delete $source_orphdat_set->{$source_orphdat_key};
    if (%$source_orphdat_set) {
        trace(View::VERBOSITY_HIGH, "Writing '$source_orphdat_path' after removing MD5 for '$source_orphdat_key'");
        write_orphdat_file($source_orphdat_path, $source_orphdat_file, $source_orphdat_set);
    } else {
        # Empty files create trouble down the line (especially with move-merges)
        trace(View::VERBOSITY_HIGH, "Deleting '$source_orphdat_path' after removing MD5 for '$source_orphdat_key' (the last one)");
        close($source_orphdat_file);
        unlink($source_orphdat_path) or die "Couldn't delete '$source_orphdat_path': $!";
        print_crud(View::VERBOSITY_MEDIUM, View::CRUD_DELETE, 
            "Deleted empty file '@{[pretty_path($source_orphdat_path)]}'\n");
    }
    print_crud(View::VERBOSITY_LOW, $crud_op, $crud_msg, "\n");
    return $source_orphdat;
}

# MODEL (MD5) ------------------------------------------------------------------
# Moves Md5Info for a MediaPath to local trash. Returns the previous Md5Info
# value if it existed (or undef if not).
sub trash_orphdat {
    my ($path) = @_;
    my $dry_run = 0;
    trace(View::VERBOSITY_MAX, "trash_orphdat('$path');");
    my $trash_path = get_trash_path($path);
    ensure_parent_dir($trash_path, $dry_run);
    return move_orphdat($path, $trash_path);
}

# MODEL (MD5) ------------------------------------------------------------------
# Removes Md5Info for a MediaPath from storage. Returns the previous Md5Info
# value if it existed (or undef if not).
sub delete_orphdat {
    my ($path) = @_;
    trace(View::VERBOSITY_MAX, "delete_orphdat('$path');");
    return move_orphdat($path, undef);
}

# MODEL (MD5) ------------------------------------------------------------------
# Takes a list of Md5Paths, and stores the concatinated Md5Info to the first
# specified file. Dies without writing anything on key collisions.
sub append_orphdat_files {
    my ($target_orphdat_path, @source_orphdat_paths) = @_;
    trace(View::VERBOSITY_MAX, 'append_orphdat_files(', join(', ', map { "'$_'" } @_), ');');
    my ($target_orphdat_file, $target_orphdat_set) = read_or_create_orphdat_file($target_orphdat_path);
    my $old_target_orphdat_set_count = scalar keys %$target_orphdat_set;
    my $dirty = 0;
    for my $source_orphdat_path (@source_orphdat_paths) {
        my (undef, $source_orphdat_set) = read_orphdat_file('<', $source_orphdat_path);
        while (my ($orphdat_key, $source_orphdat) = each %$source_orphdat_set) {
            if (exists $target_orphdat_set->{$orphdat_key}) {
                my $target_orphdat = $target_orphdat_set->{$orphdat_key};
                Data::Compare::Compare($source_orphdat, $target_orphdat) or die
                    "Can't append MD5 info from '$source_orphdat_path' to '$target_orphdat_path'" .
                    " due to key collision for '$orphdat_key'";
            } else {
                $target_orphdat_set->{$orphdat_key} = $source_orphdat;
                $dirty = 1;
            }
        }
    }
    if ($dirty) {
        trace(View::VERBOSITY_HIGH, "Writing '$target_orphdat_path' after appending data from ",
              scalar @source_orphdat_paths, " files");
        write_orphdat_file($target_orphdat_path, $target_orphdat_file, $target_orphdat_set);
        my $items_added = (scalar keys %$target_orphdat_set) - $old_target_orphdat_set_count;
        print_crud(View::VERBOSITY_LOW, View::CRUD_CREATE, 
            "Added $items_added MD5s to '${\pretty_path($target_orphdat_path)}' from ",
            join ', ', map { "'${\pretty_path($_)}'" } @source_orphdat_paths);
    } else {
        trace(View::VERBOSITY_HIGH, "Skipping no-op append of cache for '$target_orphdat_path'");
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# This is a utility for updating Md5Info. It opens the Md5Path R/W and parses
# it. Returns the Md5File and Md5Set.
sub read_or_create_orphdat_file {
    my ($orphdat_path) = @_;
    trace(View::VERBOSITY_MAX, "read_or_create_orphdat_file('$orphdat_path');");
    if (-e $orphdat_path) {
        return read_orphdat_file('+<', $orphdat_path);
    } else {
        my $fh = open_orphdat_file('+>', $orphdat_path);
        print_crud(View::VERBOSITY_MEDIUM, View::CRUD_CREATE, 
            "Created cache at '@{[pretty_path($orphdat_path)]}'\n");
        return ($fh, {});
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Low level helper routine to open a Md5Path and deserialize into a OM (Md5Set)
# which can be read, modified, and/or passed to write_orphdat_file or methods built 
# on that. Returns the Md5File and Md5Set.
sub read_orphdat_file {
    my ($open_mode, $orphdat_path) = @_;
    trace(View::VERBOSITY_MAX, "read_orphdat_file('$open_mode', '$orphdat_path');");
    my $orphdat_file = open_orphdat_file($open_mode, $orphdat_path);
    # If the first char is a open curly brace, treat as JSON,
    # otherwise do the older simple "name: md5\n" format parsing
    my $use_json = 0;
    while (<$orphdat_file>) {
        if (/^\s*([^\s])/) {
            $use_json = 1 if $1 eq '{';
            last;
        }
    }
    seek($orphdat_file, 0, 0) or die "Couldn't reset seek on file: $!";
    my $orphdat_set = {};
    if ($use_json) {
        # decode (and decode_json) converts UTF-8 binary string to perl data struct
        $orphdat_set = JSON::decode_json(join '', <$orphdat_file>);
        # TODO: Consider validating parsed content - do a lc on
        #       filename/md5s/whatever, and verify vs $MD5_DIGEST_PATTERN???
        # If there's no version data, then it is version 1. We didn't
        # start storing version information until version 2.
        while (my ($key, $values) = each %$orphdat_set) {
            # Populate missing values so we don't have to handle sparse data everywhere
            $values->{version} = 1 unless exists $values->{version};
            $values->{filename} = $key unless exists $values->{filename};
        }
    } else {
        # Parse as simple "name: md5" text
        for (<$orphdat_file>) {
            /^([^:]+):\s*($ContentHash::MD5_DIGEST_PATTERN)$/ or die "Unexpected line in '$orphdat_path': $_";
            # We use version 0 here for the very old way before we went to
            # JSON when we added more info than just the full file MD5
            my $full_md5 = lc $2;
            $orphdat_set->{lc $1} = { version => 0, filename => $1, 
                                 md5 => $full_md5, full_md5 => $full_md5 };
        }
    }
    update_orphdat_cache($orphdat_path, $orphdat_set);
    print_crud(View::VERBOSITY_MEDIUM, View::CRUD_READ, 
        "Read cache from '@{[pretty_path($orphdat_path)]}'\n");
    return ($orphdat_file, $orphdat_set);
}

# MODEL (MD5) ------------------------------------------------------------------
# Lower level helper routine that updates a MD5 info, and writes it to the file
# if necessary. The $orphdat_file and $orphdat_set params should be the existing data
# (like is returned from read_or_create_orphdat_file or read_orphdat_file). The orphdat_key and
# new_orphdat represent the new data. Returns the previous md5Info value. 
sub set_orphdat_and_write_file {
    my ($path, $new_orphdat, $orphdat_path, $orphdat_key, $orphdat_file, $orphdat_set) = @_;
    trace(View::VERBOSITY_MAX, "set_orphdat_and_write_file('$path', ...);");
    my $old_orphdat = $orphdat_set->{$orphdat_key};
    if ($old_orphdat and Data::Compare::Compare($old_orphdat, $new_orphdat)) {
        trace(View::VERBOSITY_HIGH, "Skipping no-op update of cache for '$path'");
    } else {
        $orphdat_set->{$orphdat_key} = $new_orphdat;
        trace(View::VERBOSITY_HIGH, "Writing '$orphdat_path' after updating value for key '$orphdat_key'");
        write_orphdat_file($orphdat_path, $orphdat_file, $orphdat_set);
        if (defined $old_orphdat) {
            my $changed_fields = join ', ', sort grep {
                !Data::Compare::Compare($old_orphdat->{$_}, $new_orphdat->{$_})
            } keys %$new_orphdat;
            print_crud(View::VERBOSITY_LOW, View::CRUD_UPDATE, 
                "Updated cache entry for '@{[pretty_path($path)]}': $changed_fields\n");
        } else {
            print_crud(View::VERBOSITY_LOW, View::CRUD_CREATE, 
                "Added cache entry for '@{[pretty_path($path)]}'\n");
        }
    }
    return $old_orphdat;
}

# MODEL (MD5) ------------------------------------------------------------------
# Lowest level helper routine to serialize OM into a file handle.
# Caller is expected to print_crud with more context if this method returns
# successfully.
sub write_orphdat_file {
    my ($orphdat_path, $orphdat_file, $orphdat_set) = @_;
    # TODO: write this out as UTF8 using :encoding(UTF-8):crlf (or :utf8:crlf?)
    #       and writing out the "\x{FEFF}" BOM. Not sure how to do that in
    #       a fully cross compatable way (older file versions as well as
    #       Windows/Mac compat)
    trace(View::VERBOSITY_MAX, "write_orphdat_file('$orphdat_path', <file>, { hash of @{[ scalar keys %$orphdat_set ]} items });");
    verify_orphdat_path($orphdat_path);
    seek($orphdat_file, 0, 0) or die "Couldn't reset seek on file: $!";
    truncate($orphdat_file, 0) or die "Couldn't truncate file: $!";
    if (%$orphdat_set) {
        # encode (and encode_json) produces UTF-8 binary string
        print $orphdat_file JSON->new->allow_nonref->pretty->canonical->encode($orphdat_set);
    } else {
        warn "Writing empty data to $orphdat_path";
    }
    update_orphdat_cache($orphdat_path, $orphdat_set);
    print_crud(View::VERBOSITY_MEDIUM, View::CRUD_UPDATE, 
        "Wrote cache to '@{[pretty_path($orphdat_path)]}'\n");
}

# MODEL (MD5) ------------------------------------------------------------------
# Opens a filehandle given a path to a .orphdat file. This adds safeguards
# and encoding handling on top of open_file. Use in place of open_file for
# .orphdat files.
sub open_orphdat_file {
    my ($open_mode, $orphdat_path) = @_;
    verify_orphdat_path($orphdat_path);
    return open_file($open_mode . ':crlf', $orphdat_path);
}

# MODEL (MD5) ------------------------------------------------------------------
# Verify filename of provided path is $ORPHDAT_FILENAME
sub verify_orphdat_path {
    my ($orphdat_path) = @_;
    my (undef, undef, $filename) = split_path($orphdat_path);
    $filename eq $FileTypes::ORPHDAT_FILENAME or die "Expected cache filename '${FileTypes::ORPHDAT_FILENAME}' for '$orphdat_path'";
}

# MODEL (MD5) ------------------------------------------------------------------
sub update_orphdat_cache {
    my ($orphdat_path, $orphdat_set) = @_;
    $CACHED_ORPHDAT_PATH = $orphdat_path;
    $CACHED_ORPHDAT_SET = Storable::dclone($orphdat_set);
}

# MODEL (MD5) ------------------------------------------------------------------
# Makes the base of a md5Info hash that can be used with
# or added to the results of calculate_hash to produce
# a full md5Info.
#   filename:   the filename (only) of the path
#   size:       size of the file in bytes
#   mtime:      the mtime of the file
sub make_orphdat_base {
    my ($path) = @_;
    my $stats = File::stat::stat($path) or die "Couldn't stat '$path': $!";
    my (undef, undef, $filename) = split_path($path);
    return { filename => $filename, size => $stats->size, mtime => $stats->mtime };
}

# MODEL (MD5) ------------------------------------------------------------------
# Returns a full Md5Info constructed from the cache if it can be used for the
# specified base-only Md5Info without bothering to calculate_hash. 
sub check_cached_orphdat {
    my ($path, $add_only, $cache_type, $cached_orphdat, $current_orphdat_base) = @_;
    #trace(View::VERBOSITY_MAX, 'check_cached_orphdat(...);');
    unless (defined $cached_orphdat) {
        # Note that this is assumed context from the caller, and not actually
        # something true based on this sub
        trace(View::VERBOSITY_HIGH, "$cache_type cache miss for '$path', lookup failed");
        return undef;
    }

    if ($add_only) {
        trace(View::VERBOSITY_HIGH, "$cache_type cache hit for '$path', add-only mode");
    } else {
        my @delta = ();
        unless (is_hash_version_current($path, $cached_orphdat->{version})) {
            push @delta, 'version';
        }
        unless (lc $current_orphdat_base->{filename} eq lc $cached_orphdat->{filename}) {
            push @delta, 'name';
        }
        unless (defined $cached_orphdat->{size} and 
            $current_orphdat_base->{size} == $cached_orphdat->{size}) {
            push @delta, 'size';
        }
        unless (defined $cached_orphdat->{mtime} and 
            $current_orphdat_base->{mtime} == $cached_orphdat->{mtime}) {
            push @delta, 'mtime';
        }
        if (@delta) {
            trace(View::VERBOSITY_HIGH, "$cache_type cache miss for '$path', different " . join('/', @delta));
            return undef;
        }
        trace(View::VERBOSITY_HIGH, "$cache_type cache hit for '$path', version/name/size/mtime match");
    }

    return { %{Storable::dclone($cached_orphdat)}, %$current_orphdat_base };
}

1;