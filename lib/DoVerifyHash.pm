#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoVerifyHash;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    do_verify_md5
);

# Local uses
use ContentHash qw(calculate_hash);
use FileOp      qw(default_is_dir_wanted default_is_file_wanted);
use OrPhDat     qw(find_orphdat make_orphdat_base);
use View;

# Execute verify-md5 verb
sub do_verify_md5 {
    my (@glob_patterns) = @_;
    my $all             = 0;
    my $skip_md5        = 0;
    my $file_count      = 0;
    find_orphdat(
        \&default_is_dir_wanted,     # isDirWanted
        \&default_is_file_wanted,    # isFileWanted
        sub {                        #callback
            my ( $path, $expected_md5_info ) = @_;
            $file_count++;
            if ( -e $path ) {

                # File exists
                my $actual_md5_base = make_orphdat_base($path);
                my $same_mtime =
                    $expected_md5_info->{mtime} eq $actual_md5_base->{mtime};
                my $same_size =
                    $expected_md5_info->{size} eq $actual_md5_base->{size};
                my $same_md5 = 1;
                unless ($skip_md5) {
                    my $actual_md5_hash = calculate_hash($path);
                    $same_md5 = $expected_md5_info->{full_md5} eq
                        $actual_md5_hash->{full_md5};
                }
                if ( $same_mtime && $same_size && $same_md5 ) {

                    # Everything checks out
                    print "Verified MD5 for '@{[pretty_path($path)]}'\n";
                    return;
                }
                else {
                    # Hash mismatch, needs input
                    warn "ERROR: MD5 mismatch for '@{[pretty_path($path)]}'";
                }
            }
            else {
                # File doesn't exist
                warn "ERROR: Missing file: '@{[pretty_path($path)]}'";
            }

            unless ($all) {
                while (1) {
                    print "Ignore, ignore All, Quit (i/a/q)? ", "\a";
                    chomp( my $in = <STDIN> );
                    if ( $in eq 'i' ) {
                        last;
                    }
                    elsif ( $in eq 'a' ) {
                        $all = 1;
                        last;
                    }
                    elsif ( $in eq 'q' ) {
                        exit 0;
                    }
                }
            }
        },
        @glob_patterns
    );
    print "Checked $file_count files\n";
}

1;
