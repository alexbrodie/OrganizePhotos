#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package View;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(coloredFaint coloredBold coloredByIndex colorByIndex prettyPath printCrud trace printWithIcon);

use if $^O eq 'MSWin32', 'Win32::Console::ANSI'; # must come before Term::ANSIColor
# TODO: be explicit with this and move usage to view layer
use Term::ANSIColor ();

use constant VERBOSITY_NONE => 0;    # all traces off
use constant VERBOSITY_LOW => 1;     # only important traces on
use constant VERBOSITY_MEDIUM => 2;  # moderate amount of traces on
use constant VERBOSITY_HIGH => 3;    # most traces on
use constant VERBOSITY_ALL => 4;     # all traces on

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
    return Term::ANSIColor::colored($message, colorByIndex($colorIndex));
}

# VIEW -------------------------------------------------------------------------
# Returns a color name (usable with colored()) based on an index
# [colorIndex] - Index for a color class
sub colorByIndex {
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
    my ($icon, $color) = ('', '');
    if ($type == CRUD_CREATE) {
        ($icon, $color) = ('(+)', 'blue');
    } elsif ($type == CRUD_READ) {
        return if $verbosity <= VERBOSITY_NONE;
        ($icon, $color) = ('(<)', 'magenta');
    } elsif ($type == CRUD_UPDATE) {
        ($icon, $color) = ('(>)', 'cyan');
    } elsif ($type == CRUD_DELETE) {
        ($icon, $color) = ('(X)', 'yellow');
    }
    printWithIcon($icon, $color, @_);
}

# VIEW -------------------------------------------------------------------------
sub trace {
    my ($level, @args) = @_;
    if ($level <= $verbosity) {
        my ($package, $filename, $line) = caller;
        my $icon = sprintf("T%02d@%04d", $level, $line);
        printWithIcon($icon, 'bright_black', @args);
    }
}

# VIEW -------------------------------------------------------------------------
sub printWithIcon {
    my ($icon, $color, @statements) = @_;
    my @lines = map { Term::ANSIColor::colored($_, $color) } split /\n/, join '', @statements;
    $lines[0]  = Term::ANSIColor::colored($icon, "black on_$color") . ' ' . $lines[0];
    $lines[$_] = (' ' x length $icon) . ' ' . $lines[$_] for 1..$#lines;
    print map { ($_, "\n") } @lines;
}

1;
