#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoPruneOrphdat;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    doPurgeMd5
);

# Local uses
use TraverseFiles qw(default_is_dir_wanted);
use OrPhDat       qw(find_orphdat trash_orphdat);
use View;

# Execute purge-md5 verb
sub doPurgeMd5 {
    my (@globPatterns) = @_;

    # Note that this is O(N^2) because it was easier to reuse already
    # written and tested code (especially on the error paths and atomic-ness).
    # To make this O(N) we'd want to unroll the find_orphdat method, in the loop
    # over all the keys just move the apprpriate Md5Info to a temp hash, do a
    # single append of the collected Md5Info to .orphtrash/.orphdat (similar
    # to append_orphdat_files), and then write back out the pruned .orphdat.
    # TODO: If there's another file with the same size/date/full-md5, then
    # rather than trash_orphdat, do delete_orphdat
    find_orphdat(
        \&default_is_dir_wanted,    # isDirWanted
        sub {                       # isFileWanted
            return 1;               # skip all filters for this
        },
        sub {                       #callback
            my ( $fullPath, $md5Info ) = @_;
            trash_orphdat($fullPath) unless -e $fullPath;
        },
        @globPatterns
    );
}

1;
