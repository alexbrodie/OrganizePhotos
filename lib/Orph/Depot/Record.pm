package Orph::Depot::Record;

=head1 NAME

Orph::Depot::Record - metadata stored in the depot for a file

=head1 SYNOPSYS

TODO - sample happy path code here

=head1 DESCRIPTION

This object encapsulates all the data that is or may be stored
in the Depot for a given file.

=head1 VERSION

Version 1.0

=cut

our $VERSION = '1.0';

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

use Carp qw(croak);

=head1 METHODS

=item new

Primary constructor

=cut

sub new {
    my ( $class, $self ) = @_;
    bless $self, $class;
    $self->filename;
    return $self;
}

=item filename

Returns the filename (including the extension, but
excluding the directory)

=cut

sub filename {
    my $self = shift;
    exists $self->{filename} or croak "uninitialized Record";
    return $self->{filename};
}

=item size

Returns the file size in bytes

=cut

sub size {
    my $self = shift;

    exists $self->{size} or croak "uninitialized Record";
    return $self->{size};
}

=item mtime

Returns the file date modified as a unix time stamp 

=cut

sub mtime {
    my $self = shift;
    exists $self->{mtime} or croak "uninitialized Record";
    return $self->{mtime};
}

=item hash_version

Returns an integer specifying the version of the algorithm used
to generate content_hash.

=cut

sub hash_version {
    my $self = shift;
    exists $self->{hash_version} or croak "uninitialized Record";
    return $self->{hash_version};
}

=item content_hash

Returns a string representation of a hash of the media data
including pixels and audio/video streams, i.e. the data excluding
volatile metadata.

=cut

sub content_hash {
    my $self = shift;
    exists $self->{content_hash} or croak "uninitialized Record";
    return $self->{content_hash};
}

=item full_hash

Returns a string representation of a hash of the whole file

=cut

sub full_hash {
    my $self = shift;
    exists $self->{full_hash} or croak "uninitialized Record";
    return $self->{full_hash};
}

=item TO_JSON

This method enables conversion to JSON when JSON::convert_blessed
is turned on.

=cut

sub TO_JSON {
    my $self = shift;
    return {%$self};
}

=head1 AUTHOR

Alex Brodie, 2023

=cut

1;
