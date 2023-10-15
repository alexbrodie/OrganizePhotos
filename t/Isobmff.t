#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 6;

use_ok('Isobmff');
can_ok('Isobmff', 'readIsobmffBoxHeader');
can_ok('Isobmff', 'readIsobmffFtyp');
can_ok('Isobmff', 'getIsobmffBoxDiagName');
can_ok('Isobmff', 'parseIsobmffBox');
can_ok('Isobmff', 'getIsobmffPrimaryDataExtents');
