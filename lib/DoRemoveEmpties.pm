#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoRemoveEmpties;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    doRemoveEmpties
);

# Local uses
use FileOp    qw(traverse_files default_is_dir_wanted trash_path);
use FileTypes qw(is_reserved_system_filename);
use PathOp    qw(parent_path);
use View;

# Execute remove-empties verb
sub doRemoveEmpties {
    my (@globPatterns) = @_;

    # Map from directory absolute path to sub-item count
    my %dirSubItemsMap = ();
    traverse_files(
        \&default_is_dir_wanted,    # isDirWanted
        sub {                       # isFileWanted
            my ( $fullPath, $rootFullPath, $filename ) = @_;

            # These files don't count - they're trashible, ignore them (by
            # not processing) as if they didn't exist and let them get
            # cleaned up if the folder gets trashed
            return 0 if is_reserved_system_filename($filename);
            return 0 if ( lc $filename eq $FileTypes::ORPHDAT_FILENAME );

            # TODO: exclude zero byte or hidden files as well?
            return 1;    # Other files count
        },
        sub {            # callback
            my ( $fullPath, $rootFullPath ) = @_;
            if ( -d $fullPath ) {

                # at this point, all the sub-items should be processed, see how many
                my $subItemCount = $dirSubItemsMap{$fullPath};

                # As part of a later verification check, we'll remove this dir
                # from our map. Then if other sub-items are added after we process
                # this parent dir right now, then we could have accidentally trashed
                # a non-trashable dir.
                delete $dirSubItemsMap{$fullPath};

                # If this dir is empty, then we'll want to trash it and have the
                # parent dir ignore it like trashable files (e.g. $FileTypes::ORPHDAT_FILENAME). If
                # it's not trashable, then fall through to add this to its parent
                # dir's list (to prevent the parent from being trashed).
                unless ($subItemCount) {
                    trash_path($fullPath);
                    return;
                }
            }

            # We don't mark the root item (file or dir) like all the subitems, because
            # we're not looking to remove the root's parent based on some partial knowledge
            # (e.g. if dir Alex has a lot of non-empty stuff in it and a child dir named
            # Quinn, then we wouldn't want to consider trashing Alex if we check only Quinn)
            if ( $fullPath ne $rootFullPath ) {
                my $parentFullPath = parent_path($fullPath);
                $dirSubItemsMap{$parentFullPath}++;
            }
        },
        @globPatterns
    );
    if (%dirSubItemsMap) {

        # See notes in above callback
        die "Programmer Error: unprocessed items in doRemoveEmpties map";
    }
}

1;
