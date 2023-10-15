#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;

# If this fails to locate, don't forget prove's -l flag
use_ok('FileTypes');
