#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoPruneOrphdat');
can_ok( 'DoPruneOrphdat', 'doPurgeMd5' );
