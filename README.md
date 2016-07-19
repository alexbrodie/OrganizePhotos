# NAME

OrganizePhotos - utilities for managing a collection of photos/videos

# SYNOPSIS

    ##### Typical workflow

    # Import via Lightroom
    OrganizePhotos.pl checkup /deepest/common/ancestor/dir
    # Arvhive /deepest/common/ancestor/dir (see below)

    ##### Supported operations:

    OrganizePhotos.pl add-md5
    OrganizePhotos.pl check-md5 [glob_pattern]
    OrganizePhotos.pl checkup
    OrganizePhotos.pl collect-trash
    OrganizePhotos.pl find-dupe-files [-a] [-d] [-n]
    OrganizePhotos.pl metadata-diff <files>
    OrganizePhotos.pl remove-empties
    OrganizePhotos.pl verify-md5

    ##### Complementary ExifTool commands:

    # Append all keyword metadata from SOURCE to DESTINATION
    exiftool -addTagsfromfile SOURCE -HierarchicalSubject -Subject DESTINATION

    ##### Complementary Mac commands:

    # Print trash directories
    find . -type d -name .Trash

    # Remove .DS_Store
    find . -type f -name .DS_Store -print -delete

    # Remove zero byte md5.txt files (omit "-delete" to only print)
    find . -type f -name md5.txt -empty -print -delete

    # Remove empty directories (omit "-delete" to only print)
    find . -type d -empty -print -delete

    # Remove the executable bit for media files
    find . -type f -perm +111 \( -iname "*.CRW" -or -iname "*.CR2"
        -or -iname "*.JPEG" -or -iname "*.JPG" -or -iname "*.M4V"
        -or -iname "*.MOV" -or -iname "*.MP4" -or -iname "*.MPG"
        -or -iname "*.MTS" -or -iname "*.NEF" -or -iname "*.RAF"
        -or -iname "md5.txt" \) -print -exec chmod -x {} \;

    # Remove the downloaded-and-untrusted extended attribute for the current tree
    xattr -d -r com.apple.quarantine .

    # Mirror SOURCE to TARGET
    rsync -ah --delete --delete-during --compress-level=0 --inplace --progress 
        SOURCE TARGET

    ##### Complementary PC commands:

    # Mirror SOURCE to TARGET
    robocopy /MIR SOURCE TARGET

# DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadataorganization.

MD5 hashes are stored in a md5.txt file in the file's one line per file
with the pattern:

    filename: hash

Metadata operations are powered by Image::ExifTool.

The calling pattern for each command follows the pattern:

    OrganizePhotos.pl <verb> <options>

The following verbs are available:

## add-md5

Alias: a5

For each media file under the current directory that doesn't have a
MD5 computed, generate the MD5 hash and add to md5.txt file.

This does not modify media files or their sidecars, it only adds entries
to the md5.txt files.

## check-md5

Alias: c5

For each media file under the current directory, generate the MD5 hash
and either add to md5.txt file if missing or verify hashes match if
already present.

This method is read/write for MD5s, if you want to perform read-only
MD5 checks (i.e., don't write to md5.txt), then use verify-md5.

This does not modify media files or their sidecars, it only modifies
the md5.txt files.

### Options

- **glob\_pattern**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern.

### Examples

    # Check or add MD5 for all CR2 files in the current directory
    $ OrganizePhotos.pl c5 *.CR2

## checkup

Alias: c

This command runs the following suggested suite of commands:

    check-md5
    find-dupe-files [-a | --always-continue]
    collect-trash
    remove-empties

### Options

- **-a, --always-continue**

    Always continue

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

## find-dupe-files

Alias: fdf

Find files that have multiple copies under the current directory.

### Options

- **-a, --always-continue**

    Always continue

- **-d, --auto-diff**

    Automatically do the 'd' diff command for every new group of files

- **-n, --by-name**

    Search for items based on name rather than the default of MD5

## metadata-diff &lt;files>

Alias: md

Do a diff of the specified media files (including their sidecar metadata).

This method does not modify any file.

## remove-empties

Remove any subdirectories that are empty save an md5.txt file

## verify-md5

Alias: v5

Verifies the MD5 hashes for all contents of all md5.txt files below
the current directory.

This method is read-only, if you want to add/update MD5s, use check-md5.

This method does not modify any file.

# AUTHOR

Copyright 2016, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

# SEE ALSO

[Image::ExifTool](https://metacpan.org/pod/Image::ExifTool)
