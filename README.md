# NAME

OrganizePhotos - utilities for managing a collection of photos/videos

# SYNOPSIS

       OrganizePhotos.pl <verb> <options>
       OrganizePhotos.pl VerifyMd5
       OrganizePhotos.pl CheckMd5 [glob_pattern]
       OrganizePhotos.pl FindDupeFiles
    

# DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

## VerifyMd5

Verifies the MD5 hashes for all contents of all md5.txt files below
the current directory.

MD5 hashes are stored in a md5.txt file in the file's one line per file
with the pattern:
filename: hash

This method is read-only, if you want to add/update MD5s, use CheckMd5.

## CheckMd5 \[glob\_pattern\]

For each media files under the current directory, generate the MD5 hash
and either add to md5.txt file if missing or verify hashes match if
already present.

For each file matching glob\_pattern, generate the MD5 hash and either
add to md5.txt file if missing or verify hashes match if already present.

This method is read/write, if you want to read-only MD5 checkin, 
 use VerifyMd5.

## FindDupeFiles

Find files that have multiple copies

# TODO

## FindMisplacedFiles

Find files that aren't in a directory appropriate for their date

## FindDupeFolders

Find the folders that represent the same date

## FindMissingFiles

Finds files that may be missing based on gaps in sequential photos

## FindMisplacedFiles

Find files that are in the wrong directory

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
