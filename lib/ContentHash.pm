#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package ContentHash;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    is_hash_version_current
    calculate_hash
    $MD5_DIGEST_PATTERN
);

# Local uses
use FileOp;
use FileTypes;
use Isobmff;
use View;

# Library uses
use Digest::MD5 ();
use List::Util  qw(any all);
use Readonly;

# What we expect an MD5 hash to look like
Readonly::Scalar our $MD5_DIGEST_PATTERN => qr/[0-9a-f]{32}/;

# The data returned by calculate_hash is versioned, but not all version
# changes are meaningful for every type of file. This method determines if
# the provided version is equivalent to the current version for the specified
# file type.
sub is_hash_version_current {
    my ( $path, $version ) = @_;

    #trace( $VERBOSITY_MAX, "is_hash_version_current('$path', $version);");
    my $type = get_mime_type($path);

    # Return truthy iff $version >= N where N is the last version that
    # affected the output for this file type
    if ( $type eq 'image/heic' ) {
        return ( $version >= 6 ) ? 1 : 0;
    }
    elsif ( $type eq 'image/jpeg' ) {
        return ( $version >= 1 ) ? 1 : 0;
    }
    elsif ( $type eq 'video/mp4v-es' ) {
        return ( $version >= 2 ) ? 1 : 0;
    }
    elsif ( $type eq 'image/png' ) {
        return ( $version >= 3 ) ? 1 : 0;
    }
    elsif ( $type eq 'video/quicktime' ) {
        return ( $version >= 7 ) ? 1 : 0;
    }
    elsif ( $type eq 'image/tiff' ) {

        # TODO
    }

    # This type just does whole file MD5 (the original implementation)
    return 1;
}

# Calculates and returns the MD5 digest(s) of a file.
# Returns these properties as a hashref which when combined with
# make_orphdat_base comprise a full Md5Info):
#   version:  $CURRENT_HASH_VERSION
#   md5:      primary MD5 comparison (excludes volitile data from calculation)
#   full_md5: full MD5 calculation for exact match
sub calculate_hash {
    my ($path) = @_;
    trace( $VERBOSITY_MAX, "calculate_hash('$path');" );

    #!!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE
    #!!!   $CURRENT_HASH_VERSION should be incremented whenever the output
    #!!!   of this method changes in such a way that old values need to be
    #!!!   recalculated, and is_hash_version_current should be updated accordingly.
    #!!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE
    Readonly::Scalar my $CURRENT_HASH_VERSION => 7;
    my $fh       = open_file( '<:raw', $path );    # NB: READ ONLY
    my $full_md5 = calc_md5( $path, $fh );
    seek( $fh, 0, 0 ) or die "Failed to reset seek for '$path': $!";

    # If we fail to generate a partial match, just warn and use the full file
    # MD5 rather than letting the exception loose and just skipping the file.
    my $content_md5 = undef;
    eval {
        my $type = get_mime_type($path);
        if ( $type eq 'image/heic' ) {
            $content_md5 = content_hash_heic( $path, $fh );
        }
        elsif ( $type eq 'image/jpeg' ) {
            $content_md5 = content_hash_jpeg( $path, $fh );
        }
        elsif ( $type eq 'video/mp4v-es' ) {
            $content_md5 = content_hash_mp4( $path, $fh );
        }
        elsif ( $type eq 'image/png' ) {
            $content_md5 = content_hash_png( $path, $fh );
        }
        elsif ( $type eq 'video/quicktime' ) {
            $content_md5 = content_hash_mov( $path, $fh );
        }
        elsif ( $type eq 'image/tiff' ) {

            # TODO
        }
    };
    if ( my $error = $@ ) {

        # Can't get the partial MD5, so we'll just use the full hash
        warn
            "Unavailable content MD5 for '@{[pretty_path($path)]}' with error:\n\t$error\n";
    }
    print_crud(
        $VERBOSITY_MEDIUM, $CRUD_READ,
        "Computed MD5 of '@{[pretty_path($path)]}'",
        ( $content_md5 ? ", including content only hash" : '' ), "\n"
    );
    return {
        version  => $CURRENT_HASH_VERSION,
        md5      => $content_md5 || $full_md5,
        full_md5 => $full_md5,
    };
}

