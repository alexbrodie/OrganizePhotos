#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoTest');
can_ok( 'DoTest', 'do_test' );
