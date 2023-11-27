#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 9;

use_ok('OrPhDat');
can_ok( 'OrPhDat', 'resolve_orphdat' );
can_ok( 'OrPhDat', 'find_orphdat' );
can_ok( 'OrPhDat', 'write_orphdat' );
can_ok( 'OrPhDat', 'move_orphdat' );
can_ok( 'OrPhDat', 'trash_orphdat' );
can_ok( 'OrPhDat', 'delete_orphdat' );
can_ok( 'OrPhDat', 'append_orphdat_files' );
can_ok( 'OrPhDat', 'make_orphdat_base' );
