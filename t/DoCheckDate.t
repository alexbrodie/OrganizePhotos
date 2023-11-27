#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoCheckDate');
can_ok( 'DoCheckDate', 'do_check_date' );
