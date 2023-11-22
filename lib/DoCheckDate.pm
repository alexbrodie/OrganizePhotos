#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoCheckDate;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    do_check_date
);

# Local uses
use FileOp qw(traverse_files default_is_dir_wanted default_is_file_wanted move_path);
use FileTypes qw(get_sidecar_paths);
use MetaData qw(get_date_taken check_path_dates);
use View qw(pretty_path print_with_icon);

# EXPERIMENTAL
sub do_check_date {
    my (@globPatterns) = @_;
    my $dry_run = 0;
    #$View::Verbosity = View::VERBOSITY_HIGH;
    my $all = 0;
    traverse_files(
        \&default_is_dir_wanted, # isDirWanted
        \&default_is_file_wanted, # isFileWanted
        sub {  # callback
            my ($path, $root_path) = @_;

            my $date = get_date_taken($path);
            my $fixed_path = check_path_dates($path, $date);
            #$fixed_path =~ s/\/(\d{4}-\d\d-\d\d-)(\d{4}-\d\d-\d\d-)/\/$1/;
            #$fixed_path =~ s/(\w{4}\d{4})[- ]\d(\.\w{2,4})$/$1$2/;

            if ($path ne $fixed_path) {
                for (get_sidecar_paths($path)) {
                    my $sidecar_fixed_path = check_path_dates($_, $date);
                    warn "sidecars not yet supported, path to fix has sidecars: '". pretty_path($path) ."'";
                    return;
                }

                if (-e $fixed_path) {
                    print_with_icon('[!]', 'yellow', 
                                    "Wrong date in path '". pretty_path($path) ."'\n".
                                    "         should be '". pretty_path($fixed_path) ."'\n".
                                    "which already exists.");
                } else {
                    print_with_icon('[?]', 'yellow', 
                                    " from '". pretty_path($path) ."'\n".
                                    "   to '". pretty_path($fixed_path) ."'");
                    my $move = $all;
                    unless ($move) {
                        while (1) {
                            print "Move file (y/n/a/q)? ";
                            chomp(my $in = <STDIN>);
                            if ($in eq 'y') {
                                $move = 1;
                                last;
                            } elsif ($in eq 'n') {
                                last;
                            } elsif ($in eq 'a') {
                                $move = 1;
                                $all = 1;
                                last;
                            } elsif ($in eq 'q') {
                                exit 0;
                            }
                        }
                    }
                    if ($move) {
                        move_path($path, $fixed_path, $dry_run);
                    }
                }
            }
        },
        @globPatterns);
}

1;