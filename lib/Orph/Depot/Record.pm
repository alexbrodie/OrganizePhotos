package Orph::Depot::Record;

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

use Carp qw(croak);

sub new {
    my ( $class, $self ) = @_;
    bless $self, $class;
    $self->filename;
    return $self;
}

sub filename {
    my $self = shift;
    exists $self->{filename} or croak "uninitialized Record";
    return $self->{filename};
}

sub size {
    my $self = shift;

    exists $self->{size} or croak "uninitialized Record";
    return $self->{size};
}

sub mtime {
    my $self = shift;
    exists $self->{mtime} or croak "uninitialized Record";
    return $self->{mtime};
}

sub hash_version {
    my $self = shift;
    exists $self->{hash_version} or croak "uninitialized Record";
    return $self->{hash_version};
}

sub content_hash {
    my $self = shift;
    exists $self->{content_hash} or croak "uninitialized Record";
    return $self->{content_hash};
}

sub full_hash {
    my $self = shift;
    exists $self->{full_hash} or croak "uninitialized Record";
    return $self->{full_hash};
}

sub TO_JSON {
    my $self = shift;
    return {%$self};
}

1;
