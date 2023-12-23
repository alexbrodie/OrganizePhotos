package Orph::Depot::DataFile;

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

use FileTypes;
use FileOp qw(open_file);
use Orph::Depot::Record;
use PathOp qw(split_path);
use View   qw(pretty_path print_crud);

use Readonly;
use Carp qw(carp croak);
use JSON qw(decode_json);

Readonly our $DEPOT_FILENAME => '.orphdat';

# Primary constructor
sub new {
    my ( $class, $path ) = @_;

    _verify_path($path);

    my $self = { path => $path };
    bless $self, $class;

    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->end_access();
}

# Accessor for path
sub path {
    my ($self) = @_;
    return $self->{path};
}

# Internal accessor for file handle
sub _handle {
    my ($self) = @_;
    my $value = $self->{_handle} or croak "Call DataFile::open first";
    return $value;
}

# Opens the file in the specified access mode (see open for options)
# Todo - make this private so only the supported open modes are exposed
sub access {
    my ( $self, $open_mode ) = @_;

    $self->{_handle} and croak "DataFile is already open";

    $self->{_handle} = FileOp::open_file( $open_mode . ':crlf', $self->path );
    $self->{_open_mode} = $open_mode;

    return $self;
}

# Opens the file in RW mode, creating it if it doesn't exist
sub access_rw {
    my ($self) = @_;

    if ( -e $self->path ) {
        $self->access('+<');
    }
    else {
        $self->access('+>');
        print_crud(
            $View::VERBOSITY_MEDIUM, $View::CRUD_CREATE,
            "Created cache at '",
            pretty_path( $self->path ), "'\n"
        );
    }

    return $self;
}

# Closes the file opened with an access routine
sub end_access {
    my ($self) = @_;

    if ( exists $self->{_handle} ) {
        close $self->{_handle};
        delete $self->{_handle};
        delete $self->{_open_mode};
    }

    return $self;
}

# Reads a record set.
#
# Assumes this file was already opened using access_rw or access of < or +< modes.
sub read_records {
    my ($self) = @_;

    my $p = $self->path;
    my $h = $self->_handle;
    seek( $h, 0, 0 ) or croak "Couldn't reset seek on '$p': $!";

    # decode (and decode_json) converts UTF-8 binary string to perl data struct
    my $record_set = decode_json( join '', <$h> );

    # TODO: Consider validating parsed content - do a lc on
    #       filename/md5s/whatever, and verify vs $MD5_DIGEST_PATTERN???
    # If there's no version data, then it is version 1. We didn't
    # start storing version information until version 2.
    while ( my ( $key, $value ) = each %$record_set ) {
        $value = $self->_create_record($value);
    }

    print_crud( $View::VERBOSITY_MEDIUM, $View::CRUD_READ, "Read cache from '",
        pretty_path($p), "'\n" );

    return $record_set;
}

# Writes a record set.
#
# Assumes this file was already opened using access_rw or access of > or +< modes.
sub write_records {
    my ( $self, $record_set ) = @_;

    my $p = $self->path;
    my $h = $self->_handle;
    seek( $h, 0, 0 )  or croak "Couldn't reset seek on '$p': $!";
    truncate( $h, 0 ) or croak "Couldn't truncate '$p': $!";

    if (%$record_set) {

        # encode (and encode_json) produces UTF-8 binary string
        # TODO - write this out transactionally to a temp file and move upon
        # success to avoid corrupted files due to errors (eg TO_JSON issues)
        print $h JSON->new->allow_nonref->convert_blessed->pretty->canonical
            ->encode($record_set);
    }
    else {
        carp "Writing empty data to '$p'";
    }

    print_crud( $View::VERBOSITY_MEDIUM, $View::CRUD_UPDATE, "Wrote cache to '",
        pretty_path($p), "'\n" );
}

# Deletes the file
sub erase {
    my ($self) = @_;

    $self->end_access();

    my $p = $self->path;
    unlink($p) or croak "Couldn't delete '$p': $!";

    print_crud( $View::VERBOSITY_MEDIUM, $View::CRUD_DELETE, "Deleted cache '",
        pretty_path($p), "'\n" );
}

sub _create_record {
    my ( $self, $json ) = @_;
    return Orph::Depot::Record->new($json);
}

# Verify filename of provided path is $hNAME
sub _verify_path {
    my ($path) = @_;
    my ( undef, undef, $filename ) = split_path($path);
    $filename eq $DEPOT_FILENAME
        or croak "Expected cache filename '$DEPOT_FILENAME' for '$path'";
}

1;
