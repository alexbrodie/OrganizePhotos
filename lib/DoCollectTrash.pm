#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoCollectTrash;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    doCollectTrash
);

# Local uses
use FileOp qw(traverse_files trash_path_with_root);
use PathOp qw(split_path);

# Execute collect-trash verb
sub doCollectTrash {
    my (@globPatterns) = @_;
    traverse_files(
        sub {  # isDirWanted
            return 1;
        },
        sub {  # isFileWanted
            return 0;
        },
        sub {  # callback
            my ($fullPath, $rootFullPath) = @_;
            my ($vol, $dir, $filename) = split_path($fullPath);
            if (lc $filename eq $FileTypes::TRASH_DIR_NAME) {
                # Convert root/bunch/of/dirs/.orphtrash to root/.orphtrash/bunch/of/dirs
                trash_path_with_root($fullPath, $rootFullPath);
            }
        },
        @globPatterns);
}

1;