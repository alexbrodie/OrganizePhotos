#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;

use_ok('DoVerifyHash');
can_ok('DoVerifyHash', 'do_verify_md5');
