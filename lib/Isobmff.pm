#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package Isobmff;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    readIsobmffBoxHeader
    readIsobmffFtyp
    getIsobmffBoxDiagName
    parseIsobmffBox
    getIsobmffPrimaryDataExtents
);

# MODEL (ISOBMFF) --------------------------------------------------------------
# The ISO/IEC Base Media File Format (ISOBMFF) is a container format that was
# adopted from QuickTime and is used by: MP4 (.mp4, .m4a, .m4p, .m4b, .m4r,
# .m4v), .3gp, .3g2, .mj2, .dvb, .dcf, .m21, .f4v, HEIF (.heif, .heifs, .heic,
# .heics, .avci, .avcs, .avif, .avifs). It entails a series of nested boxes
# starting with "ftyp".
#
# This function takes a file handle with seek position at the start of a
# box, reads the header, sets the seek to the start of data, and returns
# a hashref containing:
#
# __begin_pos : non-negative integer specifying the seek position of the start
#       of the box which is the same as the seek of the file handle when
#       passed to this method
# __data_pos : positive integer specifying the seek position of the
#       beginning of the data
# __data_size : non-negative integer specifying the size of the box's data
#       in bytes, or missing if there's no end (i.e. continues to end of
#       parent container)
# __end_pos : positive integer specifying the seek position immediately
#       following the box, or missing if there's no end (i.e. continues to
#       the end of its parent container)
# __type : FourCC string specifying the box type
#
# Here the '__' prefix is used for box header data. Fields within the data
# of the box are intended to have the 'f_' prefix (e.g. f_version), and
# child boxes with the 'b_' prefix (e.g. b_hdlr).
sub readIsobmffBoxHeader {
    my ( $mediaPath, $fh ) = @_;
    my $startPos = tell($fh);
    read( $fh, my $fileData, 8 )
        or die
        "Failed to read ISOBMFF box header from '$mediaPath' at $startPos: $!";
    my ( $boxSize, $type ) = unpack( 'Na4', $fileData );
    my $headerSize = 8;
    if ( $boxSize == 1 ) {

        # 1 means it's 64 bit size
        read( $fh, $fileData, 8 )
            or die
            "Failed to read ISOBMFF box extended size from '$mediaPath': $!";
        $boxSize = unpack( 'Q>', $fileData );
        $headerSize += 8;
    }
    my %box = (
        __type      => $type,
        __begin_pos => $startPos,
        __data_pos  => $startPos + $headerSize
    );

    # Box size of zero means that it goes to the EOF in which case
    # we don't have a data size or end of box position either
    if ( $boxSize != 0 ) {
        $boxSize >= $headerSize
            or die "Bad size for ISOBMFF box '$type': $boxSize";

        # Note that any of these can be computed from the other, so
        # only one is necessary, but all are added for convinence
        %box = (
            %box,
            __data_size => $boxSize - $headerSize,
            __end_pos   => $startPos + $boxSize
        );
    }
    return \%box;
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Reads the File Type Box (ftyp) which should be the first box in an
# ISOBMFF file. The returns a hashref with the general box header data
# from readIsobmffBoxHeader as well as:
#
# major_brand : string specifying the best use of the file, e.g. "qt" or "heic"
# minor_version : the integer version of major_brand
# compatible_brands : array of strings specifying other brands that the
#       file is compliant with
sub readIsobmffFtyp {
    my ( $mediaPath, $fh ) = @_;
    my $box = readIsobmffBoxHeader( $mediaPath, $fh );
    $box->{__type} eq 'ftyp'
        or die "box type was not ftyp as expected: $box->{__type}";
    my $size = $box->{__data_size};
    $size >= 8 && ( $size % 4 ) == 0
        or die "ftyp box data was unexpected size $size";
    read( $fh, my $fileData, $size )
        or die "failed to read ISOBMFF box data from '$mediaPath': $!";
    my ( $majorBrand, $minorVersion, @compatibleBrands ) =
        unpack( 'a4N(a4)*', $fileData );
    return {
        %$box,
        f_major_brand       => $majorBrand,
        f_minor_version     => $minorVersion,
        f_compatible_brands => \@compatibleBrands
    };
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Gets a short name for a box suitable for adding context alongside a filename
# for diagnostics such as traces and die statements.
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub getIsobmffBoxDiagName {
    my ( $mediaPath, $box ) = @_;
    return sprintf "'%s' %s@[0x%08x-0x%08x)", $mediaPath,
        @{$box}{qw(__type __begin_pos __end_pos)};
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Helper routine for parseIsobmffBox to read and interpret ISOBMFF box data
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub unpackIsobmffBoxData {
    my ( $mediaPath, $fh, $box, $format, $size ) = @_;
    my $pos = tell($fh);
    $box->{__data_pos} <= $pos
        or die "seek position $pos is before start of box data in "
        . getIsobmffBoxDiagName( $mediaPath, $box );
    if ( exists $box->{__data_size} ) {
        my $maxRead = $box->{__data_pos} + $box->{__data_size} - $pos;
        if ( defined $size ) {
            $size <= $maxRead
                or die "can't read $size bytes at $pos from "
                . getIsobmffBoxDiagName( $mediaPath, $box )
                . ": only $maxRead bytes left in box";
        }
        else {
            $size = $maxRead;
        }
    }
    elsif ( !defined $size ) {

        # i'm not sure we need to handle this case
        die
            "don't (yet) know how to do sizeless read and unpack in unbounded box for "
            . getIsobmffBoxDiagName( $mediaPath, $box );
    }
    my $bytesRead = read( $fh, my $fileData, $size );
    defined $bytesRead and $bytesRead == $size
        or die "failed to read $size bytes at $pos from "
        . getIsobmffBoxDiagName( $mediaPath, $box ) . ": $!";
    return unpack( $format, $fileData );
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Helper routine for parseIsobmffBox that parses ISOBMFF box data version
# and flags which come at the beginning of "full" boxes' data.
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub readIsobmffBoxVersionAndFlags {
    my ( $mediaPath, $fh, $box, $maxSupportedVersion ) = @_;
    my ( $version, @flagsBytes ) =
        unpackIsobmffBoxData( $mediaPath, $fh, $box, 'C4', 4 );
    my $flags = $flagsBytes[0] << 16 | $flagsBytes[1] << 8 | $flagsBytes[2];
    $box->{f_version} = $version;
    $box->{f_flags}   = $flags;
    !defined $maxSupportedVersion
        or $version <= $maxSupportedVersion
        or die "unsupported version $version for "
        . getIsobmffBoxDiagName( $mediaPath, $box );
    return ( $version, $flags );
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Helper routine for parseIsobmffBox that parses a series of children
#
# NB: in addition to ISOBMFF, this also works for QTFF (i.e. .mov)
sub parseIsobmffBoxChildren {
    my ( $mediaPath, $fh, $parent, $count, $parseChildBox ) = @_;
    $parseChildBox = \&parseIsobmffBox unless $parseChildBox;
    my @childrenArray = ();
    my %childrenHash  = ();
    while ( ( !defined $count ) || ( $count-- > 0 ) ) {

        # Deserialize and verify header
        my $child = readIsobmffBoxHeader( $mediaPath, $fh );
        if ( exists $child->{__end_pos} ) {
            !defined $parent->{__end_pos}
                or $child->{__end_pos} <= $parent->{__end_pos}
                or die
                "box extended past parent end ($parent->{__end_pos}) for "
                . getIsobmffBoxDiagName( $mediaPath, $child );
        }
        elsif ( exists $parent->{__end_pos} ) {
            $child->{__end_pos} = $parent->{__end_pos};
        }

        # Deserialize data
        $parseChildBox->( $mediaPath, $fh, $child );
        push @childrenArray,                         $child;
        push @{ $childrenHash{ $child->{__type} } }, $child;

        # Advance to next box or terminate loop
        last unless exists $child->{__end_pos};
        seek( $fh, $child->{__end_pos}, 0 )
            or die "failed to seek to $child->{__end_pos} for "
            . getIsobmffBoxDiagName( $mediaPath, $child ) . ": $!";
        if ( exists $parent->{__end_pos} ) {
            last if $child->{__end_pos} >= $parent->{__end_pos};
        }
        else {
            last if eof($fh);
        }
    }
    $count
        and die "failed to read all child boxes, $count still remain for"
        . getIsobmffBoxDiagName( $mediaPath, $parent );

    # TODO - let caller specify whether to use by type hash and/or by array?
    $parent->{b} = \@childrenArray;
    while ( my ( $k, $v ) = each %childrenHash ) {
        $parent->{"b_$k"} = ( @$v == 1 ) ? $v->[0] : $v;
    }
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Deserialize an ISOBMFF file and creates data structure representation
#
# mediaPath : the path to the file being deserialized, mostly for use in
#       error messages and diagnostics
# fh : an open readable file handle with seek set to the beginning of the
#       first box to be processed
# box : the parent container to put the results (a tree of boxes with
#       properties and child boxes); on the first call this should be
#       an empty hashref that serves as sort of header node
#
# Usage:
#       my $fh = open_file('<:raw', $mediaPath);
#       my $ftyp = readIsobmffFtyp($mediaPath, $fh);
#       # (Add verification of $ftyp's brand/version here.)
#       my $bmff = { b_ftyp => $ftyp };
#       parseIsobmffBox($mediaPath, $fh, $bmff);
#       # (Process box data here, e.g. get the primary's 'ifde' box.)
#       my $id = $bmff->{b_meta}->{b_pitm}->{f_item_id};
#       my ($infe) = grep { $_->{f_item_id} == $id } @{$bmff->{b_meta}->{b_iinf}->{b_infe}};
#
# NB: this does not work for QTFF (i.e. .mov) because the format of
# data are not identical between boxes in each - for example 'meta'
# contains version/flags in ISOBMFF but not QTFF.
sub parseIsobmffBox {
    my ( $mediaPath, $fh, $box ) = @_;

    # By default when reading child boxes we just recurisvely process
    # but some boxes might need to customize reading of their children
    # with some extra context based logic. So they can override this:
    my $processChildBox = sub {
        my ($child) = @_;
        parseIsobmffBox( $mediaPath, $fh, $child );
    };
    unless ( my $type = $box->{__type} ) {
        parseIsobmffBoxChildren( $mediaPath, $fh, $box );
    }
    elsif ( $type eq 'dinf' ) { # -------------------- Data Information --- dinf
        parseIsobmffBoxChildren( $mediaPath, $fh, $box );
    }
    elsif ( $type eq 'dref' ) { # ---------------------- Data Reference --- dref
        readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 0 );
        parseIsobmffBoxChildren( $mediaPath, $fh, $box,
            unpackIsobmffBoxData( $mediaPath, $fh, $box, 'N', 4 ) );
    }
    elsif ( $type eq 'hdlr' ) { # ------------------- Handler Reference --- hdlr
        readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 0 );
        @{$box}{qw(f_handler_type)} =
            unpackIsobmffBoxData( $mediaPath, $fh, $box, 'x4a4', 8 );
    }
    elsif ( $type eq 'idat' ) { # --------------------------- Item Data --- idat
          # This blob of data can be referenced if iloc's construction_method is
          # idat_offset (1). There's no pre-structured data to be parsed.
    }
    elsif ( $type eq 'iinf' ) { # -------------------- Item Information --- iinf
        readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 0 );
        parseIsobmffBoxChildren( $mediaPath, $fh, $box,
            unpackIsobmffBoxData( $mediaPath, $fh, $box, 'n', 2 ) );
    }
    elsif ( $type eq 'iloc' ) { # ----------------------- Item Location --- iloc
            # The fields offset_size, length_size, base_offset_size, index_size,
            # item_count, and extent_count are intermediate values only used to
            # parse other values within this box and so provide little use other
            # than distraction and overhead if retained
        my ( $version, $flags ) =
            readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 2 );
        my @values     = unpackIsobmffBoxData( $mediaPath, $fh, $box, 'C2', 2 );
        my $offsetSize = $values[0] >> 4;
        my $lengthSize = $values[0] & 0xf;
        my $baseOffsetSize = $values[1] >> 4;
        my $indexSize      = 0;

        if ( $version == 1 or $version == 2 ) {
            $indexSize = $values[1] & 0xf;
        }
        my $itemCount = 0;
        if ( $version < 2 ) {
            $itemCount = unpackIsobmffBoxData( $mediaPath, $fh, $box, 'n', 2 );
        }
        elsif ( $version == 2 ) {
            $itemCount = unpackIsobmffBoxData( $mediaPath, $fh, $box, 'N', 4 );
        }
        my $readIntegerSized = sub {
            my ($byteSize) = @_;
            if ( $byteSize == 0 ) {
                return 0;
            }
            elsif ( $byteSize == 4 ) {
                return ( unpackIsobmffBoxData( $mediaPath, $fh, $box, 'N', 4 ) )
                    [0];
            }
            elsif ( $byteSize == 8 ) {
                return (
                    unpackIsobmffBoxData( $mediaPath, $fh, $box, 'Q>', 8 ) )[0];
            }
            else {
                die "unexpected integer size $byteSize for "
                    . getIsobmffBoxDiagName( $mediaPath, $box );
            }
        };
        my @items = ();
        for ( my $i = 0; $i < $itemCount; $i++ ) {
            my %item = ();
            if ( $version < 2 ) {
                @item{qw(item_id)} =
                    unpackIsobmffBoxData( $mediaPath, $fh, $box, 'n', 2 );
            }
            elsif ( $version == 2 ) {
                @item{qw(item_id)} =
                    unpackIsobmffBoxData( $mediaPath, $fh, $box, 'N', 4 );
            }
            if ( $version == 1 or $version == 2 ) {
                @item{qw(construction_method)} =
                    unpackIsobmffBoxData( $mediaPath, $fh, $box, 'n', 2 );
            }
            @item{qw(data_reference_index)} =
                unpackIsobmffBoxData( $mediaPath, $fh, $box, 'n', 2 );
            $item{base_offset} = $readIntegerSized->($baseOffsetSize);
            my $extentCount =
                unpackIsobmffBoxData( $mediaPath, $fh, $box, 'n', 2 );
            my @extents = ();
            for ( my $j = 0; $j < $extentCount; $j++ ) {
                my %extent = ();
                $extent{extent_index} = $readIntegerSized->($indexSize)
                    if $indexSize;
                $extent{extent_offset} = $readIntegerSized->($offsetSize);
                $extent{extent_length} = $readIntegerSized->($lengthSize);
                push @extents, \%extent;
            }
            $item{extents} = \@extents;
            push @items, \%item;
        }
        $box->{f_items} = \@items;
    }
    elsif ( $type eq 'infe' ) { # --------------------- Item Info Entry --- infe
        my ( $version, $flags ) =
            readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 3 );
        if ( $version < 2 ) {
            @{$box}{
                qw(f_item_id f_item_protection_index f_item_name f_content_type f_content_encoding)
            } = unpackIsobmffBoxData( $mediaPath, $fh, $box, 'nnZ*Z*Z*' );
        }
        else {
            @{$box}{qw(f_item_id f_item_protection_index f_item_type)} =
                ( $version == 2 )
                ? unpackIsobmffBoxData( $mediaPath, $fh, $box, 'nna4', 8 )
                : unpackIsobmffBoxData( $mediaPath, $fh, $box, 'Nna4', 10 );
            if ( $box->{f_item_type} eq 'mime' ) {
                @{$box}{qw(f_item_name f_content_type f_content_encoding)} =
                    unpackIsobmffBoxData( $mediaPath, $fh, $box, 'Z*Z*Z*' );
            }
            elsif ( $box->{f_item_type} eq 'uri ' ) {
                @{$box}{qw(f_item_name f_item_uri_type)} =
                    unpackIsobmffBoxData( $mediaPath, $fh, $box, 'Z*Z*' );
            }
            else {
                @{$box}{qw(f_item_name)} =
                    unpackIsobmffBoxData( $mediaPath, $fh, $box, 'Z*' );
            }
        }
    }
    elsif ( $type eq 'iprp' ) { # --------------------- Item Properties --- iprp
            # TODO - I can't find documentation for this, skip for now
    }
    elsif ( $type eq 'iref' ) { # ---------------------- Item Reference --- iref
        my ( $version, $flags ) =
            readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 1 );
        my $idFormat = ( $version == 0 ) ? 'n' : 'N';
        parseIsobmffBoxChildren(
            $mediaPath,
            $fh, $box, undef,
            sub {
                my ( $mediaPath, $fh, $child ) = @_;
                my @values = unpackIsobmffBoxData( $mediaPath, $fh, $child,
                    "$idFormat n/$idFormat" );
                $child->{f_from_item_id} = shift @values;
                $child->{f_to_item_id}   = [@values];
            }
        );
    }
    elsif ( $type eq 'mdat' ) { # -------------------------- Media Data --- mdat
            # This blob of data is referenced elsewhere (e.g. iloc) and has no
            # pre-structured data to be parsed.
    }
    elsif ( $type eq 'meta' ) { # ---------------------------- Metadata --- meta
           # TODO - it seems like Apple QTFF (ftyp->major_brand = 'qt  ') 'meta'
         # atom is missing version/flags and ISO BMFF 'meta' box has version/flags?
        readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 0 );
        parseIsobmffBoxChildren( $mediaPath, $fh, $box );
    }
    elsif ( $type eq 'moov' ) { # ------------------------------- Movie --- moov
        parseIsobmffBoxChildren( $mediaPath, $fh, $box );
    }
    elsif ( $type eq 'pitm' ) { # ------------------------ Primary Item --- pitm
        readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 0 );
        @{$box}{qw(f_item_id)} =
            unpackIsobmffBoxData( $mediaPath, $fh, $box, 'n', 2 );
    }
    elsif ( $type eq 'url ' ) { # ----------------------- Data Entry Url --- url
        readIsobmffBoxVersionAndFlags( $mediaPath, $fh, $box, 0 );

        # TODO - Then optional string?
        #$box->{f_location} =
    }
    elsif ( $type ne 'free' and $type ne 'skip' and $type ne 'wide' ) {

        # free, skip, wide are just ignorable padding
        print STDERR "Unknown box type '$type' for ",
            getIsobmffBoxDiagName( $mediaPath, $box ), "\n";
    }
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Given a deserialized ISOBMFF file and a set of item IDs, looks up the
# direct and indirect references in the meta/iref box to build a set of
# all referenced item IDs.
#
# NB: this does not work for QTFF
sub resolveIsobmffIref {
    my ($bmff) = shift;
    my %refs   = ();
    my $irefs  = $bmff->{b_meta}->{b_iref}->{b};
    for ( my @queue = grep { $refs{$_}++ == 0 } @_; @queue > 0; ) {
        my $itemId = shift @queue;
        for ( grep { $_->{f_from_item_id} == $itemId } @$irefs ) {
            push @queue, grep { $refs{$_}++ == 0 } @{ $_->{f_to_item_id} };
        }
    }
    my @result = sort { $a <=> $b } map { $_ + 0 } keys %refs;
    return @result;
}

