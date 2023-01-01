#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package View;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    colored_bold
    colored_faint
    colored_by_index
    pretty_path
    print_crud
    print_with_icon
    trace
    dump_struct
);
our @EXPORT_OK = qw(
    get_color_for_index
);

# Library uses
use File::Basename;
use if $^O eq 'MSWin32', 'Win32::Console::ANSI'; # must come before Term::ANSIColor
use Term::ANSIColor ();

use constant VERBOSITY_NONE => 0;    # all traces off
use constant VERBOSITY_LOW => 1;     # only important traces on
use constant VERBOSITY_MEDIUM => 2;  # moderate amount of traces on
use constant VERBOSITY_HIGH => 3;    # most traces on
use constant VERBOSITY_MAX => 4;     # all traces on

our $Verbosity = VERBOSITY_NONE;

use constant CRUD_UNKNOWN => 0;
use constant CRUD_CREATE => 1;
use constant CRUD_READ => 2;
use constant CRUD_UPDATE => 3;
use constant CRUD_DELETE => 4;

sub colored_faint {
    my ($message) = @_;
    return Term::ANSIColor::colored($message, 'faint');
}

sub colored_bold {
    my ($message) = @_;
    return Term::ANSIColor::colored($message, 'bold');
}

# Colorizes text for diffing purposes
# [message] - Text to color
# [color_index] - Index for a color class
sub colored_by_index {
    my ($message, $color_index) = @_;
    return Term::ANSIColor::colored($message, get_color_for_index($color_index));
}

# Returns a color name (usable with colored()) based on an index
# [color_index] - Index for a color class
sub get_color_for_index {
    my ($color_index) = @_;
    my @colors = ('green', 'red', 'blue', 'yellow', 'magenta', 'cyan');
    return 'bright_' . $colors[$color_index % scalar @colors];
}

# Returns a form of the specified path prettified for display/reading
sub pretty_path {
    my ($path) = @_;
    my $full_path = File::Spec->rel2abs($path);
    $full_path = File::Spec->canonpath($full_path);
    my $rel_path = File::Spec->abs2rel($full_path);
    $rel_path = File::Spec->canonpath($rel_path);
    return length($full_path) < length($rel_path) ? $full_path : $rel_path;
}

# This should be called when any crud operations have been performed
sub print_crud {
    my $type = shift @_;
    # If the message starts with a space, then it's low pri
    return if $_[0] =~ /^\s/ and $Verbosity <= VERBOSITY_NONE;
    my ($icon, $color) = ('', '');
    if ($type == CRUD_CREATE) {
        ($icon, $color) = ('(+)', 'blue');
    } elsif ($type == CRUD_READ) {
        ($icon, $color) = ('(<)', 'cyan');
    } elsif ($type == CRUD_UPDATE) {
        ($icon, $color) = ('(>)', 'yellow');
    } elsif ($type == CRUD_DELETE) {
        ($icon, $color) = ('(X)', 'magenta');
    }
    print_with_icon($icon, $color, @_);
}

sub print_with_icon {
    my ($icon, $color, @statements) = @_;
    my @lines = map { Term::ANSIColor::colored($_, $color) } split /\n/, join '', @statements;
    $lines[0]  = Term::ANSIColor::colored($icon, "white on_$color") . ' ' . $lines[0];
    $lines[$_] = (' ' x length $icon) . ' ' . $lines[$_] for 1..$#lines;
    print map { ($_, "\n") } @lines;
}

sub trace {
    my ($level, @statements) = @_;
    if ($level <= $Verbosity) {
        my ($package, $filename, $line) = caller;
        print_with_icon(sprintf("T%02d", $level),
                      'bright_black', 
                      basename($filename) . '@' . $line . ': ', 
                      @statements);
    }
}

# Stringify a perl data structure suitable for traceing
sub dump_struct {
    #return Data::Dumper::Dumper(@_);
    return JSON->new->allow_nonref->allow_blessed->convert_blessed->pretty->canonical->encode(@_);
}

1;
