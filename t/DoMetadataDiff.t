#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoMetadataDiff');
can_ok('DoMetadataDiff', 'do_metadata_diff');
