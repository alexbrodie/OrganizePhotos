#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 3;

use_ok('ContentHash');
can_ok( 'ContentHash', 'is_hash_version_current' );
can_ok( 'ContentHash', 'calculate_hash' );
