#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoRemoveEmpties');
can_ok( 'DoRemoveEmpties', 'doRemoveEmpties' );
