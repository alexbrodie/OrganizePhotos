#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoFindDupeDirs;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    doFindDupeDirs
);

# Local uses
use FileTypes;

# EXPERIMENTAL
# Execute find-dupe-dirs verb
sub doFindDupeDirs {

    # TODO: clean this up and use traverse_files
    my %keyToPaths = ();
    File::Find::find(
        {
            preprocess => sub {

                # skip trash
                return
                    grep { ( !-d ) || ( lc ne $FileTypes::TRASH_DIR_NAME ) } @_;
            },
            wanted => sub {
                if (
                    -d and ( /^(\d\d\d\d)-(\d\d)-(\d\d)\b/
                        or /^(\d\d)-(\d\d)-(\d\d)\b/
                        or /^(\d\d)(\d\d)(\d\d)\b/ )
                    )
                {

                    my $y = $1 < 20 ? $1 + 2000 : $1 < 100 ? $1 + 1900 : $1;
                    push @{ $keyToPaths{"$y-$2-$3"} }, File::Spec->rel2abs($_);
                }
            }
        },
        File::Spec->curdir()
    );

    #while (my ($key, $paths) = each %keyToPaths) {
    for my $key ( sort keys %keyToPaths ) {
        my $paths = $keyToPaths{$key};
        if ( @$paths > 1 ) {
            print "$key:\n";
            print "\t$_\n" for @$paths;
        }
    }
}

1;
