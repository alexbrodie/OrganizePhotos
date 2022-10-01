#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package PathOp;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    getTrashPathFor
    comparePathWithExtOrder
    parentPath
    changeFilename
    combinePath
    catExt
    splitExt
);

use Const::Fast qw(const);

# TODO!! Consolidate $md5Filename and $trashDirName once we know where they should live

# Filename only portion of the path to Md5File which stores
# Md5Info data for other files in the same directory
const my $md5Filename => '.orphdat';

# This subdirectory contains the trash for its parent
const my $trashDirName => '.orphtrash';

# MODEL (Path Operations) ------------------------------------------------------
# Gets the local trash location for the specified path: the same filename
# in the .orphtrash subdirectory.
sub getTrashPathFor {
    my ($fullPath) = @_;
    my ($vol, $dir, $filename) = File::Spec->splitpath($fullPath);
    my $trashDir = File::Spec->catdir($dir, $trashDirName);
    return combinePath($vol, $trashDir, $filename);
}

# MODEL (Path Operations) ------------------------------------------------------
sub comparePathWithExtOrder {
    my ($fullPathA, $fullPathB) = @_;
    my ($volA, $dirA, $filenameA) = File::Spec->splitpath($fullPathA);
    my ($volB, $dirB, $filenameB) = File::Spec->splitpath($fullPathB);
    return compareDir($dirA, $dirB) ||
           compareFilenameWithExtOrder($filenameA, $filenameB);
}

# MODEL (Path Operations) ------------------------------------------------------
sub compareDir {
    my ($dirA, $dirB) = @_;
    return 0 if $dirA eq $dirB; # optimization
    my @as = File::Spec->splitdir($dirA);
    my @bs = File::Spec->splitdir($dirB);
    for (my $i = 0;; $i++) {
        if ($i >= @as) {
            if ($i >= @bs) {
                return 0; # A and B both ran out, so they're equal
            } else {
                return -1; # A is ancestor of B, so A goes first
            }
        } else {
            if ($i >= @bs) {
                return 1; # B is ancestor of A, so B goes first
            } else {
                # Compare this generation - if not equal, then we
                # know the order, else move on to children
                my $c = lc $as[$i] cmp lc $bs[$i];
                return $c if $c;
            }
        }
    }
}

# MODEL (Path Operations) ------------------------------------------------------
sub compareFilenameWithExtOrder {
    my ($filenameA, $filenameB) = @_;
    my ($basenameA, $extA) = splitExt($filenameA);
    my ($basenameB, $extB) = splitExt($filenameB);
    # Compare by basename first
    my $c = lc ($basenameA || '') cmp lc ($basenameB || '');
    return $c if $c;
    # Next by extorder
    my $extOrderA = main::getFileTypeInfo($extA, 'EXTORDER') || 0;
    my $extOrderB = main::getFileTypeInfo($extB, 'EXTORDER') || 0;
    $c = $extOrderA <=> $extOrderB;
    return $c if $c;
    # And then just the extension as a string
    return lc ($extA || '') cmp lc ($extB || '');
}

# MODEL (Path Operations) ------------------------------------------------------
sub parentPath {
    my ($path) = @_;
    return changeFilename($path, undef);
}

# MODEL (Path Operations) ------------------------------------------------------
sub changeFilename {
    my ($path, $newFilename) = @_;
    my ($vol, $dir, $oldFilename) = File::Spec->splitpath($path);
    my $newPath = combinePath($vol, $dir, $newFilename);
    return wantarray ? ($newPath, $oldFilename) : $newPath;
}

# MODEL (Path Operations) ------------------------------------------------------
# Experience shows that canonpath should follow catpath. This wrapper
# combines the two.
sub combinePath {
    return File::Spec->canonpath(File::Spec->catpath(@_));
}

# MODEL (Path Operations) ------------------------------------------------------
# The inverse of splitExt, this combines a basename and extension into a
# filename.
sub catExt {
    my ($basename, $ext) = @_;
    if ($ext) {
        return $basename ? "$basename.$ext" : ".$ext";
    } else {
        return $basename;
    }
}

# MODEL (Path Operations) ------------------------------------------------------
# Splits the filename into basename and extension. (Both without a dot.) It
# is usually used like the following example
#       my ($vol, $dir, $filename) = File::Spec->splitpath($path);
#       my ($basename, $ext) = splitExt($filename);
sub splitExt {
    my ($path) = @_;
    my ($basename, $ext) = $path =~ /^(.*)\.([^.]*)/;
    # TODO: handle case without extension - if no re match then just return ($path, '')
    return ($basename, $ext);
}

1;