# Reads a file as if it were an ISOBMFF file,
# and returns the MD5 digest of the data in the mdat box.
sub hash_isobmff_mdat {
    my ( $path, $fh ) = @_;
    until ( eof($fh) ) {
        my $box = readIsobmffBoxHeader( $path, $fh );
        if ( $box->{__type} eq 'mdat' ) {
            return calc_md5( $path, $fh, $box->{__data_size} );
        }
        last unless exists $box->{__end_pos};
        seek( $fh, $box->{__end_pos}, 0 )
            or die "failed to seek '$path' to $box->{__end_pos}: $!";
    }
    return;
}

# Reads a file as if it were an ISOBMFF file,
# and returns the MD5 digest of the data
sub hash_isobmff_primary_item {
    my ( $path, $fh ) = @_;
    my $ftyp = readIsobmffFtyp( $path, $fh );

    # This only works for ISO BMFF, not Apple QTFF (i.e. mp3, heic)
    any { $ftyp->{f_major_brand} eq $_ } ( 'mp41', 'mp42', 'heic' )
        or die "unexpected brand for " . getIsobmffBoxDiagName( $path, $ftyp );
    my $bmff = { b_ftyp => $ftyp };
    parseIsobmffBox( $path, $fh, $bmff );
    my $md5 = Digest::MD5->new;
    for ( getIsobmffPrimaryDataExtents( $path, $bmff ) ) {
        seek( $fh, $_->{pos}, 0 )
            or die "Failed to seek '$path' to $_->{pos}: $!";
        add_to_md5_digest( $md5, $path, $fh, $_->{size} );
    }
    return resolve_md5_digest($md5);
}

sub content_hash_heic {
    my ( $path, $fh ) = @_;
    return hash_isobmff_primary_item( $path, $fh );
}

# If JPEG, skip metadata which may change and only hash pixel data
# and hash from Start of Scan [SOS] to end of file
sub content_hash_jpeg {
    my ( $path, $fh ) = @_;

    # Read Start of Image [SOI]
    read( $fh, my $file_data, 2 )
        or die "Failed to read JPEG SOI from '$path': $!";
    my ($soi) = unpack( 'n', $file_data );
    $soi == 0xffd8 or die "File didn't start with JPEG SOI marker: '$path'";

    # Read blobs until SOS
    my $tags = '';
    while (1) {
        read( $fh, my $file_data, 4 )
            or die
            "Failed to read JPEG tag header from '$path' at @{[tell $fh]} after $tags: $!";
        my ( $tag, $size ) = unpack( 'nn', $file_data );

        # Take all the file after the SOS
        return calc_md5( $path, $fh ) if $tag == 0xffda;

        # Else, skip past this tag
        $tags .= sprintf( "%04x,%04x;", $tag, $size );
        my $address = tell($fh) + $size - 2;
        seek( $fh, $address, 0 )
            or die "Failed to seek '$path' to $address: $!";
    }
}

sub content_hash_mov {
    my ( $path, $fh ) = @_;
    return hash_isobmff_mdat( $path, $fh );
}

