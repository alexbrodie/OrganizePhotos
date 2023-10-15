#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 7;

use_ok('FileTypes');
can_ok('FileTypes', 'get_file_type_info');
can_ok('FileTypes', 'get_mime_type');
can_ok('FileTypes', 'get_sidecar_paths');
can_ok('FileTypes', 'get_trash_path');
can_ok('FileTypes', 'compare_path_with_ext_order');
can_ok('FileTypes', 'is_reserved_system_filename');
