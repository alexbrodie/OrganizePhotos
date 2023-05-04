#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package ContentHash;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    isMd5InfoVersionUpToDate
    calculateMd5Info
);

# Local uses
use FileOp;
use FileTypes;
use Isobmff;
use View;

# Library uses
use Const::Fast qw(const);
use Digest::MD5 ();
use List::Util qw(any all);

# What we expect an MD5 hash to look like
const our $md5DigestPattern => qr/[0-9a-f]{32}/;

# The data returned by calculateMd5Info is versioned, but not all version 
# changes are meaningful for every type of file. This method determines if
# the provided version is equivalent to the current version for the specified
# file type.
sub isMd5InfoVersionUpToDate {
    my ($mediaPath, $version) = @_;
    #trace(View::VERBOSITY_MAX, "isMd5InfoVersionUpToDate('$mediaPath', $version);");
    my $type = get_mime_type($mediaPath);
    # Return truthy iff $version >= N where N is the last version that
    # affected the output for this file type
    if ($type eq 'image/heic') {
        return ($version >= 6) ? 1 : 0;
    } elsif ($type eq 'image/jpeg') {
        return ($version >= 1) ? 1 : 0;
    } elsif ($type eq 'video/mp4v-es') {
        return ($version >= 2) ? 1 : 0;
    } elsif ($type eq 'image/png') {
        return ($version >= 3) ? 1 : 0;
    } elsif ($type eq 'video/quicktime') {
        return ($version >= 7) ? 1 : 0;
    } elsif ($type eq 'image/tiff') {
        # TODO
    }
    # This type just does whole file MD5 (the original implementation)
    return 1;
}

# Calculates and returns the MD5 digest(s) of a file.
# Returns these properties as a hashref which when combined with 
# makeMd5InfoBase comprise a full Md5Info):
#   version:  $calculateMd5InfoVersion
#   md5:      primary MD5 comparison (excludes volitile data from calculation)
#   full_md5: full MD5 calculation for exact match
sub calculateMd5Info {
    my ($mediaPath) = @_;
    trace(View::VERBOSITY_MEDIUM, "getMd5('$mediaPath');");
    #!!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE
    #!!!   $calculateMd5InfoVersion should be incremented whenever the output
    #!!!   of this method changes in such a way that old values need to be 
    #!!!   recalculated, and isMd5InfoVersionUpToDate should be updated accordingly.
    #!!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE !!! IMPORTANT NOTE
    const my $calculateMd5InfoVersion => 7;
    my $fh = openOrDie('<:raw', $mediaPath);
    my $fullMd5Hash = getMd5Digest($mediaPath, $fh);
    seek($fh, 0, 0) or die "Failed to reset seek for '$mediaPath': $!";
    # If we fail to generate a partial match, just warn and use the full file
    # MD5 rather than letting the exception loose and just skipping the file.
    my $partialMd5Hash = undef;
    eval {
        my $type = get_mime_type($mediaPath);
        if ($type eq 'image/heic') {
            $partialMd5Hash = getHeicContentMd5($mediaPath, $fh);
        } elsif ($type eq 'image/jpeg') {
            $partialMd5Hash = getJpgContentMd5($mediaPath, $fh);
        } elsif ($type eq 'video/mp4v-es') {
            $partialMd5Hash = getMp4ContentMd5($mediaPath, $fh);
        } elsif ($type eq 'image/png') {
            $partialMd5Hash = getPngContentMd5($mediaPath, $fh);
        } elsif ($type eq 'video/quicktime') {
            $partialMd5Hash = getMovContentMd5($mediaPath, $fh);
        } elsif ($type eq 'image/tiff') {
            # TODO
        }
    };
    if (my $error = $@) {
        # Can't get the partial MD5, so we'll just use the full hash
        warn "Unavailable content MD5 for '@{[pretty_path($mediaPath)]}' with error:\n\t$error\n";
    }
    print_crud(View::CRUD_READ, "  Computed MD5 of '@{[pretty_path($mediaPath)]}'",
              ($partialMd5Hash ? ", including content only hash" : ''), "\n");
    return {
        version => $calculateMd5InfoVersion,
        md5 => $partialMd5Hash || $fullMd5Hash,
        full_md5 => $fullMd5Hash,
    };
}

