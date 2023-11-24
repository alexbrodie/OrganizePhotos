#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

package DoTest;
use Exporter;
our @ISA    = ('Exporter');
our @EXPORT = qw(
    do_test
);

# Local uses
use View qw(print_with_icon);

# Execute test verb. This is intended to run a suite of tests.
sub do_test {
    my (@args) = @_;
    print_with_icon( '/!\\', 'yellow', 'Not implemented' );
}

1;
