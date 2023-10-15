#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package PathOp;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    change_filename
    combine_dir
    combine_ext
    combine_path
    parent_path
    split_dir
    split_ext
    split_path
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
    my $new_path = combine_path($vol, $dir, $new_filename);
    return wantarray ? ($new_path, $old_filename) : $new_path;
}

# Splits a path into three components:
#   my ($volume, $dirs, $filename) = split_path($path);
# The inverse of combine_path.
sub split_path { ## no critic (RequireArgUnpacking)
    return File::Spec->splitpath(@_);
}

# Merges the three components:
#   my $path = combine_path($volume, $dirs, $filename);
# The inverse of split_path.
sub combine_path { ## no critic (RequireArgUnpacking)
    # Experience shows that canonpath should follow catpath.
    return File::Spec->canonpath(File::Spec->catpath(@_));
}

# The inverse of combine_dir
sub split_dir { ## no critic (RequireArgUnpacking)
    return File::Spec->splitdir(@_);
}

# The inverse of split_dir
sub combine_dir { ## no critic (RequireArgUnpacking)
    return File::Spec->catdir(@_);
}

# The inverse of split_ext, this combines a basename and extension into a
# filename.
sub combine_ext {
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