#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 8;

use_ok('FileOp');
can_ok( 'FileOp', 'trash_path' );
can_ok( 'FileOp', 'trash_path_and_sidecars' );
can_ok( 'FileOp', 'trash_path_with_root' );
can_ok( 'FileOp', 'move_path' );
can_ok( 'FileOp', 'ensure_parent_dir' );
can_ok( 'FileOp', 'try_remove_empty_dir' );
can_ok( 'FileOp', 'open_file' );
