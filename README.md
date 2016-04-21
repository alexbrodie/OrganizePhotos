# NAME

OrganizePhotos - utilities for managing a collection of photos/videos

# SYNOPSIS

    OrganizePhotos.pl <verb> <options>
    OrganizePhotos.pl add-md5
    OrganizePhotos.pl check-md5 [glob_pattern]
    OrganizePhotos.pl verify-md5
    OrganizePhotos.pl find-dupe-files [-a | --always-continue]
    OrganizePhotos.pl metadata-diff
    OrganizePhotos.pl collect-trash

# DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

MD5 hashes are stored in a md5.txt file in the file's one line per file
with the pattern:

    filename: hash

Metadata operations are powered by Image::ExifTool.

## add-md5

Alias: a5

For each media file under the current directory that doesn't have a
MD5 computed, generate the MD5 hash and add to md5.txt file.

## check-md5

Alias: c5

For each media file under the current directory, generate the MD5 hash
and either add to md5.txt file if missing or verify hashes match if
already present.

This method is read/write, if you want to read-only MD5 checkin,
use verify-md5.

## check-md5 &lt;glob\_pattern>

Alias: c5

For each file matching glob\_pattern, generate the MD5 hash and either
add to md5.txt file if missing or verify hashes match if already present.

This method is read/write, if you want to read-only MD5 checkin,
use verify-md5.

## verify-md5

Alias: v5

Verifies the MD5 hashes for all contents of all md5.txt files below
the current directory.

This method is read-only, if you want to add/update MD5s, use check-md5.

## find-dupe-files

Alias: fdf

Find files that have multiple copies under the current directory.

### Options

- **-a, --always-continue**

    Always continue

## metadata-diff &lt;files>

Alias: md

Do a diff of the specified media files (including their sidecar metadata).

## collect-trash

Alias: ct

Looks recursively for .Trash subdirectories under the current directory
and moves that content to the current directory's .Trash perserving
directory structure.

For example if we had the following trash:

    ./Foo/.Trash/1.jpg
    ./Foo/.Trash/2.jpg
    ./Bar/.Trash/1.jpg

After collection we would have:

    ./.Trash/Foo/1.jpg
    ./.Trash/Foo/2.jpg
    ./.Trash/Bar/1.jpg

# TODO

## FindMisplacedFiles

Find files that aren't in a directory appropriate for their date

## FindDupeFolders

Find the folders that represent the same date

## FindMissingFiles

Finds files that may be missing based on gaps in sequential photos

## FindScreenShots

Find files which are screenshots

## FindOrphanedFiles

Find XMP or THM files that don't have a cooresponding main file

## --if-modified-since

Flag for CheckMd5/VerifyMd5 to only check files created/modified since
the provided timestamp or timestamp at last MD5 check

# AUTHOR

Copyright 2016, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

# SEE ALSO

[Image::ExifTool](https://metacpan.org/pod/Image::ExifTool)
