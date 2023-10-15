#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 3;

# If this fails to locate, don't forget prove's -l flag
use_ok('ContentHash');
can_ok('ContentHash', 'is_hash_version_current');
can_ok('ContentHash', 'calculate_hash');
