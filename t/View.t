#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 9;

use_ok('View');
can_ok('View', 'colored_bold');
can_ok('View', 'colored_faint');
can_ok('View', 'colored_by_index');
can_ok('View', 'dump_struct');
can_ok('View', 'pretty_path');
can_ok('View', 'print_crud');
can_ok('View', 'print_with_icon');
can_ok('View', 'trace');