sub content_hash_mp4 {
    my ( $path, $fh ) = @_;
    my $ftyp        = readIsobmffFtyp( $path, $fh );
    my $major_brand = $ftyp->{f_major_brand};

    # 'isom' means the first version of ISO Base Media, and is not supposed to
    # ever be a major brand, but it happens. Try to handle a little bit.
    if ( $major_brand eq 'isom' ) {
        my @compatible =
            grep { $_ ne 'isom' } @{ $ftyp->{f_compatible_brands} };
        $major_brand = $compatible[0] if @compatible == 1;
    }

    # This works for both Apple QTFF and ISO BMFF (i.e. mov, mp4, heic)
    unless ( any { $major_brand eq $_ }
        ( 'heic', 'isom', 'mp41', 'mp42', 'qt  ' ) )
    {
        my $brand = "'$ftyp->{f_major_brand}'";
        if ( @{ $ftyp->{f_compatible_brands} } ) {
            $brand = $brand . ' (\''
                . join( '\', \'', @{ $ftyp->{f_compatible_brands} } ) . '\')';
        }
        warn "unexpected brand $brand for "
            . getIsobmffBoxDiagName( $path, $ftyp );
        return;
    }
    return hash_isobmff_mdat( $path, $fh );
}

sub content_hash_png {
    my ( $path, $fh ) = @_;
    read( $fh, my $file_data, 8 )
        or die "Failed to read PNG header from '$path': $!";
    my @actual_header = unpack( 'C8', $file_data );
    my @png_header    = ( 137, 80, 78, 71, 13, 10, 26, 10 );
    Data::Compare::Compare( \@actual_header, \@png_header )
        or die "File didn't start with PNG header: '$path'";
    my $md5 = Digest::MD5->new;
    while ( !eof($fh) ) {

        # Read chunk header
        read( $fh, $file_data, 8 )
            or die
            "Failed to read PNG chunk header from '$path' at @{[tell $fh]}: $!";
        my ( $size, $type ) = unpack( 'Na4', $file_data );
        my $seek_start_of_data = tell($fh);

        # TODO: Check that 'IHDR' chunk comes first and 'IEND' last?
        if ( $type eq 'tEXt' or $type eq 'zTXt' or $type eq 'iTXt' ) {

            # This is a text field, so not pixel data
            # TODO: should we only skip the type 'iTXt' and subtype
            # 'XML:com.adobe.xmp'?
        }
        else {
            # The type and data should be enough - don't need size or CRC
            # BUGBUG - this seems slightly wrong in that if things move around
            # and mean the same thing the MD5s will change even though the
            # contents haven't meaningfully changed, and can result in us
            # falsely reporting that there have been non-metadata changes
            # (i.e. pixel data) changes to the file.
            $md5->add($type);
            add_to_md5_digest( $md5, $path, $fh, $size );
        }

        # Seek to start of next chunk (past header, data, and CRC)
        my $address = $seek_start_of_data + $size + 4;
        seek( $fh, $address, 0 )
            or die "Failed to seek '$path' to $address: $!";
    }
    return resolve_md5_digest($md5);
}

# Get/verify/canonicalize hash from a FILEHANDLE object
sub calc_md5 {
    my ( $path, $fh, $size ) = @_;
    my $md5 = Digest::MD5->new;
    add_to_md5_digest( $md5, $path, $fh, $size );
    return resolve_md5_digest($md5);
}

sub add_to_md5_digest {
    my ( $md5, $path, $fh, $size ) = @_;
    unless ( defined $size ) {
        $md5->addfile($fh);
    }
    else {
        # There's no addfile with a size limit, so we roll our own
        # by reading in chunks and adding one at a time (since $size
        # might be huge and we don't want to read it all into memory)
        my $chunk_size = 1024;
        for (
            my $remaining = $size;
            $remaining > 0;
            $remaining -= $chunk_size
            )
        {
            my $read_size = $chunk_size < $remaining ? $chunk_size : $remaining;
            read( $fh, my $file_data, $read_size )
                or die
                "Failed to read $read_size bytes from '$path' at @{[tell $fh]}: $!";
            $md5->add($file_data);
        }
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Extracts, verifies, and canonicalizes resulting MD5 digest
# final result from a Digest::MD5.
sub resolve_md5_digest {
    my ($md5) = @_;
    my $hexdigest = lc $md5->hexdigest;
    $hexdigest =~ /$MD5_DIGEST_PATTERN/ or die "Unexpected MD5: $hexdigest";
    return $hexdigest;
}

1;
