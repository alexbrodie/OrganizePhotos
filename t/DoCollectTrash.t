#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoCollectTrash');
can_ok( 'DoCollectTrash', 'doCollectTrash' );
