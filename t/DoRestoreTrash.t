#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoRestoreTrash');
can_ok('DoRestoreTrash', 'doRestoreTrash');
