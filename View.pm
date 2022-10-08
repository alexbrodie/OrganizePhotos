#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package View;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
    coloredBold
    coloredFaint
    coloredByIndex
    prettyPath
    printCrud
    printWithIcon
    trace
    dumpStruct
);
our @EXPORT_OK = qw(
    getColorForIndex
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

our $verbosity = VERBOSITY_NONE;

use constant CRUD_UNKNOWN => 0;
use constant CRUD_CREATE => 1;
use constant CRUD_READ => 2;
use constant CRUD_UPDATE => 3;
use constant CRUD_DELETE => 4;

# VIEW -------------------------------------------------------------------------
sub coloredFaint {
    my ($message) = @_;
    return Term::ANSIColor::colored($message, 'faint');
}

# VIEW -------------------------------------------------------------------------
sub coloredBold {
    my ($message) = @_;
    return Term::ANSIColor::colored($message, 'bold');
}

# VIEW -------------------------------------------------------------------------
# Colorizes text for diffing purposes
# [message] - Text to color
# [colorIndex] - Index for a color class
sub coloredByIndex {
    my ($message, $colorIndex) = @_;
    return Term::ANSIColor::colored($message, getColorForIndex($colorIndex));
}

# VIEW -------------------------------------------------------------------------
# Returns a color name (usable with colored()) based on an index
# [colorIndex] - Index for a color class
sub getColorForIndex {
    my ($colorIndex) = @_;
    my @colors = ('green', 'red', 'blue', 'yellow', 'magenta', 'cyan');
    return 'bright_' . $colors[$colorIndex % scalar @colors];
}

# VIEW -------------------------------------------------------------------------
# Returns a form of the specified path prettified for display/reading
sub prettyPath {
    my ($path) = @_;
    $path = File::Spec->abs2rel($path);
    return $path;
}

# VIEW -------------------------------------------------------------------------
# This should be called when any crud operations have been performed
sub printCrud {
    my $type = shift @_;
    # If the message starts with a space, then it's low pri
    return if $_[0] =~ /^\s/ and $verbosity <= VERBOSITY_NONE;
    my ($icon, $color) = ('', '');
    if ($type == CRUD_CREATE) {
        ($icon, $color) = ('(+)', 'blue');
    } elsif ($type == CRUD_READ) {
        ($icon, $color) = ('(<)', 'magenta');
    } elsif ($type == CRUD_UPDATE) {
        ($icon, $color) = ('(>)', 'cyan');
    } elsif ($type == CRUD_DELETE) {
        ($icon, $color) = ('(X)', 'yellow');
    }
    printWithIcon($icon, $color, @_);
}

# VIEW -------------------------------------------------------------------------
sub printWithIcon {
    my ($icon, $color, @statements) = @_;
    my @lines = map { Term::ANSIColor::colored($_, $color) } split /\n/, join '', @statements;
    $lines[0]  = Term::ANSIColor::colored($icon, "white on_$color") . ' ' . $lines[0];
    $lines[$_] = (' ' x length $icon) . ' ' . $lines[$_] for 1..$#lines;
    print map { ($_, "\n") } @lines;
}

# VIEW -------------------------------------------------------------------------
sub trace {
    my ($level, @statements) = @_;
    if ($level <= $verbosity) {
        my ($package, $filename, $line) = caller;
        printWithIcon(sprintf("T%02d", $level),
                      'bright_black', 
                      basename($filename) . '@' . $line . ': ', 
                      @statements);
    }
}

# VIEW -------------------------------------------------------------------------
# Stringify a perl data structure suitable for traceing
sub dumpStruct {
    #return Data::Dumper::Dumper(@_);
    return JSON->new->allow_nonref->allow_blessed->convert_blessed->pretty->canonical->encode(@_);
}

1;
