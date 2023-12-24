package Orph::Depot::RecordKey;

=head1 NAME

Orph::Depot::RecordKey - object that enables retrieving a Record from the Depot

=head1 SYNOPSYS

my $key = Orph::Depot::RecordKey->new($path);
my $result_set = Orph::Depot::DataFile
    ->new($key->depot_path)
    ->access('<')
    ->read_records();
my $record = $result_set->{$key->record_key};

=head1 DESCRIPTION

RecordKey is the object by which you determine where to get the
Record corresponding to a path from the Depot.

=head1 VERSION

Version 1.0

=cut

our $VERSION = '1.0';

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

use Orph::Depot::DataFile;
use PathOp qw(change_filename);

=head1 METHODS

=item new

Primary constructor

=cut

sub new {
    my ( $class, $path ) = @_;

    my ( $depot_path, $old_filename ) =
        change_filename( $path, $Orph::Depot::DataFile::DEPOT_FILENAME );

    my $self = {
        subject_path => $path,
        depot_path   => $depot_path,
        record_key   => lc $old_filename
    };
    bless $self, $class;

    return $self;
}

=item subject_path

Accessor for the path to the file that this is the
key for, i.e. the path it was constructed with.

=cut

sub subject_path {
    my $self = shift;
    return $self->{subject_path};
}

=item depot_path

Accessor for the path to the DataFile that this key
belongs to.

=cut

sub depot_path {
    my $self = shift;
    return $self->{depot_path};
}

=item record_key

Accessor for the key to the DataFile's record set

=cut

sub record_key {
    my $self = shift;
    return $self->{record_key};
}

=head1 AUTHOR

Alex Brodie, 2023

=cut

1;
