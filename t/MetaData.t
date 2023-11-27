#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 5;

use_ok('MetaData');
can_ok( 'MetaData', 'check_path_dates' );
can_ok( 'MetaData', 'extract_info' );
can_ok( 'MetaData', 'get_date_taken' );
can_ok( 'MetaData', 'read_metadata' );