# MODEL (ISOBMFF) --------------------------------------------------------------
# Gets an ordered list of pos/size data that specifies the data ranges
# for the primary data item.
#
# NB: this does not work for QTFF
sub getIsobmffPrimaryDataExtents {
    my ( $mediaPath, $bmff ) = @_;

    # Get the primary ID (from meta/pitm) and lookup all IDs that it
    # references (using meta/iref), and loop over all the extents for
    # those IDs (using meta/iloc's items).
    my @extents = ();
    my $iloc    = $bmff->{b_meta}->{b_iloc};
    for my $id (
        resolveIsobmffIref( $bmff, $bmff->{b_meta}->{b_pitm}->{f_item_id} ) )
    {
        for my $item ( grep { $id == $_->{item_id} } @{ $iloc->{f_items} } ) {
            $item->{data_reference_index} == 0
                or die
                "only iloc data_reference_index of 'this file' (0) is currently supported for "
                . getIsobmffBoxDiagName( $mediaPath, $iloc );
            my $method = $item->{construction_method};
            if ( $method == 0 ) {    # 0 is 'file_offset'
                for ( @{ $item->{extents} } ) {
                    my $pos  = $item->{base_offset} + $_->{extent_offset};
                    my $size = $_->{extent_length};

                    # TODO - verify this is inside of mdat?
                    push @extents, { pos => $pos, size => $size };
                }
            }
            elsif ( $method == 1 ) {    # 1 is 'idat_offset'
                my $idat       = $bmff->{b_meta}->{b_idat};
                my $baseOffset = $idat->{__data_pos} + $item->{base_offset};
                for ( @{ $item->{extents} } ) {
                    my $pos  = $baseOffset + $_->{extent_offset};
                    my $size = $_->{extent_length};
                    (          $idat->{__data_pos} <= $pos
                            && $pos + $size <=
                            $idat->{__data_pos} + $idat->{__data_size} )
                        or die
                        "extent range of pos=$pos, size=$size out of idat bounds "
                        . "pos=$idat->{__data_pos}, size=$idat->{__data_size} for  "
                        . getIsobmffBoxDiagName( $mediaPath, $iloc );
                    push @extents, { pos => $pos, size => $size };
                }
            }
            else {
                die
                    "only iloc construction_method of file_offset (0) or idat_offset (1) "
                    . "currently supported for "
                    . getIsobmffBoxDiagName( $mediaPath, $iloc );
            }
        }
    }

    # Join contiguous spans of extents, but don't do anything fancy with
    # overlapping things or reordering to force joins - we want it to be
    # as identical to original as possible
    for ( my $i = 1; $i < @extents; $i++ ) {
        my ( $x, $y ) = @extents[ $i - 1, $i ];
        if ( $x->{pos} + $x->{size} == $y->{pos} ) {
            $x->{size} += $y->{size};
            splice @extents, $i--, 1;
        }
    }
    return @extents;
}

1;
