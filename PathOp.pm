#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package PathOp;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    parentPath
    changeFilename
    combinePath
    catExt
    splitExt
);

# Library uses
use File::Spec;

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