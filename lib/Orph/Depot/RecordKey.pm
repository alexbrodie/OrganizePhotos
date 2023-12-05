#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package RecordKey;

use FileTypes;    # for ORPHDAT_FILENAME, TODO: rafactor this
use PathOp qw(change_filename);

sub new {
    my $class = shift;
    my ($path) = @_;

    my ( $depot_path, $old_filename ) =
        change_filename( $path, $FileTypes::ORPHDAT_FILENAME );

    my $self = {
        subject_path => $path,
        depot_path   => $depot_path,
        record_key   => lc $old_filename
    };
    bless $self, $class;

    return $self;
}

sub subject_path {
    my $self = shift;
    return $self->{subject_path};
}

sub depot_path {
    my $self = shift;
    return $self->{depot_path};
}

sub record_key {
    my $self = shift;
    return $self->{record_key};
}

1;
