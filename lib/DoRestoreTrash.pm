#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoRestoreTrash;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    doRestoreTrash
);

# Local uses
use FileOp qw(traverse_files move_path);
use PathOp qw(combine_path split_path);
use View;

# Execute restore-trash verb
sub doRestoreTrash {
    my (@globPatterns) = @_;
    my $dry_run = 0;
    traverse_files(
        sub {    # isDirWanted
            return 1;
        },
        sub {    # isFileWanted
            return 0;
        },
        sub {    # callback
            my ( $fullPath, $rootFullPath ) = @_;
            my ( $vol, $dir, $filename ) = split_path($fullPath);
            if ( lc $filename eq $FileTypes::TRASH_DIR_NAME ) {
                move_path( $fullPath, combine_path( $vol, $dir ), $dry_run );
            }
        },
        @globPatterns
    );
}

1;
