#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package PathOp;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    parent_path
    change_filename
    split_path
    split_dir
    combine_path
    cat_ext
    split_ext
);

# Library uses
use File::Spec;

sub parent_path {
    my ($path) = @_;
    return change_filename($path, undef);
}

sub change_filename {
    my ($path, $new_filename) = @_;
    my ($vol, $dir, $old_filename) = split_path($path);
    my $newPath = combine_path($vol, $dir, $new_filename);
    return wantarray ? ($newPath, $old_filename) : $newPath;
}

sub split_path {
    return File::Spec->splitpath(@_);
}

sub split_dir {
    return File::Spec->splitdir(@_);
}

# Experience shows that canonpath should follow catpath. This wrapper
# combines the two.
sub combine_path {
    return File::Spec->canonpath(File::Spec->catpath(@_));
}

# The inverse of split_ext, this combines a basename and extension into a
# filename.
sub cat_ext {
    my ($basename, $ext) = @_;
    if ($ext) {
        return $basename ? "$basename.$ext" : ".$ext";
    } else {
        return $basename;
    }
}

# Splits the filename into basename and extension. (Both without a dot.) It
# is usually used like the following example
#       my ($vol, $dir, $filename) = split_path($path);
#       my ($basename, $ext) = split_ext($filename);
sub split_ext {
    my ($path) = @_;
    my ($basename, $ext) = $path =~ /^(.*)\.([^.]*)/;
    # TODO: handle case without extension - if no re match then just return ($path, '')
    return ($basename, $ext);
}

1;