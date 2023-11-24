#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoCheckHash;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    do_check_hash
);

# Local uses
use FileOp  qw(traverse_files default_is_dir_wanted default_is_file_wanted);
use OrPhDat qw(resolve_orphdat);

# Execute check-md5 verb
sub do_check_hash {
    my ( $add_only, $force_recalc, @glob_patterns ) = @_;
    traverse_files(
        \&default_is_dir_wanted,     # isDirWanted
        \&default_is_file_wanted,    # isFileWanted
        sub {                        # callback
            my ( $fullPath, $rootFullPath ) = @_;
            -f $fullPath
                and
                resolve_orphdat( $fullPath, $add_only, $force_recalc, undef );
        },
        @glob_patterns
    );
}

1;