# Reads a file as if it were an ISOBMFF file of the specified brand,
# and returns the MD5 digest of the data in the mdat box.
sub getIsobmffMdatMd5 {
    my ($mediaPath, $fh) = @_;
    until (eof($fh)) {
        my $box = readIsobmffBoxHeader($mediaPath, $fh);
        if ($box->{__type} eq 'mdat') {
            return getMd5Digest($mediaPath, $fh, $box->{__data_size});
        }
        last unless exists $box->{__end_pos};
        seek($fh, $box->{__end_pos}, 0) or die 
            "failed to seek '$mediaPath' to $box->{__end_pos}: $!";
    }
    return undef;
}

sub getIsobmffPrimaryItemDataMd5 {
    my ($mediaPath, $fh) = @_;
    my $ftyp = readIsobmffFtyp($mediaPath, $fh);
    # This only works for ISO BMFF, not Apple QTFF (i.e. mp3, heic)
    any { $ftyp->{f_major_brand} eq $_ } ('mp41', 'mp42', 'heic') or die
        "unexpected brand for " . getIsobmffBoxDiagName($mediaPath, $ftyp);
    my $bmff = { b_ftyp => $ftyp };
    parseIsobmffBox($mediaPath, $fh, $bmff);
    my $md5 = new Digest::MD5;
    for (getIsobmffPrimaryDataExtents($mediaPath, $bmff)) {
        seek($fh, $_->{pos}, 0) or die 
            "Failed to seek '$mediaPath' to $_->{pos}: $!";
        addToMd5Digest($md5, $mediaPath, $fh, $_->{size});
    }
    return resolveMd5Digest($md5);
}

sub getHeicContentMd5 {
    return getIsobmffPrimaryItemDataMd5(@_);
}

# If JPEG, skip metadata which may change and only hash pixel data
# and hash from Start of Scan [SOS] to end of file
sub getJpgContentMd5 {
    my ($mediaPath, $fh) = @_;
    # Read Start of Image [SOI]
    read($fh, my $fileData, 2) or die "Failed to read JPEG SOI from '$mediaPath': $!";
    my ($soi) = unpack('n', $fileData);
    $soi == 0xffd8 or die "File didn't start with JPEG SOI marker: '$mediaPath'";
    # Read blobs until SOS
    my $tags = '';
    while (1) {
        read($fh, my $fileData, 4) or die
            "Failed to read JPEG tag header from '$mediaPath' at @{[tell $fh]} after $tags: $!";
        my ($tag, $size) = unpack('nn', $fileData);
        # Take all the file after the SOS
        return getMd5Digest($mediaPath, $fh) if $tag == 0xffda;
        # Else, skip past this tag
        $tags .= sprintf("%04x,%04x;", $tag, $size);
        my $address = tell($fh) + $size - 2;
        seek($fh, $address, 0) or die "Failed to seek '$mediaPath' to $address: $!";
    }
}

sub getMovContentMd5 {
    return getIsobmffMdatMd5(@_);
}

