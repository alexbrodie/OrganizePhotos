#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoCheckHash');
can_ok( 'DoCheckHash', 'do_check_hash' );