sub getMp4ContentMd5 {
    my ($mediaPath, $fh) = @_;
    my $ftyp = readIsobmffFtyp($mediaPath, $fh);
    my $majorBrand = $ftyp->{f_major_brand};
    # 'isom' means the first version of ISO Base Media, and is not supposed to
    # ever be a major brand, but it happens. Try to handle a little bit.
    if ($majorBrand eq 'isom') {
        my @compatible = grep { $_ ne 'isom' } @{$ftyp->{f_compatible_brands}};
        $majorBrand = $compatible[0] if @compatible == 1;
    } 
    # This works for both Apple QTFF and ISO BMFF (i.e. mov, mp4, heic)
    unless (any { $majorBrand eq $_ } ('heic', 'isom', 'mp41', 'mp42', 'qt  ')) {
        my $brand = "'$ftyp->{f_major_brand}'";
        if (@{$ftyp->{f_compatible_brands}}) {
            $brand = $brand . ' (\'' . join('\', \'', @{$ftyp->{f_compatible_brands}}) . '\')';
        }
        warn "unexpected brand $brand for " . getIsobmffBoxDiagName($mediaPath, $ftyp);
        return undef;
    }
    return getIsobmffMdatMd5(@_);
}

sub getPngContentMd5 {
    my ($mediaPath, $fh) = @_;
    read($fh, my $fileData, 8) or die "Failed to read PNG header from '$mediaPath': $!";
    my @actualHeader = unpack('C8', $fileData);
    my @pngHeader = ( 137, 80, 78, 71, 13, 10, 26, 10 );
    Data::Compare::Compare(\@actualHeader, \@pngHeader) or die
        "File didn't start with PNG header: '$mediaPath'";
    my $md5 = new Digest::MD5;
    while (!eof($fh)) {
        # Read chunk header
        read($fh, $fileData, 8) or die
            "Failed to read PNG chunk header from '$mediaPath' at @{[tell $fh]}: $!";
        my ($size, $type) = unpack('Na4', $fileData);
        my $seekStartOfData = tell($fh);
        # TODO: Check that 'IHDR' chunk comes first and 'IEND' last?
        if ($type eq 'tEXt' or $type eq 'zTXt' or $type eq 'iTXt') {
            # This is a text field, so not pixel data
            # TODO: should we only skip the type 'iTXt' and subtype
            # 'XML:com.adobe.xmp'? 
        } else {
            # The type and data should be enough - don't need size or CRC
            # BUGBUG - this seems slightly wrong in that if things move around
            # and mean the same thing the MD5s will change even though the
            # contents haven't meaningfully changed, and can result in us
            # falsely reporting that there have been non-metadata changes
            # (i.e. pixel data) changes to the file.
            $md5->add($type);
            addToMd5Digest($md5, $mediaPath, $fh, $size);
        }
        # Seek to start of next chunk (past header, data, and CRC)
        my $address = $seekStartOfData + $size + 4;
        seek($fh, $address, 0) or die "Failed to seek '$mediaPath' to $address: $!";
    }
    return resolveMd5Digest($md5);
}

# Get/verify/canonicalize hash from a FILEHANDLE object
sub getMd5Digest {
    my ($mediaPath, $fh, $size) = @_;
    my $md5 = new Digest::MD5;
    addToMd5Digest($md5, $mediaPath, $fh, $size);
    return resolveMd5Digest($md5);
}

sub addToMd5Digest {
    my ($md5, $mediaPath, $fh, $size) = @_;
    unless (defined $size) {
        $md5->addfile($fh);
    } else {
        # There's no addfile with a size limit, so we roll our own
        # by reading in chunks and adding one at a time (since $size
        # might be huge and we don't want to read it all into memory)
        my $chunkSize = 1024;
        for (my $remaining = $size; $remaining > 0; $remaining -= $chunkSize) {
            my $readSize = $chunkSize < $remaining ? $chunkSize : $remaining;
            read($fh, my $fileData, $readSize)
                or die "Failed to read $readSize bytes from '$mediaPath' at @{[tell $fh]}: $!";
            $md5->add($fileData);
        }
    }
}

# MODEL (MD5) ------------------------------------------------------------------
# Extracts, verifies, and canonicalizes resulting MD5 digest
# final result from a Digest::MD5.
sub resolveMd5Digest {
    my ($md5) = @_;
    my $hexdigest = lc $md5->hexdigest;
    $hexdigest =~ /$md5DigestPattern/ or die "Unexpected MD5: $hexdigest";
    return $hexdigest;
}

1;